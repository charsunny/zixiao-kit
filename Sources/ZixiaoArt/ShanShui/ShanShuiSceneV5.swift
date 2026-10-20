// shanshui@5 painting path. Preserve this version when adding future painting styles.
import CoreGraphics
import Foundation
import ZixiaoColor

extension ZXArt {
    /// Scene geometry has its own generator version and entropy stream. V3 brush rollout is unrelated.
    enum PoetryPaintingRenderer {
        static func generate(seed: Seed, size: CGSize, palette: Palette, scene: PoetryScene,
                             options: SceneOptions, quietTop: Double, verse: VerseLayout) -> (drawing: Drawing, trace: Trace) {
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
                        } else if record.motif == .moon, shapes[i].fill != nil {
                            shapes[i].fill = palette.ink.opacity(palette.isDark ? 0.48 : 0.08)
                        }
                    }
                }
                func appendLayer(_ layer: Layer) {
                    guard !layer.shapes.isEmpty else { return }
                    if part.near { nearSpans.append(.init(layer: layers.count, range: 0..<layer.shapes.count)) }
                    layers.append(layer)
                }
                if let m = part.mist {
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

/// A small composition vocabulary. Objects are fitted as whole objects, never cut into unreadable fragments.
private final class PaintingStage {
    typealias Motif = ZXArt.SceneMotif
    let engine: ShanShuiEngine
    let w: Double, h: Double
    let palette: ZXArt.Palette
    let verse: CGRect
    let art: CGRect
    let foreground: CGRect
    let purpose: ZXArt.ScenePurpose?
    let composition: ZXArt.SceneComposition?
    var parts: [ShanShuiEngine.Part] = []
    var elements: [ZXArt.SceneElement] = []
    var placed = Set<Motif>()
    var celestialLayers: [(layer: Int, motif: Motif)] = []
    var boats: [ZXArt.Anchors.Boat] = []
    var currentScene: ZXArt.PoetryScene = .retreat
    var bankSurface: (x0: Double, step: Double, heights: [Double])?

    init(seed: ZXArt.Seed, width: Double, height: Double, palette: ZXArt.Palette, verse: ZXArt.VerseLayout, quietTop: Double, options: ZXArt.SceneOptions) {
        self.w = width; self.h = height; self.palette = palette
        purpose = options.purpose; composition = options.composition
        self.verse = options.purpose == .reading ? .null : verse.rect(in: CGSize(width: width, height: height)).insetBy(dx: -8, dy: -8)
        engine = ShanShuiEngine(seed: .init("poetry-painting-v1:" + seed.string))
        engine.drawTowers = false
        engine.anchorLog = []
        let pad = min(width, height) * 0.045
        let top = max(pad, quietTop * height)
        if options.purpose == nil && options.composition == nil {
            switch verse.side {
            case .right:
                art = CGRect(x: pad, y: top, width: max(60, self.verse.minX - pad * 2), height: height - top - pad)
            case .left:
                art = CGRect(x: self.verse.maxX + pad, y: top,
                             width: max(60, width - self.verse.maxX - pad * 2), height: height - top - pad)
            case .top:
                if width > height * 1.3 {
                    art = CGRect(x: self.verse.maxX + pad, y: pad,
                                 width: max(60, width - self.verse.maxX - pad * 2), height: height - 2 * pad)
                } else {
                    art = CGRect(x: pad, y: max(top, self.verse.maxY + pad), width: width - 2 * pad,
                                 height: max(60, height - max(top, self.verse.maxY + pad) - pad))
                }
            }
            let bottomTop = max(self.verse.maxY + pad, height * 0.75)
            if width <= height * 1.3, bottomTop < height - pad - 40 {
                foreground = CGRect(x: pad, y: bottomTop, width: width - 2 * pad, height: height - bottomTop - pad)
            } else {
                foreground = CGRect(x: art.minX, y: art.minY + art.height * 0.72, width: art.width, height: art.height * 0.28)
            }
        } else {
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
            let low = options.purpose == .reading ? height * 0.74 : max(self.verse.maxY + pad, height * 0.74)
            if width <= height * 1.3, footer - low > 28 {
                foreground = CGRect(x: pad, y: low, width: width - 2 * pad, height: footer - low)
            } else {
                foreground = CGRect(x: art.minX, y: art.minY + art.height * 0.72,
                    width: art.width, height: art.height * 0.28)
            }
        }
    }

    private func slot(_ x: Double, _ y: Double, _ width: Double, _ height: Double, front: Bool = false) -> CGRect {
        let box = front ? foreground : art
        return CGRect(x: box.minX + x * box.width, y: box.minY + y * box.height,
                      width: width * box.width, height: height * box.height)
    }

    @discardableResult
    private func add(_ motif: Motif, _ box: CGRect, repeatable: Bool = false) -> Bool {
        guard repeatable || !placed.contains(motif) else { return false }
        let raw = motif == .stream && currentScene == .desert ? engine.paintingLongRiver() : engine.paintingAsset(motif)
        let placement = groundedSlot(motif, scaledSlot(motif, box))
        guard let object = fitted(raw, to: placement) else { return false }
        // Each object gets its own layer, retaining stable ordering and inspection metadata.
        let actual = object.bounds
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
        guard purpose != nil else { return requested }
        var maxWidth = requested.width, maxHeight = requested.height
        switch motif {
        case .house, .hut, .pavilion, .templeGate, .cityGate:
            let close = currentScene == .moonNight
            let village = currentScene == .village
            maxWidth = min(maxWidth, art.width * (close ? 0.50 : (village ? 0.33 : 0.26)))
            maxHeight = min(maxHeight, art.height * (close ? 0.18 : (village ? 0.14 : 0.11)))
            if let main = elements.first(where: { $0.motif == "mainMountain" }) {
                maxHeight = min(maxHeight, main.bounds.cgRect.height * h * 0.28)
            }
        case .pagoda:
            maxWidth = min(maxWidth, art.width * 0.14)
            maxHeight = min(maxHeight, art.height * 0.25)
            if let main = elements.first(where: { $0.motif == "mainMountain" }) {
                maxHeight = min(maxHeight, main.bounds.cgRect.height * h * 0.30)
            }
        case .pine, .oldTree, .bareTree, .layeredTree, .willow, .blossom, .maple:
            let mountainScene = [ZXArt.PoetryScene.retreat, .temple, .historic].contains(currentScene)
            maxHeight = min(maxHeight, min(art.height * (mountainScene ? 0.46 : 0.62), art.width * (mountainScene ? 0.85 : 0.65)))
            if let main = elements.first(where: { $0.motif == "mainMountain" }) {
                maxHeight = min(maxHeight, main.bounds.cgRect.height * h * 0.68)
            }
        case .bamboo:
            maxHeight = min(maxHeight, art.height * 0.25)
            if let main = elements.first(where: { $0.motif == "mainMountain" }) {
                maxHeight = min(maxHeight, main.bounds.cgRect.height * h * 0.42)
            }
        default: break
        }
        return CGRect(x: requested.midX - maxWidth / 2, y: requested.maxY - maxHeight,
            width: maxWidth, height: maxHeight)
    }

    /// Buildings and trees meet the actual bank silhouette, not independent percentage baselines.
    private func groundedSlot(_ motif: Motif, _ requested: CGRect) -> CGRect {
        guard purpose != nil else { return requested }
        if motif == .window, currentScene == .moonNight,
           let house = elements.first(where: { $0.motif == "house" })?.bounds.cgRect {
            return CGRect(x: (house.minX + house.width * 0.32) * w,
                y: (house.minY + house.height * 0.60) * h, width: house.width * w * 0.14, height: house.height * h * 0.22)
        }
        let rooted: Set<Motif> = [.oldTree, .bareTree, .layeredTree, .pine, .bamboo, .willow,
            .blossom, .maple, .house, .hut, .pavilion, .pagoda, .templeGate, .cityGate]
        guard rooted.contains(motif), let surface = bankSurface else { return requested }
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
        return CGRect(x: requested.minX, y: y - requested.height, width: requested.width, height: requested.height)
    }

    private func recordBank(_ object: (canv: ZXArt.SSCanv, bounds: CGRect)) {
        guard purpose != nil else { return }
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
        guard rooted.contains(motif) else { return }
        let buildings: Set<Motif> = [.house, .hut, .pavilion, .pagoda, .templeGate, .cityGate]
        let height = purpose != nil && buildings.contains(motif)
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
        for k in 0..<2 {
            let raw = engine.paintingDistant(k)
            let box = slot(composition == .depth ? Double(k) * 0.10 : 0,
                0.07 + Double(k) * (composition == .oppositeBank ? 0.10 : 0.17),
                composition == .depth ? 0.88 : 1, 0.29)
            if let object = fitted(raw, to: box) {
                parts.append(.init(canv: object.canv, mist: .init(depth: object.bounds.height * 3,
                    blur: 0.7, peak: 0.92, floorY: object.bounds.maxY, floorDepth: object.bounds.height * 0.6)))
                engine.noted(.ridge(.far), object.canv)
            }
        }
        if main, let object = fitted(engine.paintingMountain(standalone: purpose != nil), to: slot(0.02, 0.01, 0.95, 0.75)) {
            parts.append(.init(canv: object.canv))
            engine.noted(.ridge(.main), object.canv)
            if purpose != nil {
                let r = object.bounds
                elements.append(.init(motif: "mainMountain", bounds: .init(x: r.minX / w, y: r.minY / h,
                    width: r.width / w, height: r.height / h)))
            }
        }
    }

    private func water() {
        let raw = engine.paintingAsset(.waves)
        if let object = fitted(raw, to: slot(0, 0.78, 1, 0.17)) {
            parts.append(.near(object.canv)); engine.noted(.water, object.canv)
        }
        if let object = fitted(raw, to: slot(0, 0.24, 1, 0.63, front: true)) {
            parts.append(.near(object.canv)); engine.noted(.water, object.canv)
        }
    }

    private func ground(for scene: ZXArt.PoetryScene) {
        guard ![.desert, .ocean].contains(scene) else { return }
        let narrow = [.fishing, .lotusPond].contains(scene)
        let box: CGRect
        if composition == .oppositeBank { box = slot(0.01, 0.63, narrow ? 0.42 : 1, 0.14) }
        else { box = narrow ? slot(0.01, 0.67, 0.34, 0.25) : slot(0, 0.65, 1, 0.22) }
        if let object = fitted(engine.paintingBank(), to: box) {
            parts.append(.near(object.canv))
            recordBank(object)
        }
        if !narrow, let object = fitted(engine.paintingBank(),
                                        to: slot(0.0, 0.12, 0.75, 0.74, front: true)) {
            parts.append(.near(object.canv))
        }
    }

    func compose(scene: ZXArt.PoetryScene, options: ZXArt.SceneOptions) {
        currentScene = scene
        let chosen = Set(options.motifs)
        func include(_ motif: Motif, _ box: CGRect) { if chosen.contains(motif) { add(motif, box) } }
        if ![.desert, .ocean, .courtyard].contains(scene) { hills([.retreat, .temple, .historic].contains(scene)) }
        if [.fishing, .waterTown, .farewell, .lotusPond, .moonNight, .ocean].contains(scene) { water() }
        for motif in [Motif.mist, .afterRain] where chosen.contains(motif) {
            add(motif, slot(0.02, 0.16, 0.96, 0.10))
        }
        ground(for: scene)
        switch scene {
        case .retreat:
            include(.pine, slot(0.01, 0.20, 0.77, 0.64))
            include(.bamboo, slot(0.70, 0.55, 0.28, 0.29))
            include(.hut, slot(0.50, 0.72, 0.35, 0.12))
            include(.stream, slot(0.43, 0.75, 0.24, 0.21))
        case .fishing:
            if chosen.contains(.angler) { add(.angler, slot(0.39, 0.58, 0.55, 0.14)) }
            else if chosen.contains(.sail) { add(.sail, slot(0.16, 0.47, 0.7, 0.29)) }
            else { include(.boat, slot(0.14, 0.62, 0.75, 0.15)) }
            include(.reeds, slot(0.03, 0.15, 0.27, 0.8, front: true))
        case .waterTown:
            include(.house, slot(0.53, 0.60, 0.43, 0.19))
            if chosen.contains(.house) { add(.house, slot(0.68, 0.61, 0.26, 0.12), repeatable: true) }
            include(.willow, slot(0.0, 0.14, 0.69, 0.64))
            include(.bridge, slot(0.08, 0.14, 0.52, 0.33, front: true))
            include(.mooredBoat, slot(0.64, 0.51, 0.25, 0.14, front: true))
        case .farewell:
            include(.willow, slot(0.01, 0.13, 0.70, 0.64))
            include(.pavilion, slot(0.66, 0.60, 0.29, 0.16))
            include(.traveler, slot(0.56, 0.72, 0.07, 0.09))
            if chosen.contains(.traveler) { add(.traveler, slot(0.67, 0.73, 0.06, 0.08), repeatable: true) }
            include(.path, slot(0.05, 0, 0.28, 0.8, front: true))
            include(.mooredBoat, slot(0.60, 0.55, 0.30, 0.17, front: true))
        case .village:
            if purpose == nil { include(.cookingSmoke, slot(0.56, 0.33, 0.12, 0.24)) }
            add(.layeredTree, slot(0.01, 0.20, 0.46, 0.53))
            include(.house, slot(0.39, 0.56, 0.44, 0.18))
            if chosen.contains(.house) { add(.house, slot(0.67, 0.59, 0.30, 0.13), repeatable: true) }
            if purpose != nil, chosen.contains(.cookingSmoke), let house = elements.first(where: { $0.motif == "house" })?.bounds.cgRect {
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
            include(.lotus, slot(0.0, 0.33, 0.94, 0.52))
            include(.willow, slot(0.61, 0.03, 0.37, 0.59))
            include(.dragonfly, slot(0.24, 0.33, 0.18, 0.08))
        case .autumnTravel:
            include(.bareTree, slot(0.0, 0.08, 0.76, 0.72))
            include(.vine, slot(0.18, 0.21, 0.30, 0.35))
            include(.crow, slot(0.12, 0.23, 0.13, 0.08))
            include(.path, slot(0.05, 0, 0.52, 0.95, front: true))
            include(.traveler, slot(0.49, 0.72, 0.06, 0.08))
            include(.horse, slot(0.58, 0.26, 0.18, 0.44, front: true))
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
            include(.boat, slot(0.08, 0.65, 0.5, 0.14, front: true))
        case .temple:
            include(.templeGate, slot(0.52, 0.61, 0.44, 0.20))
            include(.pagoda, purpose == nil ? slot(0.04, 0.20, 0.22, 0.32) : slot(0.06, 0.48, 0.14, 0.25))
            include(.bamboo, slot(0.01, 0.50, 0.40, 0.32))
            include(.path, slot(0.15, 0, 0.45, 0.95, front: true))
        case .courtyard:
            include(.courtyard, slot(0, 0.36, 1, 0.49))
            include(.window, slot(0.07, 0.45, 0.32, 0.27))
            include(.curtain, slot(0.09, 0.46, 0.27, 0.23))
            include(.willow, slot(0.58, 0.02, 0.40, 0.61))
        case .historic:
            include(.cityGate, slot(0.56, 0.61, 0.37, 0.18))
            include(.terrace, slot(0.02, 0.05, 0.65, 0.56, front: true))
            include(.ruins, slot(0.67, 0.48, 0.3, 0.31, front: true))
            include(.traveler, slot(0.30, 0.65, 0.10, 0.12))
        case .desert:
            include(.dunes, slot(0, 0.4, 1, 0.44))
            if chosen.contains(.dunes) { add(.dunes, slot(0, 0.2, 1, 0.75, front: true), repeatable: true) }
            include(.stream, slot(0.02, 0.74, 0.96, 0.12))
        case .ocean:
            include(.waves, slot(0, 0.35, 1, 0.54))
            include(.reef, slot(0.68, 0.35, 0.29, 0.5, front: true))
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
            case .egret: add(motif, slot(0.7, 0.58, 0.13, 0.17))
            case .crow, .swallow, .dragonfly, .butterfly: add(motif, slot(0.48, 0.32, 0.17, 0.12))
            case .waterfall: add(motif, slot(0.15, 0.34, 0.18, 0.45))
            case .stream: add(motif, slot(0.60, 0.02, 0.22, 0.88, front: true))
            case .mist, .afterRain: add(motif, slot(0.02, 0.42, 0.96, 0.10))
            case .rain: break
            case .snow: add(motif, slot(0, 0.2, 1, 0.65, front: true))
            case .path: add(motif, slot(0.1, 0.1, 0.4, 0.8, front: true))
            case .reeds, .grass: add(motif, slot(0.03, 0.1, 0.20, 0.8, front: true))
            case .horse: add(motif, slot(0.60, 0.25, 0.28, 0.62, front: true))
            case .traveler: add(motif, slot(0.38, 0.66, 0.1, 0.12))
            default: add(motif, slot(0.01, 0.23, 0.48, 0.59))
            }
        }
    }
}
