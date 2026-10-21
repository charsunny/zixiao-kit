// shanshui@5 painting path. Preserve this version when adding future painting styles.
import Foundation

extension ShanShuiEngine {
    /// Straight joinery: vertical mullions, square lattice, or ice-crack tracery. No skewed
    /// wall slab is carried with the window, so the same frame can be set into a house or court.
    func paintingWindow(embedded: Bool = false) -> ZXArt.SSCanv {
        let form = Int(r() * 4096) % 3
        let w = [44.0, 56, 62][form], h = 52.0
        let frame = [P(0, 0), P(w, 0), P(w, h), P(0, h), P(0, 0)]
        var c = [poly(frame, fil: .white, str: nil), poly(frame, fil: .gray(0, embedded ? 0.045 : 0.065), str: nil)]
        c += inkEdges(frame, width: 1.8, tone: 0.72, dry: 0.30)
        c += inkEdges([P(3, 3), P(w - 3, 3), P(w - 3, h - 3), P(3, h - 3), P(3, 3)],
                      width: 0.7, tone: 0.48, dry: 0.35)
        if form < 2 {
            let spacing = form == 0 ? 8.0 : 12.0
            for x in stride(from: 10.0, to: w - 5, by: spacing) {
                c += inkLine([P(x, 4), P(x, h - 4)], width: 0.8, tone: 0.61, dry: 0.3)
            }
            for y in (form == 0 ? [37.0] : [16.0, 28, 40]) {
                c += inkLine([P(4, y), P(w - 4, y)], width: 0.8, tone: 0.56, dry: 0.3)
            }
        } else {
            let a = P(19, 17), b = P(41, 13), d = P(35, 34), e = P(15, 37)
            for line in [[P(4, 9), a, b, P(48, 4)], [P(4, 28), a, e, P(10, 48)],
                         [a, d, b, P(58, 24)], [e, d, P(49, 48)], [d, P(58, 39)]] {
                c += inkEdges(line, width: 0.85, tone: 0.58, dry: 0.32)
            }
        }
        c += inkLine([P(-2, h + 2), P(w + 2, h + 2)], width: 1.6, tone: 0.66, dry: 0.33)
        return c
    }

