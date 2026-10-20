// shanshui@5 painting path. Preserve this version when adding future painting styles.
import Foundation

extension ShanShuiEngine {
    func paintingAsset(_ motif: ZXArt.SceneMotif) -> ZXArt.SSCanv {
        switch motif {
        case .pine, .oldTree, .bareTree, .layeredTree, .willow, .blossom, .maple: return paintingTree(motif)
        case .bamboo: return paintingBamboo()
        case .lotus: return paintingLotus()
        case .bridge: return paintingBridge()
        case .house: return paintingHouse()
        case .courtyard: return paintingCourtyard()
        case .window: return paintingWindow()
        case .fields: return paintingFields()
        case .dunes: return paintingDunes()
        case .beaconSmoke, .cookingSmoke: return paintingSmoke(beacon: motif == .beaconSmoke)
        case .reeds, .grass: return paintingReeds()
        case .boat, .angler, .mooredBoat, .sail: return paintingBoat(motif)
        case .traveler: return paintingPerson()
        case .egret: return paintingEgret()
        case .crow, .swallow: return paintingBird(swallow: motif == .swallow)
        case .waves, .stream: return paintingWater(stream: motif == .stream)
        case .reef: return paintingRock()
        case .snow: return paintingRock(width: 160, height: 22, tone: 0.25)
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
    private func inkSurface(_ points: [P], textured: Bool) -> ZXArt.SSCanv {
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
        result.append(poly(shadow, fil: .gray(0, 0.06), str: nil))

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
                width: 0.45 + r() * 0.9, tone: (0.08 + 0.32 * s) * moisture, dry: 0.55 + 0.25 * (1 - s))
        }

        // Moss dots (点苔) along the upper contour: small, dark, in clusters of two or three.
        let tops = points.enumerated().filter { _, p in p.y < y0 + h * 0.4 }.map(\.offset)
        if !tops.isEmpty {
            let clusters = max(2, min(9, Int(w / 28)))
            for _ in 0..<clusters {
                let p = points[tops[Int(r() * Double(tops.count)) % tops.count]]
                let dots = 2 + Int(r() * 2.5)
                for k in 0..<dots {
                    let x = p.x + (r() - 0.5) * 5, y = p.y + 1.2 + r() * 2.5 + Double(k) * 0.4
                    result += inkBlot(x, y, radius: 0.8 + r() * 0.9, squash: 0.55 + r() * 0.3,
                        angle: -0.4 + r() * 0.8, tone: 0.55 + r() * 0.3)
                }
            }
        }
        return result
    }

    func paintingHouse() -> ZXArt.SSCanv {
        let front = [P(20, 63), P(99, 86), P(99, 130), P(20, 106)]
        let side = [P(99, 86), P(128, 43), P(165, 75), P(165, 115), P(99, 130)]
        let backRoof = [P(48, 21), P(128, 43), P(172, 75), P(92, 53)]
        let roof = [P(6, 62), P(48, 21), P(128, 43), P(100, 89)]
        var c = [poly(front, fil: .white, str: nil), poly(side, fil: .white, str: nil)]
        c.append(poly(side, fil: .gray(0, 0.12), str: nil))
        c.append(poly(backRoof, fil: .gray(0, 0.12), str: nil))
        c.append(poly(roof, fil: .white, str: nil))
        c.append(poly(roof, fil: .gray(0, 0.17), str: nil))
        c += inkEdges([P(3, 56), P(6, 62), P(48, 21), P(128, 43), P(172, 75), P(176, 71)], width: 1.8, tone: 0.75, dry: 0.43)
        c += inkEdges([P(6, 62), P(100, 89), P(105, 85)], width: 2.6, tone: 0.85, dry: 0.4)
        c += inkEdges([P(100, 89), P(128, 43)], width: 1.9, tone: 0.65, dry: 0.5)
        for k in 0..<16 {
            let t = Double(k + 1) / 17
            c += inkLine([P(48 + 80 * t, 21 + 22 * t), P(6 + 94 * t, 62 + 27 * t)],
                width: 0.5 + r() * 0.35, tone: 0.18 + r() * 0.22, dry: 0.65)
        }
        c += inkEdges([P(20, 67), P(20, 106), P(99, 130), P(165, 115), P(165, 79)], width: 1.0, tone: 0.5)
        c += inkLine([P(99, 89), P(99, 130)], width: 1.1, tone: 0.55)
        for x in [40.0, 68] {
            let y = 86 + (x - 40) * 0.28
            c += inkLine([P(x, y), P(x + 10, y + 3)], width: 3, tone: 0.65, dry: 0.25)
        }
        c += inkLine([P(127, 99), P(127, 121)], width: 5.5, tone: 0.62, dry: 0.12)
        return c
    }

