// shanshui@5 painting path. Preserve this version when adding future painting styles.
import Foundation

extension ShanShuiEngine {
    func paintingAsset(_ motif: ZXArt.SceneMotif) -> ZXArt.SSCanv {
        switch motif {
        case .pine, .oldTree, .bareTree, .layeredTree, .willow, .blossom, .maple: return paintingTree(motif)
        case .bamboo: return paintingBamboo()
        case .lotus: return paintingLotus()
        case .bridge: return paintingBridge()
        case .house, .hut: return paintingHouse()
        case .pavilion: return paintingPavilion()
        case .templeGate: return paintingTempleGate()
        case .pagoda: return paintingPagoda()
        case .path: return paintingFootpath()
        case .courtyard: return paintingCourtyard()
        case .window: return paintingWindow()
        case .fields: return paintingFields()
        case .dunes: return paintingDunes()
        case .beaconSmoke, .cookingSmoke: return paintingSmoke(beacon: motif == .beaconSmoke)
        case .reeds, .grass: return paintingReeds()
        case .moon, .crescent, .sunrise, .sunset, .stars, .waterfall, .rain, .snow:
            return paintingAtmosphere(motif)
        case .vine: return paintingVine()
        case .horse: return paintingHorse()
        case .terrace: return paintingTerrace()
        case .fence: return paintingFence()
        case .boat, .angler, .mooredBoat, .sail: return paintingBoat(motif)
        case .traveler: return paintingPerson()
        case .egret: return paintingEgret()
        case .crow, .swallow: return paintingBird(swallow: motif == .swallow)
        case .waves, .stream: return paintingWater(stream: motif == .stream)
        case .reef: return paintingRock()
        case .mist, .afterRain: return paintingDistant(0)
        default: return paintingLegacy(sceneAsset(motif))
        }
    }

    /// Reuse the original architectural / figure geometry with stronger, broken ink contours.
    func paintingLegacy(_ source: ZXArt.SSCanv, textured: Bool = false) -> ZXArt.SSCanv {
        var out: ZXArt.SSCanv = []
        for var p in source {
            let originalFill = p.fil
            let filled = originalFill.map { $0.a > 0 } ?? false
            if let color = originalFill, color != .white, color.a > 0 {
                p.fil = .gray(0, min(0.85, color.a * (1 - color.r / 255) * 1.25))
            }
            let stroke = p.str
            p.str = nil
            out.append(p)
            if originalFill == .white { out += inkSurface(p.p, textured: textured) }
            // Existing filled brush polygons are the ink body, not another centreline.
            // Tracing their perimeter again loses the original dry stroke and multiplies geometry.
            if !filled || originalFill == .white,
               let stroke, stroke.a > 0, stroke.r < 250, p.wid > 0 {
                out += inkLine(p.p, width: max(0.45, p.wid * 1.2),
                    tone: min(0.8, stroke.a * (1 - stroke.r / 255) * 1.4), dry: 0.40)
            }
        }
        return out
    }

