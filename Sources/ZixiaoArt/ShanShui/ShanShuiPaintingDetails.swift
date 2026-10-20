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

    /// Dunes as a level-distance (平远) band: long low ridges with a crisp crest, the lee side
    /// shaded, nearer ridges darker. `far` draws the pale ridges beyond the river.
    func paintingDunes(far: Bool = false) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let layers = far ? [(y: 34.0, amp: 9.0, tone: 0.05), (y: 48, amp: 7, tone: 0.07)]
                         : [(y: 30.0, amp: 16.0, tone: 0.08), (y: 62, amp: 20, tone: 0.11), (y: 96, amp: 14, tone: 0.14)]
        for (k, layer) in layers.enumerated() {
            let phase = r() * 6, freq = 1.1 + r() * 0.9
            let crest = (0...90).map { i -> P in
                let t = Double(i) / 90
                let wave = pow(abs(sin(t * .pi * freq + phase)), 1.4)
                return P(t * 300, layer.y - layer.amp * (0.35 + 0.65 * wave) - 3 * (n(t * 5 + phase, Double(k)) - 0.5))
            }
            // Each ridge is a long lens: it thins to nothing at both ends, so layers overlap
            // without the hard vertical edges of a rectangle.
            let base = crest.enumerated().map { i, p in
                P(p.x, p.y + 4 + 36 * pow(sin(Double(i) / 90 * .pi), 0.6))
            }
            c.append(poly(crest + base.reversed(), fil: .white, str: nil))
            c.append(poly(crest + base.reversed(), fil: .gray(0, layer.tone), str: nil))
            // Lee side: a darker sliver hanging under the crest, thinning away from the peaks.
            let lee = crest.map { p in P(p.x, p.y + 3 + 6 * abs(sin(p.x * 0.03 + phase))) }
            c.append(poly(crest + lee.reversed(), fil: .gray(0, layer.tone * 0.9), str: nil))
            c += inkLine(crest, width: far ? 0.5 : 0.7 + Double(k) * 0.25, tone: (far ? 0.14 : 0.22) + Double(k) * 0.08, dry: 0.5)
            if !far {
                // Sand ripples: a few short, parallel strokes on the nearest slopes.
                for _ in 0..<(4 + k * 3) {
                    let x = 20 + r() * 260, y = layer.y + 6 + r() * 14
                    c += inkLine([P(x, y), P(x + 10 + r() * 14, y - 1 - r())], width: 0.5, tone: 0.10 + Double(k) * 0.03, dry: 0.6)
                }
            }
        }
        return c
    }

    /// Beacon smoke rises straight in still desert air (孤烟直) and only spreads at the very top;
    /// village smoke (炊烟) wavers. Both are pale washes, never hard lines.
    func paintingSmoke(beacon: Bool) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        if beacon {
            let drift = r() < 0.5 ? -1.0 : 1.0
            let core = (0...30).map { i -> P in
                let t = Double(i) / 30
                return P(30 + drift * 10 * pow(max(0, t - 0.8) / 0.2, 2), 130 - t * 130)
            }
            let left = core.enumerated().map { i, p in P(p.x - (1.2 + 3 * pow(Double(i) / 30, 3)), p.y) }
            let right = core.enumerated().map { i, p in P(p.x + (1.2 + 3 * pow(Double(i) / 30, 3)), p.y) }
            c.append(poly(left + right.reversed(), fil: .gray(0, 0.10), str: nil))
            c += inkLine(core, width: 0.6, tone: 0.16, dry: 0.6)
            c += inkBlot(core.last!.x + drift * 4, 4, radius: 7, squash: 0.35, angle: drift * 0.3, tone: 0.06)
            return c
        }
        for k in 0..<4 {
            let line = (0...24).map { i -> P in
                let t = Double(i) / 24
                return P(30 + sin(t * 5.5 + Double(k) * 0.4) * (3 + 10 * t) + Double(k) * 1.2, 130 - t * 130)
            }
            c += inkLine(line, width: 1.6 + Double(k) * 0.8, tone: 0.05, dry: 0.4, profile: .rise)
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
