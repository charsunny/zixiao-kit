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
        let height = 135 + r() * 22, girth = old ? 19 + r() * 7 : 8 + r() * 3
        let joints = [root, root + P(-direction * 5, -height * 0.20),
            root + P(direction * (old ? 14 : 6), -height * 0.43),
            root + P(lean * 0.45 - direction * 6, -height * 0.66),
            root + P(lean * 0.78, -height * 0.84), root + P(lean, -height)]
        let spine = inkCurve(joints, steps: 10)
        func at(_ t: Double) -> P { spine[min(spine.count - 1, Int(t * Double(spine.count - 1)))] }
        // Keep long limbs angular and ascending. Only the terminal twigs make crab claws.
        // Fine strokes are filled tapers, so no constant-width bristle survives the lifted tip.
        func branchStroke(_ path: [P], width: Double, tone: Double) -> ZXArt.SSCanv {
            var left: [P] = [], right: [P] = []
            for i in path.indices {
                let t = Double(i) / Double(path.count - 1)
                let delta = path[min(i + 1, path.count - 1)] - path[max(0, i - 1)]
                let length = max(0.001, hypot(delta.x, delta.y))
                let pressure = pow(1 - t, 0.85) * (0.94 + 0.06 * sin(t * 19))
                let offset = P(-delta.y, delta.x) * (width * pressure * 0.5 / length)
                left.append(path[i] + offset); right.append(path[i] - offset)
            }
            var marks = [poly(left + right.reversed(), fil: .gray(0, tone), str: nil)]
            if width > 2.5 {
                // A dry split stays inside the broad base and ends before the fine tip.
                let split = Array(path.dropFirst(2).prefix(path.count / 2))
                marks += inkLine(split, width: width * 0.13, tone: 0.22, dry: 0.65, profile: .cone)
            }
            return marks
        }
        func terminals(_ tip: P, side: Double, pale: Double) -> ZXArt.SSCanv {
            var tips: ZXArt.SSCanv = []
            let count = 3 + Int(r() * 3)
            for j in 0..<count {
                let spread = Double(j) / Double(count - 1)
                let origin = tip + P(-side * spread * 3.5, spread * 1.2)
                let reach = 3 + r() * 3.5 + spread * 2
                let end: P
                let bend: P
                if form == 0 {
                    bend = origin + P(side * reach * (0.5 + spread * 0.5), -1.5 + spread)
                    end = bend + P(-side * (0.5 + r() * 1.5), 3 + r() * 4)
                } else {
                    bend = origin + P(side * (spread - 0.15) * reach, -reach * 0.55)
                    end = bend + P(side * (spread - 0.4) * 3, -2 - r() * 3)
                }
                tips += branchStroke(inkCurve([origin, bend, end]), width: 0.45 + r() * 0.25, tone: pale)
            }
            return tips
        }
        var c: ZXArt.SSCanv = [], frontBranches: ZXArt.SSCanv = [], perches: [P] = []
        let branches = form == 2 ? 6 : 5
        for k in 0..<branches {
            let t = 0.30 + Double(k) * 0.60 / Double(branches - 1)
            let from = at(t)
            let side = (k == 1 || k == 4) ? -direction : direction
            let sparse = side != direction
            let reach = (32 + r() * 20) * (sparse ? 0.66 : 1.0) * (1.14 - t * 0.42)
            let rise = (form == 0 ? 14.0 : 26.0) + r() * 13
            let elbow = from + P(side * reach * 0.55, -rise * 0.55)
            let tip = from + P(side * reach, -rise)
            let limb = inkCurve([from, from + P(side * reach * 0.22, -rise * 0.12), elbow, tip])
            let foreground = k == 0 || k == 3
            var branch = branchStroke(limb, width: (old ? 6.5 : 3.8) * (1 - t * 0.55),
                tone: foreground ? 0.77 : 0.61)
            perches.append(elbow)
            let forks = sparse ? 2 : 3
            for j in 0..<forks {
                let u = 0.40 + Double(j) * 0.23
                let origin = limb[Int(u * Double(limb.count - 1))]
                let length = 12 + r() * 10
                let end = origin + P(side * length * (j % 2 == 0 ? 0.60 : 0.95),
                    -length * (j % 2 == 0 ? 1.05 : 0.30))
                let secondary = inkCurve([origin, origin + (end - origin) * 0.48 + P(-side * 2, 1), end])
                branch += branchStroke(secondary, width: 1.5 + r() * 0.7, tone: foreground ? 0.61 : 0.50)
                // Each secondary carries an offset fine twig and its own continuing tip.
                let twigRoot = secondary[secondary.count / 2]
                let twigEnd = twigRoot + P(side * (5 + r() * 6), -4 - r() * 7)
                branch += branchStroke(inkCurve([twigRoot, (twigRoot + twigEnd) / 2 + P(side * 1.5, 1), twigEnd]),
                    width: 0.8 + r() * 0.3, tone: 0.46)
                branch += terminals(twigEnd, side: side, pale: 0.37)
                branch += terminals(end, side: side, pale: 0.43)
            }
            branch += terminals(tip, side: side, pale: 0.43)
            if foreground { frontBranches += branch } else { c += branch }
        }
        let crown = at(1)
        for side in [-direction, direction] {
            let end = crown + P(side * (7 + r() * 6), -6 - r() * 5)
            c += branchStroke(inkCurve([at(0.92), crown, end]), width: 1.4, tone: 0.50)
            c += terminals(end, side: side, pale: 0.39)
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
        c += frontBranches
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