    /// Shading inside the actual rock / mountain contour, painted the way a brush builds it:
    /// one pale wash, then texture strokes that gather on the shadow side and in the recesses,
    /// leaving the lit top planes as paper. Moss dots in scorched ink sit on the upper edges.
    /// Light comes from the upper left; no straight-edged wash bands.
    func inkSurface(_ points: [P], textured: Bool, shadowWash: Bool = true) -> ZXArt.SSCanv {
        guard let x0 = points.map(\.x).min(), let x1 = points.map(\.x).max(),
              let y0 = points.map(\.y).min(), let y1 = points.map(\.y).max(),
              x1 - x0 > 25, y1 - y0 > 15 else { return [] }
        var result = [poly(points, fil: .gray(0, textured ? 0.05 : 0.03), str: nil)]
        guard textured else { return result }
        let w = x1 - x0, h = y1 - y0
        func inside(_ p: P) -> Bool {
            var result = false, previous = points.last!
            for current in points {
                if (current.y > p.y) != (previous.y > p.y),
                   p.x < (previous.x - current.x) * (p.y - current.y) / (previous.y - current.y) + current.x {
                    result.toggle()
                }
                previous = current
            }
            return result
        }
        /// 0 on the lit upper-left planes, 1 in the shadowed lower-right; noise breaks the gradient
        /// into irregular patches so it reads as folded rock, not a ramp.
        func shade(_ x: Double, _ y: Double) -> Double {
            let u = (x - x0) / w, v = (y - y0) / h
            let base = 0.55 * u + 0.75 * v - 0.25 + 0.5 * (n(x * 0.05, y * 0.05, 7) - 0.5)
            return min(1, max(0, base))
        }
        // A second, darker wash only where the shade is deep, built from the shadowed half of the
        // outline itself (lit side pulled in), so its edge follows the rock rather than a ruler.
        let shadow = points.map { p -> P in
            let pull = 1 - min(1, shade(p.x, p.y) * 1.6)
            return P(p.x + (x1 - p.x) * pull * 0.55, p.y + (y1 - p.y) * pull * 0.45)
        }
        if shadowWash { result.append(poly(shadow, fil: .gray(0, 0.10), str: nil)) }

        // Texture strokes: density and tone follow the shade.
        let count = min(900, max(50, Int(w * h / 45)))
        for _ in 0..<count {
            let x = x0 + r() * w, y = y0 + r() * h
            let s = shade(x, y)
            let length = min(22, h * (0.05 + r() * 0.10))
            let lean = -1 - r() * 3
            let end = P(x + lean, y + length)
            let keep = r() < 0.12 + 0.88 * s
            guard keep, inside(P(x, y)), inside(end) else { continue }
            let moisture = 0.5 + 0.8 * n(x * 0.04, y * 0.04)
            result += inkLine([P(x, y), P(x + lean * 0.5, y + length * 0.45), end],
                width: 0.45 + r() * 0.9, tone: (0.08 + 0.42 * s) * moisture * snowLight, dry: 0.55 + 0.25 * (1 - s))
        }

        // Moss dots (点苔) along the upper contour: small, dark, in clusters of two or three.
        let tops = points.enumerated().filter { _, p in p.y < y0 + h * 0.4 }.map(\.offset)
        if !tops.isEmpty {
            // Few clusters, sitting on the crest itself: flat horizontal dabs, not round dots.
            let clusters = max(1, min(5, Int(w / 55)))
            for _ in 0..<clusters {
                let p = points[tops[Int(r() * Double(tops.count)) % tops.count]]
                let dots = 2 + Int(r() * 2)
                for k in 0..<dots {
                    let x = p.x + (Double(k) - 1) * (1.6 + r() * 1.4), y = p.y + 0.3 + r() * 1.0
                    result += inkBlot(x, y, radius: 0.55 + r() * 0.5, squash: 0.38 + r() * 0.2,
                        angle: -0.25 + r() * 0.5, tone: 0.42 + r() * 0.28)
                }
            }
        }
        return result
    }

