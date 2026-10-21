// Current shanshui@5 painting path; all page profiles share one composition and scale model.
import CoreGraphics
import Foundation
import ZixiaoColor

extension ZXArt {
    /// Scene geometry has its own generator version and entropy stream. V3 brush rollout is unrelated.
    enum PoetryPaintingRenderer {
        static func generate(seed: Seed, size: CGSize, palette: Palette, scene: PoetryScene,
                             options: SceneOptions, quietTop: Double, verse: VerseLayout) -> (drawing: Drawing, trace: Trace) {
            let options = options.resolvedForPainting(scene: scene, seed: seed.string)
            let ratio = Double(size.height / size.width)
            let w = 420 * max(1, 1 / ratio), h = 420 * max(1, ratio)
            let stage = PaintingStage(seed: seed, width: w, height: h, palette: palette, verse: verse, quietTop: quietTop, options: options)
            stage.compose(scene: scene, options: options)
            var layers: [Layer] = []
            var nearSpans: [ShapeSpan] = []
            for (index, part) in stage.parts.enumerated() {
                var shapes: [Shape] = []
                let motif = stage.celestialLayers.first(where: { $0.layer == index })?.motif
                ZXArt.appendPaintingShapes(part.canv, motif: motif, palette: palette, into: &shapes)
                func appendLayer(_ layer: Layer) {
                    guard !layer.shapes.isEmpty else { return }
                    if part.near { nearSpans.append(.init(layer: layers.count, range: 0..<layer.shapes.count)) }
                    layers.append(layer)
                }
                if part.plain {
                    appendLayer(.init(shapes: shapes))
                } else if let m = part.mist {
                    let (ridge, x0) = LayerMist.ridge(of: shapes, step: 2)
                    appendLayer(.init(mist: .init(depth: m.depth, blur: m.blur, peakOpacity: m.peak,
                        ridge: ridge, ridgeX0: x0, ridgeStep: 2, floorY: m.floorY, floorDepth: m.floorDepth), shapes: shapes))
                } else {
                    // Only loaded strokes and broad ink masses bleed. Fine dry hairs stay crisp.
                    var wet = shapes.filter { shape in
                        guard shape.fill != nil, let last = shape.points.last else { return false }
                        var area = 0.0, previous = last
                        for point in shape.points {
                            area += Double(previous.x) * Double(point.y) - Double(previous.y) * Double(point.x)
                            previous = point
                        }
                        return abs(area) > 50
                    }
                    for i in wet.indices {
                        wet[i].fill = wet[i].fill?.opacity(0.22)
                        wet[i].stroke = wet[i].stroke?.opacity(0.22)
                    }
                    appendLayer(.init(wash: .init(bleed: 0.8, rim: 0.10, grain: 0.12), fade: part.fade, shapes: wet))
                    appendLayer(.init(tooth: 0.18, fade: part.fade, shapes: shapes))
                }
            }
            var paper = stage.engine.backgroundPaper()
            paper.tint = palette.ink
            paper.strength *= 0.32
            var drawing = Drawing(width: w, height: h, background: palette.paper, paper: paper, layers: layers)
            if options.purpose == .reading {
                drawing.quietRect = .init(x: 0, y: 0, width: w, height: quietTop * h)
            } else { drawing.setVerse(verse, quietTop: quietTop) }
            drawing.nearSpans = nearSpans
            drawing.sceneElements = stage.elements
            drawing.anchors = Anchors.build(pieces: stage.engine.anchorPieces, width: w, height: h,
                                            blocked: { _, _ in false })
            if drawing.anchors == nil { drawing.anchors = Anchors() }
            drawing.anchors?.boats = stage.boats
            if drawing.anchors?.sky == nil { drawing.anchors?.sky = .init(y: 0...0.38) }
            var trace = Trace(logicalWidth: w, logicalHeight: h, prngAfter: stage.engine.e.state)
            for part in stage.parts { for poly in part.canv { trace.add(poly.p.map { ($0.x, $0.y) }) } }
            return (drawing, trace)
        }
    }
}

/// Independent entropy keeps size variation stable without changing mountain or brush generation.
enum PaintingTreeScale {
    static func multiplier(seed: String, motif: ZXArt.SceneMotif, instance: Int) -> Double {
        var hash: UInt32 = 2_166_136_261
        for byte in "tree-size-v1:\(seed):\(motif.rawValue):\(instance)".utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return 0.5 + 0.5 * Double(hash) / Double(UInt32.max)
    }
}

/// A small composition vocabulary. Objects are fitted as whole objects, never cut into unreadable fragments.
private final class PaintingStage {
    typealias Motif = ZXArt.SceneMotif
    let engine: ShanShuiEngine
    let w: Double, h: Double
    let palette: ZXArt.Palette
    let verse: CGRect
    let art: CGRect
    let foreground: CGRect
    /// Lowest y the painting may use (recommendation pages keep a reading strip at the bottom).
    let footer: Double
    let purpose: ZXArt.ScenePurpose
    let composition: ZXArt.SceneComposition
    let seed: String
    var parts: [ShanShuiEngine.Part] = []
    var elements: [ZXArt.SceneElement] = []
    var placed = Set<Motif>()
    var celestialLayers: [(layer: Int, motif: Motif)] = []
    var boats: [ZXArt.Anchors.Boat] = []
    var mountainRidges: [[ZXArt.P]] = []
    var summitLedge: CGRect?
    var historicGroundNeeded = false
    enum Structure { case high, deep, level, corner }
    var structure: Structure = .level
    var currentScene: ZXArt.PoetryScene = .retreat
    var bankSurface: (x0: Double, step: Double, heights: [Double])?
    var preparedGround: (canv: ZXArt.SSCanv, bounds: CGRect)?
    var groundInBand = false
    /// Set while placing an object at an explicit, already-grounded position and size.
    var pinned = false
    /// Top of the full-width ground band beneath the verse, when the page has one.
    let bandTop: Double?
    let waterEngine: ShanShuiEngine

    init(seed: ZXArt.Seed, width: Double, height: Double, palette: ZXArt.Palette, verse: ZXArt.VerseLayout, quietTop: Double, options: ZXArt.SceneOptions) {
        self.w = width; self.h = height; self.palette = palette
        self.seed = seed.string
        purpose = options.purpose ?? .inscription; composition = options.composition ?? .corner
        self.verse = options.purpose == .reading ? .null : verse.rect(in: CGSize(width: width, height: height)).insetBy(dx: -8, dy: -8)
        engine = ShanShuiEngine(seed: .init("poetry-painting-v1:" + seed.string))
        waterEngine = ShanShuiEngine(seed: .init("poetry-water-v1:" + seed.string))
        engine.drawTowers = false
        engine.anchorLog = []
        let pad = min(width, height) * 0.045
        let top = max(pad, quietTop * height)
        let footer = options.purpose == .recommendation ? height * 0.87 : height - pad
        self.footer = footer
        // Inscribed portrait: the verse sits in the sky on one side; the ground beneath it can run
        // the full width. Nil when the verse is a full-height column (wide formats) or absent.
        if !self.verse.isNull, width <= height * 1.3, self.verse.maxY < height * 0.82 {
            bandTop = self.verse.maxY + pad * 0.4
        } else { bandTop = nil }
        let left: Double, available: Double
        if options.purpose == .reading {
            left = pad; available = width - 2 * pad
        } else if verse.side == .right {
            left = pad; available = max(60, self.verse.minX - 2 * pad)
        } else if verse.side == .left || width > height * 1.3 {
            left = self.verse.maxX + pad; available = max(60, width - left - pad)
        } else {
            left = pad; available = width - 2 * pad
        }
        let start = verse.side == .top && options.purpose != .reading && width <= height * 1.3
            ? max(top, self.verse.maxY + pad) : top
        let high = max(60, footer - start)
        switch options.composition ?? .corner {
        case .corner:
            let inset = options.purpose == .reading ? available * 0.15 : 0
            art = CGRect(x: left + (verse.side == .left ? inset : 0), y: start + high * 0.08,
                width: available - inset, height: high * 0.87)
        case .oppositeBank:
            art = CGRect(x: left, y: start, width: available, height: high * 0.70)
        case .depth:
            art = CGRect(x: left, y: start, width: available, height: high * 0.96)
        }
        let low = options.purpose == .reading ? height * 0.66 : max(self.verse.maxY + pad, height * 0.58)
        if width <= height * 1.3, footer - low > 28 {
            foreground = CGRect(x: pad, y: low, width: width - 2 * pad, height: footer - low)
        } else {
            foreground = CGRect(x: art.minX, y: art.minY + art.height * 0.72,
                width: art.width, height: art.height * 0.28)
        }
    }

    /// The lower ground of the page: full width beneath the verse when there is room, otherwise
    /// the lower part of the painting column (wide pages, where the verse is a full-height column).
    private func lowerBand(columnFrom fraction: Double = 0.55) -> CGRect {
        let pad = min(w, h) * 0.045
        if let top = bandTop, footer - top > 20 {
            return CGRect(x: pad, y: top, width: w - 2 * pad, height: footer - top)
        }
        let top = art.minY + art.height * fraction
        return CGRect(x: art.minX, y: top, width: art.width, height: max(20, footer - top))
    }

