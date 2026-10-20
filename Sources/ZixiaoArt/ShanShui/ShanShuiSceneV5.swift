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
                ZXArt.appendShapes(part.canv, palette: palette, into: &shapes)
                if let record = stage.celestialLayers.first(where: { $0.layer == index }) {
                    for i in shapes.indices {
                        if record.motif == .sunset || record.motif == .sunrise {
                            shapes[i].fill = ZXHex(red: 0.67, green: 0.25, blue: 0.20).opacity(palette.isDark ? 0.40 : 0.26)
                        } else if record.motif == .moon, palette.isDark, let fill = shapes[i].fill {
                            // On dark paper the moon is the light: a bright disc, a faint halo.
                            shapes[i].fill = palette.ink.opacity(fill.alpha > 0.9 ? 0.52 : 0.05)
                        }
                    }
                }
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
                    appendLayer(.init(wash: .init(bleed: 0.8, rim: 0.10, grain: 0.12), shapes: wet))
                    appendLayer(.init(tooth: 0.18, shapes: shapes))
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
    let purpose: ZXArt.ScenePurpose
    let composition: ZXArt.SceneComposition
    let seed: String
    var parts: [ShanShuiEngine.Part] = []
    var elements: [ZXArt.SceneElement] = []
    var placed = Set<Motif>()
    var celestialLayers: [(layer: Int, motif: Motif)] = []
    var boats: [ZXArt.Anchors.Boat] = []
    var currentScene: ZXArt.PoetryScene = .retreat
    var bankSurface: (x0: Double, step: Double, heights: [Double])?
    var groundInBand = false
    var mainSummit: ZXArt.P?
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
    private func add(_ motif: Motif, _ box: CGRect, repeatable: Bool = false) -> Bool {
        guard repeatable || !placed.contains(motif) else { return false }
        let raw: ZXArt.SSCanv
        if motif == .stream {
            raw = currentScene == .desert ? waterEngine.paintingLongRiver()
                : waterEngine.paintingChannel(width: box.width, height: box.height)
        } else { raw = engine.paintingAsset(motif) }
        let scaled = scaledSlot(motif, box)
        let placement = motif == .window ? groundedSlot(motif, scaled) : scaled
        guard var object = fitted(raw, to: placement) else { return false }
        if motif != .window {
            // Ground the fitted object: its actual canopy / roof size can be much smaller than the slot.
            let landed = groundedSlot(motif, object.bounds)
            if landed != object.bounds {
                guard let moved = fitted(raw, to: landed) else { return false }
                object = moved
            }
        }
        // Each object gets its own layer, retaining stable ordering and inspection metadata.
        let actual = object.bounds
        if motif == .stream { engine.noted(.water, object.canv) }
        support(motif, bounds: actual)
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
        case .house, .hut, .pavilion, .templeGate, .cityGate:
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
            maxHeight = min(maxHeight, min(art.height * (mountainScene ? 0.46 : 0.62), art.width * (mountainScene ? 0.85 : 0.65)))
            if let main = elements.first(where: { $0.motif == "mainMountain" }) {
                maxHeight = min(maxHeight, main.bounds.cgRect.height * h * 0.28)
            }
        case .bamboo:
            maxHeight = min(maxHeight, art.height * 0.25)
            if let main = elements.first(where: { $0.motif == "mainMountain" }) {
                maxHeight = min(maxHeight, main.bounds.cgRect.height * h * 0.16)
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

    /// Buildings and trees meet the actual bank silhouette, not independent percentage baselines.
    private func groundedSlot(_ motif: Motif, _ requested: CGRect) -> CGRect {
        if motif == .window, currentScene == .moonNight,
           let house = elements.first(where: { $0.motif == "house" })?.bounds.cgRect {
            return CGRect(x: (house.minX + house.width * 0.32) * w,
                y: (house.minY + house.height * 0.60) * h, width: house.width * w * 0.14, height: house.height * h * 0.22)
        }
        let rooted: Set<Motif> = [.oldTree, .bareTree, .layeredTree, .pine, .bamboo, .willow,
            .blossom, .maple, .house, .hut, .pavilion, .pagoda, .templeGate, .cityGate, .fence]
        guard rooted.contains(motif), let surface = bankSurface else { return requested }
        var requested = requested
        let building = [Motif.house, .hut, .pavilion, .pagoda, .templeGate, .cityGate].contains(motif)
        let endX = surface.x0 + surface.step * Double(surface.heights.count - 1)
        let radius = min((endX - surface.x0) * 0.45, building ? requested.width * 0.36 : min(8, requested.width * 0.1))
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
        if [.house, .hut, .pavilion, .pagoda, .templeGate, .cityGate].contains(motif) {
            // A broad foundation must reach the lower bank under both walls, not perch on a single high stone.
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
        }
        return landed
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
    private func support(_ motif: Motif, bounds: CGRect) {
        let rooted: Set<Motif> = [.oldTree, .bareTree, .layeredTree, .pine, .bamboo, .willow,
            .blossom, .maple, .house, .hut, .pavilion, .pagoda, .templeGate, .cityGate,
            .courtyard, .terrace, .ruins]
        guard rooted.contains(motif), currentScene != .courtyard else { return }
        let buildings: Set<Motif> = [.house, .hut, .pavilion, .pagoda, .templeGate, .cityGate]
        let height = buildings.contains(motif)
            ? max(1, min(4, bounds.height * 0.10)) : min(24, max(5, bounds.height * 0.13))
        let box = CGRect(x: max(art.minX, bounds.minX - 3), y: bounds.maxY - height * 0.15,
            width: min(art.width, bounds.width + 8), height: height)
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
        for k in 0..<2 {
            let raw = engine.paintingDistant(k)
            let width = 0.58 + engine.r() * 0.16
            let x = (k == 0) == side ? 1 - width : 0.0
            let box = slot(x, 0.06 + Double(k) * (composition == .oppositeBank ? 0.10 : 0.15), width, 0.24)
            if let object = fitted(raw, to: box) {
                // Crest stays legible; the body dissolves downward into mist.
                parts.append(.init(canv: object.canv, mist: .init(depth: object.bounds.height * 1.1,
                    blur: 0.35, peak: 0.95, floorY: object.bounds.maxY, floorDepth: object.bounds.height * 0.7)))
                engine.noted(.ridge(.far), object.canv)
            }
        }
        if main, let object = fitted(engine.paintingMountain(), to: slot(0.02, 0.01, 0.95, 0.75)) {
            // 山腰云锁: the lower third of the main peak dissolves into cloud instead of
            // standing on the bank like a monument.
            let r = object.bounds
            parts.append(.init(canv: object.canv))
            parts.append(.init(canv: engine.paintingCloud(over: r), plain: true))
            // The true summit: the highest point of the outline in the middle half of the peak.
            let core = object.canv.flatMap(\.p).filter { $0.x > r.minX + r.width * 0.25 && $0.x < r.maxX - r.width * 0.25 }
            mainSummit = core.min { $0.y < $1.y }
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

    private func mountainStreamSlot() -> CGRect {
        guard let bank = elements.first(where: { $0.motif == "groundBank" })?.bounds.cgRect else {
            return slot(0.27, 0.67, 0.30, 0.30)
        }
        let obstacles = elements.filter { ["pine", "bamboo", "hut"].contains($0.motif) }
            .map { $0.bounds.cgRect }.sorted { $0.minX < $1.minX }
        var gaps: [(Double, Double)] = [], cursor = bank.minX + bank.width * 0.12
        for obstacle in obstacles {
            if obstacle.minX > cursor { gaps.append((cursor, obstacle.minX)) }
            cursor = max(cursor, obstacle.maxX)
        }
        gaps.append((cursor, bank.maxX - bank.width * 0.08))
        let viable = gaps.filter { $0.1 - $0.0 > bank.width * 0.08 }
        let gap = viable.min { abs(($0.0 + $0.1) / 2 - bank.midX) < abs(($1.0 + $1.1) / 2 - bank.midX) }
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

    private func ground(for scene: ZXArt.PoetryScene) {
        guard ![.desert, .ocean, .courtyard, .historic].contains(scene) else { return }
        let narrow = [.fishing, .lotusPond].contains(scene)
        var box: CGRect
        if composition == .oppositeBank { box = slot(0.01, 0.63, narrow ? 0.42 : 1, 0.14) }
        else { box = narrow ? slot(0.01, 0.67, 0.34, 0.25) : slot(0, 0.65, 1, 0.22) }
        // Inscribed portrait: the verse fills the sky on one side, so the ground runs the full
        // width of the band beneath it, the way a hanging scroll's foreground spans the paper.
        if !verse.isNull, w <= h * 1.3, verse.maxY < h * 0.82 {
            let pad = min(w, h) * 0.045
            let top = verse.maxY + pad * 0.4, bottom = min(foreground.maxY, h - pad)
            let width = (w - 2 * pad) * (narrow ? 0.5 : 1)
            let x = verse.minX > w / 2 || narrow ? pad : w - pad - width
            box = CGRect(x: x, y: top, width: width, height: max(20, min(bottom - top, h * 0.13)))
            groundInBand = true
        }
        if let object = fitted(engine.paintingBank(), to: box) {
            parts.append(.near(object.canv))
            recordBank(object)
        }
        // Foreground slope: a small dark corner, not a second ground plane across the page.
        if !narrow, !groundInBand, let object = fitted(engine.paintingBank(),
                                        to: slot(0.0, 0.52, 0.40, 0.48, front: true)) {
            parts.append(.near(object.canv))
            let r = object.bounds
            elements.append(.init(motif: "nearBank", bounds: .init(x: r.minX / w, y: r.minY / h,
                width: r.width / w, height: r.height / h)))
        }
    }

    func compose(scene: ZXArt.PoetryScene, options: ZXArt.SceneOptions) {
        currentScene = scene
        let chosen = Set(options.motifs)
        func include(_ motif: Motif, _ box: CGRect) { if chosen.contains(motif) { add(motif, box) } }
        if ![.desert, .ocean, .courtyard].contains(scene) { hills([.retreat, .temple, .historic].contains(scene)) }
        if [.fishing, .waterTown, .farewell, .lotusPond, .moonNight].contains(scene) { water() }
        for motif in [Motif.mist, .afterRain] where chosen.contains(motif) {
            add(motif, slot(0.02, 0.16, 0.96, 0.10))
        }
        // 一河两岸: scenes without a main peak get a pale far bank in the middle distance, so the
        // eye travels near bank → water → far bank → distant hills instead of across empty paper.
        let farShoreScenes: Set<ZXArt.PoetryScene> = [.fishing, .waterTown, .farewell, .village, .spring,
            .lotusPond, .autumnTravel, .winterForest, .moonNight]
        if farShoreScenes.contains(scene),
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
            include(.hut, slot(0.50, 0.72, 0.35, 0.12))
            include(.stream, mountainStreamSlot())
        case .fishing:
            if chosen.contains(.angler) { add(.angler, slot(0.39, 0.58, 0.55, 0.14)) }
            else if chosen.contains(.sail) { add(.sail, slot(0.16, 0.47, 0.7, 0.29)) }
            else { include(.boat, slot(0.14, 0.62, 0.75, 0.15)) }
            include(.reeds, slot(0.03, 0.15, 0.27, 0.8, front: true))
        case .waterTown:
            include(.house, slot(0.53, 0.60, 0.43, 0.19))
            if chosen.contains(.house) { add(.house, slot(0.68, 0.61, 0.26, 0.12), repeatable: true) }
            include(.willow, slot(0.0, 0.14, 0.69, 0.64))
            let channel = slot(0.06, 0.14, 0.56, 0.80, front: true)
            layWater(waterEngine.paintingChannel(width: channel.width, height: channel.height, river: true),
                in: channel, motif: "riverChannel")
            include(.bridge, slot(0.08, 0.14, 0.52, 0.33, front: true))
            include(.mooredBoat, slot(0.78, 0.55, 0.20, 0.17, front: true))
        case .farewell:
            include(.willow, slot(0.01, 0.13, 0.70, 0.64))
            include(.pavilion, slot(0.66, 0.60, 0.29, 0.16))
            include(.traveler, slot(0.56, 0.72, 0.07, 0.09))
            if chosen.contains(.traveler) { add(.traveler, slot(0.67, 0.73, 0.06, 0.08), repeatable: true) }
            include(.path, slot(0.05, 0, 0.28, 0.8, front: true))
            include(.mooredBoat, slot(0.77, 0.55, 0.22, 0.17, front: true))
        case .village:
            add(.layeredTree, slot(0.01, 0.20, 0.46, 0.53))
            include(.house, slot(0.39, 0.56, 0.44, 0.18))
            if chosen.contains(.house) { add(.house, slot(0.67, 0.59, 0.30, 0.13), repeatable: true) }
            if chosen.contains(.cookingSmoke), let house = elements.first(where: { $0.motif == "house" })?.bounds.cgRect {
                let smokeHeight = house.height * h * 1.8
                add(.cookingSmoke, CGRect(x: (house.minX + house.width * 0.5) * w,
                    y: (house.minY + house.height * 0.15) * h - smokeHeight,
                    width: house.width * w * 0.3, height: smokeHeight))
            }
            include(.fields, slot(0.05, 0.0, 0.9, 0.92, front: true))
            include(.fence, slot(0.10, 0.76, 0.66, 0.06))
            include(.path, slot(0.65, 0.62, 0.24, 0.34))
        case .spring:
            include(.blossom, slot(0.0, 0.12, 0.76, 0.70))
            include(.layeredTree, slot(0.65, 0.34, 0.32, 0.47))
            include(.path, slot(0.2, 0.02, 0.48, 0.9, front: true))
        case .lotusPond:
            include(.lotus, slot(0.0, 0.10, 0.60, 0.62, front: true))
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
            include(.bareTree, slot(0.0, 0.08, 0.76, 0.72))
            // The vine hangs from the old tree's crown; it never floats on its own.
            if chosen.contains(.vine), let tree = elements.first(where: { $0.motif == "bareTree" })?.bounds.cgRect {
                add(.vine, CGRect(x: (tree.minX + tree.width * 0.12) * w, y: (tree.minY + tree.height * 0.06) * h,
                    width: tree.width * w * 0.76, height: tree.height * h * 0.55))
            }
            include(.crow, slot(0.12, 0.23, 0.13, 0.08))
            include(.path, slot(0.05, 0, 0.52, 0.95, front: true))
            // Rider and horse share one ground plane and one scale (马与人同高): a small pair on the road.
            include(.traveler, slot(0.50, 0.30, 0.045, 0.16, front: true))
            include(.horse, slot(0.555, 0.33, 0.10, 0.13, front: true))
            include(.bridge, slot(0.01, 0.08, 0.42, 0.29, front: true))
            include(.stream, slot(0.02, 0.36, 0.35, 0.55, front: true))
        case .winterForest:
            include(.oldTree, slot(0.01, 0.18, 0.62, 0.64))
            include(.bareTree, slot(0.59, 0.22, 0.36, 0.56))
            if chosen.contains(.bareTree) { add(.bareTree, slot(0.40, 0.27, 0.20, 0.43), repeatable: true) }
            include(.house, slot(0.61, 0.73, 0.28, 0.10))
            include(.snow, slot(0, 0.1, 1, 0.8, front: true))
        case .moonNight:
            add(.house, slot(0.23, 0.55, 0.65, 0.26))
            include(.window, slot(0.43, 0.67, 0.14, 0.14))
            include(.boat, slot(0.78, 0.55, 0.20, 0.18, front: true))
        case .temple:
            include(.templeGate, slot(0.52, 0.61, 0.44, 0.20))
            include(.pagoda, slot(0.06, 0.48, 0.14, 0.25))
            include(.bamboo, slot(0.01, 0.50, 0.40, 0.32))
            include(.path, slot(0.15, 0, 0.45, 0.95, front: true))
        case .courtyard:
            // The wall stands on the ground beneath the verse; the willow grows behind it, its trunk
            // hidden by the wall, its crown heaped above into the open column (杨柳堆烟).
            let pad = min(w, h) * 0.045
            let top = verse.isNull ? h * 0.55 : verse.maxY + pad * 0.4
            let wallBox = CGRect(x: pad, y: top + (h - pad - top) * 0.10, width: (w - 2 * pad) * 0.94,
                                 height: (h - pad - top) * 0.86)
            if let wall = fitted(engine.paintingCourtyard(), to: wallBox) {
                let leftSide = verse.isNull || verse.minX > w / 2
                let willowW = art.width * 0.62
                let rootY = wall.bounds.minY + wall.bounds.height * 0.32
                include(.willow, CGRect(x: leftSide ? art.minX + art.width * 0.04 : art.maxX - willowW,
                                        y: art.minY, width: willowW, height: rootY - art.minY))
                parts.append(.near(wall.canv))
                let r = wall.bounds
                elements.append(.init(motif: Motif.courtyard.rawValue, bounds: .init(x: r.minX / w, y: r.minY / h,
                    width: r.width / w, height: r.height / h)))
                placed.insert(.courtyard)
                let near = CGRect(x: r.minX + r.width * 0.06, y: r.minY + r.height * 0.34,
                                  width: r.width * 0.18, height: r.height * 0.30)
                include(.window, near)
                include(.curtain, near.insetBy(dx: near.width * 0.12, dy: near.height * 0.10))
            }
        case .historic:
            // 念天地之悠悠: one high peak in cloud and a single tiny figure on its summit, facing
            // the open side of the page. No pavilion, no steps; the emptiness is the subject.
            if chosen.contains(.traveler), let summit = mainSummit {
                let size = h * 0.034
                add(.traveler, CGRect(x: summit.x - size * 0.3, y: summit.y + size * 0.30 - size,
                                      width: size * 0.6, height: size))
            }
            placed.formUnion([.terrace, .ruins, .cityGate, .traveler])
        case .desert:
            // 大漠孤烟直，长河落日圆: a low horizon under the verse and a vast sky. Far dunes, the
            // long river and the near dunes run the full width; the sun sits on the horizon and
            // the smoke rises from it on the other side.
            let pad = min(w, h) * 0.045
            let horizon = verse.isNull ? h * 0.62 : max(verse.maxY + pad * 0.6, h * 0.55)
            let full = CGRect(x: pad, y: horizon, width: w - 2 * pad, height: h - pad - horizon)
            if let far = fitted(engine.paintingDunes(far: true), to: CGRect(x: full.minX, y: horizon,
                width: full.width, height: full.height * 0.10)) {
                parts.append(.near(far.canv))
            }
            if chosen.contains(.stream) {
                layWater(waterEngine.paintingRiverRibbon(), in: CGRect(x: full.minX, y: horizon + full.height * 0.10,
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
            let sunSize = w * 0.09
            let sunX = verse.isNull || verse.minX > w / 2 ? art.minX + art.width * 0.55 : art.maxX - art.width * 0.55
            if chosen.contains(.sunset) {
                add(.sunset, CGRect(x: sunX - sunSize / 2, y: horizon - sunSize * 1.05, width: sunSize, height: sunSize))
            }
            if chosen.contains(.beaconSmoke) {
                let smokeX = verse.isNull || verse.minX > w / 2 ? art.minX + art.width * 0.15 : art.maxX - art.width * 0.15
                add(.beaconSmoke, CGRect(x: smokeX - w * 0.04, y: horizon - h * 0.32, width: w * 0.08, height: h * 0.32))
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
                                  height: (verse.isNull ? h * 0.7 : verse.maxY) - horizon - 4)
                if let reflection = fitted(waterEngine.paintingReflection(width: path.width, height: path.height), to: path) {
                    parts.append(.near(reflection.canv))
                }
            }
            let top = verse.isNull ? h * 0.62 : verse.maxY + pad * 0.3
            let near = CGRect(x: pad, y: top, width: w - 2 * pad, height: h - pad - top)
            let raw = waterEngine.paintingSurface(.sea, width: near.width, height: near.height).map { p -> ZXArt.SSPoly in
                var q = p; q.p = p.p.map { .init($0.x + near.minX, $0.y + near.minY) }; return q
            }
            parts.append(.near(raw)); engine.noted(.water, raw)
            elements.append(.init(motif: Motif.waves.rawValue, bounds: .init(x: near.minX / w, y: near.minY / h,
                width: near.width / w, height: near.height / h)))
            placed.insert(.waves)
            if chosen.contains(.reef) {
                let reefBox = CGRect(x: verse.isNull || verse.minX > w / 2 ? w - pad - near.width * 0.30 : pad,
                                     y: near.minY + near.height * 0.45, width: near.width * 0.30, height: near.height * 0.55)
                if let rock = fitted(engine.paintingRock(width: 120, height: 55, tone: 1.3), to: reefBox) {
                    parts.append(.near(rock.canv)); placed.insert(.reef)
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
            case .moon, .crescent, .sunrise, .sunset: add(motif, slot(0.61, 0.06, 0.16, 0.12))
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
            case .snow: add(motif, slot(0, 0.2, 1, 0.65, front: true))
            case .path: add(motif, slot(0.1, 0.1, 0.4, 0.8, front: true))
            case .reeds, .grass: add(motif, slot(0.03, 0.1, 0.20, 0.8, front: true))
            case .horse: add(motif, slot(0.60, 0.25, 0.28, 0.62, front: true))
            case .traveler: add(motif, slot(0.38, 0.66, 0.1, 0.12))
            default: add(motif, slot(0.01, 0.23, 0.48, 0.59))
            }
        }
        waterDetails()
    }
}