    /// Bamboo blind: horizontal slats bound by two tapes, with a rolled lower edge.
    /// Pull cords keep the full hanging extent even when most of the blind is rolled up.
    func paintingCurtain(width: Double = 54, height: Double = 77) -> ZXArt.SSCanv {
        let form = Int(r() * 4096) % 5
        let w = 54.0, drop = [15.0, 28, 41, 54, 67][form]
        let blind = [P(0, 0), P(w, 0), P(w, drop), P(0, drop)]
        var c = [poly(blind, fil: .white, str: nil)]
        for y in stride(from: 3.0, through: drop - 1, by: 3) {
            c += inkLine([P(1, y), P(w - 1, y)], width: 0.7, tone: 0.34 + r() * 0.12, dry: 0.43)
        }
        for x in [13.0, 41] {
            c += inkLine([P(x, 0), P(x, drop)], width: 1.1, tone: 0.53, dry: 0.32)
        }
        c += inkEdges([P(0, drop), P(0, 0), P(w, 0), P(w, drop)], width: 0.9, tone: 0.55, dry: 0.35)
        let roll = [P(0, drop), P(w, drop), P(w, drop + 4), P(0, drop + 4), P(0, drop)]
        c += inkEdges(roll, width: 1.4, tone: 0.65, dry: 0.3)
        c += inkLine([P(-3, -2), P(w + 3, -2)], width: 2, tone: 0.73)
        c += inkLine([P(w - 6, 1), P(w - 6, 75)], width: 0.55, tone: 0.48, dry: 0.4)
        c += inkLine([P(w - 8, 75), P(w - 4, 75)], width: 1.1, tone: 0.6)
        return c.map { p in
            var q = p; q.p = p.p.map { P($0.x * width / 54, $0.y * height / 77) }
            q.wid *= min(width / 54, height / 77); return q
        }
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

    /// Long sand crests: paper on the windward face, a dry veil below the lee edge.
    func paintingDunes(far: Bool = false) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let count = far ? 2 + Int(r() * 2) : 2 + Int(r() * 65536) % 3
        for k in 0..<count {
            let depth = Double(k) / Double(max(1, count - 1))
            let x0 = -20 - depth * 18 + r() * 22, span = 300 + r() * 75
            let base = (far ? 8.0 : 22.0) + Double(k) * (far ? 7 : 29)
            let rise = far ? 5 + r() * 5 : 17 + r() * 18
            let bias = 0.28 + r() * 0.40
            let crest = inkCurve([P(x0, base + rise * 0.30), P(x0 + span * bias, base - rise),
                P(x0 + span * (bias + (1 - bias) * 0.5), base - rise * 0.32), P(x0 + span, base + rise * 0.12)], steps: 20)
            if far {
                c += inkLine(crest, width: 0.65, tone: 0.18 + depth * 0.04, dry: 0.48)
                continue
            }
            // Open the foot into paper: only the crest is outlined, never a closed lens.
            for band in 0..<14 {
                func edge(_ t: Double) -> [P] {
                    crest.enumerated().map { i, p in
                        let u = Double(i) / Double(crest.count - 1)
                        return p + P(-rise * 0.25 * t, rise * 0.90 * t * pow(sin(u * .pi), 0.5))
                    }
                }
                let t = Double(band) / 14
                c.append(poly(edge(t) + edge(Double(band + 1) / 14).reversed(),
                    fil: .gray(0, (0.06 + depth * 0.025) * pow(1 - t, 1.8)), str: nil))
            }
            c += inkLine(crest, width: 0.8 + depth * 0.35, tone: 0.25 + depth * 0.13, dry: 0.38)
            for _ in 0..<(4 + Int(r() * 4)) {
                let start = 8 + Int(r() * 27), length = 9 + Int(r() * 12), offset = 3 + r() * rise * 0.35
                let sweep = Array(crest[start..<min(crest.count, start + length)]).map { $0 + P(-offset * 0.7, offset) }
                c += inkLine(sweep, width: 3 + r() * 5, tone: 0.14 + depth * 0.08, dry: 0.78)
            }
        }
        return c
    }

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
                let sway = sin(t1 * 2.5) * 0.5
                c.append(poly([P(30 - w0, y0), P(30 + sway - w1, y1), P(30 + sway + w1, y1), P(30 + w0, y0)],
                    fil: .gray(0, 0.058 * (1 - t0 * 0.94)), str: nil))
            }
            c += inkLine([P(30, 130), P(30, 70), P(30.4, 40)], width: 0.45, tone: 0.09, dry: 0.75)
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

// A battered earthen beacon, composed with smoke at its summit by the scene.
extension ShanShuiEngine {
    func paintingBeacon() -> ZXArt.SSCanv {
        let top = [P(18, 8), P(45, 8), P(51, 13), P(13, 13)]
        let front = [P(13, 13), P(51, 13), P(59, 44), P(5, 44)]
        var c = [poly(front, fil: .white, str: nil), poly(top, fil: .white, str: nil)]
        c += inkLine(top + [top[0]], width: 1.3, tone: 0.70, dry: 0.45)
        c += inkLine([P(13, 13), P(5, 44), P(59, 44), P(51, 13)], width: 1.5, tone: 0.62, dry: 0.5)
        for y in [21.0, 29, 37] {
            c += inkLine([P(16, y), P(40 + r() * 8, y + 1)], width: 2.2, tone: 0.22, dry: 0.8)
        }
        c += inkLine([P(46, 15), P(52, 41)], width: 4, tone: 0.38, dry: 0.7)
        c += inkLine([P(0, 45), P(30, 46), P(65, 45)], width: 0.9, tone: 0.35, dry: 0.6)
        return c
    }
}
