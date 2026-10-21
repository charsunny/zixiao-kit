// shanshui@5: the trunk, vine and perches share one branch skeleton.
import Foundation

extension ShanShuiEngine {
    struct PaintedWoodyTree {
        var canvas: ZXArt.SSCanv
        var vine: ZXArt.SSCanv
        var perches: [P]
    }

    func paintingWoodyTree(old: Bool) -> PaintedWoodyTree {
        let root = old ? P(65, 175) : P(66, 178)
        let form = Int(r() * 65536) % 3
        let direction = r() < 0.5 ? -1.0 : 1.0
        let lean = direction * (form == 1 ? 43 + r() * 16 : 12 + r() * 17)
        let height = 135 + r() * 22, girth = old ? 14 + r() * 5 : 7 + r() * 3
        let joints = [root, root + P(-direction * 5, -height * 0.20),
            root + P(direction * (old ? 14 : 6), -height * 0.43),
            root + P(lean * 0.45 - direction * 6, -height * 0.66),
            root + P(lean * 0.78, -height * 0.84), root + P(lean, -height)]
        let spine = inkCurve(joints, steps: 10)
        func at(_ t: Double) -> P { spine[min(spine.count - 1, Int(t * Double(spine.count - 1)))] }
        var c: ZXArt.SSCanv = [], perches: [P] = []
        let branches = form == 2 ? 6 : 4
        for k in 0..<branches {
            let t = 0.34 + Double(k) * 0.56 / Double(branches - 1)
            let from = at(t), side = k % 2 == 0 ? -direction : direction
            let length = (31 + r() * 22) * (1.15 - t * 0.45)
            let elbow = from + P(side * length * 0.55, -11 - r() * 11)
            let tip = elbow + P(side * length * 0.45, form == 0 ? 4 + r() * 9 : -17 - r() * 11)
            c += inkLine(inkCurve([from, from + P(side * 8, -5), elbow, tip]),
                width: (old ? 7.5 : 4.3) * (1 - t * 0.6), tone: 0.85, dry: 0.34, profile: .cone)
            perches.append(elbow)
            for j in 0..<2 {
                let origin = j == 0 ? elbow : tip
                let end = origin + P(side * (9 + r() * 9), form == 0 ? 9 + r() * 9 : -13 - r() * 8)
                let bend = origin + P(side * 8, -6 - r() * 5)
                c += inkLine(inkCurve([origin, bend, end]), width: 1.2 + r() * 0.7,
                    tone: 0.73, dry: 0.38, profile: .cone)
            }
        }
        // A tapered, outlined trunk keeps paper in its lit side; knots interrupt the bark.
        let left = spine.enumerated().map { i, p -> P in
            let t = Double(i) / Double(spine.count - 1)
            return p + P(-girth * 0.5 * pow(1 - t, 0.8), 0)
        }
        let right = spine.enumerated().map { i, p -> P in
            let t = Double(i) / Double(spine.count - 1)
            return p + P(girth * 0.5 * pow(1 - t, 0.8), 0)
        }
        c.append(poly(left + right.reversed(), fil: .white, str: nil))
        c += inkLine(left, width: old ? 2.4 : 1.6, tone: 0.78, dry: 0.4)
        c += inkLine(right.reversed(), width: old ? 3.5 : 2.0, tone: 0.88, dry: 0.36)
        for k in 0..<4 {
            let start = 0.08 + Double(k) * 0.19
            let run = (0...10).map { j -> P in
                let t = start + Double(j) * 0.012
                return at(t) + P(girth * (0.14 + 0.1 * sin(t * 20)), 0)
            }
            c += inkLine(run, width: old ? 2.0 : 0.8, tone: 0.5, dry: 0.65)
        }
        if old {
            for t in [0.26, 0.54, 0.73] {
                let p = at(t) + P(-girth * 0.12, 0), radius = girth * (1 - t) * 0.24
                let knot = (0...20).map { i -> P in
                    let a = Double(i) * .pi / 10
                    return p + P(cos(a) * radius, sin(a) * radius * 1.7)
                }
                c += inkLine(knot, width: 1.2, tone: 0.72, dry: 0.42)
                c += inkLine([p + P(0, -radius), p + P(0.5, radius)], width: 1.2, tone: 0.85)
            }
        }
        for dx in [-15.0, -6, 12] {
            c += inkLine(inkCurve([root + P(dx * 0.15, -13), root + P(dx * 0.5, -1), root + P(dx, 3)]),
                width: old ? 3.4 : 2.0, tone: 0.76, dry: 0.42, profile: .cone)
        }
        // The vine alternates exposed crossings around the same twisting trunk, then drops
        // from a real branch. Gaps stand for the hidden back of each turn.
        var vine: ZXArt.SSCanv = []
        for k in 0..<4 {
            let start = 0.13 + Double(k) * 0.17
            let wrap = (0...18).map { j -> P in
                let u = Double(j) / 18, t = start + u * 0.13
                return at(t) + P(cos(u * .pi) * girth * (1 - t) * 0.70, 0)
            }
            vine += inkLine(wrap, width: 1.0, tone: 0.72, dry: 0.35)
        }
        for perch in perches.prefix(form == 2 ? 2 : 1) {
            let loop = inkCurve([perch + P(-7, 4), perch + P(-3, -4), perch + P(5, -2),
                perch + P(9, 17), perch + P(3, 37), perch + P(11, 58 + r() * 15)])
            vine += inkLine(loop, width: 0.9, tone: 0.68, dry: 0.4)
            for p in loop.prefix(15) where r() < 0.2 {
                vine += inkLine([p, p + P(3, 2)], width: 2.0, tone: 0.8, profile: .lens)
            }
        }
        return .init(canvas: c, vine: vine, perches: perches)
    }
}