    private func slot(_ x: Double, _ y: Double, _ width: Double, _ height: Double, front: Bool = false) -> CGRect {
        let box = front ? foreground : art
        let r = CGRect(x: box.minX + x * box.width, y: box.minY + y * box.height,
                       width: width * box.width, height: height * box.height)
        // Like an inscribed hanging scroll: the verse sits in the sky on one side, and the ground
        // beneath it runs the full width of the page. Anything wholly below the verse keeps its
        // relative place but spreads across the lower band instead of staying in the side column.
        guard !front, !verse.isNull, r.minY >= verse.maxY else { return r }
        let pad = min(w, h) * 0.045
        let band = CGRect(x: pad, y: 0, width: w - 2 * pad, height: h)
        let u0 = (r.minX - art.minX) / art.width, u1 = (r.maxX - art.minX) / art.width
        return CGRect(x: band.minX + u0 * band.width, y: r.minY,
                      width: (u1 - u0) * band.width, height: r.height)
    }

    @discardableResult
    private func add(_ motif: Motif, _ box: CGRect, repeatable: Bool = false, source: ZXArt.SSCanv? = nil) -> Bool {
        guard repeatable || !placed.contains(motif) else { return false }
        let raw: ZXArt.SSCanv
        if let source { raw = source }
        else if motif == .stream {
            raw = currentScene == .desert ? waterEngine.paintingLongRiver()
                : waterEngine.paintingChannel(width: box.width, height: box.height)
        } else if motif == .window, currentScene == .courtyard {
            raw = engine.paintingWindow(embedded: true)
        } else { raw = engine.paintingAsset(motif) }
        var box = box
        // Paths and fields are drawn on the ground they belong to, never hanging below it.
        if groundInBand, [.path, .fields].contains(motif),
           let bank = elements.first(where: { $0.motif == "groundBank" })?.bounds.cgRect {
            let b = CGRect(x: bank.minX * w, y: bank.minY * h, width: bank.width * w, height: bank.height * h)
            box = motif == .path
                ? CGRect(x: b.minX + b.width * 0.30, y: b.minY + b.height * 0.25, width: b.width * 0.22, height: b.height * 0.70)
                : CGRect(x: b.minX + b.width * 0.48, y: b.minY + b.height * 0.18, width: b.width * 0.46, height: b.height * 0.55)
        }
        let scaled = pinned ? box : scaledSlot(motif, box)
        let placement = motif == .window ? groundedSlot(motif, scaled) : scaled
        guard var object = fitted(raw, to: placement) else { return false }
        if motif != .window, !pinned {
            // Ground the fitted object: its actual canopy / roof size can be much smaller than the slot.
            let landed = groundedSlot(motif, object.bounds)
            if landed != object.bounds {
                guard let moved = fitted(raw, to: landed) else { return false }
                object = moved
            }
        }
        let trees: Set<Motif> = [.pine, .oldTree, .bareTree, .layeredTree, .willow, .blossom, .maple]
        var plantedRoot: ZXArt.P?
        if trees.contains(motif), let surface = bankSurface {
            // A leaning crown's bounding-box centre is not the trunk root. Old-tree bark
            // also extends below its root; neither should determine where the tree stands.
            let points = raw.flatMap(\.p)
            let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
            let minY = points.map(\.y).min()!
            let root = motif == .oldTree ? ZXArt.P(65, 175) : ZXArt.P(66, 178)
            let scale = object.bounds.width / (maxX - minX)
            let rootX = object.bounds.minX + (root.x - minX) * scale
            let rootY = object.bounds.minY + (root.y - minY) * scale
            let end = surface.x0 + surface.step * Double(surface.heights.count - 1)
            let landedX = min(end - 1, max(surface.x0 + 1, rootX))
            if let foot = bankFoot(landedX - 0.5, landedX + 0.5) {
                let landed = object.bounds.offsetBy(dx: landedX - rootX, dy: foot - rootY)
                guard let moved = fitted(raw, to: landed) else { return false }
                object = moved
                plantedRoot = .init(landedX, foot)
            }
        }
        if motif == .traveler || motif == .horse {
            let cleared = clearFigureGround(object.bounds)
            if cleared != object.bounds, let moved = fitted(raw, to: cleared) { object = moved }
        }
        if [.moon, .crescent, .sunrise, .sunset].contains(motif), !mountainRidges.isEmpty {
            guard let sky = openSky(for: object.bounds), let moved = fitted(raw, to: sky) else { return false }
            object = moved
        }
        let accents: Set<Motif> = [.pine, .oldTree, .bareTree, .layeredTree, .willow, .bamboo,
            .blossom, .maple, .house, .hut, .pavilion, .templeGate, .pagoda, .boat, .angler,
            .mooredBoat, .traveler, .horse, .bridge, .reeds]
        if accents.contains(motif) { object.canv = engine.paintingInk(object.canv, depth: .near) }
        // Each object gets its own layer, retaining stable ordering and inspection metadata.
        let actual = object.bounds
        if motif == .stream { engine.noted(.water, object.canv) }
        support(motif, bounds: actual, root: plantedRoot)
        if [.mist, .afterRain, .dunes].contains(motif) {
            parts.append(.init(canv: object.canv, mist: .init(depth: actual.height * 4,
                blur: motif == .dunes ? 0.4 : 0.7, peak: 0.95, floorY: actual.maxY,
                floorDepth: actual.height * (motif == .dunes ? 0.28 : 0.8))))
        } else { parts.append(.near(object.canv)) }
        elements.append(.init(motif: motif.rawValue,
            bounds: .init(x: actual.minX / w, y: actual.minY / h, width: actual.width / w, height: actual.height / h)))
        if [.moon, .sunrise, .sunset].contains(motif) {
            celestialLayers.append((parts.count - 1, motif))
        }
        let kind: ZXArt.AnchorPiece.Kind?
        switch motif {
        case .boat, .mooredBoat, .angler, .sail:
            kind = nil
            if let hull = object.canv.first {
                let xs = hull.p.map(\.x), ys = hull.p.map(\.y)
                if let minX = xs.min(), let maxX = xs.max(), let bottom = ys.max() {
                    boats.append(.init(x: (minX + maxX) / 2 / w, y: bottom / h, length: (maxX - minX) / w, flipped: false))
                }
            }
        case .house, .courtyard, .cityGate, .templeGate: kind = .building(.house)
        case .hut, .pavilion, .terrace: kind = .building(.pavilion)
        case .pagoda: kind = .building(.pagoda)
        case .oldTree, .bareTree, .layeredTree, .pine, .bamboo, .willow, .blossom, .maple: kind = .tree(.tree03)
        default: kind = nil
        }
        if let kind { engine.noted(kind, object.canv) }
        placed.insert(motif)
        return true
    }

    /// Scale by the scene's common ground plane, rather than filling each independent placeholder.
    private func scaledSlot(_ motif: Motif, _ requested: CGRect) -> CGRect {
        var maxWidth = requested.width, maxHeight = requested.height
        switch motif {
        case .house, .hut, .pavilion, .templeGate, .cityGate, .terrace, .ruins:
            let close = currentScene == .moonNight
            let village = currentScene == .village
            maxWidth = min(maxWidth, art.width * (close ? 0.50 : (village ? 0.33 : 0.26)))
            maxHeight = min(maxHeight, art.height * (close ? 0.18 : (village ? 0.14 : 0.11)))
            if let surface = bankSurface {
                let width = surface.step * Double(surface.heights.count - 1)
                maxWidth = min(maxWidth, width * (close ? 0.7 : 0.46))
            }
            if let main = elements.first(where: { $0.motif == "mainMountain" }) {
                maxHeight = min(maxHeight, main.bounds.cgRect.height * h * 0.075)
            }
        case .pagoda:
            maxWidth = min(maxWidth, art.width * 0.14)
            maxHeight = min(maxHeight, art.height * 0.25)
            if let main = elements.first(where: { $0.motif == "mainMountain" }) {
                maxHeight = min(maxHeight, main.bounds.cgRect.height * h * 0.15)
            }
        case .pine, .oldTree, .bareTree, .layeredTree, .willow, .blossom, .maple:
            let mountainScene = [ZXArt.PoetryScene.retreat, .temple, .historic].contains(currentScene)
            if currentScene == .retreat, let ground = preparedGround {
                maxWidth = min(maxWidth, ground.bounds.width * 0.38)
            }
            maxHeight = min(maxHeight, min(art.height * (mountainScene ? 0.46 : 0.62), art.width * (mountainScene ? 0.85 : 0.65)))
            if let main = elements.first(where: { $0.motif == "mainMountain" }) {
                // The pine of 明月松间照 is the protagonist of a mountain retreat, not a sapling.
                let lead = motif == .pine && currentScene == .retreat
                maxHeight = min(maxHeight, main.bounds.cgRect.height * h * (lead ? 0.55 : 0.28))
            }
        case .traveler, .horse:
            maxHeight = min(maxHeight, art.width * (motif == .horse ? 0.065 : 0.052))
        case .bamboo:
            maxHeight = min(maxHeight, art.height * 0.34)
            if let main = elements.first(where: { $0.motif == "mainMountain" }) {
                maxHeight = min(maxHeight, main.bounds.cgRect.height * h * 0.26)
            }
        default: break
        }
        // Vary between half and all of the approved small tree, preserving its root and proportions.
        // Both limits scale together, including trees constrained by width rather than height.
        switch motif {
        case .pine, .oldTree, .bareTree, .layeredTree, .willow, .blossom, .maple, .bamboo:
            let instance = elements.filter { $0.motif == motif.rawValue }.count
            // Near trees carry the darkest ink and lead the eye; keep them within 70–100% of the cap.
            let scale = 0.4 + 0.6 * PaintingTreeScale.multiplier(seed: seed, motif: motif, instance: instance)
            maxWidth *= scale
            maxHeight *= scale
        default: break
        }
        return CGRect(x: requested.midX - maxWidth / 2, y: requested.maxY - maxHeight,
            width: maxWidth, height: maxHeight)
    }

