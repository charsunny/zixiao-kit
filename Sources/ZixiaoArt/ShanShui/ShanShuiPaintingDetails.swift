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

    /// Paddy fields as the farmer sees them across the slope: curved bund lines (田埂) that follow
    /// the ground and close up with distance, sparse rows of seedlings, no filled panels.
    func paintingFields() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let rows = 5
        let phase = r() * 3
        for k in 0..<rows {
            let t = Double(k) / Double(rows - 1)                 // 0 far … 1 near
            let y = 14 + 86 * pow(t, 1.3)
            let bow = 4 + 8 * t
            let bund = (0...24).map { i -> P in
                let u = Double(i) / 24
                return P(10 + 150 * u, y + bow * sin(u * .pi + phase * 0.2) - 6 * u + 2 * n(u * 4, Double(k)))
            }
            c += inkLine(bund, width: 0.6 + t * 0.7, tone: 0.20 + t * 0.15, dry: 0.5)
            // Seedlings: short upright ticks between this bund and the next, thinning with distance.
            for _ in 0..<(4 + Int(t * 10)) {
                let i = 1 + Int(r() * 22), p = bund[i]
                let dy = 3 + r() * (6 + 10 * t)
                c += inkLine([P(p.x, p.y + dy), P(p.x - 0.4, p.y + dy - 1.5 - 2 * t)], width: 0.45 + 0.3 * t,
                    tone: 0.18 + 0.12 * t, dry: 0.5)
            }
        }
        return c
    }

    /// Dunes. `far`: one pale, nearly level line of ridges at the horizon. Near: two or three
    /// large crescent dunes whose crests run diagonally, a gentle sunlit windward slope and a
    /// steep lee face in darker wash, overlapping in depth.
    func paintingDunes(far: Bool = false) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        if far {
            let phase = r() * 6
            let crest = (0...90).map { i -> P in
                let t = Double(i) / 90
                return P(t * 300, 20 - 6 * pow(abs(sin(t * .pi * 2.3 + phase)), 1.5) - 2 * n(t * 6, 1))
            }
            let base = crest.enumerated().map { i, p in P(p.x, p.y + 3 + 6 * pow(sin(Double(i) / 90 * .pi), 0.5)) }
            c.append(poly(crest + base.reversed(), fil: .gray(0, 0.07), str: nil))
            c += inkLine(crest, width: 0.5, tone: 0.16, dry: 0.55)
            return c
        }
        let dunes = 2 + Int(r() * 2)
        for k in 0..<dunes {
            let depth = Double(k) / Double(max(1, dunes - 1))        // 0 far … 1 near
            let base = 40 + depth * 70, height = 18 + depth * 26
            let x0 = -40 + r() * 50 - depth * 40, x1 = x0 + 280 + r() * 90
            let peakX = x0 + (x1 - x0) * (0.55 + r() * 0.2)
            // Windward slope: long and gentle; lee: short and steep.
            let windward = (0...30).map { i -> P in
                let t = Double(i) / 30
                return P(x0 + (peakX - x0) * t, base - height * pow(t, 1.6))
            }
            let lee = (1...12).map { i -> P in
                let t = Double(i) / 12
                return P(peakX + (x1 - peakX) * t, base - height * (1 - pow(t, 0.7)))
            }
            let crest = windward + lee
            let floor = crest.enumerated().map { i, p in
                P(p.x, p.y + (base + 14 - p.y) * pow(sin(Double(i) / Double(crest.count - 1) * .pi), 0.35))
            }
            c.append(poly(crest + floor.reversed(), fil: .white, str: nil))
            // Sand is mostly paper: a faint body, a little more tone just under the crest.
            c.append(poly(crest + floor.reversed(), fil: .gray(0, 0.025 + depth * 0.02), str: nil))
            let lip = crest.map { P($0.x, $0.y + 5 + depth * 4) }
            c.append(poly(crest + lip.reversed(), fil: .gray(0, 0.03 + depth * 0.03), str: nil))
            // Lee face: nested, fading washes plus dry strokes down the slope, never one hard wedge.
            let shadowTop = Array(crest.suffix(lee.count + 4))
            for k in 0..<3 {
                let reach = (4 + depth * 5) * (1 + Double(k) * 0.8)
                let foot = shadowTop.map { P($0.x - reach * 0.8, min(base + 8, $0.y + reach)) }
                c.append(poly(shadowTop + foot.reversed(), fil: .gray(0, (0.035 + depth * 0.035) * (1 - Double(k) * 0.25)), str: nil))
            }
            for _ in 0..<(4 + Int(depth * 6)) {
                let p = shadowTop[Int(r() * Double(shadowTop.count - 1))]
                let len = 5 + r() * (8 + depth * 8)
                c += inkLine([P(p.x, p.y + 1), P(p.x - len * 0.6, p.y + len)], width: 1.2 + r() * 1.6,
                    tone: 0.06 + depth * 0.06, dry: 0.75)
            }
            c += inkLine(crest, width: 0.6 + depth * 0.7, tone: 0.20 + depth * 0.25, dry: 0.45)
            // Ripples on the windward slope, parallel to the crest.
            for j in 0..<(3 + Int(depth * 5)) {
                let t = 0.2 + r() * 0.6, i = Int(t * 30)
                let p = windward[i], dy = 4 + Double(j % 3) * 3
                c += inkLine([P(p.x - 8, p.y + dy + 2), P(p.x + 6, p.y + dy)], width: 0.45, tone: 0.10 + depth * 0.06, dry: 0.6)
            }
        }
        return c
    }

    /// Beacon smoke rises straight in still desert air (孤烟直) and only spreads at the very top;
    /// village smoke (炊烟) wavers. Both are pale washes, never hard lines.
    func paintingSmoke(beacon: Bool) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        if beacon {
            // A column that rises dead straight and thins away: stacked segments, paler and a
            // little wider with height, so it ends in air rather than in a hard cap.
            let segments = 8
            for k in 0..<segments {
                let t0 = Double(k) / Double(segments), t1 = Double(k + 1) / Double(segments)
                let y0 = 130 - t0 * 130, y1 = 130 - t1 * 130
                let w0 = 1.6 + 2.6 * t0, w1 = 1.6 + 2.6 * t1
                let sway = 0.0
                c.append(poly([P(30 - w0, y0), P(30 + sway - w1, y1), P(30 + sway + w1, y1), P(30 + w0, y0)],
                    fil: .gray(0, 0.11 * (1 - t0 * 0.85)), str: nil))
            }
            c += inkLine([P(30, 130), P(30, 70), P(30.4, 40)], width: 0.5, tone: 0.12, dry: 0.7)
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
