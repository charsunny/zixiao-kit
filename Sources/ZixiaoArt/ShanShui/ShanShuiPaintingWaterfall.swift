// shanshui@5: a fall is the reserved white between two loaded cliff faces.
import Foundation

extension ShanShuiEngine {
    struct PaintedWaterfall {
        var canvas: ZXArt.SSCanv
        var outlet: P
    }

    func paintingWaterfall() -> PaintedWaterfall {
        let form = Int(r() * 65536) % 3, tiers = form == 2 ? 2 : 1
        let gap = form == 1 ? 24 + r() * 10 : 13 + r() * 7
        let height = form == 1 ? 153.0 : (form == 2 ? 205.0 : 183.0)
        let bend = tiers == 2 ? 14 + r() * 12 : (r() - 0.5) * 9
        let center = tiers == 2
            ? [P(58, 10), P(57, height * 0.40), P(58 + bend, height * 0.51), P(59 + bend, height)]
            : [P(58, 10), P(59 + bend, height)]
        let left = center.map { $0 - P(gap / 2, 0) }, right = center.map { $0 + P(gap / 2, 0) }
        var c: ZXArt.SSCanv = []
        for side in [-1.0, 1.0] {
            let edge = side < 0 ? left : right
            let first = edge[0], last = edge.last!
            let outer = [P(first.x + side * (26 + r() * 10), side < 0 ? 5 : 18),
                P(first.x + side * (39 + r() * 12), height * 0.34),
                P(last.x + side * 30, height * 0.71), P(last.x + side * 37, height + 9)]
            c.append(poly(edge + outer.reversed(), fil: .white, str: nil))
            for j in 0..<(edge.count - 1) {
                let a = edge[j], b = edge[j + 1]
                c.append(poly([a, b, b + P(side * 12, 0), a + P(side * 18, 7)],
                    fil: .gray(0, 0.14 + r() * 0.08), str: nil))
                c += inkLine([a + P(side * 2, 3), (a + b) / 2 + P(side * 5, 0), b + P(side * 9, -4)],
                    width: 7 + r() * 5, tone: 0.84, dry: 0.48, profile: .cone)
            }
            for j in 0..<3 {
                let t = 0.10 + Double(j) * 0.27
                let p = first + (last - first) * t + P(side * (13 + r() * 8), 0)
                let reach = height * (0.16 + r() * 0.12)
                c += inkLine([p, p + P(side * 8, reach * 0.45), p + P(side * 16, reach)],
                    width: 3 + r() * 3, tone: 0.56, dry: 0.63, profile: .cone)
                c += inkLine([p + P(side * 5, 3), p + P(side * 16, reach * 0.75)],
                    width: 0.9, tone: 0.50, dry: 0.6)
            }
            c += inkEdges(outer, width: 1.6, tone: 0.64, dry: 0.42)
            c += inkEdges(edge, width: 1.4, tone: 0.75, dry: 0.35)
            c += inkEdges([outer[0], P(first.x + side * 12, outer[0].y - 2), first],
                width: 1.8, tone: 0.72, dry: 0.4)
        }
        // No grey strip in the fall: a few dilute vertical streaks on paper.
        let water = left + right.reversed()
        c.append(poly(water, fil: .white, str: nil))
        for offset in [-gap * 0.26, gap * 0.18] {
            let line = center.map { $0 + P(offset, 0) }
            c += inkLine(inkCurve(line), width: 0.65, tone: 0.16, dry: 0.50)
        }
        if tiers == 2 {
            c += inkLine([left[1] + P(-2, 6), center[2] + P(0, -3), right[2] + P(4, -2)],
                width: 1.0, tone: 0.35, dry: 0.55)
        }
        let foot = center.last!
        // Spray opens the cliff foot: soft paper blotches, not an opaque rectangular mask.
        for _ in 0..<8 {
            let x = foot.x + (r() - 0.5) * 43, y = height - 1 + r() * 13
            c += inkBlot(x, y, radius: 7 + r() * 6, squash: 0.45, tone: 0.04).map { p in
                var q = p; q.fil = C(255, 255, 255, 0.65); return q
            }
        }
        let outlet = P(foot.x + 19, height + 50)
        let l = inkCurve([foot + P(-14, 9), foot + P(-21, 24), outlet + P(-10, 0)])
        let rr = inkCurve([foot + P(17, 9), foot + P(9, 29), outlet + P(11, 0)])
        for edge in [l, rr] { c += inkLine(edge, width: 1.1, tone: 0.48, dry: 0.45) }
        for (dx, dy) in [(-10.0, 18.0), (4, 24), (9, 39)] {
            c += inkLine([foot + P(dx, dy), foot + P(dx + 8, dy - 0.3)], width: 0.65, tone: 0.24, dry: 0.45)
        }
        return .init(canvas: c, outlet: outlet)
    }
}