    /// Lowest bank point under a span (the larger y), so a broad base reaches the ground.
    private func bankFoot(_ x0: Double, _ x1: Double) -> Double? {
        guard let s = bankSurface else { return nil }
        let first = max(0, Int(floor((x0 - s.x0) / s.step))), last = min(s.heights.count - 1, Int(ceil((x1 - s.x0) / s.step)))
        guard first <= last else { return nil }
        return s.heights[first...last].filter(\.isFinite).max()
    }

    /// Place a building at the main mountain's foot, `along` its width, sized against the
    /// mountain (丈山尺树寸马分人), standing on the bank directly beneath.
    private func placeAtFoot(_ motif: Motif, along: Double, height: Double, aspect: Double) {
        guard let m = elements.first(where: { $0.motif == "mainMountain" })?.bounds.cgRect else { return }
        let peak = CGRect(x: m.minX * w, y: m.minY * h, width: m.width * w, height: m.height * h)
        let bh = peak.height * height, bw = bh * aspect
        guard let surface = bankSurface else { return }
        let bankEnd = surface.x0 + surface.step * Double(surface.heights.count - 1)
        let cx = min(max(peak.minX + peak.width * along, surface.x0 + bw * 0.5), bankEnd - bw * 0.5)
        guard let foot = bankFoot(cx - bw * 0.4, cx + bw * 0.4) else { return }
        pinned = true
        add(motif, CGRect(x: cx - bw / 2, y: foot - bh, width: bw, height: bh))
        pinned = false
    }

    /// Buildings and trees meet the actual bank silhouette, not independent percentage baselines.
    private func groundedSlot(_ motif: Motif, _ requested: CGRect) -> CGRect {
        if motif == .window, currentScene == .moonNight,
           let house = elements.first(where: { ["house", "hut"].contains($0.motif) })?.bounds.cgRect {
            return CGRect(x: (house.minX + house.width * 0.17) * w,
                y: (house.minY + house.height * 0.64) * h, width: house.width * w * 0.17, height: house.height * h * 0.22)
        }
        let rooted: Set<Motif> = [.oldTree, .bareTree, .layeredTree, .pine, .bamboo, .willow,
            .blossom, .maple, .house, .hut, .pavilion, .pagoda, .templeGate, .cityGate, .terrace, .ruins, .fence, .traveler, .horse]
        guard rooted.contains(motif), let surface = bankSurface else { return requested }
        var requested = requested
        let building = [Motif.house, .hut, .pavilion, .pagoda, .templeGate, .cityGate, .terrace, .ruins].contains(motif)
        let broadBase = building || motif == .bamboo
        let endX = surface.x0 + surface.step * Double(surface.heights.count - 1)
        let radius = min((endX - surface.x0) * 0.45, broadBase ? requested.width * 0.36 : min(8, requested.width * 0.1))
        let low = max(surface.x0 + radius, art.minX + requested.width / 2)
        let high = min(endX - radius, art.maxX - requested.width / 2)
        let fraction = min(max((requested.midX - art.minX) / art.width, 0), 1)
        var desired = surface.x0 + radius + fraction * max(0, endX - surface.x0 - 2 * radius)
        if motif == .house, let previous = elements.last(where: { $0.motif == "house" })?.bounds.cgRect,
           desired > previous.midX * w {
            desired = max(desired, previous.maxX * w + requested.width * 0.18)
        }
        let center = low <= high ? min(max(desired, low), high) : min(max(desired, surface.x0 + radius), endX - radius)
        requested.origin.x = center - requested.width / 2
        let position = (requested.midX - surface.x0) / surface.step
        guard position >= 0, position <= Double(surface.heights.count - 1) else { return requested }
        let lo = Int(position), hi = min(lo + 1, surface.heights.count - 1)
        var y = min(surface.heights[lo], surface.heights[hi])
        if broadBase {
            // A broad foundation or grove must reach the lower bank across its footprint,
            // not balance its whole base on the highest point under the centre.
            let first = max(0, Int(floor((requested.midX - requested.width * 0.36 - surface.x0) / surface.step)))
            let last = min(surface.heights.count - 1, Int(ceil((requested.midX + requested.width * 0.36 - surface.x0) / surface.step)))
            if first <= last, let base = surface.heights[first...last].filter(\.isFinite).max() { y = base }
        }
        guard y.isFinite else { return requested }
        var landed = CGRect(x: requested.minX, y: y - requested.height, width: requested.width, height: requested.height)
        // A tall tree or roof that would reach into the verse steps aside along the bank
        // rather than being dropped from the painting.
        if landed.intersects(verse) {
            let left = verse.minX - landed.width - 2, right = verse.maxX + 2
            if left >= surface.x0, left + landed.width <= endX { landed.origin.x = left }
            else if right + landed.width <= endX { landed.origin.x = right }
            if landed.minX != requested.minX,
               let foot = bankFoot(landed.midX - radius, landed.midX + radius) {
                landed.origin.y = foot - landed.height
            }
        }
        return landed
    }

    /// Applies to both explicitly pinned farewell figures and ordinary grounded travelers.
    private func clearFigureGround(_ requested: CGRect) -> CGRect {
        guard let surface = bankSurface else { return requested }
        let endX = surface.x0 + surface.step * Double(surface.heights.count - 1)
        let occupied = elements.filter { ["house", "hut", "pavilion", "templeGate", "pagoda", "terrace", "ruins", "cityGate", "traveler", "horse"].contains($0.motif) }
            .map { CGRect(x: $0.bounds.cgRect.minX * w, y: $0.bounds.cgRect.minY * h,
                width: $0.bounds.cgRect.width * w, height: $0.bounds.cgRect.height * h) }
        guard occupied.contains(where: { $0.intersects(requested) }) else { return requested }
        var xs = [surface.x0 + 1, endX - requested.width - 1]
        for obstacle in occupied { xs += [obstacle.minX - requested.width - 3, obstacle.maxX + 3] }
        for x in xs.sorted(by: { abs($0 - requested.minX) < abs($1 - requested.minX) }) {
            guard x >= surface.x0, x + requested.width <= endX,
                  let foot = bankFoot(x, x + requested.width) else { continue }
            let candidate = CGRect(x: x, y: foot - requested.height, width: requested.width, height: requested.height)
            if !candidate.intersects(verse), !occupied.contains(where: { $0.intersects(candidate) }) { return candidate }
        }
        return requested
    }

    private func recordBank(_ object: (canv: ZXArt.SSCanv, bounds: CGRect)) {
        let count = 64, x0 = object.bounds.minX, step = object.bounds.width / Double(63)
        guard step > 0 else { return }
        var heights = Array(repeating: Double.infinity, count: count)
        for poly in object.canv {
            for (a, b) in zip(poly.p, poly.p.dropFirst()) {
                let lo = max(0, Int(ceil((min(a.x, b.x) - x0) / step)))
                let hi = min(count - 1, Int(floor((max(a.x, b.x) - x0) / step)))
                guard lo <= hi else { continue }
                for i in lo...hi {
                    let x = x0 + Double(i) * step
                    let t = abs(b.x - a.x) < 0.0001 ? 0 : (x - a.x) / (b.x - a.x)
                    heights[i] = min(heights[i], a.y + (b.y - a.y) * t)
                }
            }
        }
        bankSurface = (x0, step, heights)
        let r = object.bounds
        elements.append(.init(motif: "groundBank", bounds: .init(x: r.minX / w, y: r.minY / h,
            width: r.width / w, height: r.height / h)))
    }

    /// Rooted rock shelves connect the tree groups, houses and paths into terrain.
    private func support(_ motif: Motif, bounds: CGRect, root: ZXArt.P? = nil) {
        let rooted: Set<Motif> = [.oldTree, .bareTree, .layeredTree, .pine, .bamboo, .willow,
            .blossom, .maple, .house, .hut, .pavilion, .pagoda, .templeGate, .cityGate,
            .courtyard, .terrace, .ruins]
        guard rooted.contains(motif), currentScene != .courtyard else { return }
        let buildings: Set<Motif> = [.house, .hut, .pavilion, .pagoda, .templeGate, .cityGate, .terrace, .ruins]
        // A building stands on a low rock platform as wide as itself, so a sloping bank never
        // leaves one corner hanging in the air.
        let isBuilding = buildings.contains(motif)
        let height = isBuilding ? max(2, bounds.height * 0.18) : min(24, max(5, bounds.height * 0.13))
        let spread = isBuilding ? bounds.width * 0.12 : 4
        let width = root == nil ? bounds.width : max(8, bounds.width * 0.38)
        let box = CGRect(x: (root?.x ?? bounds.midX) - width / 2 - spread,
            y: (root?.y ?? bounds.maxY) - height * 0.35, width: width + 2 * spread, height: height)
        if let rock = fitted(engine.paintingRock(width: 125, height: 24, tone: 0.7), to: box) {
            parts.append(.near(rock.canv))
        }
    }

