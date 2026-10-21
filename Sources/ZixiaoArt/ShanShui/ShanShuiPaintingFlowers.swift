// shanshui@5: flowers grow from branches and lotus leaves rise on straight stalks.
import Foundation

extension ShanShuiEngine {
    struct PaintedLotus {
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

    func paintingLotusDrawing() -> PaintedLotus {
        let form = Int(r() * 65536) % 3, count = 3 + Int(r() * 65536) % 3
        var c: ZXArt.SSCanv = []
        for k in 0..<count {
            let x = 25 + Double(k) * 112 / Double(count - 1) + (r() - 0.5) * 10
            let y = 67 + r() * 48, rx = 23 + r() * 15, ry = 12 + r() * 10
            let tilt = (r() - 0.5) * 0.35, phase = r() * 6
            func placed(_ p: P) -> P { P(x + p.x * cos(tilt) - p.y * sin(tilt), y + p.x * sin(tilt) + p.y * cos(tilt)) }
            let stalk = [P(x + 2, 150 + r() * 4), P(x + 0.6, y + 3)]
            c += inkLine(stalk, width: 1.3 + r() * 0.6, tone: 0.68, dry: 0.28, profile: .even)
            for sy in stride(from: y + 15, to: 146, by: 9) {
                c += inkLine([P(x + 1, sy), P(x + (Int(sy) % 2 == 0 ? 2.8 : -0.8), sy - 0.8)],
                    width: 0.8, tone: 0.74, dry: 0.2)
            }
            let edge = (0...64).map { i -> P in
                let a = Double(i) * .pi / 32
                let wave = 1 + 0.055 * sin(a * 7 + phase) + 0.035 * cos(a * 11)
                return placed(P(cos(a) * rx * wave, sin(a) * ry * wave))
            }
            let tone = 0.40 + Double(k) / Double(count) * 0.28 + r() * 0.09
            c.append(poly(edge, fil: .white, str: nil))
            c.append(poly(edge, fil: .gray(0, tone), str: nil))
            // A folded lip exposes paper between the upper and lower leaf planes.
            let fold = inkCurve([placed(P(-rx * 0.92, -ry * 0.2)), placed(P(-rx * 0.2, -ry * 0.45)),
                placed(P(rx * 0.40, -ry * 0.08)), placed(P(rx * 0.92, -ry * 0.24))])
            c.append(poly(fold + fold.reversed().map { $0 + P(0, 1.5) }, fil: .white, str: nil))
            c += inkLine(fold, width: 1.8, tone: min(0.88, tone + 0.18), dry: 0.4)
            let center = placed(P(0, ry * 0.12))
            for j in 0..<7 {
                let a = Double(j) * .pi / 3.5 + 0.25
                let tip = placed(P(cos(a) * rx * 0.83, sin(a) * ry * 0.85))
                c.append(poly([center, tip, tip + P(0.2, 0.25), center + P(0.7, 0.4)], fil: .white, str: nil))
            }
            // Broken darker ink is bounded by the leaf, concentrated near its stem and rim.
            for _ in 0..<7 {
                let p = placed(P((r() - 0.5) * rx * 1.25, (r() - 0.5) * ry))
                c += inkBlot(p.x, p.y, radius: 2 + r() * 4, squash: 0.35, tone: 0.12)
            }
        }
        let fx = 69 + r() * 24, fy = 37 + r() * 6
        c += inkLine([P(fx + 1, 153), P(fx, fy + 15)], width: 1.3, tone: 0.65, dry: 0.28)
        let tip: P
        if form == 0 {
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
        return .init(canvas: c, flowerTip: tip)
    }
}
