// Small, reusable ink objects for scene composition. All randomness belongs to the new scene engine.
import Foundation

extension ShanShuiEngine {
    func sceneLine(_ points: [P], width: Double = 1.2, tone: Double = 0.6) -> ZXArt.SSCanv {
        stroke(ZXArt.div(points, 5), wid: width, col: .ink(tone), noi: 0.35, out: 0)
    }

    func sceneEllipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double,
                      fill: C? = nil, tone: Double = 0.5) -> ZXArt.SSCanv {
        let points = (0...40).map { i -> P in
            let a = Double(i) / 40 * 2 * Double.pi
            return P(x + cos(a) * rx, y + sin(a) * ry)
        }
        return [poly(points, fil: fill, str: .ink(tone), wid: 0.7)]
    }

    func sceneAsset(_ motif: ZXArt.SceneMotif) -> ZXArt.SSCanv {
        switch motif {
        case .oldTree: return tree06(0, 0, hei: 120, wid: 4)
        case .bareTree: return sceneBareTree()
        case .layeredTree: return tree05(0, 0, hei: 150, wid: 4)
        case .pine: return scenePine()
        case .bamboo: return sceneBamboo()
        case .willow: return sceneWillow()
        case .reeds, .grass: return sceneGrass(reeds: motif == .reeds)
        case .maple: return sceneBlossom(maple: true)
        case .vine: return sceneVine()
        case .blossom: return sceneBlossom(maple: false)
        case .lotus: return sceneLotus()
        case .bridge: return sceneBridge()
        case .house: return arch02(50, 90, wid: 100, rot: 0.35, sto: 1, sty: 2)
        case .hut: return arch01(50, 100, hei: 55, wid: 110, per: 0.5)
        case .pavilion: return arch04(50, 100, hei: 23, wid: 80, sto: 1)
        case .pagoda: return arch03(50, 100, hei: 14, wid: 50, sto: 5)
        case .templeGate: return sceneGate(temple: true)
        case .cityGate: return sceneGate(temple: false)
        case .courtyard: return sceneCourtyard()
        case .window: return sceneWindow()
        case .curtain: return sceneCurtain()
        case .terrace: return sceneTerrace()
        case .ruins: return sceneRuins()
        case .fence: return sceneFence()
        case .fields: return sceneFields()
        case .path: return scenePath()
        case .boat, .mooredBoat, .sail, .angler: return sceneBoat(motif)
        case .traveler:
            return man(40, 100, sca: 0.9) + sceneLine([P(58, 54), P(63, 102)], width: 1)
        case .horse: return sceneHorse()
        case .egret: return sceneEgret()
        case .crow, .swallow: return sceneBird(swallow: motif == .swallow)
        case .dragonfly: return sceneDragonfly()
        case .butterfly: return sceneButterfly()
        case .stream: return sceneStream()
        case .waterfall: return sceneWaterfall()
        case .dunes: return sceneDunes()
        case .beaconSmoke, .cookingSmoke: return sceneSmoke(beacon: motif == .beaconSmoke)
        case .mist, .afterRain: return sceneMist()
        case .moon, .crescent, .sunrise, .sunset: return sceneCelestial(motif)
        case .stars: return sceneStars()
        case .snow: return sceneSnowGround()
        case .waves: return sceneWaves()
        case .reef: return rock(50, 100, 4, hei: 45, wid: 100, sha: 2)
        case .rain: return [] // moving precipitation belongs to the app weather overlay
        }
    }

    private func scenePine() -> ZXArt.SSCanv {
        var c = sceneLine([P(35, 100), P(43, 76), P(40, 53), P(56, 24), P(65, 3)], width: 4, tone: 0.72)
        for (x, y, direction) in [(43.0, 73.0, -1.0), (42, 51, 1), (55, 29, -1), (64, 7, 1)] {
            let tip = P(x + direction * (28 + r() * 15), y - 12)
            c += sceneLine([P(x, y + 12), P(x + direction * 15, y - 4), tip], width: 2.4)
            for i in 0..<4 {
                let bx = tip.x + Double(i - 2) * 7
                for k in 0..<9 {
                    let a = -Double.pi * (0.12 + Double(k) * 0.09)
                    c += sceneLine([P(bx, tip.y + 4), P(bx + cos(a) * (12 + r() * 8), tip.y + sin(a) * 12)], width: 0.65, tone: 0.62)
                }
            }
        }
        return c
    }

    private func sceneBamboo() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for k in 0..<4 {
            let x = Double(k) * 17 + 12, bend = Double(k - 1) * 8
            let height = 80 + r() * 40
            c += sceneLine([P(x, 110), P(x + bend * 0.5, 110 - height * 0.5), P(x + bend, 110 - height)], width: 2.0)
            for j in 1...5 {
                let y = 110 - height * Double(j) / 6, tx = x + bend * Double(j) / 6
                c += sceneLine([P(tx - 2, y), P(tx + 2, y - 0.8)], width: 1.1, tone: 0.9)
                if j % 2 == k % 2 {
                    for leaf in 0..<5 {
                        let dir = (j + k) % 2 == 0 ? 1.0 : -1.0
                        let dx = dir * (14 + Double(leaf) * 4), dy = Double(leaf - 2) * 6 - 8
                        c += blob(tx + dx * 0.5, y + dy * 0.5, len: hypot(dx, dy), wid: 3,
                                  ang: atan2(dy, dx), col: .ink(0.62 + r() * 0.18))
                    }
                }
            }
        }
        return c
    }

    private func sceneWillow() -> ZXArt.SSCanv {
        var c = sceneLine([P(45, 120), P(48, 83), P(42, 53), P(58, 23)], width: 4.5, tone: 0.65)
        for k in 0..<9 {
            let x = 8 + Double(k) * 10
            let start = P(47, 52), crest = P(x, 12 + abs(x - 50) * 0.15)
            c += sceneLine([start, P((start.x + x) / 2, 20), crest], width: 1.3)
            let bottom = 65 + r() * 40
            let strand = (0...16).map { i -> P in
                let t = Double(i) / 16
                return P(x + sin(t * 2.0) * 8, crest.y + t * bottom)
            }
            c += sceneLine(strand, width: 0.8, tone: 0.55)
            for i in stride(from: 3, through: 15, by: 2) {
                let p = strand[i]
                c += blob(p.x - 2, p.y + 2, len: 8, wid: 2, ang: 1.0, col: .ink(0.45))
            }
        }
        return c
    }

    private func sceneGrass(reeds: Bool) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for k in 0..<12 {
            let x = Double(k) * 7, tip = P(x + (r() - 0.5) * 25, 10 + r() * 55)
            c += sceneLine([P(x, 100), P(x + 4, 55), tip], width: 0.8, tone: 0.55)
            c += sceneLine([P(x, 85), P(x - 10, 62), P(x - 16, 64)], width: 1.2, tone: 0.45)
            if reeds { c += blob(tip.x, tip.y - 4, len: 15, wid: 3.8, ang: -1.4, col: .ink(0.38)) }
        }
        return c
    }

    private func sceneBlossom(maple: Bool) -> ZXArt.SSCanv {
        var c = sceneBareTree()
        let branchPoints = c.flatMap(\.p)
        guard !branchPoints.isEmpty else { return c }
        for k in 0..<32 {
            let p = branchPoints[Int(r() * Double(branchPoints.count)) % branchPoints.count]
            if maple {
                let leaf = (0..<10).map { i -> P in
                    let a = Double(i) / 10 * 2 * Double.pi
                    let radius = i % 2 == 0 ? 4.8 : 2.0
                    return P(p.x + cos(a) * radius, p.y + sin(a) * radius)
                }
                c.append(poly(leaf, fil: .ink(0.38), str: .ink(0.45), wid: 0.3))
            } else {
                for j in 0..<5 {
                    let a = Double(j) / 5 * 2 * Double.pi
                    c += sceneEllipse(p.x + cos(a) * 2.8, p.y + sin(a) * 2.8, 2.6, 2.0, fill: .white, tone: 0.35)
                }
                c += blob(p.x, p.y, len: 1.5, wid: 1.5, col: .ink(0.8))
            }
            if k % 4 == 0 { c += sceneLine([p, P(p.x + 6, p.y - 7)], width: 0.5) }
        }
        return c
    }

    private func sceneVine() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for strand in 0..<3 {
            let line = (0...50).map { i -> P in
                let t = Double(i) / 50
                return P(35 + Double(strand) * 12 + sin(t * 14) * (5 + t * 9), t * 110)
            }
            c += sceneLine(line, width: 0.8)
        }
        return c
    }

    private func sceneLotus() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for (x, y, rx, ry) in [(26.0, 79.0, 25.0, 9.0), (73, 92, 30, 10), (58, 47, 20, 8)] {
            let leaf = (0...36).map { i -> P in
                let a = 0.3 + Double(i) / 36 * 5.6
                return P(x + cos(a) * rx, y + sin(a) * ry)
            } + [P(x, y)]
            c.append(poly(leaf, fil: .ink(0.15), str: .ink(0.45), wid: 0.7))
            for j in 0..<7 {
                let a = 0.4 + Double(j) * 0.8
                c += sceneLine([P(x, y), P(x + cos(a) * rx * 0.9, y + sin(a) * ry * 0.9)], width: 0.35, tone: 0.3)
            }
            c += sceneLine([P(x, y), P(x - 3, 112)], width: 0.8, tone: 0.42)
        }
        c += sceneLine([P(38, 105), P(41, 66), P(39, 29)], width: 1.1)
        for k in -3...3 {
            let x = 39 + Double(k) * 4
            c += sceneLine([P(39, 32), P(x - 6, 22), P(x, 4 + abs(Double(k)) * 3), P(x + 6, 22), P(39, 32)], width: 0.7, tone: 0.5)
        }
        return c
    }

    private func sceneBridge() -> ZXArt.SSCanv {
        let top = (0...40).map { i -> P in
            let x = Double(i) * 3
            return P(x, 30 - sin(Double(i) / 40 * Double.pi) * 21)
        }
        let arch = (0...40).reversed().map { i -> P in
            let x = Double(i) * 3
            return P(x, 43 - sin(Double(i) / 40 * Double.pi) * 21)
        }
        var c = [poly(top + arch, fil: .white, str: .ink(0.6), wid: 1.0)]
        c += sceneLine(top.map { P($0.x, $0.y - 8) }, width: 0.9)
        for i in stride(from: 0, through: 40, by: 5) {
            let p = top[i]
            c += sceneLine([P(p.x, p.y - 10), P(p.x, p.y + 1)], width: 1)
        }
        for i in stride(from: 3, to: 38, by: 6) { c += sceneLine([top[i], arch[40 - i]], width: 0.45, tone: 0.3) }
        return c
    }

    private func sceneGate(temple: Bool) -> ZXArt.SSCanv {
        var c = [poly([P(0, 100), P(0, 55), P(105, 55), P(105, 100)], fil: .white, str: .ink(0.55), wid: 1)]
        c += sceneLine([P(35, 100), P(35, 69), P(41, 62), P(60, 62), P(67, 69), P(67, 100)], width: 1.5)
        c += roof(51, 32, hei: 19, wid: 115, rot: 0.5, per: 0.5)
        c += box(51, 55, hei: 23, wid: 83, rot: 0.5, per: 0.5, tra: false)
        c += roof(51, 28, hei: 20, wid: 110, rot: 0.5, per: 0.5)
        if temple { c += roof(51, 7, hei: 15, wid: 72, rot: 0.5, per: 0.5) }
        else {
            for k in 0..<8 { c += sceneLine([P(Double(k) * 15, 55), P(Double(k) * 15, 49), P(Double(k) * 15 + 8, 49)], width: 0.9) }
        }
        return c
    }

    private func sceneCourtyard() -> ZXArt.SSCanv {
        var c = [poly([P(0, 100), P(0, 43), P(40, 43), P(40, 23), P(100, 23), P(100, 100)], fil: .white, str: .ink(0.4), wid: 1)]
        c += sceneLine([P(0, 43), P(40, 43), P(40, 23), P(100, 23)], width: 2.2)
        c += sceneLine([P(0, 48), P(44, 48), P(44, 28), P(100, 28)], width: 0.7)
        c += sceneLine([P(57, 100), P(57, 67), P(65, 58), P(76, 58), P(84, 67), P(84, 100)], width: 1)
        for k in 0..<5 { c += sceneLine([P(6 + Double(k) * 8, 70), P(10 + Double(k) * 8, 70)], width: 0.6, tone: 0.22) }
        return c
    }

    private func sceneWindow() -> ZXArt.SSCanv {
        var c = sceneLine([P(5, 100), P(5, 4), P(85, 4), P(85, 100)], width: 2.8, tone: 0.65)
        c += sceneLine([P(11, 100), P(11, 10), P(79, 10), P(79, 100)], width: 0.8)
        for x in [28.0, 45, 62] { c += sceneLine([P(x, 12), P(x, 97)], width: 0.65, tone: 0.38) }
        for y in [31.0, 53, 75, 97] { c += sceneLine([P(12, y), P(78, y)], width: 0.65, tone: 0.38) }
        return c
    }

    private func sceneCurtain() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for k in 0..<10 {
            let x = Double(k) * 8
            c += sceneLine([P(x, 0), P(x + 2, 38), P(x + sin(Double(k)) * 4 + 12, 85 + cos(Double(k)) * 5)], width: 0.55, tone: 0.25)
        }
        c += sceneLine([P(0, 0), P(75, 0)], width: 1.8)
        return c
    }

    private func sceneTerrace() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for k in 0..<4 {
            let inset = Double(k) * 7, y = 100 - Double(k) * 8
            c += sceneLine([P(inset, y), P(120 - inset, y), P(120 - inset, y - 7), P(inset + 5, y - 7)], width: 1.5, tone: 0.52)
        }
        c += arch04(60, 69, hei: 18, wid: 70, sto: 1)
        return c
    }

    private func sceneRuins() -> ZXArt.SSCanv {
        let edge = [P(0, 100), P(0, 58), P(20, 58), P(20, 68), P(28, 68), P(28, 52), P(45, 52), P(45, 75), P(70, 75), P(70, 100)]
        var c = [poly(edge, fil: .white, str: .ink(0.45), wid: 1)]
        for k in 0..<10 {
            let x = r() * 65, y = 76 + r() * 20
            c += sceneLine([P(x, y), P(x + 7, y)], width: 0.6, tone: 0.3)
        }
        c += rock(78, 100, 3, hei: 12, wid: 18)
        return c
    }

    private func sceneFence() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for k in 0..<13 {
            let x = Double(k) * 8
            c += sceneLine([P(x + 3, 100), P(x, 74 + r() * 6)], width: 1.3, tone: 0.55)
        }
        for y in [83.0, 94] { c += sceneLine([P(0, y), P(105, y + 2)], width: 1.3, tone: 0.5) }
        return c
    }

    private func sceneFields() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for k in 0..<5 {
            let y = 20 + Double(k) * 16, half = 22 + Double(k) * 10
            c += sceneLine([P(60 - half, y), P(55, y - 5), P(60 + half, y)], width: 1.3, tone: 0.4)
        }
        for k in -3...3 { c += sceneLine([P(55 + Double(k) * 5, 15), P(60 + Double(k) * 19, 86)], width: 0.65, tone: 0.28) }
        return c
    }

    private func scenePath() -> ZXArt.SSCanv {
        let left = (0...50).map { i -> P in let t = Double(i) / 50; return P(44 + sin(t * 7) * (3 + t * 19), t * 100) }
        let right = (0...50).map { i -> P in let t = Double(i) / 50; return P(46 + sin(t * 7) * (3 + t * 19) + t * 22, t * 100) }
        return sceneLine(left, width: 1.0, tone: 0.3) + sceneLine(right, width: 0.8, tone: 0.25)
    }

    /// Adapt the legacy branch / bark vocabulary to bounded, readable bare-tree silhouettes.
    private func sceneBareTree() -> ZXArt.SSCanv {
        var c = sceneLine([P(49, 110), P(43, 84), P(48, 61), P(43, 38), P(51, 8)], width: 4.2, tone: 0.65)
        for k in 0..<7 {
            let side = k % 2 == 0 ? -1.0 : 1.0
            let y = 82 - Double(k) * 10, length = 25 + r() * 15
            let start = P(46, y), joint = P(46 + side * length * 0.45, y - 12), tip = P(46 + side * length, y - 33)
            c += sceneLine([start, joint, tip], width: 1.5 - Double(k) * 0.1, tone: 0.58)
            c += sceneLine([joint, P(joint.x - side * 4, joint.y - 16), P(joint.x + side * 4, joint.y - 25)], width: 0.65, tone: 0.55)
            c += sceneLine([tip, P(tip.x + side * 9, tip.y - 6)], width: 0.55, tone: 0.45)
        }
        return c
    }

    private func sceneBoat(_ kind: ZXArt.SceneMotif) -> ZXArt.SSCanv {
        var c = [poly([P(0, 80), P(18, 91), P(90, 91), P(110, 80), P(80, 85), P(20, 85)], fil: .white, str: .ink(0.7), wid: 1)]
        c += sceneLine([P(10, 82), P(100, 82)], width: 0.8, tone: 0.45)
        if kind == .sail {
            c += sceneLine([P(53, 85), P(53, 2)], width: 1.2)
            c += [poly([P(51, 5), P(20, 58), P(51, 63)], fil: .white, str: .ink(0.5), wid: 0.8)]
            for y in [25.0, 38, 51] { c += sceneLine([P(51, y), P(51 - y * 0.45, y - 2)], width: 0.6, tone: 0.3) }
        } else if kind == .angler {
            c += man(36, 83, sca: 0.6, hat: .hat02, len: [0, 30, 20, 28, 18, 25, 20, 20, 15])
            c += sceneLine([P(37, 64), P(88, 32), P(128, 23)], width: 0.8, tone: 0.7)
            c += sceneLine([P(128, 23), P(131, 60), P(130, 99)], width: 0.4, tone: 0.4)
        } else if kind == .mooredBoat {
            c += sceneLine([P(1, 81), P(-20, 68), P(-20, 54)], width: 0.6)
        } else { c += man(36, 83, sca: 0.6, hat: .hat02, ite: .stick01) }
        return c
    }

    private func sceneHorse() -> ZXArt.SSCanv {
        let outline = [P(20, 52), P(29, 43), P(45, 40), P(65, 43), P(74, 39),
            P(80, 26), P(83, 16), P(88, 11), P(95, 14), P(101, 24), P(98, 29),
            P(91, 26), P(86, 39), P(83, 54), P(73, 63), P(55, 66), P(34, 64)]
        // Periodic Catmull–Rom interpolation gives a continuous brush contour.
        var body: [P] = []
        for i in outline.indices {
            let p0 = outline[(i + outline.count - 1) % outline.count], p1 = outline[i]
            let p2 = outline[(i + 1) % outline.count], p3 = outline[(i + 2) % outline.count]
            for step in 0..<6 {
                let t = Double(step) / 6, t2 = t * t, t3 = t2 * t
                func coordinate(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                    0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                }
                body.append(P(coordinate(p0.x, p1.x, p2.x, p3.x), coordinate(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        var c = [poly(body, fil: .ink(0.25), str: .ink(0.7), wid: 1)]
        for line in [[P(31, 60), P(26, 83), P(20, 99)], [P(41, 61), P(47, 82), P(47, 99)], [P(69, 62), P(65, 83), P(60, 99)], [P(78, 59), P(85, 80), P(82, 98)]] {
            c += sceneLine(line, width: 2.0, tone: 0.7)
        }
        c += sceneLine([P(21, 51), P(12, 56), P(10, 80), P(4, 87)], width: 2.1)
        c += sceneLine([P(87, 13), P(84, 26), P(78, 41)], width: 2.6)
        c += sceneLine([P(89, 9), P(88, 0), P(93, 8)], width: 0.9)
        return c
    }

    private func sceneEgret() -> ZXArt.SSCanv {
        var c = sceneEllipse(43, 56, 18, 8, fill: .white, tone: 0.7)
        c += sceneLine([P(54, 54), P(66, 39), P(59, 24), P(64, 11), P(74, 10), P(87, 13)], width: 2.4, tone: 0.65)
        c += sceneLine([P(43, 63), P(43, 86), P(34, 99)], width: 0.9)
        c += sceneLine([P(49, 62), P(51, 84), P(54, 99)], width: 0.9)
        return c
    }

    private func sceneBird(swallow: Bool) -> ZXArt.SSCanv {
        if swallow {
            return sceneLine([P(0, 0), P(17, 13), P(30, 16), P(43, 7), P(62, 0)], width: 2.2, tone: 0.75)
                + sceneLine([P(29, 14), P(24, 29), P(34, 21), P(43, 29), P(34, 13)], width: 1.4, tone: 0.7)
        }
        var c = blob(30, 35, len: 25, wid: 15, ang: 0.4, col: .ink(0.85))
        c += blob(44, 24, len: 11, wid: 10, col: .ink(0.85))
        c += sceneLine([P(46, 23), P(57, 26)], width: 1.3)
        c += sceneLine([P(20, 38), P(9, 49)], width: 3)
        c += sceneLine([P(29, 39), P(30, 51), P(37, 52)], width: 0.8)
        return c
    }

    private func sceneDragonfly() -> ZXArt.SSCanv {
        var c = sceneLine([P(50, 20), P(48, 70)], width: 1.2, tone: 0.7)
        for (x, y) in [(4.0, 20.0), (90, 24), (13, 45), (84, 49)] {
            c += sceneEllipse((x + 48) / 2, (y + 37) / 2, abs(x - 48) / 2, 3, fill: .white, tone: 0.4)
        }
        return c
    }

    private func sceneButterfly() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for (x, y, a) in [(33.0, 25.0, -0.7), (65, 25, 0.7), (37, 49, 0.4), (61, 49, -0.4)] {
            c += blob(x, y, len: 35, wid: 21, ang: a, col: .ink(0.35))
        }
        c += sceneLine([P(49, 25), P(49, 65)], width: 2)
        return c
    }

    private func sceneStream() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for offset in [0.0, 16] {
            c += sceneLine((0...35).map { i in let t = Double(i) / 35; return P(45 + sin(t * 8) * (8 + t * 16) + offset * t, t * 100) }, width: 1, tone: 0.4)
        }
        for k in 1..<8 {
            let y = Double(k) * 13, x = 45 + sin(y / 100 * 8) * (8 + y * 0.16)
            c += sceneLine([P(x + 4, y), P(x + 10, y + 1)], width: 0.7, tone: 0.28)
        }
        return c
    }

    private func sceneWaterfall() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for k in 0..<8 {
            let x = 40 + Double(k) * 3
            let pts = (0...24).map { i -> P in let t = Double(i) / 24; return P(x + sin(t * 9 + Double(k)) * 1.5, t * 100) }
            c += sceneLine(pts, width: k == 0 || k == 7 ? 1.6 : 0.5, tone: k == 0 || k == 7 ? 0.6 : 0.18)
        }
        c += sceneEllipse(50, 105, 22, 3, tone: 0.24)
        return c
    }

    private func sceneDunes() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for row in 0..<3 {
            let y = 28 + Double(row) * 27
            let points = (0...60).map { i -> P in let x = Double(i) * 3; return P(x, y - sin(Double(i) / 60 * Double.pi + Double(row) * 0.7) * 20) }
            c += sceneLine(points, width: 1.6, tone: 0.28 + Double(row) * 0.10)
            for j in 1...5 { c += sceneLine(points.map { P($0.x, $0.y + Double(j) * 1.8) }, width: 0.4, tone: 0.04) }
        }
        return c
    }

    private func sceneSmoke(beacon: Bool) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for k in 0..<5 {
            let points = (0...35).map { i -> P in
                let t = Double(i) / 35
                let dx = beacon ? sin(t * 3) * 2 : sin(t * 10) * 7 + t * 16
                return P(30 + dx + Double(k) * (1 - t) * 1.5, 100 - t * 100)
            }
            c += sceneLine(points, width: beacon ? 1.0 : 0.7, tone: 0.12 + Double(k) * 0.015)
        }
        return c
    }

    private func sceneMist() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for k in 0..<7 {
            c += sceneEllipse(60 + sin(Double(k)) * 20, 30 + Double(k) * 2, 65, 5,
                              fill: C(255, 255, 255, 0.2), tone: 0)
        }
        return c
    }

    private func sceneCelestial(_ kind: ZXArt.SceneMotif) -> ZXArt.SSCanv {
        if kind == .crescent {
            let outer = (0...40).map { i -> P in let a = Double(i) / 40 * Double.pi; return P(40 + sin(a) * 25, 35 - cos(a) * 25) }
            let inner = (0...40).reversed().map { i -> P in let a = Double(i) / 40 * Double.pi; return P(40 + sin(a) * 13, 35 - cos(a) * 25) }
            return [poly(outer + inner, fil: .ink(0.25), str: .ink(0.28), wid: 0.4)]
        }
        return sceneEllipse(40, 40, 25, 25, fill: kind == .moon ? .white : .ink(0.28), tone: kind == .moon ? 0.2 : 0.1)
    }

    private func sceneStars() -> ZXArt.SSCanv {
        (0..<9).flatMap { _ in sceneEllipse(r() * 100, r() * 65, 0.5 + r(), 0.5 + r(), fill: .ink(0.4), tone: 0) }
    }

    private func sceneSnowGround() -> ZXArt.SSCanv {
        (0..<5).flatMap { k in sceneLine([P(0, Double(k) * 10), P(30, Double(k) * 10 - 3), P(70, Double(k) * 10 + 1), P(110, Double(k) * 10)], width: 1.2, tone: 0.15) }
    }

    private func sceneWaves() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for row in 0..<7 {
            let y = Double(row) * 14
            let pts = (0...70).map { i -> P in let x = Double(i) * 3; return P(x, y + sin(x * 0.045 + Double(row) * 1.5) * (1 + Double(row) * 0.7)) }
            c += sceneLine(pts, width: 0.5 + Double(row) * 0.12, tone: 0.12 + Double(row) * 0.035)
        }
        return c
    }
}