    /// Withered vine (枯藤) hanging from branches: a few strands of unequal length that sway
    /// slightly, with small dark leaves bunched near the top. Drawn in the crown's own frame.
    func paintingVine() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let strands = 3 + Int(r() * 3)
        for k in 0..<strands {
            let x = 15 + r() * 65, top = r() * 12
            let length = 24 + pow(r(), 0.7) * 80
            let sway = (r() - 0.5) * 36
            let line = inkCurve([P(x, top), P(x + sway + 7, top + length * 0.25),
                P(x + sway - 5, top + length * 0.52), P(x + sway * 0.5, top + length * 0.78),
                P(x + sway * 0.6 + 4, top + length)])
            c += inkLine(line, width: k == 0 ? 1.5 : 0.65, tone: 0.65, dry: 0.5)
            if k < 2 {
                let loop = inkCurve([P(x, top + 4), P(x + 12, top - 5), P(x + 21, top + 3), P(x + 13, top + 12)])
                c += inkLine(loop, width: 0.7, tone: 0.6, dry: 0.5)
            }
            for _ in 0..<(3 + Int(r() * 6)) {
                let t = pow(r(), 2.2) * 0.55
                let i = min(line.count - 1, Int(t * Double(line.count - 1)))
                c += inkBlot(line[i].x + (r() - 0.5) * 6, line[i].y, radius: 1.4 + r() * 1.8,
                    squash: 0.45, angle: r() * 3, tone: 0.65 + r() * 0.2)
            }
        }
        return c
    }

    /// 白描瘦马: hip, withers and tucked belly remain legible through a very dilute coat.
    /// Three anatomical poses, with knees forward and hocks behind the hind legs.
    func paintingHorse(pose requested: Int? = nil, facingLeft: Bool? = nil) -> ZXArt.SSCanv {
        let pose = requested ?? Int(r() * 3), flip = facingLeft ?? (r() < 0.5)
        let tone = 0.48 + r() * 0.23
        let headY = pose == 2 ? 62.0 : (pose == 1 ? 21.0 : 36.0)
        let outline = inkCurve([P(23, 35), P(27, 28), P(35, 25), P(48, 29), P(65, 28),
            P(73, 25), P(83, headY - 12), P(92, headY - 7), P(101, headY + 4),
            P(99, headY + 9), P(94, headY + 9), P(86, headY + 1),
            P(81, 44), P(73, 48), P(59, 51), P(43, 48), P(29, 47), P(23, 35)])
        var c = [poly(outline, fil: .white, str: nil)]
        c.append(poly(outline, fil: .gray(0, 0.025 + r() * 0.055), str: nil))
        c += inkLine(outline, width: 1.05, tone: tone, dry: 0.43)
        // Hip and shoulder planes, ribs and mane: a few strokes, never a filled oval.
        for line in [[P(29, 30), P(35, 33), P(32, 43)], [P(73, 29), P(69, 36), P(73, 45)],
                     [P(48, 35), P(51, 43)], [P(55, 35), P(58, 44)]] {
            c += inkLine(inkCurve(line), width: 0.65, tone: tone * 0.55, dry: 0.55)
        }
        c += inkLine(inkCurve([P(73, 25), P(81, headY - 12), P(87, headY - 9)]),
                     width: 2.1, tone: tone, dry: 0.60)
        c += inkLine([P(86, headY - 9), P(84, headY - 17), P(89, headY - 10)], width: 1, tone: 0.8)
        c += inkLine([P(91, headY - 6), P(92, headY - 13)], width: 0.8, tone: 0.7)
        c += inkBlot(94, headY, radius: 0.7, squash: 0.65, tone: 0.8)
        // Far legs first; a walking foreleg lifts at the knee, while the other carries the weight.
        let legs: [[P]] = [
            [P(36, 46), P(42, 57), P(37, 66), P(42, 80)],
            [P(76, 45), P(79, 62), P(77, 80)],
            [P(29, 44), P(34, 55), P(27, 65), P(pose == 1 ? 18 : 26, 80)],
            pose == 1 ? [P(70, 46), P(78, 59), P(88, 63), P(84, 70)]
                      : [P(70, 46), P(72, 62), P(pose == 2 ? 65 : 71, 80)]
        ]
        for (i, leg) in legs.enumerated() {
            c += inkLine(leg, width: i < 2 ? 1 : 1.5, tone: i < 2 ? tone * 0.6 : tone, dry: 0.37)
            let foot = leg.last!
            c += inkLine([P(foot.x - 1, foot.y), P(foot.x + 2, foot.y)], width: 1.6, tone: tone)
        }
        c += inkLine(inkCurve([P(24, 31), P(18, 39), P(17, 56), P(13, 67)]), width: 2.3, tone: tone, dry: 0.6)
        if pose == 1 || r() < 0.45 {
            c += inkLine([P(43, 28), P(44, 34), P(61, 35), P(64, 28)], width: 1.6, tone: tone)
            c += inkLine([P(51, 35), P(50, 50)], width: 0.7, tone: tone * 0.8)
        }
        if flip { c = c.map { var p = $0; p.p = p.p.map { P(112 - $0.x, $0.y) }; return p } }
        return c
    }

    /// 烘云托月: the moon is left as paper; a soft ring of pale wash around it makes it glow.
    func paintingMoon() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        // Many faint, overlapping rings fade the halo smoothly; no outline on the disc.
        for k in 0..<16 {
            let radius = 52 - Double(k) * 1.9
            c += sceneEllipse(40, 40, radius, radius, fill: C(0, 0, 0, 0.009), tone: 0)
        }
        c += sceneEllipse(40, 40, 21, 21, fill: .white, tone: 0)
        return c
    }

    /// An ancient terrace (古台): a low platform of dressed stone with a battered face and a
    /// short broken parapet, seen slightly from below.
    func paintingTerrace() -> ZXArt.SSCanv {
        let top = [P(14, 8), P(106, 8)], base = [P(0, 30), P(120, 30)]
        let face = [top[0], top[1], base[1], base[0]]
        var c = [poly(face, fil: .white, str: nil), poly(face, fil: .gray(0, 0.16), str: nil)]
        c += inkEdges([P(0, 30), P(14, 8), P(106, 8), P(120, 30)], width: 1.4, tone: 0.7, dry: 0.4)
        c += inkLine([P(0, 30), P(120, 30)], width: 1.8, tone: 0.75, dry: 0.4)
        for k in 1..<4 {  // stone courses
            let y = 8 + Double(k) * 5.5, inset = 14 * (1 - Double(k) * 5.5 / 22)
            c += inkLine([P(inset + 2, y), P(120 - inset - 2, y)], width: 0.5, tone: 0.3, dry: 0.6)
        }
        for x in stride(from: 18.0, to: 102, by: 14) where r() < 0.7 {  // broken parapet
            c += inkLine([P(x, 8), P(x, 2 + r() * 2)], width: 1.2, tone: 0.65, dry: 0.4)
        }
        return c
    }

    /// A thatched cottage (茅屋) as landscape painters draw it, frontal and level: a broad roof
    /// with deep eaves and a ridge whose ends lift slightly, short walls in shadow under the eaves,
    /// an open bay on the right (the left bay is left for a window), on a low stone plinth.
    /// Everything is symmetric about the vertical; nothing in the drawing leans.
    func paintingHouse() -> ZXArt.SSCanv {
        let ridge = [P(30, 22), P(42, 26), P(122, 26), P(134, 22)]
        let eave = [P(0, 55), P(10, 58), P(154, 58), P(164, 55)]
        let roof = [P(42, 26), P(122, 26), P(154, 58), P(10, 58)]
        let wall = [P(18, 58), P(146, 58), P(146, 92), P(18, 92)]
        var c = [poly(wall, fil: .white, str: nil), poly(wall, fil: .gray(0, 0.07), str: nil)]
        // Shadow under the eaves and the open bay carry the darkest ink of the building.
        c.append(poly([P(18, 58), P(146, 58), P(146, 65), P(18, 65)], fil: .gray(0, 0.22), str: nil))
        let bay = [P(98, 64), P(124, 64), P(124, 92), P(98, 92)]
        c.append(poly(bay, fil: .gray(0, 0.55), str: nil))
        c.append(poly(roof, fil: .white, str: nil))
        c.append(poly(roof, fil: .gray(0, 0.20), str: nil))
        // Thatch: strokes fall from the ridge to the eave, fanning out toward the ends.
        for k in 0..<22 {
            let t = (Double(k) + 0.3 + r() * 0.4) / 22
            let top = P(42 + 80 * t, 27), bottom = P(10 + 144 * t, 57 - r() * 1.5)
            c += inkLine([top, P((top.x + bottom.x) / 2, (top.y + bottom.y) / 2 + 1), bottom],
                width: 0.5 + r() * 0.5, tone: 0.20 + r() * 0.22, dry: 0.6)
        }
        c += inkLine(inkCurve(ridge, steps: 4), width: 2.4, tone: 0.82, dry: 0.35)
        c += inkLine(inkCurve(eave, steps: 4), width: 2.0, tone: 0.85, dry: 0.30)
        c += inkEdges([P(42, 26), P(10, 58)], width: 1.3, tone: 0.62, dry: 0.45)
        c += inkEdges([P(122, 26), P(154, 58)], width: 1.3, tone: 0.62, dry: 0.45)
        for x in [18.0, 58, 98, 124, 146] {
            c += inkEdges([P(x, 62), P(x, 92)], width: 1.3, tone: 0.62, dry: 0.3)
        }
        // Plinth (台基): a little wider than the walls, level, with a dark foot.
        let plinth = [P(10, 92), P(154, 92), P(158, 99), P(6, 99)]
        c.append(poly(plinth, fil: .white, str: nil))
        c.append(poly(plinth, fil: .gray(0, 0.14), str: nil))
        c += inkEdges([P(10, 92), P(154, 92)], width: 1.0, tone: 0.55, dry: 0.4)
        c += inkLine([P(4, 99.5), P(82, 100), P(160, 99.5)], width: 1.8, tone: 0.65, dry: 0.45)
        return c
    }

    /// A rustic fence: upright posts of slightly uneven height, two level rails sagging a little
    /// between posts. Nothing leans.
    func paintingFence() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let posts = 12
        for k in 0..<posts {
            let x = 4 + Double(k) * 9
            let top = 2 + r() * 4
            c += inkEdges([P(x, top), P(x, 30)], width: 1.1 + r() * 0.4, tone: 0.50 + r() * 0.15, dry: 0.4)
        }
        for y in [11.0, 21] {
            var rail: [P] = []
            for k in 0..<posts {
                let x = 4 + Double(k) * 9
                rail.append(P(x, y))
                if k < posts - 1 { rail.append(P(x + 4.5, y + 0.6)) }
            }
            c += inkLine(rail, width: 1.0, tone: 0.48, dry: 0.45)
        }
        return c
    }

    func paintingCourtyard() -> ZXArt.SSCanv {
        // Oblique parallel projection, as in ruled-line painting (界画): top and foot stay parallel.
        let slope = 0.22
        let top = [P(14, 48), P(176, 48 + 162 * slope)], bottom = [P(14, 140), P(176, 140 + 162 * slope)]
        let face = [top[0], top[1], bottom[1], bottom[0]]
        let ground = inkCurve([P(-18, 139), P(6, 133), P(52, 147), P(124, 160), P(194, 178),
            P(159, 202), P(70, 186), P(-12, 164)])
        var c = [poly(ground, fil: .white, str: nil), poly(ground, fil: .gray(0, 0.045), str: nil)]
        c += inkLine([P(-14, 146), P(8, 142), P(32, 148)], width: 0.8, tone: 0.27, dry: 0.7)
        c += inkLine([P(132, 178), P(172, 185), P(187, 183)], width: 0.7, tone: 0.19, dry: 0.72)
        c += [poly(face, fil: .white, str: nil), poly(face, fil: .gray(0, 0.04), str: nil)]
        // The near end turns a corner: a narrow return face in shadow shows the wall's thickness.
        let end = [P(0, 42), P(14, 48), P(14, 140), P(0, 134)]
        c.append(poly(end, fil: .white, str: nil))
        c.append(poly(end, fil: .gray(0, 0.16), str: nil))
        c += inkEdges([P(0, 42), P(0, 134), P(14, 140)], width: 1.0, tone: 0.5)
        c += inkLine([P(14, 48), P(14, 140)], width: 0.8, tone: 0.45, dry: 0.4)
        // Coping: a dark tiled band along the top, overhanging both faces.
        let coping = [P(-4, 36), P(10, 41), P(180, 41 + 170 * slope), P(180, 48 + 170 * slope), P(10, 50), P(-4, 44)]
        c.append(poly(coping, fil: .gray(0, 0.62), str: nil))
        c += inkLine([P(-4, 36), P(10, 41), P(180, 41 + 170 * slope)], width: 1.6, tone: 0.85, dry: 0.3)
        for k in 0..<24 {
            let t = (Double(k) + 0.5) / 24
            let x = 12 + 166 * t, y = 42 + 166 * t * slope
            c += inkLine([P(x, y), P(x + 0.4, y + 6)], width: 0.5, tone: 0.3, dry: 0.5)
        }
        // Moon gate: a circular opening; inside, the paler wall of the next court.
        let cx = 86.0, cy = 108.0 + 72 * slope, rx = 22.0, ry = 25.0
        let ring = (0...48).map { i -> P in
            let a = Double(i) / 48 * 2 * Double.pi
            return P(cx + cos(a) * rx, cy + sin(a) * ry)
        }.filter { $0.y <= 140 + (($0.x - 14) * slope) - 3 }
        c.append(poly(ring, fil: .gray(0, 0.10), str: nil))
        c += inkLine(ring, width: 1.6, tone: 0.62, dry: 0.3)
        c += inkLine([P(cx - rx + 4, cy + 4), P(cx + rx - 3, cy + 4 + 6 * slope)], width: 0.8, tone: 0.25, dry: 0.5)
        c += inkLine([P(cx - rx + 6, cy - 4), P(cx + rx - 4, cy - 4 + 6 * slope)], width: 2.4, tone: 0.30, dry: 0.4)
        // Plinth and a few faint wall stains.
        c += inkLine([P(0, 134), P(14, 140), P(176, 140 + 162 * slope)], width: 1.6, tone: 0.55, dry: 0.45)
        for _ in 0..<8 {
            let x = 20 + r() * 150, y = 62 + x * slope + r() * 60
            c += inkLine([P(x, y), P(x + 3 + r() * 4, y + 1)], width: 0.6, tone: 0.08, dry: 0.6)
        }
        return c
    }

    func paintingBridge(_ specification: PaintingBridge? = nil) -> ZXArt.SSCanv {
        let bridge = specification ?? paintingBridgePlan()
        let w = bridge.width, floor = 60.0
        var c: ZXArt.SSCanv = []
        if bridge.kind == .arch {
            let top = bridge.deck
            let arch = bridge.arch
            let face = top + [P(w, floor)] + arch.reversed() + [P(0, floor)]
            c += [poly(face, fil: .white, str: nil), poly(face, fil: .gray(0, 0.045), str: nil)]
            c += inkLine(top, width: 1.9, tone: 0.72, dry: 0.45)
            c += inkLine(arch, width: 2.0, tone: 0.78, dry: 0.40)
            for k in 1..<10 {
                let t = Double(k) / 10, x = w * (0.10 + t * 0.80)
                let y = floor - sin(t * .pi) * bridge.rise
                c += inkLine([P(x, y), P(x + (x - w / 2) * 0.04, y - 5)], width: 0.65, tone: 0.35, dry: 0.5)
            }
        } else {
            let deckY = 42.0, thick = bridge.kind == .slab ? 6.0 : 3.5
            let deck = [P(0, deckY), P(w * 0.48, deckY - 1), P(w, deckY + 1),
                        P(w, deckY + thick), P(w * 0.49, deckY + thick - 1), P(0, deckY + thick)]
            c += [poly(deck, fil: .white, str: nil), poly(deck, fil: .gray(0, 0.04), str: nil)]
            c += inkLine(Array(deck.prefix(3)), width: 1.9, tone: 0.76, dry: 0.25)
            c += inkLine(Array(deck.suffix(3)), width: 2.1, tone: 0.80, dry: 0.28)
            let piers = bridge.kind == .slab ? [w * 0.19, w * 0.79] : [w * 0.13, w * 0.86]
            for x in piers {
                if bridge.kind == .slab {
                    let pier = [P(x - 3, deckY + thick), P(x + 3, deckY + thick),
                                P(x + 3, floor), P(x - 3, floor)]
                    c.append(poly(pier, fil: .gray(0, 0.16), str: nil))
                    c += inkLine([P(x - 3, deckY + thick), P(x - 3, floor)], width: 1.5, tone: 0.70, dry: 0.3)
                    c += inkLine([P(x + 3, deckY + thick), P(x + 3, floor)], width: 1.0, tone: 0.50, dry: 0.35)
                } else {
                    // A single straight wooden pile enters the water, with no looped foot.
                    c += inkLine([P(x, deckY + 2), P(x + 0.4, floor + 1)], width: 2.5, tone: 0.82, dry: 0.23)
                }
            }
        }
        if bridge.railing {
            let deck = bridge.deck
            // One low handrail on three posts, inset from the ends; no fence or door frame.
            c += inkLine(Array(deck[3...33]).map { P($0.x, $0.y - 6) }, width: 1.15, tone: 0.62, dry: 0.32)
            for i in [5, 18, 31] {
                let p = deck[i]
                c += inkLine([P(p.x, p.y - 6.5), P(p.x, p.y + 0.5)], width: 1.1, tone: 0.67, dry: 0.3)
            }
        }
        if bridge.pedestrian {
            let foot = bridge.deck[21]
            c += paintingPerson(pose: 0).map { poly in
                var p = poly
                p.p = p.p.map { P(foot.x + ($0.x - 44) * 0.5, foot.y + ($0.y - 44) * 0.5) }
                p.wid *= 0.5
                return p
            }
        }
        return c
    }

    func paintingBridgePlan() -> PaintingBridge {
        PaintingBridge(kind: PaintingBridge.Kind.allCases[Int(r() * 65_536) % 3], width: 140 + r() * 32,
                       rise: 24 + r() * 13, railing: r() < 0.5, pedestrian: r() < 0.3)
    }

    func paintingBridgeReflection(_ bridge: PaintingBridge) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        if bridge.kind == .arch {
            let reflected = bridge.arch.map { P($0.x, 120 - $0.y) }
            for start in stride(from: 1, to: reflected.count - 4, by: 7) {
                c += inkLine(Array(reflected[start...start + 4]), width: 0.85, tone: 0.22, dry: 0.65)
            }
        }
        if bridge.kind != .arch {
            // Piles and piers continue as broken, wavering reflections, so they stand in water
            // rather than ending on paper like table legs.
            let piers = bridge.kind == .slab ? [0.19, 0.79] : [0.13, 0.86]
            for u in piers {
                let x = bridge.width * u
                for k in 0..<3 {
                    let y = 62 + Double(k) * 5.5
                    c += inkLine([P(x - 0.8, y), P(x + 0.9, y + 2.2), P(x - 0.4, y + 3.6)],
                        width: bridge.kind == .slab ? 2.4 : 1.4, tone: 0.30 - Double(k) * 0.07, dry: 0.5)
                }
            }
        }
        for (x, y, length) in [(0.24, 65.0, 0.23), (0.44, 71, 0.30), (0.18, 82, 0.38)] {
            c += inkLine([P(bridge.width * x, y), P(bridge.width * (x + length * 0.5), y + 0.5),
                          P(bridge.width * (x + length), y)], width: 0.8, tone: 0.33, dry: 0.5)
        }
        return c
    }

    /// 点景人物: seven heads tall, with walking, folded sleeves, carrying and seated poses.
    func paintingPerson(hat: Bool = false, pose requested: Int? = nil, facingLeft: Bool? = nil) -> ZXArt.SSCanv {
        let pose = requested ?? Int(r() * 4), flip = facingLeft ?? (r() < 0.5)
        let tone = 0.58 + r() * 0.22
        let hx = pose == 0 ? 46.0 : 43.0
        var c = inkBlot(hx, 7, radius: 2.6, squash: 0.90, tone: tone)
        if hat || r() < 0.45 {
            c += inkLine([P(hx - 7, 7), P(hx, 2), P(hx + 7, 8), P(hx - 7, 7)], width: 0.85, tone: tone)
        }
        let seated = pose == 3
        let hem = seated ? 29.0 : 37.0
        let back = inkCurve([P(hx - 1, 12), P(39, 19), P(seated ? 36 : 34, hem - 3), P(43, hem)])
        let front = inkCurve([P(hx + 1, 12), P(48, 20), P(seated ? 56 : 49, hem - 3), P(seated ? 55 : 46, hem)])
        c.append(poly(back + front.reversed(), fil: .white, str: nil))
        c += inkLine(back, width: 1.25, tone: tone, profile: .cone)
        c += inkLine(front, width: 1.0, tone: tone * 0.8, profile: .cone)
        c += inkLine([P(42, 22), P(39, hem - 3), P(46, hem)], width: 0.8, tone: tone * 0.7, profile: .cone)
        let sleeve: [P] = pose == 1 ? [P(40, 17), P(43, 24), P(51, 22), P(46, 18)]
            : [P(45, 16), P(48, 23), P(55, 24)]
        c += inkLine(sleeve, width: 1.5, tone: tone, profile: .cone)
        if pose == 0 {
            c += inkLine([P(54, 23), P(58, 44)], width: 0.65, tone: tone)
        } else if pose == 2 {
            c += inkLine([P(28, 18), P(59, 13)], width: 0.9, tone: tone)
            c += inkLine([P(29, 18), P(28, 29)], width: 0.55, tone: tone)
            c += inkLine([P(24, 28), P(23, 35), P(33, 35), P(32, 28), P(24, 28)], width: 1.2, tone: tone)
        }
        let feet: [[P]] = seated ? [[P(51, 27), P(59, 30), P(59, 34), P(63, 34)]]
            : [[P(40, 36), P(pose == 0 ? 34 : 41, 43), P(pose == 0 ? 30 : 38, 44)],
               [P(47, 36), P(49, 43), P(53, 44)]]
        for foot in feet { c += inkLine(foot, width: 1.1, tone: tone, dry: 0.4) }
        if flip { c = c.map { var p = $0; p.p = p.p.map { P(88 - $0.x, $0.y) }; return p } }
        return c
    }

    func paintingBoat(_ kind: ZXArt.SceneMotif) -> ZXArt.SSCanv {
        let hull = inkCurve([P(0, 87), P(22, 94), P(86, 97), P(130, 85), P(103, 101), P(35, 106), P(8, 99), P(0, 87)])
        var c = [poly(hull, fil: .gray(0, 0.48), str: nil)] // first shape is the hull anchor
        c += inkLine([P(0, 87), P(36, 94), P(86, 94), P(130, 85)], width: 1.0, tone: 0.8)
        if kind == .angler {
            let person = paintingPerson(hat: true, pose: 3, facingLeft: false).map { p -> ZXArt.SSPoly in
                var q = p; q.p = p.p.map { P($0.x * 0.75 + 10, $0.y * 0.75 + 64) }; q.wid *= 0.75; return q
            }
            c += person
            for k in 0..<5 { // 蓑衣: a few dry slashes, never a detailed portrait.
                c += inkLine([P(38 + Double(k) * 2, 70), P(34 + Double(k) * 3, 82)],
                    width: 1.2, tone: 0.6, dry: 0.6)
            }
            c += inkLine([P(47, 76), P(85, 55), P(131, 47)], width: 1.0, tone: 0.8)
            c += inkLine(inkCurve([P(131, 47), P(137, 69), P(137, 113)]), width: 0.5, tone: 0.4)
        } else if kind == .sail {
            c += inkLine([P(58, 91), P(57, 0)], width: 1.5, tone: 0.8)
            let sail = inkCurve([P(57, 8), P(24, 62), P(14, 78), P(57, 68)])
            c.append(poly(sail, fil: .white, str: nil))
            c.append(poly(sail, fil: .gray(0, 0.09), str: nil))
            c += inkLine(sail, width: 0.9, tone: 0.5)
            for y in [28.0, 42, 56] { c += inkLine([P(57, y), P(57 - y * 0.5, y + 6)], width: 0.5, tone: 0.3) }
        } else {
            let awning = inkCurve([P(44, 93), P(48, 76), P(63, 69), P(87, 74), P(96, 92)])
            c.append(poly(awning, fil: .white, str: nil))
            c.append(poly(awning, fil: .gray(0, 0.13), str: nil))
            c += inkLine(awning, width: 1.3, tone: 0.75)
            // Curving bamboo ribs and a dark opening give the canopy volume at small scale.
            for dx in [0.0, 9, 18, 27] {
                c += inkLine(inkCurve([P(46 + dx, 92), P(48 + dx, 79), P(56 + dx, 73)]),
                    width: 0.7, tone: 0.48, dry: 0.45)
            }
            let opening = inkCurve([P(79, 92), P(82, 80), P(88, 79), P(94, 92)])
            c.append(poly(opening, fil: .gray(0, 0.58), str: nil))
            c += inkLine(inkCurve([P(17, 93), P(8, 101), P(-10, 107)]), width: 1.3, tone: 0.7, dry: 0.45)
        }
        return c
    }

    func paintingEgret() -> ZXArt.SSCanv {
        var c = inkLine([P(23, 36), P(17, 40), P(5, 46)], width: 6.5, tone: 0.5, dry: 0.12, profile: .lens)
        c += inkLine(inkCurve([P(24, 37), P(33, 31), P(26, 21), P(30, 9), P(37, 8)]), width: 2, tone: 0.65)
        c += inkLine([P(36, 8), P(49, 10)], width: 0.8, tone: 0.85)
        c += inkLine([P(15, 43), P(14, 63), P(8, 68)], width: 0.8, tone: 0.65)
        c += inkLine([P(19, 43), P(23, 61), P(31, 63)], width: 0.8, tone: 0.65)
        return c
    }

    /// A flock of crows or a pair of swallows. Each wing has its own beat, body and tail.
    func paintingBird(swallow: Bool, count requested: Int? = nil) -> ZXArt.SSCanv {
        let count = requested ?? (swallow ? (r() < 0.25 ? 1 : 2) : 2 + Int(r() * 4))
        var c: ZXArt.SSCanv = []
        for i in 0..<count {
            let x = Double(i) * (swallow ? 37 : 23) + r() * 8
            let y = r() * 24 + Double(i % 2) * 12
            let scale = 0.55 + r() * 0.45
            let beat = Int(r() * 3)
            let lift = beat == 0 ? -13.0 : (beat == 1 ? 7.0 : -3.0)
            var bird = inkLine([P(0, -3), P(2, 3), P(0, 7)], width: swallow ? 2 : 3.6, tone: 0.86, profile: .cone)
            let span = swallow ? 22.0 : 16.0
            bird += inkLine([P(0, 0), P(-span * 0.5, lift * 0.3 - 2), P(-span, lift)],
                            width: swallow ? 2.3 : 3.3, tone: 0.86, profile: .cone)
            bird += inkLine([P(1, 1), P(span * 0.55, lift * 0.4 - 3), P(span * 0.9, lift - 4)],
                            width: swallow ? 2 : 3, tone: 0.78, profile: .cone)
            if swallow {
                bird += inkLine([P(1, 5), P(-6, 18)], width: 1.2, tone: 0.86, profile: .cone)
                bird += inkLine([P(1, 5), P(8, 17)], width: 1.2, tone: 0.86, profile: .cone)
            } else {
                bird += inkLine([P(0, 5), P(-3, 11)], width: 2.2, tone: 0.8, profile: .cone)
            }
            c += bird.map { var p = $0; p.p = p.p.map { P(x + $0.x * scale, y + $0.y * scale) }; p.wid *= scale; return p }
        }
        return c
    }

    /// Feet at the origin, so a perch can be attached to an actual painted branch.
    func paintingPerchedCrow() -> ZXArt.SSCanv {
        let flip = r() < 0.5 ? -1.0 : 1.0
        let attitude = Int(r() * 3)
        let headY = attitude == 0 ? -8.0 : (attitude == 1 ? -10.0 : -7.0)
        let headX = attitude == 2 ? 4.0 : 2.5
        // The belly sits directly on the branch. Only two tiny claws show below it.
        var c: ZXArt.SSCanv = []
        for x in [-1.5, 1.0] {
            c += inkLine([P(x, -1), P(x + 0.5, 0), P(x + 1.5, 0)], width: 0.7, tone: 0.85, dry: 0.2)
        }
        let tailY = attitude == 1 ? 3.5 : 1.0
        c += inkLine([P(-2, -4), P(-5.5, -1), P(-10, tailY)], width: 3.5, tone: 0.92, dry: 0.18, profile: .cone)
        c += inkBlot(-0.7, -4.8, radius: 5.1, squash: 0.92, angle: -0.25, tone: 0.92)
        c += inkBlot(headX, headY, radius: 2.8, squash: 0.95, tone: 0.94)
        c.append(poly([P(headX + 2, headY - 0.6), P(headX + 6, headY + 0.7),
                       P(headX + 2, headY + 1.1)], fil: .gray(0, 0.94), str: nil))
        return c.map { var p = $0; p.p = p.p.map { P($0.x * flip, $0.y) }; return p }
    }

    func paintingWater(stream: Bool) -> ZXArt.SSCanv {
        stream ? paintingChannel(width: 110, height: 210) : paintingSurface(.lake)
    }
}
