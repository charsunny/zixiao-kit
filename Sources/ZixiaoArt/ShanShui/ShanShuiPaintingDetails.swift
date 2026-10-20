// shanshui@5 painting path. Preserve this version when adding future painting styles.
import Foundation

extension ShanShuiEngine {
    func paintingWindow() -> ZXArt.SSCanv {
        let wall = [P(0, 7), P(100, 24), P(100, 118), P(0, 118)]
        var c = [poly(wall, fil: .white, str: nil), poly(wall, fil: .gray(0, 0.06), str: nil)]
        c += inkEdges([P(0, 0), P(104, 18)], width: 7, tone: 0.68, dry: 0.43)
        c += inkEdges([P(20, 31), P(76, 40), P(76, 100), P(20, 91), P(20, 31)], width: 2.6, tone: 0.72)
        let opening = [P(25, 37), P(71, 44), P(71, 94), P(25, 86)]
        c.append(poly(opening, fil: .gray(0, 0.11), str: nil))
        for x in [39.0, 55] { c += inkEdges([P(x, 39 + (x - 25) * 0.15), P(x, 88 + (x - 25) * 0.15)], width: 1.1, tone: 0.62) }
        for y in [58.0, 76] { c += inkEdges([P(26, y), P(71, y + 7)], width: 0.9, tone: 0.52) }
        c += inkEdges([P(13, 96), P(80, 107)], width: 2.5, tone: 0.75)
        return c
    }

    func paintingFields() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for k in 0..<4 {
            let y = 18 + Double(k) * 20, offset = Double(k) * 9
            let upper = inkCurve([P(34 - offset, y), P(67, y - 5), P(103 + offset, y + 4), P(151 + offset, y + 8)])
            let lower = inkCurve([P(151 + offset, y + 18), P(100 + offset, y + 12), P(62, y + 10), P(23 - offset, y + 18)])
            c.append(poly(upper + lower, fil: .gray(0, 0.04 + r() * 0.045), str: nil))
            c += inkLine(upper, width: 1.1, tone: 0.32, dry: 0.58)
            for _ in 0..<13 {
                let x = 28 + r() * 120, yy = y + 3 + r() * 11
                c += inkLine([P(x, yy), P(x - 1.2, yy - 3 - r() * 3)], width: 0.65, tone: 0.2 + r() * 0.23)
            }
        }
        return c
    }

    func paintingDunes() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        // All slopes meet a shared fading floor. Separate rectangular fill bases look like panels.
        for k in 0..<4 {
            let phase = Double(k) * 1.3, height = 127 - Double(k) * 27
            let ridge = (0...90).map { i -> P in
                let t = Double(i) / 90
                let envelope = pow(max(0, sin(t * .pi)), 0.64)
                return P(t * 270, 200 - envelope * (height + sin(t * .pi * 1.4 + phase) * 18))
            }
            c.append(poly(ridge, fil: .white, str: nil))
            c.append(poly(ridge, fil: .gray(0, 0.035 + Double(k) * 0.025), str: nil))
            c += inkLine(Array(ridge.dropFirst(3).dropLast(3)), width: 0.9, tone: 0.22, dry: 0.62)
            for _ in 0..<14 {
                let x = 30 + r() * 210, y = 183 + r() * 12
                c += inkLine([P(x, y), P(x + 4 + r() * 12, y - 0.5)], width: 0.6, tone: 0.08, dry: 0.75)
            }
        }
        return c
    }

    func paintingSmoke(beacon: Bool) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for k in 0..<5 {
            let line = (0...18).map { i -> P in
                let t = Double(i) / 18
                return P(30 + sin(t * (beacon ? 3.0 : 6) + Double(k) * 0.2) * (beacon ? 3 : 12) + Double(k - 2),
                         130 - t * 130)
            }
            c += inkLine(line, width: Double(k) * 0.6 + 1, tone: beacon ? 0.08 : 0.06,
                dry: 0.42, profile: .rise)
        }
        return c
    }

    /// A clump of reeds leaning one way in the wind: stems of unequal height rising from one root
    /// area, long leaves arching out at different heights, pale plumes at the tips.
    func paintingReeds() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let wind = r() < 0.5 ? -1.0 : 1.0
        let stems = 9 + Int(r() * 6)
        for k in 0..<stems {
            let root = P(30 + (r() - 0.5) * 34 + Double(k) * 1.5, 112 + r() * 4)
            let height = 55 + r() * 50
            let bend = wind * (8 + r() * 18) * height / 100
            let tip = P(root.x + bend, root.y - height)
            let stem = inkCurve([root, P(root.x + bend * 0.25, root.y - height * 0.5), tip])
            c += inkLine(stem, width: 0.7 + r() * 0.5, tone: 0.42 + r() * 0.25, dry: 0.35)
            // One or two leaves per stem, leaving at different heights and arching downwind.
            for _ in 0..<(1 + Int(r() * 2)) {
                let t = 0.25 + r() * 0.45
                let i = min(stem.count - 1, Int(t * Double(stem.count - 1)))
                let base = stem[i], length = 18 + r() * 22
                let leaf = inkCurve([base, P(base.x + wind * length * 0.5, base.y - length * 0.35),
                                     P(base.x + wind * length, base.y - length * 0.05 + r() * 8)])
                c += inkLine(leaf, width: 1.8 + r() * 1.4, tone: 0.40 + r() * 0.3, dry: 0.2, profile: .lens)
            }
            // Plume: a soft, pale dab trailing downwind from the tip.
            if r() < 0.75 {
                c += inkBlot(tip.x + wind * 2.5, tip.y + 3, radius: 3 + r() * 2, squash: 0.35,
                    angle: wind * 1.1, tone: 0.16 + r() * 0.12)
            }
        }
        return c
    }

    func paintingLongRiver() -> ZXArt.SSCanv {
        paintingRiverRibbon()
    }
}