    func paintingCourtyard() -> ZXArt.SSCanv {
        let face = [P(0, 68), P(48, 68), P(48, 42), P(143, 42), P(143, 143), P(0, 143)]
        var c = [poly(face, fil: .white, str: nil), poly(face, fil: .gray(0, 0.045), str: nil)]
        c += inkEdges([P(0, 65), P(46, 65), P(46, 39), P(146, 39)], width: 3.7, tone: 0.78, dry: 0.38)
        c += inkEdges([P(0, 70), P(51, 70), P(51, 45), P(146, 45)], width: 0.9, tone: 0.4)
        let gate = inkCurve([P(82, 142), P(82, 102), P(87, 86), P(103, 82), P(118, 94), P(121, 142)])
        c.append(poly(gate, fil: .gray(0, 0.16), str: nil))
        c += inkEdges(gate, width: 1.5, tone: 0.62, dry: 0.32)
        for _ in 0..<10 {
            let x = 5 + r() * 132, y = 74 + r() * 64
            c += inkEdges([P(x, y), P(x + 4 + r() * 5, y + 0.6)], width: 0.6, tone: 0.11, dry: 0.5)
        }
        return c
    }

    func paintingBridge() -> ZXArt.SSCanv {
        let top = inkCurve([P(0, 42), P(29, 26), P(77, 12), P(121, 25), P(156, 43)])
        let arch = inkCurve([P(156, 60), P(127, 60), P(113, 39), P(79, 30), P(43, 42), P(28, 60), P(0, 60)])
        var c = [poly(top + arch, fil: .white, str: nil), poly(top + arch, fil: .gray(0, 0.10), str: nil)]
        c += inkLine(top, width: 2.8, tone: 0.72, dry: 0.45)
        c += inkLine(arch, width: 2.6, tone: 0.85, dry: 0.32)
        c += inkLine(top.map { P($0.x, $0.y - 7) }, width: 1.1, tone: 0.52, dry: 0.4)
        for k in 0..<7 {
            let x = 8 + Double(k) * 23, y = 42 - sin(x / 156 * .pi) * 27
            c += inkLine([P(x, y - 9), P(x, y + 1)], width: 1.0, tone: 0.6)
            c += inkLine([P(x + 3, y + 5), P(x + 11, y + 8)], width: 0.6, tone: 0.23, dry: 0.6)
        }
        for (x, y) in [(-8.0, 59.0), (137, 62)] {
            c += paintingRock(width: 35, height: 18).map { p in
                var result = p; result.p = p.p.map { P($0.x + x, $0.y + y - 10) }; return result
            }
        }
        return c
    }

    func paintingPerson() -> ZXArt.SSCanv {
        var c = inkBlot(44, 8, radius: 2.7, squash: 0.8, tone: 0.85)
        let robe = inkCurve([P(43, 13), P(39, 22), P(31, 35), P(27, 38), P(45, 39), P(50, 34), P(46, 19)])
        c.append(poly(robe, fil: .white, str: nil))
        c.append(poly(robe, fil: .gray(0, 0.13), str: nil))
        c += inkLine(Array(robe.prefix(robe.count / 2)), width: 1.2, tone: 0.72)
        c += inkLine([P(43, 15), P(46, 25), P(54, 27)], width: 1.6, tone: 0.75)
        c += inkLine([P(52, 25), P(57, 46)], width: 0.7, tone: 0.7)
        c += inkLine([P(40, 38), P(36, 44), P(31, 45)], width: 1.2, tone: 0.8)
        c += inkLine([P(47, 36), P(48, 44), P(52, 45)], width: 1.2, tone: 0.8)
        return c
    }

    func paintingBoat(_ kind: ZXArt.SceneMotif) -> ZXArt.SSCanv {
        let hull = inkCurve([P(0, 87), P(22, 94), P(86, 97), P(130, 85), P(103, 101), P(35, 106), P(8, 99), P(0, 87)])
        var c = [poly(hull, fil: .gray(0, 0.48), str: nil)] // first shape is the hull anchor
        c += inkLine([P(0, 87), P(36, 94), P(86, 94), P(130, 85)], width: 1.0, tone: 0.8)
        if kind == .angler {
            let person = paintingPerson().map { p -> ZXArt.SSPoly in
                var q = p; q.p = p.p.map { P($0.x * 0.75 + 10, $0.y * 0.75 + 56) }; q.wid *= 0.75; return q
            }
            c += person
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
            c += inkLine(awning, width: 1.3, tone: 0.65)
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

    func paintingBird(swallow: Bool) -> ZXArt.SSCanv {
        var c = inkLine([P(3, 4), P(19, 18), P(27, 18)], width: swallow ? 3 : 4, tone: 0.9, profile: .tip)
        c += inkLine([P(27, 18), P(37, 12), P(49, 0)], width: 3, tone: 0.8, profile: .tip)
        c += inkLine([P(26, 17), P(30, 23), P(25, 28)], width: 2.2, tone: 0.8)
        if swallow { c += inkLine([P(30, 23), P(35, 30)], width: 1.3, tone: 0.9) }
        return c
    }

    func paintingWater(stream: Bool) -> ZXArt.SSCanv {
        stream ? paintingChannel(width: 110, height: 210) : paintingSurface(.lake)
    }
}