    private func fitted(_ raw: ZXArt.SSCanv, to box: CGRect) -> (canv: ZXArt.SSCanv, bounds: CGRect)? {
        let points = raw.flatMap(\.p)
        guard box.width > 0, box.height > 0,
              let x0 = points.map(\.x).min(), let x1 = points.map(\.x).max(),
              let y0 = points.map(\.y).min(), let y1 = points.map(\.y).max(), x1 > x0, y1 > y0 else { return nil }
        let scale = min(box.width / (x1 - x0), box.height / (y1 - y0))
        let dx = box.midX - (x0 + x1) / 2 * scale, dy = box.maxY - y1 * scale
        let transformed = raw.map { poly -> ZXArt.SSPoly in
            var p = poly
            p.p = poly.p.map { .init($0.x * scale + dx, $0.y * scale + dy) }
            p.wid *= scale
            return p
        }
        let actual = CGRect(x: x0 * scale + dx, y: y0 * scale + dy, width: (x1 - x0) * scale, height: (y1 - y0) * scale)
        guard !actual.intersects(verse), CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: -1, dy: -1).contains(actual) else { return nil }
        return (transformed, actual)
    }

    private func hills(_ main: Bool = false) {
        // Two ranges, staggered: the far one higher, paler and to one side; the nearer one lower
        // and offset the other way. Each covers part of the width so the sky stays open.
        let side = engine.r() < 0.5
        let ranges = currentScene == .historic || structure == .corner || structure == .high ? 1 : 2
        for k in 0..<ranges {
            let raw = engine.paintingDistant(k)
            let width = 0.58 + engine.r() * 0.16
            let x = (k == 0) == side ? 1 - width : 0.0
            let box: CGRect
            if !main, structure == .deep || structure == .level {
                // Keep both ranges above the far bank, higher/paler first, then lower/darker.
                box = slot(x, 0.015 + Double(k) * 0.07, width, 0.15)
            } else if structure == .deep {
                box = slot(0.40 - Double(k) * 0.17, 0.02 + Double(k) * 0.19,
                           0.54 + Double(k) * 0.10, 0.30)
            } else if structure == .corner {
                box = slot(side ? 0.48 : 0.02, 0.26, 0.48, 0.12)
            } else { box = slot(x, 0.06 + Double(k) * 0.10, width, 0.24) }
            if let object = fitted(raw, to: box) {
                // Crest stays legible; the body dissolves downward into mist.
                parts.append(.init(canv: object.canv, mist: .init(depth: object.bounds.height * 1.1,
                    blur: 0.35, peak: 0.95, floorY: object.bounds.maxY, floorDepth: object.bounds.height * 0.7)))
                engine.noted(.ridge(.far), object.canv)
                let r = object.bounds
                elements.append(.init(motif: "farMountain", bounds: .init(x: r.minX / w, y: r.minY / h,
                    width: r.width / w, height: r.height / h)))
            }
        }
        var peakBox = slot(0.02, 0.01, 0.95, 0.75)
        if let ground = preparedGround {
            let foot = ground.bounds.minY + ground.bounds.height * 0.58
            peakBox = CGRect(x: peakBox.minX, y: peakBox.minY, width: peakBox.width,
                             height: max(40, foot - peakBox.minY))
        }
        if main, structure == .high {
            let guestBox = CGRect(x: peakBox.minX + peakBox.width * 0.48,
                y: peakBox.minY + peakBox.height * 0.28, width: peakBox.width * 0.51, height: peakBox.height * 0.62)
            if let guest = fitted(engine.paintingMountain(form: .folded), to: guestBox) {
                let r = guest.bounds
                if let outline = guest.canv.first { mountainRidges.append(Array(outline.p.dropLast(2))) }
                parts.append(.init(canv: engine.paintingInk(guest.canv, depth: .middle),
                    fade: .init(top: r.minY + r.height * 0.55, bottom: r.maxY, seed: engine.inkSeed())))
            }
            peakBox.size.width *= 0.94
        }
        if currentScene == .historic {
            // Reserve headroom for the summit figure inside the painting area, including the
            // recommendation header. Fitting the mountain alone does not reserve this space.
            let headroom = art.height * 0.04
            peakBox.origin.y += headroom
            peakBox.size.height -= headroom
        }
        if main, let object = fitted(engine.paintingMountain(form: structure == .deep ? .clustered : .folded, terraced: currentScene == .historic), to: peakBox) {
            // 山腰云锁: the lower third of the main peak dissolves into cloud instead of
            // standing on the bank like a monument.
            let r = object.bounds
            if let outline = object.canv.first {
                let ridge = Array(outline.p.dropLast(2))
                mountainRidges.append(ridge)
                if currentScene == .historic, let top = ridge.map(\.y).min() {
                    // Choose one contiguous bearing plane, never bridge two summits over a cleft.
                    var runs: [[ZXArt.P]] = [], run: [ZXArt.P] = []
                    for p in ridge {
                        if abs(p.y - top) < 0.001 { run.append(p) }
                        else if !run.isEmpty { runs.append(run); run = [] }
                    }
                    if !run.isEmpty { runs.append(run) }
                    let ledge = runs.max { ($0.last!.x - $0.first!.x) < ($1.last!.x - $1.first!.x) } ?? []
                    if let left = ledge.first, let right = ledge.last {
                        summitLedge = CGRect(x: left.x, y: top, width: right.x - left.x, height: 1)
                    }
                }
            }
            parts.append(.init(canv: object.canv, fade: .init(top: r.maxY - r.height * 0.42,
                bottom: r.maxY - r.height * 0.04, seed: engine.inkSeed())))
            engine.noted(.ridge(.main), object.canv)
            elements.append(.init(motif: "mainMountain", bounds: .init(x: r.minX / w, y: r.minY / h,
                width: r.width / w, height: r.height / h)))
        }
    }

    private func water() {
        let kind: PaintingWaterKind
        switch currentScene {
        case .waterTown, .farewell, .fishing: kind = .river
        case .lotusPond: kind = .pond
        case .ocean: kind = .sea
        default: kind = .lake
        }
        let upper = slot(0, 0.45, 1, 0.52)
        let lower = slot(0, 0.10, 1, 0.86, front: true)
        let whole = upper.union(lower)
        let raw = waterEngine.paintingSurface(kind, width: whole.width, height: whole.height).map { p -> ZXArt.SSPoly in
            var q = p; q.p = p.p.map { .init($0.x + whole.minX, $0.y + whole.minY) }; return q
        }
        // One perspective grid crosses both safe painting areas. Clip at the verse reserve;
        // never fit the same wave patch twice at different scales.
        let top = CGRect(x: upper.minX, y: upper.minY, width: upper.width,
            height: max(0, min(lower.minY, upper.maxY) - upper.minY))
        for box in [top, lower] where box.height > 0 {
            let clipped = clipWater(raw, to: box)
            guard !clipped.isEmpty else { continue }
            parts.append(.near(clipped)); engine.noted(.water, clipped)
            elements.append(.init(motif: kind == .sea ? Motif.waves.rawValue : kind.rawValue + "Water", bounds: .init(x: box.minX / w,
                y: box.minY / h, width: box.width / w, height: box.height / h)))
        }
        placed.insert(.waves)
    }

    private func clipWater(_ raw: ZXArt.SSCanv, to box: CGRect) -> ZXArt.SSCanv {
        raw.compactMap { poly in
            var points = poly.p
            for edge in 0..<4 {
                func distance(_ p: ZXArt.P) -> Double {
                    switch edge {
                    case 0: return p.x - box.minX
                    case 1: return box.maxX - p.x
                    case 2: return p.y - box.minY
                    default: return box.maxY - p.y
                    }
                }
                guard var previous = points.last else { return nil }
                var clipped: [ZXArt.P] = []
                for p in points {
                    let a = distance(previous), b = distance(p)
                    if (a >= 0) != (b >= 0) {
                        let t = a / (a - b)
                        clipped.append(.init(previous.x + (p.x - previous.x) * t,
                            previous.y + (p.y - previous.y) * t))
                    }
                    if b >= 0 { clipped.append(p) }
                    previous = p
                }
                points = clipped
            }
            guard points.count > 2 else { return nil }
            var result = poly; result.p = points; return result
        }
    }

    private func layWater(_ raw: ZXArt.SSCanv, in box: CGRect, motif: String) {
        guard let object = fitted(raw, to: box) else { return }
        parts.append(.near(object.canv))
        engine.noted(.water, object.canv)
        let r = object.bounds
        elements.append(.init(motif: motif, bounds: .init(x: r.minX / w, y: r.minY / h,
            width: r.width / w, height: r.height / h)))
    }

    /// Crows gather beside the tree; perched feet are pinned to painted branch points.
    private func treeCrows() {
        guard let tree = elements.first(where: { ["oldTree", "bareTree"].contains($0.motif) })?.bounds.cgRect else { return }
        let b = CGRect(x: tree.minX * w, y: tree.minY * h, width: tree.width * w, height: tree.height * h)
        let minX = Double(b.minX), maxX = Double(b.maxX)
        let minY = Double(b.minY + b.height * 0.22), maxY = Double(b.minY + b.height * 0.55)
        var candidates: [ZXArt.P] = []
        for part in parts {
            for polygon in part.canv {
                for point in polygon.p {
                    if point.x >= minX && point.x <= maxX && point.y > minY && point.y < maxY {
                        candidates.append(point)
                    }
                }
            }
        }
        for fraction in [0.23, 0.77] {
            let target = ZXArt.P(b.minX + b.width * fraction, b.minY + b.height * 0.38)
            func distance(_ point: ZXArt.P) -> Double {
                let dx = point.x - target.x, dy = point.y - target.y
                return dx * dx + dy * dy
            }
            guard let branch = candidates.min(by: { distance($0) < distance($1) }) else { continue }
            let scale = b.height * 0.036 / 17
            let bird = engine.paintingPerchedCrow().map { poly -> ZXArt.SSPoly in
                var p = poly; p.p = p.p.map { .init(branch.x + $0.x * scale, branch.y + $0.y * scale) }
                p.wid *= scale; return p
            }
            parts.append(.near(bird))
        }
        add(.crow, CGRect(x: max(1, b.minX - b.width * 0.2), y: b.minY - b.height * 0.12,
            width: b.width * 0.9, height: b.height * 0.15))
    }

    /// A shared scale and a rein connect the traveler and horse; their feet follow the same road.
    private func journey() {
        guard let bank = elements.first(where: { $0.motif == "groundBank" })?.bounds.cgRect else { return }
        let personH = art.width * 0.052, horseH = personH * 1.18
        let x = (bank.minX + bank.width * 0.59) * w
        let pose = Int(engine.r() * 2) // Grazing is reserved for the standalone animal.
        let horse = engine.paintingHorse(pose: pose, facingLeft: false)
        let person = engine.paintingPerson(pose: 0, facingLeft: false)
        let horseW = personH * 1.7, personW = personH * 0.75
        guard let foot = bankFoot(x, x + horseW + personW) else { return }
        pinned = true
        let horsePlaced = add(.horse, CGRect(x: x, y: foot - horseH, width: horseW, height: horseH), source: horse)
        let personPlaced = add(.traveler, CGRect(x: x + horseW + personH * 0.24, y: foot - personH,
            width: personW, height: personH), source: person)
        pinned = false
        guard horsePlaced, personPlaced,
              let hb = elements.last(where: { $0.motif == "horse" })?.bounds.cgRect,
              let pb = elements.last(where: { $0.motif == "traveler" })?.bounds.cgRect else { return }
        func anchor(_ raw: ZXArt.SSCanv, _ b: CGRect, _ p: ZXArt.P) -> ZXArt.P {
            let points = raw.flatMap(\.p), x0 = points.map(\.x).min()!, x1 = points.map(\.x).max()!
            let y0 = points.map(\.y).min()!
            let scale = b.width * w / (x1 - x0)
            return .init(b.minX * w + (p.x - x0) * scale, b.minY * h + (p.y - y0) * scale)
        }
        let muzzle = anchor(horse, hb, .init(99, pose == 1 ? 28 : 43))
        let hand = anchor(person, pb, .init(54, 24))
        let rein = engine.inkCurve([muzzle, .init((muzzle.x + hand.x) / 2, max(muzzle.y, hand.y) + personH * 0.22), hand])
        parts.append(.near(engine.inkLine(rein, width: 0.32, tone: 0.58, dry: 0.4)))
    }

    /// Place water, bridge and reflection without independently fitting their bounding boxes.
    private func crossing(river: Bool) {
        guard let bank = elements.first(where: { $0.motif == "groundBank" })?.bounds.cgRect else { return }
        let b = CGRect(x: bank.minX * w, y: bank.minY * h, width: bank.width * w, height: bank.height * h)
        let width = min(b.width * 0.36, art.width * 0.46)
        let box = CGRect(x: b.minX + b.width * 0.12, y: b.minY + b.height * 0.10,
                         width: width, height: b.height * 0.88)
        let phase = waterEngine.r() * 1.6 - 0.8
        let channel = PaintingWaterChannel(width: width, height: box.height, phase: phase, broad: true)
        func place(_ raw: ZXArt.SSCanv, x: Double, y: Double, scale: Double = 1, motif: String) {
            let canvas = raw.map { poly -> ZXArt.SSPoly in
                var p = poly; p.p = p.p.map { .init(x + $0.x * scale, y + $0.y * scale) }
                p.wid *= scale; return p
            }
            let points = canvas.flatMap(\.p)
            guard let x0 = points.map(\.x).min(), let x1 = points.map(\.x).max(),
                  let y0 = points.map(\.y).min(), let y1 = points.map(\.y).max() else { return }
            parts.append(.near(canvas))
            if motif != "bridge" { engine.noted(.water, canvas) }
            elements.append(.init(motif: motif, bounds: .init(x: x0 / w, y: y0 / h, width: (x1 - x0) / w, height: (y1 - y0) / h)))
        }
        place(waterEngine.paintingChannel(channel), x: box.minX, y: box.minY, motif: river ? "riverChannel" : "stream")
        placed.insert(.stream)
        let left = channel.point(0.46, across: -1), right = channel.point(0.46, across: 1)
        let bridge = engine.paintingBridgePlan()
        let scale = (right.x - left.x) * 1.30 / bridge.width
        let x = box.minX + (left.x + right.x) / 2 - bridge.width * scale / 2
        let y = box.minY + left.y - 60 * scale
        place(engine.paintingBridge(bridge), x: x, y: y, scale: scale, motif: "bridge")
        placed.insert(.bridge)
        place(engine.paintingBridgeReflection(bridge), x: x, y: y, scale: scale, motif: "bridgeReflection")
        // The bridge ends disappear into short bank contours, without separate round stone piles.
        let landing = bridge.kind == .arch ? 54.0 : 42.0
        var joins: ZXArt.SSCanv = []
        for (end, side) in [(0.0, -1.0), (bridge.width, 1.0)] {
            joins += engine.inkLine([.init(end - side * 2, landing + 1), .init(end + side * 8, landing + 1),
                                    .init(end + side * 18, landing - 3)], width: 1.0, tone: 0.48, dry: 0.6)
        }
        parts.append(.near(joins.map { poly in
            var p = poly; p.p = p.p.map { .init(x + $0.x * scale, y + $0.y * scale) }; p.wid *= scale; return p
        }))
    }

    /// Search actual sky above the main and guest ridges, not their rectangular bounding boxes.
    /// A disc drawn in front of an opaque mountain must never overlap its shoulder.
    private func openSky(for requested: CGRect) -> CGRect? {
        func clearsRidges(_ rect: CGRect) -> Bool {
            let clearance = rect.insetBy(dx: -3, dy: -3)
            for ridge in mountainRidges {
                for (a, b) in zip(ridge, ridge.dropFirst()) {
                    let left = max(clearance.minX, min(a.x, b.x))
                    let right = min(clearance.maxX, max(a.x, b.x))
                    guard left <= right else { continue }
                    let dx = b.x - a.x
                    let y0 = abs(dx) < 0.001 ? min(a.y, b.y) : a.y + (b.y - a.y) * (left - a.x) / dx
                    let y1 = abs(dx) < 0.001 ? min(a.y, b.y) : a.y + (b.y - a.y) * (right - a.x) / dx
                    if clearance.maxY >= min(y0, y1) { return false }
                }
            }
            return true
        }
        if clearsRidges(requested) { return requested }
        let pad = min(w, h) * 0.045
        for scale in [1.0, 0.8, 0.6] {
            let width = requested.width * scale, height = requested.height * scale
            let skyTop = max(pad, art.minY)
            let sky = CGRect(x: art.minX, y: skyTop, width: art.width,
                height: max(height, min(footer, art.minY + art.height * 0.55) - skyTop))
            var candidates: [CGRect] = []
            for row in 0...16 { for column in 0...16 {
                let x = sky.minX + max(0, sky.width - width) * Double(column) / 16
                let y = sky.minY + max(0, sky.height - height) * Double(row) / 16
                let rect = CGRect(x: x, y: y, width: width, height: height)
                if !rect.intersects(verse), clearsRidges(rect) { candidates.append(rect) }
            } }
            // Keep the original compositional relationship whenever nearby blank paper is available.
            if let nearest = candidates.min(by: {
                hypot($0.midX - requested.midX, $0.midY - requested.midY)
                    < hypot($1.midX - requested.midX, $1.midY - requested.midY)
            }) { return nearest }
        }
        return nil
    }

    private func celestialSlot(_ motif: Motif) -> CGRect {
        let sun = motif == .sunset || motif == .sunrise
        let fraction = PaintingTreeScale.multiplier(seed: seed, motif: motif, instance: 0) * 2 - 1
        let x = structure == .high ? 0.73 : 0.24 + fraction * 0.49
        let y = sun ? (structure == .corner ? 0.31 : 0.23) : 0.04 + fraction * 0.14
        return slot(x, y, sun ? 0.13 : 0.18, sun ? 0.10 : 0.14)
    }

    private func mountainStreamSlot() -> CGRect {
        guard let bank = elements.first(where: { $0.motif == "groundBank" })?.bounds.cgRect else {
            return slot(0.27, 0.67, 0.30, 0.30)
        }
        let obstacles = elements.filter { ["pine", "bamboo", "hut"].contains($0.motif) }
            .map { $0.bounds.cgRect }.sorted { $0.minX < $1.minX }
        var gaps: [(Double, Double)] = [], cursor = bank.minX + 0.002
        for obstacle in obstacles {
            if obstacle.minX > cursor { gaps.append((cursor, obstacle.minX)) }
            cursor = max(cursor, obstacle.maxX)
        }
        gaps.append((cursor, bank.maxX - 0.002))
        let viable = gaps.filter { $0.1 - $0.0 > 0.004 }
        let gap = viable.max { $0.1 - $0.0 < $1.1 - $1.0 }
            ?? (bank.minX + bank.width * 0.35, bank.minX + bank.width * 0.55)
        let near = elements.first(where: { $0.motif == "nearBank" })?.bounds.cgRect ?? bank
        let bottom = max(bank.maxY, near.maxY) * h
        return CGRect(x: gap.0 * w, y: bank.minY * h, width: (gap.1 - gap.0) * w,
            height: max(12, bottom - bank.minY * h))
    }

    private func waterDetails() {
        if currentScene == .retreat, let stream = elements.first(where: { $0.motif == "stream" })?.bounds.cgRect {
            let box = CGRect(x: (stream.midX - stream.width) * w, y: stream.maxY * h,
                width: stream.width * w * 2, height: h * 0.018)
            if let pool = fitted(waterEngine.paintingSurface(.pond, width: box.width, height: box.height), to: box) {
                parts.append(.near(pool.canv))
            }
        }
        for boat in boats {
            let box = CGRect(x: (boat.x - boat.length * 0.60) * w, y: boat.y * h,
                width: boat.length * w * 1.2, height: max(5, boat.length * w * 0.12))
            let raw = waterEngine.paintingSurface(.pond, width: box.width, height: box.height)
            guard let wake = fitted(raw, to: box) else { continue }
            parts.append(.near(wake.canv))
        }
        guard currentScene == .moonNight,
              let light = elements.first(where: { ["moon", "crescent", "sunrise", "sunset"].contains($0.motif) })?.bounds.cgRect else { return }
        let x = light.midX * w - foreground.width * 0.07, width = foreground.width * 0.14
        var top = foreground.minY + foreground.height * 0.26
        if let bank = elements.first(where: { $0.motif == "nearBank" })?.bounds.cgRect,
           x < bank.maxX * w, x + width > bank.minX * w {
            top = max(top, bank.maxY * h + 1)
        }
        let height = min(foreground.height * 0.60, foreground.maxY - top)
        guard height >= 6 else { return }
        let box = CGRect(x: x, y: top, width: width, height: height)
        if let reflection = fitted(waterEngine.paintingReflection(width: box.width, height: box.height), to: box) {
            parts.append(.near(reflection.canv))
            let r = reflection.bounds
            elements.append(.init(motif: "waterReflection", bounds: .init(x: r.minX / w, y: r.minY / h,
                width: r.width / w, height: r.height / h)))
        }
    }

    private func ground(for scene: ZXArt.PoetryScene, prepareOnly: Bool = false) {
        guard ![.desert, .ocean, .courtyard].contains(scene) else { return }
        let narrow = [.fishing, .lotusPond].contains(scene)
        var box: CGRect
        if composition == .oppositeBank { box = slot(0.01, 0.63, narrow ? 0.42 : 1, 0.14) }
        else { box = narrow ? slot(0.01, 0.67, 0.34, 0.25) : slot(0, 0.65, 1, 0.22) }
        // Inscribed portrait: the verse fills the sky on one side, so the ground runs the full
        // width of the band beneath it, the way a hanging scroll's foreground spans the paper.
        if let top = bandTop {
            let pad = min(w, h) * 0.045
            let bottom = min(foreground.maxY, h - pad)
            let width = (w - 2 * pad) * (narrow ? 0.5 : 1)
            let x = verse.minX > w / 2 || narrow ? pad : w - pad - width
            box = CGRect(x: x, y: top, width: width, height: max(20, min(bottom - top, h * 0.13)))
            groundInBand = true
        }
        if scene == .historic {
            box = CGRect(x: box.minX, y: box.maxY - box.height * 0.35,
                         width: box.width, height: box.height * 0.35)
        }
        if prepareOnly {
            preparedGround = fitted(engine.paintingBank(style: [.retreat, .temple].contains(scene) ? .cliff : (scene == .historic || structure == .corner ? .headland : .shoal)), to: box)
            if groundInBand, var ground = preparedGround {
                // Terrain fills the whole lower band. Fitting it like a tree would narrow a
                // steep bank into a floating island; only its horizontal ground plane expands.
                let scaleX = box.width / ground.bounds.width
                let x0 = ground.bounds.minX
                ground.canv = ground.canv.map { poly in
                    var p = poly
                    p.p = poly.p.map { .init(box.minX + ($0.x - x0) * scaleX, $0.y) }
                    return p
                }
                ground.bounds.origin.x = box.minX
                ground.bounds.size.width = box.width
                preparedGround = ground
            }
            if let object = preparedGround, scene != .historic || historicGroundNeeded { recordBank(object) }
            return
        }
        if scene == .historic {
            let band = lowerBand(columnFrom: 0.74)
            let box = CGRect(x: band.minX, y: band.minY + band.height * 0.20,
                             width: band.width * 0.90, height: band.height * 0.20)
            if let earth = fitted(waterEngine.paintingDistant(0), to: box) {
                // A low, broad trace of land below the cloud, not another tall floating peak.
                let canvas = earth.canv.map { poly -> ZXArt.SSPoly in
                    var p = poly
                    p.p = poly.p.map { .init(box.minX + ($0.x - earth.bounds.minX) * box.width / earth.bounds.width, $0.y) }
                    return p
                }
                parts.append(.init(canv: engine.paintingInk(canvas, depth: .middle),
                    mist: .init(depth: earth.bounds.height, blur: 0.45, peak: 0.85,
                                floorY: earth.bounds.maxY, floorDepth: earth.bounds.height * 0.9)))
            }
            if !historicGroundNeeded { return }
        }
        if let object = preparedGround {
            // In the band beneath the verse the near ground dissolves downward into mist and water,
            // instead of ending in a hard edge like an island floating on the paper.
            let b = object.bounds
            let canvas = scene == .historic ? engine.paintingInk(object.canv, depth: .far) : object.canv
            parts.append(groundInBand
                ? .init(canv: canvas, near: true, fade: .init(top: b.minY + b.height * 0.60,
                        bottom: b.maxY + b.height * 0.08, seed: engine.inkSeed()))
                : .near(canvas))
        }
        // Foreground slope: a small dark corner, not a second ground plane across the page.
        if scene != .historic, !narrow, !groundInBand, structure != .level, let object = fitted(engine.paintingBank(),
                                        to: slot(0.0, 0.52, 0.40, 0.48, front: true)) {
            parts.append(.near(object.canv))
            let r = object.bounds
            elements.append(.init(motif: "nearBank", bounds: .init(x: r.minX / w, y: r.minY / h,
                width: r.width / w, height: r.height / h)))
        }
    }

    func compose(scene: ZXArt.PoetryScene, options: ZXArt.SceneOptions) {
        currentScene = scene
        historicGroundNeeded = options.motifs.contains(.ruins) || options.motifs.contains(.cityGate)
        if [.retreat, .temple, .historic].contains(scene) {
            structure = composition == .depth ? .deep : .high
        } else {
            switch composition {
            case .corner: structure = .corner
            case .depth: structure = .deep
            case .oppositeBank: structure = .level
            }
        }
        if scene == .winterForest { engine.snowLight = 0.45 }
        ground(for: scene, prepareOnly: true)
        let chosen = Set(options.motifs)
        func include(_ motif: Motif, _ box: CGRect) { if chosen.contains(motif) { add(motif, box) } }
        if ![.desert, .ocean, .courtyard].contains(scene) { hills([.retreat, .temple, .historic].contains(scene)) }
        if [.fishing, .waterTown, .farewell, .lotusPond, .moonNight].contains(scene) { water() }
        for motif in [Motif.mist, .afterRain] where chosen.contains(motif) {
            if ![ZXArt.PoetryScene.retreat, .temple, .historic].contains(scene),
               let range = elements.first(where: { $0.motif == "farMountain" }) {
                // Existing distant ranges already dissolve into mist; do not add a third ridge.
                elements.append(.init(motif: motif.rawValue, bounds: range.bounds))
                placed.insert(motif)
                continue
            }
            let y = [.retreat, .temple, .historic].contains(scene) ? 0.58 : 0.16
            add(motif, slot(0.02, y, 0.96, 0.07))
        }
        // 一河两岸: scenes without a main peak get a pale far bank in the middle distance, so the
        // eye travels near bank → water → far bank → distant hills instead of across empty paper.
        let farShoreScenes: Set<ZXArt.PoetryScene> = [.fishing, .waterTown, .farewell, .village, .spring,
            .lotusPond, .autumnTravel, .winterForest, .moonNight]
        if farShoreScenes.contains(scene), structure == .level || structure == .deep,
           let shore = fitted(engine.paintingFarShore(), to: slot(0, composition == .oppositeBank ? 0.24 : 0.30, 1, 0.16)) {
            parts.append(.init(canv: shore.canv))
            elements.append(.init(motif: "farShore", bounds: .init(x: shore.bounds.minX / w, y: shore.bounds.minY / h,
                width: shore.bounds.width / w, height: shore.bounds.height / h)))
        }
        ground(for: scene)
        switch scene {
        case .retreat:
            include(.pine, slot(0.01, 0.20, 0.77, 0.64))
            include(.bamboo, slot(0.70, 0.55, 0.28, 0.29))
            if chosen.contains(.hut) { placeAtFoot(.hut, along: 0.72, height: 0.10, aspect: 1.7) }
            include(.stream, mountainStreamSlot())
        case .fishing:
            if chosen.contains(.angler) { add(.angler, slot(0.39, 0.58, 0.55, 0.14)) }
            else if chosen.contains(.sail) { add(.sail, slot(0.16, 0.47, 0.7, 0.29)) }
            else { include(.boat, slot(0.14, 0.62, 0.75, 0.15)) }
            // Reeds grow at the water's edge of the near bank, not floating below it.
            if chosen.contains(.reeds), let bank = elements.first(where: { $0.motif == "groundBank" })?.bounds.cgRect {
                let b = CGRect(x: bank.minX * w, y: bank.minY * h, width: bank.width * w, height: bank.height * h)
                let reedH = max(b.height * 2.4, h * 0.10)
                let towardWater = verse.isNull || verse.minX > w / 2
                add(.reeds, CGRect(x: towardWater ? b.maxX - b.width * 0.30 : b.minX - b.width * 0.05,
                                   y: b.maxY - reedH, width: b.width * 0.35, height: reedH))
            } else { include(.reeds, slot(0.03, 0.15, 0.27, 0.8, front: true)) }
        case .waterTown:
            include(.house, slot(0.53, 0.60, 0.43, 0.19))
            if chosen.contains(.house) { add(.house, slot(0.68, 0.61, 0.26, 0.12), repeatable: true) }
            include(.willow, slot(0.0, 0.14, 0.69, 0.64))
            if chosen.contains(.bridge) { crossing(river: true) }
            include(.mooredBoat, slot(0.78, 0.55, 0.20, 0.17, front: true))
        case .farewell:
            include(.pavilion, slot(0.33, 0.60, 0.29, 0.16))
            include(.willow, slot(0.01, 0.13, 0.70, 0.64))
            if chosen.contains(.traveler), let bank = elements.first(where: { $0.motif == "groundBank" })?.bounds.cgRect {
                let size = art.width * 0.043
                for fraction in [0.53, 0.57] {
                    let x = (bank.minX + bank.width * fraction) * w
                    if let foot = bankFoot(x - size * 0.2, x + size * 0.2) {
                        pinned = true
                        add(.traveler, CGRect(x: x - size * 0.3, y: foot - size, width: size * 0.6, height: size), repeatable: true)
                        pinned = false
                    }
                }
            }
            include(.path, slot(0.05, 0, 0.28, 0.8, front: true))
            include(.mooredBoat, slot(0.77, 0.55, 0.22, 0.17, front: true))
        case .village:
            add(chosen.contains(.pine) ? .pine : .layeredTree, slot(0.01, 0.20, 0.46, 0.53))
            include(chosen.contains(.hut) ? .hut : .house, slot(0.39, 0.56, 0.44, 0.18))
            if chosen.contains(.house) { add(.house, slot(0.67, 0.59, 0.30, 0.13), repeatable: true) }
            if chosen.contains(.cookingSmoke), let house = elements.first(where: { ["house", "hut"].contains($0.motif) })?.bounds.cgRect {
                let smokeHeight = house.height * h * 1.8
                add(.cookingSmoke, CGRect(x: (house.minX + house.width * 0.5) * w,
                    y: (house.minY + house.height * 0.15) * h - smokeHeight,
                    width: house.width * w * 0.3, height: smokeHeight))
            }
            include(.fields, slot(0.05, 0.0, 0.9, 0.92, front: true))
            // A low fence runs in front of the cottage's left side, lower than its eaves.
            if chosen.contains(.fence), let house = elements.first(where: { ["house", "hut"].contains($0.motif) })?.bounds.cgRect {
                let hb = CGRect(x: house.minX * w, y: house.minY * h, width: house.width * w, height: house.height * h)
                let fh = hb.height * 0.42, fw = hb.width * 1.1
                pinned = true
                add(.fence, CGRect(x: hb.minX - fw * 0.85, y: hb.maxY + hb.height * 0.06 - fh, width: fw, height: fh))
                pinned = false
            }
            include(.path, slot(0.65, 0.62, 0.24, 0.34))
        case .spring:
            include(.blossom, slot(0.0, 0.12, 0.76, 0.70))
            include(.layeredTree, slot(0.65, 0.34, 0.32, 0.47))
            include(.path, slot(0.2, 0.02, 0.48, 0.9, front: true))
        case .lotusPond:
            include(.lotus, slot(0.0, 0.05, 0.56, 0.90, front: true))
            include(.willow, slot(0.61, 0.03, 0.37, 0.59))
            if chosen.contains(.stream), let bank = elements.first(where: { $0.motif == "groundBank" })?.bounds.cgRect {
                // A spring entering a pond opens into shallow ripples at the bank, not a
                // freestanding mountain stream in the middle of the pool.
                let inlet = CGRect(x: bank.maxX * w - art.width * 0.03, y: bank.maxY * h,
                    width: art.width * 0.42, height: art.width * 0.08)
                layWater(waterEngine.paintingSurface(.pond, width: inlet.width, height: inlet.height),
                    in: inlet, motif: "stream")
                placed.insert(.stream)
            }
            // 早有蜻蜓立上头: the dragonfly perches on the bud's tip (bud sits ~55% across the asset).
            if chosen.contains(.dragonfly), let lotus = elements.first(where: { $0.motif == "lotus" })?.bounds.cgRect {
                let size = lotus.width * w * 0.16
                add(.dragonfly, CGRect(x: (lotus.minX + lotus.width * 0.55) * w - size / 2,
                    y: lotus.minY * h - size * 0.45, width: size, height: size * 0.5))
            }
        case .autumnTravel:
            include(chosen.contains(.oldTree) ? .oldTree : .bareTree, slot(0.0, 0.08, 0.76, 0.72))
            // The vine hangs from the old tree's crown; it never floats on its own.
            if chosen.contains(.vine), let tree = elements.first(where: { ["oldTree", "bareTree"].contains($0.motif) })?.bounds.cgRect {
                add(.vine, CGRect(x: (tree.minX + tree.width * 0.12) * w, y: (tree.minY + tree.height * 0.06) * h,
                    width: tree.width * w * 0.76, height: tree.height * h * 0.55))
            }
            if chosen.contains(.crow) { treeCrows() }
            include(.path, slot(0.05, 0, 0.52, 0.95, front: true))
            // Rider and horse share one ground plane and one scale (马与人同高): a small pair on the road.
            if chosen.contains(.horse), chosen.contains(.traveler) { journey() }
            else {
                include(.traveler, slot(0.50, 0.30, 0.045, 0.16, front: true))
                include(.horse, slot(0.555, 0.33, 0.10, 0.13, front: true))
            }
            if chosen.contains(.bridge) { crossing(river: false) }
            else { include(.stream, mountainStreamSlot()) }
        case .winterForest:
            include(.oldTree, slot(0.01, 0.18, 0.62, 0.64))
            include(.bareTree, slot(0.59, 0.22, 0.36, 0.56))
            if chosen.contains(.bareTree) { add(.bareTree, slot(0.40, 0.27, 0.20, 0.43), repeatable: true) }
            include(.house, slot(0.61, 0.73, 0.28, 0.10))
            // Snow is left as paper (roof, slope tops, branches); falling snow belongs to the weather layer.
            // It is still recorded, so weather and captions know the scene is snowbound.
            if chosen.contains(.snow), let bank = elements.first(where: { $0.motif == "groundBank" }) {
                elements.append(.init(motif: Motif.snow.rawValue, bounds: bank.bounds))
            }
            placed.insert(.snow)
        case .moonNight:
            add(.house, slot(0.23, 0.55, 0.65, 0.26))
            include(.window, slot(0.43, 0.67, 0.14, 0.14))
            include(.boat, slot(0.78, 0.55, 0.20, 0.18, front: true))
        case .temple:
            // The temple nestles at the mountain's foot: a gate in the fold, a pagoda beside it.
            if chosen.contains(.pagoda) { placeAtFoot(.pagoda, along: 0.32, height: 0.24, aspect: 0.42) }
            if chosen.contains(.templeGate) { placeAtFoot(.templeGate, along: 0.62, height: 0.12, aspect: 1.8) }
            include(.bamboo, slot(0.01, 0.50, 0.40, 0.32))
            include(.path, slot(0.15, 0, 0.45, 0.95, front: true))
        case .courtyard:
            // The wall stands on the ground beneath the verse; the willow grows behind it, its trunk
            // hidden by the wall, its crown heaped above into the open column (杨柳堆烟).
            let band = lowerBand(columnFrom: 0.45)
            let wallBox = CGRect(x: band.minX, y: band.minY + band.height * 0.10, width: band.width * 0.94,
                                 height: band.height * 0.86)
            if let wall = fitted(engine.paintingCourtyard(), to: wallBox) {
                // Root the willow just behind the wall's near end, so the wall hides its trunk.
                let willowW = art.width * 0.62
                let rootY = wall.bounds.minY + wall.bounds.height * 0.67
                let x = min(max(art.minX, wall.bounds.minX + wall.bounds.width * 0.18 - willowW / 2), art.maxX - willowW)
                // Its root is behind the wall: size the whole tree from that ground plane,
                // so the normal small near-tree multiplier does not hide the crown as well.
                pinned = true
                include(.willow, CGRect(x: x, y: art.minY, width: willowW, height: rootY - art.minY))
                pinned = false
                let r = wall.bounds
                parts.append(.init(canv: wall.canv, near: true,
                    fade: .init(top: r.minY + r.height * 0.76, bottom: r.maxY, seed: engine.inkSeed())))
                elements.append(.init(motif: Motif.courtyard.rawValue, bounds: .init(x: r.minX / w, y: r.minY / h,
                    width: r.width / w, height: r.height / h)))
                placed.insert(.courtyard)
                let near = CGRect(x: r.minX + r.width * 0.20, y: r.minY + r.height * 0.34,
                                  width: r.width * 0.12, height: r.height * 0.23)
                include(.window, near)
                include(.curtain, near.insetBy(dx: near.width * 0.12, dy: near.height * 0.10))
            }
        case .historic:
            // The summit itself is the platform; its rim is inset into the bearing rock.
            if let ledge = summitLedge {
                let left = ledge.minX + ledge.width * 0.12, right = ledge.maxX - ledge.width * 0.12
                let depth = max(0.8, ledge.width * 0.08)
                if chosen.contains(.terrace) {
                    let rim = engine.inkLine([.init(left, ledge.minY), .init(right, ledge.minY)],
                        width: 0.8, tone: 0.6, dry: 0.55)
                        + engine.inkLine([.init(left + 1, ledge.minY + depth), .init(right - 1, ledge.minY + depth)],
                            width: 0.5, tone: 0.32, dry: 0.65)
                    parts.append(.init(canv: rim))
                    engine.noted(.building(.pavilion), rim)
                    elements.append(.init(motif: "terrace", bounds: .init(x: left / w, y: ledge.minY / h,
                        width: (right - left) / w, height: depth / h)))
                    placed.insert(.terrace)
                }
                if chosen.contains(.traveler) {
                    let height = min(art.height * 0.028, ledge.width * 0.65)
                    let box = CGRect(x: ledge.midX - height * 0.25, y: ledge.minY - height,
                                     width: height * 0.5, height: height)
                    if let person = fitted(engine.paintingAsset(.traveler), to: box) {
                        parts.append(.init(canv: person.canv))
                        let b = person.bounds
                        elements.append(.init(motif: "traveler", bounds: .init(x: b.minX / w, y: b.minY / h,
                            width: b.width / w, height: b.height / h)))
                        placed.insert(.traveler)
                    }
                }
            }
            include(.ruins, slot(0.08, 0.62, 0.20, 0.12))
            include(.cityGate, slot(0.65, 0.58, 0.24, 0.16))
        case .desert:
            // 大漠孤烟直，长河落日圆: a low horizon under the verse and a vast sky. Far dunes, the
            // long river and the near dunes run the full width; the sun sits on the horizon and
            // the smoke rises from it on the other side.
            let full = lowerBand(columnFrom: 0.45)
            let horizon = full.minY
            if let far = fitted(engine.paintingDunes(far: true), to: CGRect(x: full.minX, y: horizon,
                width: full.width, height: full.height * 0.10)) {
                parts.append(.near(far.canv))
                elements.append(.init(motif: "farDunes", bounds: .init(x: far.bounds.minX / w, y: far.bounds.minY / h,
                    width: far.bounds.width / w, height: far.bounds.height / h)))
            }
            if chosen.contains(.stream) {
                layWater(engine.paintingInk(waterEngine.paintingRiverRibbon(), depth: .middle), in: CGRect(x: full.minX, y: horizon + full.height * 0.10,
                    width: full.width, height: full.height * 0.16), motif: "stream")
                placed.insert(.stream)
            }
            if let near = fitted(engine.paintingDunes(), to: CGRect(x: full.minX, y: horizon + full.height * 0.28,
                width: full.width, height: full.height * 0.72)) {
                parts.append(.near(near.canv))
                elements.append(.init(motif: Motif.dunes.rawValue, bounds: .init(x: near.bounds.minX / w,
                    y: near.bounds.minY / h, width: near.bounds.width / w, height: near.bounds.height / h)))
            }
            placed.insert(.dunes)
            let sunSize = min(w, h) * 0.085
            let sunX = verse.isNull || verse.minX > w / 2 ? art.minX + art.width * 0.55 : art.maxX - art.width * 0.55
            if chosen.contains(.sunset) {
                add(.sunset, CGRect(x: sunX - sunSize / 2, y: horizon - sunSize * 1.05, width: sunSize, height: sunSize))
            }
            if chosen.contains(.beaconSmoke) {
                let smokeX = verse.isNull || verse.minX > w / 2 ? art.minX + art.width * 0.15 : art.maxX - art.width * 0.15
                let smokeTop = max(art.minY, horizon - h * 0.32)
                add(.beaconSmoke, CGRect(x: smokeX - w * 0.04, y: smokeTop, width: w * 0.08, height: horizon - smokeTop))
            }
        case .ocean:
            // 海上生明月: a low sea horizon in the open column, the moon just clear of it with a
            // broken path of light beneath; bare water in between; rhythmic near waves across the
            // full width below the verse, and a dark reef in the near corner.
            let pad = min(w, h) * 0.045
            let horizon = art.minY + art.height * 0.36
            parts.append(.near(engine.inkLine([ZXArt.P(art.minX, horizon), ZXArt.P(art.minX + art.width * 0.45, horizon + 0.3),
                ZXArt.P(art.maxX, horizon - 0.2)], width: 0.7, tone: 0.28, dry: 0.5)))
            let lightMotif: Motif? = chosen.contains(.moon) ? .moon : (chosen.contains(.sunrise) ? .sunrise : nil)
            if let light = lightMotif {
                let size = art.width * 0.16
                let x = art.minX + art.width * 0.42
                add(light, CGRect(x: x - size / 2, y: horizon - size * 0.92, width: size, height: size))
                let path = CGRect(x: x - art.width * 0.07, y: horizon + 2, width: art.width * 0.14,
                                  height: max(6, lowerBand(columnFrom: 0.62).minY - horizon - 4))
                if let reflection = fitted(waterEngine.paintingReflection(width: path.width, height: path.height), to: path) {
                    parts.append(.near(reflection.canv))
                }
            }
            let near = lowerBand(columnFrom: 0.62)
            let raw = waterEngine.paintingSurface(.sea, width: near.width, height: near.height).map { p -> ZXArt.SSPoly in
                var q = p; q.p = p.p.map { .init($0.x + near.minX, $0.y + near.minY) }; return q
            }
            parts.append(.near(raw)); engine.noted(.water, raw)
            elements.append(.init(motif: Motif.waves.rawValue, bounds: .init(x: near.minX / w, y: near.minY / h,
                width: near.width / w, height: near.height / h)))
            placed.insert(.waves)
            if chosen.contains(.reef) {
                let reefBox = CGRect(x: verse.isNull || verse.minX > w / 2 ? near.maxX - near.width * 0.30 : near.minX,
                                     y: near.minY + near.height * 0.45, width: near.width * 0.30, height: near.height * 0.55)
                if let rock = fitted(engine.paintingRock(width: 120, height: 55, tone: 1.3), to: reefBox) {
                    parts.append(.near(rock.canv)); placed.insert(.reef)
                    elements.append(.init(motif: Motif.reef.rawValue, bounds: .init(x: rock.bounds.minX / w,
                        y: rock.bounds.minY / h, width: rock.bounds.width / w, height: rock.bounds.height / h)))
                }
            }
        }
        // Add textual accents after the main scene. Sky state is mutually exclusive and stays above the horizon.
        for motif in options.canonicalMotifs where !placed.contains(motif) {
            switch motif {
            case .boat where chosen.contains(.angler) || chosen.contains(.mooredBoat) || chosen.contains(.sail): continue
            case .moon where chosen.contains(.crescent): continue
            case .sunrise where chosen.contains(.moon) || chosen.contains(.crescent): continue
            case .sunset where chosen.contains(.moon) || chosen.contains(.crescent): continue
            case .moon, .crescent, .sunrise, .sunset: add(motif, celestialSlot(motif))
            case .stars: add(motif, slot(0.05, 0.0, 0.85, 0.18))
            case .cookingSmoke: add(motif, slot(0.56, 0.25, 0.15, 0.24))
            case .beaconSmoke: add(motif, slot(0.28, 0.22, 0.06, 0.4))
            case .egret: add(motif, slot(0.72, 0.60, 0.06, 0.08))
            case .butterfly:
                // A pair of butterflies near the blossoms, at the scale of a petal cluster.
                if let tree = elements.first(where: { ["blossom", "willow", "layeredTree"].contains($0.motif) })?.bounds.cgRect {
                    let size = max(5, tree.width * w * 0.07)
                    add(motif, CGRect(x: tree.maxX * w - size * 0.5, y: (tree.minY + tree.height * 0.30) * h,
                        width: size, height: size * 0.8))
                } else { add(motif, slot(0.48, 0.32, 0.04, 0.03)) }
            case .crow, .swallow, .dragonfly: add(motif, slot(0.30, 0.18, 0.07, 0.04))
            case .waterfall: add(motif, slot(0.15, 0.34, 0.18, 0.45))
            case .stream: add(motif, slot(0.60, 0.02, 0.22, 0.88, front: true))
            case .mist, .afterRain: add(motif, slot(0.02, 0.42, 0.96, 0.10))
            case .rain: break
            case .vine: continue // only ever hangs from a tree crown
            case .snow: continue // left as paper; the weather layer paints falling snow
            case .path: add(motif, slot(0.1, 0.1, 0.4, 0.8, front: true))
            case .reeds, .grass: add(motif, slot(0.03, 0.1, 0.20, 0.8, front: true))
            case .bridge: crossing(river: false)
            case .horse: add(motif, slot(0.60, 0.25, 0.28, 0.62, front: true))
            case .traveler: add(motif, slot(0.38, 0.66, 0.1, 0.12))
            default: add(motif, slot(0.01, 0.23, 0.48, 0.59))
            }
        }
        waterDetails()
    }
}
