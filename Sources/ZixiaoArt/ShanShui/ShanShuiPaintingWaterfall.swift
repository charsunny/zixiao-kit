// shanshui@5: a fall is the reserved white between two loaded cliff faces.
import Foundation

extension ShanShuiEngine {
    struct PaintedWaterfall {
        var canvas: ZXArt.SSCanv
        var outlet: P
    }

    func paintingWaterfall() -> PaintedWaterfall {
        let tiers = 1 + Int(r() * 65536) % 2
        let gap = 10 + r() * 12, bend = tiers == 2 ? 13 + r() * 9 : (r() - 0.5) * 9
        let center = [P(58, 10), P(57, 78), P(58 + bend, 98), P(59 + bend, 182)]
        let left = center.map { $0 - P(gap / 2, 0) }, right = center.map { $0 + P(gap / 2, 0) }
        var c: ZXArt.SSCanv = []
        for side in [-1.0, 1.0] {
            let edge = side < 0 ? left : right
            let outer = [P(edge[0].x + side * (28 + r() * 10), 22),
                P(edge[0].x + side * (40 + r() * 8), 69),
                P(edge[2].x + side * 32, 126), P(edge[3].x + side * 37, 192)]
            let face = edge + outer.reversed()
            c.append(poly(face, fil: .white, str: nil))
            // A broken plane next to the fall carries the ink; the outside cliff stays light.
            for j in 0..<3 {
                let a = edge[j], b = edge[j + 1]
                c.append(poly([a, b, b + P(side * 13, 0), a + P(side * 19, 7)],
                    fil: .gray(0, 0.12 + r() * 0.07), str: nil))
                c += inkLine([a + P(side * 2, 3), (a + b) / 2 + P(side * 6, 0), b + P(side * 8, -4)],
                    width: 5 + r() * 5, tone: 0.76, dry: 0.56, profile: .cone)
                for k in 0..<3 {
                    let offset = side * (12 + Double(k) * 6)
                    c += inkLine([a + P(offset, 9), b + P(offset * 0.7, -9)],
                        width: 1.0 + r(), tone: 0.48, dry: 0.6)
                }
            }
            c += inkLine(inkCurve(outer), width: 1.8, tone: 0.66, dry: 0.48)
            c += inkEdges(edge, width: 1.5, tone: 0.74, dry: 0.35)
            let cap = [outer[0], P(edge[0].x + side * 15, 3 + r() * 5), edge[0]]
            c += inkLine(cap, width: 2, tone: 0.70, dry: 0.40)
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
            let x = foot.x + (r() - 0.5) * 43, y = 181 + r() * 13
            c += inkBlot(x, y, radius: 7 + r() * 6, squash: 0.45, tone: 0.04).map { p in
                var q = p; q.fil = C(255, 255, 255, 0.65); return q
            }
        }
        let outlet = P(foot.x + 19, 232)
        let l = inkCurve([foot + P(-14, 9), foot + P(-21, 24), outlet + P(-10, 0)])
        let rr = inkCurve([foot + P(17, 9), foot + P(9, 29), outlet + P(11, 0)])
        for edge in [l, rr] { c += inkLine(edge, width: 1.1, tone: 0.48, dry: 0.45) }
        for (dx, dy) in [(-10.0, 18.0), (4, 24), (9, 39)] {
            c += inkLine([foot + P(dx, dy), foot + P(dx + 8, dy - 0.3)], width: 0.65, tone: 0.24, dry: 0.45)
        }
        return .init(canvas: c, outlet: outlet)
    }
}
