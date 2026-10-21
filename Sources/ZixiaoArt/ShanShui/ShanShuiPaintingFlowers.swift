// shanshui@5: flowers grow from branches and lotus leaves rise on straight stalks.
import Foundation

extension ShanShuiEngine {
    enum LotusStage: String, CaseIterable { case young, flowering, spent }

    struct PaintedLotus {
        var stage: LotusStage
        var canvas: ZXArt.SSCanv
        var flowerTip: P
    }

    func paintingFloweringTree() -> ZXArt.SSCanv {
        let plum = r() < 0.5, branches = 3 + Int(r() * 65536) % 3
        let lean = (r() - 0.5) * 65
        let trunk = inkCurve([P(66, 178), P(62, 149), P(73, 119), P(61 + lean * 0.4, 84), P(66 + lean, 30)])
        var c = inkLine(trunk, width: plum ? 7.5 : 5, tone: 0.82, dry: 0.4, profile: .cone)
        c += inkLine(trunk.map { $0 + P(-1.5, 0) }, width: 1.1, tone: 0.4, dry: 0.65)
        for k in 0..<branches {
            let t = 0.32 + Double(k) * 0.14
            let origin = trunk[Int(t * Double(trunk.count - 1))]
            let side = k % 2 == 0 ? -1.0 : 1.0
            let elbow = origin + P(side * (18 + r() * 13), -17 - r() * 14)
            let end = elbow + P(side * (13 + r() * 17), -16 - r() * 18)
            let limb = inkCurve([origin, elbow, end])
            c += inkLine(limb, width: 3.6 - Double(k) * 0.45, tone: 0.8, dry: 0.38, profile: .cone)
            for j in 0..<3 {
                let from = limb[(j + 1) * (limb.count - 1) / 4]
                let tip = from + P(side * (j == 1 ? -8 : 11), -12 - r() * 14)
                let twig = inkCurve([from, from + P(side * 4, -9), tip])
                c += inkLine(twig, width: 1.0, tone: 0.67, dry: 0.35)
                let flowers = plum ? 2 + Int(r() * 2) : 4 + Int(r() * 3)
                for f in 0..<flowers {
                    let u = Double(f + 1) / Double(flowers + 1)
                    let branch = twig[Int(u * Double(twig.count - 1))]
                    let p = branch + P(f % 2 == 0 ? -3 : 3, -1)
                    if r() < 0.23 {
                        c += inkBlot(p.x, p.y, radius: 1.4, squash: 0.8, tone: 0.65)
                    } else {
                        let radius = plum ? 1.4 + r() * 0.5 : 1.6 + r() * 0.7
                        for petal in 0..<5 {
                            let a = Double(petal) * .pi * 0.4
                            let center = p + P(cos(a), sin(a)) * radius
                            let ring = (0...8).map { i -> P in
                                let angle = Double(i) * .pi / 4
                                return center + P(cos(angle), sin(angle)) * radius * 0.72
                            }
                            c.append(poly(ring, fil: .white, str: nil))
                            c += inkLine(ring, width: 0.55, tone: plum ? 0.56 : 0.42, dry: 0.25)
                        }
                        c += inkBlot(p.x, p.y, radius: 0.6, tone: 0.8)
                    }
                }
            }
        }
        for dx in [-8.0, 10] {
            c += inkLine([P(66, 169), P(66 + dx * 0.4, 177), P(66 + dx, 180)], width: 2, tone: 0.7)
        }
        return c
    }

    func paintingLotusDrawing(stage requested: LotusStage? = nil) -> PaintedLotus {
        let choice = Int(r() * 65536) % 3
        let stage = requested ?? LotusStage.allCases[choice]
        let form = Int(r() * 65536) % 3
        let count = stage == .young ? 3 : 3 + Int(r() * 65536) % (stage == .spent ? 2 : 3)
        var c: ZXArt.SSCanv = []
        for k in 0..<count {
            let x = 25 + Double(k) * 112 / Double(count - 1) + (r() - 0.5) * 10
            let y = 67 + r() * 48
            let rx = stage == .young ? 13 + r() * 10 : 23 + r() * 15
            let ry = stage == .young ? 6 + r() * 6 : (stage == .spent ? 9 + r() * 8 : 12 + r() * 10)
            let tilt = (r() - 0.5) * 0.35, phase = r() * 6
            func placed(_ p: P) -> P { P(x + p.x * cos(tilt) - p.y * sin(tilt), y + p.x * sin(tilt) + p.y * cos(tilt)) }
            let stalk = stage == .spent && k == 1
                ? [P(x + 2, 152), P(x - 5, y + 24), P(x + 0.6, y + 3)]
                : [P(x + 2, 150 + r() * 4), P(x + 0.6, y + 3)]
            c += inkLine(stalk, width: 1.3 + r() * 0.6, tone: 0.68, dry: 0.28, profile: .even)
            for sy in stride(from: y + 15, to: 146, by: 9) {
                c += inkLine([P(x + 1, sy), P(x + (Int(sy) % 2 == 0 ? 2.8 : -0.8), sy - 0.8)],
                    width: 0.8, tone: 0.74, dry: 0.2)
            }
            if stage == .young && k == 0 {
                // The first leaf is still rolled: a pointed fold, with a narrow paper seam.
                let rolled = inkCurve([P(x, y + 6), P(x - 5, y - 6), P(x + 2, y - 31),
                    P(x + 7, y - 4), P(x, y + 6)])
                c.append(poly(rolled, fil: .gray(0, 0.48), str: nil))
                c += inkLine([P(x + 2, y - 29), P(x + 1, y + 3)], width: 0.7, tone: 0.8)
                continue
            }
            let edge = (0...64).map { i -> P in
                let a = Double(i) * .pi / 32
                var wave = 1 + 0.055 * sin(a * 7 + phase) + 0.035 * cos(a * 11)
                if stage == .spent {
                    let tear = abs(atan2(sin(a - phase), cos(a - phase)))
                    if tear < 0.30 { wave *= 0.35 + tear * 2 }
                    wave += 0.09 * sin(a * 13 + phase)
                }
                return placed(P(cos(a) * rx * wave, sin(a) * ry * wave))
            }
            let tone = stage == .spent ? 0.16 + r() * 0.18 : 0.48 + Double(k) / Double(count) * 0.28 + r() * 0.12
            c.append(poly(edge, fil: .white, str: nil))
            c.append(poly(edge, fil: .gray(0, tone), str: nil))
            // A folded lip exposes paper between the upper and lower leaf planes.
            let fold = inkCurve([placed(P(-rx * 0.92, -ry * 0.2)), placed(P(-rx * 0.2, -ry * 0.45)),
                placed(P(rx * 0.40, -ry * 0.08)), placed(P(rx * 0.92, -ry * 0.24))])
            c.append(poly(fold + fold.reversed().map { $0 + P(0, 0.75) }, fil: .white, str: nil))
            c += inkLine(fold, width: 1.8, tone: min(0.88, tone + 0.18), dry: 0.4)
            if stage == .spent {
                c += inkLine(Array(edge[6...28]), width: 1.5, tone: 0.68, dry: 0.6)
                c += inkLine(Array(edge[39...59]), width: 2.2, tone: 0.75, dry: 0.55)
                for j in [11, 20, 27] {
                    let p = edge[j]
                    c += inkLine([p, p + P(3, 8 + r() * 10), p + P(7, 5 + r() * 7)],
                        width: 0.9, tone: 0.60, dry: 0.6)
                }
            }
            let center = placed(P(0, ry * 0.12))
            for j in 0..<7 {
                let a = Double(j) * .pi / 3.5 + 0.25
                let tip = placed(P(cos(a) * rx * 0.83, sin(a) * ry * 0.85))
                c.append(poly([center, tip, tip + P(0.2, 0.25), center + P(0.5, 0.3)], fil: stage == .spent ? .gray(0, 0.40) : C(255, 255, 255, 0.65), str: nil))
            }
            // Broken darker ink is bounded by the leaf, concentrated near its stem and rim.
            for _ in 0..<7 {
                let p = placed(P((r() - 0.5) * rx * 1.25, (r() - 0.5) * ry))
                c += inkBlot(p.x, p.y, radius: rx * (0.15 + r() * 0.15), squash: ry / rx * 0.65, tone: 0.12)
            }
        }
        let fx = 69 + r() * 24, fy = 37 + r() * 6
        c.insert(contentsOf: inkLine([P(fx + 1, 153), P(fx, fy + 12)], width: 1.3, tone: 0.65, dry: 0.28), at: 0)
        let tip: P
        if stage == .spent {
            tip = P(fx, fy - 7)
            let pod = inkCurve([P(fx - 11, fy), P(fx - 5, fy + 8), P(fx, fy + 12),
                P(fx + 7, fy + 6), P(fx + 12, fy - 3)])
            c.append(poly(pod, fil: .white, str: nil))
            c += inkLine(pod, width: 1.2, tone: 0.72, dry: 0.50)
            let rim = (0...24).map { j -> P in
                let a = Double(j) * .pi / 12
                return P(fx + cos(a) * 12, fy - 2 + sin(a) * 5)
            }
            c.append(poly(rim, fil: .gray(0, 0.18), str: nil))
            c += inkLine(rim, width: 1.0, tone: 0.68, dry: 0.45)
            for dx in [-6.0, 0, 5] {
                c += inkBlot(fx + dx, fy - 2 + r() * 2, radius: 1.0, squash: 0.6, tone: 0.85)
            }
        } else if stage == .young || form == 0 {
            tip = P(fx, fy - 18)
            let bud = inkCurve([P(fx, fy + 12), P(fx - 6, fy + 2), tip, P(fx + 7, fy + 2), P(fx, fy + 12)])
            c.append(poly(bud, fil: .white, str: nil))
            c += inkLine(bud, width: 0.9, tone: 0.7, dry: 0.25)
            c += inkLine([tip, P(fx + 2, fy + 7)], width: 0.55, tone: 0.5)
        } else {
            tip = P(fx, fy - 19)
            for dx in [-16.0, 14, -8, 7, 0] {
                let petalTip = P(fx + dx, fy - (dx == 0 ? 19 : 10))
                let petal = inkCurve([P(fx, fy + 12), P(fx + dx - 6, fy), petalTip,
                    P(fx + dx + 6, fy + 3), P(fx, fy + 12)])
                c.append(poly(petal, fil: .white, str: nil))
                c += inkLine(petal, width: 0.65, tone: 0.62, dry: 0.25)
            }
        }
        for x in [7.0, 78, 133] {
            c += inkLine([P(x, 156 + r() * 4), P(x + 23 + r() * 12, 156)], width: 0.65, tone: 0.2, dry: 0.5)
        }
        return .init(stage: stage, canvas: c, flowerTip: tip)
    }
}
