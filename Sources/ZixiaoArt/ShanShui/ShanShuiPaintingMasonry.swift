// Broken brickwork and city walls for shanshui@5. Earlier cartoon assets remain version-frozen.
import Foundation

extension ShanShuiEngine {
    func paintingRuins() -> ZXArt.SSCanv {
        let count = 2 + Int(r() * 65536) % 3
        var c: ZXArt.SSCanv = [], x = 0.0
        for k in 0..<count {
            let width = 39 + r() * 27, height = k == 0 ? 48 + r() * 18 : 20 + r() * 34
            let top = 75 - height, peak = 0.17 + r() * 0.17
            // A surviving flat section breaks into an oblique torn edge. A central peaked
            // outline would resemble the gable of a roof, rather than a fragment of wall.
            var crest = [P(x, top + 3 + r() * 5), P(x + width * 0.12, top + r() * 3),
                P(x + width * 0.23, top + 3 + r() * 2), P(x + width * 0.29, top + r() * 2),
                P(x + width * (0.40 + r() * 0.12), top + 2 + r() * 4),
                P(x + width * 0.60, top + height * (0.28 + r() * 0.12)),
                P(x + width * 0.67, top + height * 0.26),
                P(x + width * 0.75, top + height * (0.52 + r() * 0.10)),
                P(x + width * 0.86, top + height * 0.68),
                P(x + width, top + height * (0.72 + r() * 0.12))]
            if r() < 0.5 { crest = crest.reversed().map { P(x + width - ($0.x - x), $0.y) } }
            func head(_ px: Double) -> Double {
                for (a, b) in zip(crest, crest.dropFirst()) where px >= a.x && px <= b.x {
                    return a.y + (b.y - a.y) * (px - a.x) / max(0.01, b.x - a.x)
                }
                return 75
            }
            c.append(poly(crest + [P(x + width, 75), P(x, 75)], fil: .white, str: nil))
            let back = crest.map { $0 + P(3, -2) }
            c.append(poly(crest + back.reversed(), fil: .gray(0, 0.10), str: nil))
            c += inkEdges(crest, width: 1.6, tone: 0.68, dry: 0.45)
            c += inkLine([crest[0], P(x, 75)], width: 1.2, tone: 0.60, dry: 0.5)
            c += inkLine([crest.last!, P(x + width, 75)], width: 1.1, tone: 0.57, dry: 0.5)
            // Mortar ends at the broken profile; sparse missing courses keep the wall weathered.
            for row in 1..<Int(height / 6) {
                let y = 75 - Double(row) * 6
                let inside = stride(from: x + 2, through: x + width - 2, by: 2).filter { head($0) < y - 1 }
                if let l = inside.first, let rr = inside.last, rr - l > 6 {
                    let start = l + r() * (rr - l) * 0.2, end = rr - r() * (rr - l) * 0.2
                    c += inkLine([P(start, y), P(end, y + 0.3)], width: 0.65, tone: 0.33, dry: 0.5)
                    for joint in stride(from: l + (row % 2 == 0 ? 4 : 10), to: rr - 2, by: 14) {
                        c += inkLine([P(joint, y), P(joint, min(74, y + 5.5))], width: 0.6, tone: 0.30, dry: 0.5)
                    }
                }
            }
            for u in [peak, 0.72] {
                let root = P(x + width * u, head(x + width * u))
                for j in 0..<4 {
                    let dx = Double(j) * 4 - 6
                    c += inkLine(inkCurve([root, root + P(dx * 0.3, -4), root + P(dx, -7 - r() * 6)]),
                        width: 0.8, tone: 0.64, dry: 0.4, profile: .cone)
                }
            }
            for _ in 0..<(2 + k % 2) {
                let p = P(x + width + 2 + r() * 9, 73 + r() * 4)
                c += inkEdges([p + P(-4, 0), p + P(-3, -3), p + P(3, -2), p + P(5, 1)],
                    width: 0.7, tone: 0.47, dry: 0.5)
            }
            c += inkLine([P(x - 2, 77), P(x + width * 0.7, 77)], width: 0.8, tone: 0.3, dry: 0.6)
            x += width + 10 + r() * 15
        }
        return c
    }

    func paintingCityGate() -> ZXArt.SSCanv {
        let form = Int(r() * 65_536) % 3
        let w = [150.0, 187, 226][form], center = w / 2
        let doubleEave = form != 0, foot = 112.0, towerW = form == 2 ? 100.0 : 83.0
        var c: ZXArt.SSCanv = []
        // Timber gate tower stands on the masonry terrace; a second roof shelters the upper bay.
        let tower = [P(center - towerW / 2, 32), P(center + towerW / 2, 32),
                     P(center + towerW / 2, 64), P(center - towerW / 2, 64)]
        c.append(poly(tower, fil: .white, str: nil))
        for fraction in [-0.5, -0.25, 0, 0.25, 0.5] {
            let x = center + towerW * fraction
            c += inkLine([P(x, 32), P(x, 64)], width: 1.4, tone: 0.72, dry: 0.3)
        }
        c += inkLine([P(center - towerW / 2, 55), P(center + towerW / 2, 55)], width: 1.3, tone: 0.6)
        c += paintingHipGableRoof(width: towerW + 25, height: 29).map { p in
            var q = p; q.p = p.p.map { P($0.x + center - (towerW + 25) / 2, $0.y + 3) }; return q
        }
        if doubleEave {
            let upperW = towerW * 0.67
            let upper = [P(center - upperW / 2, 4), P(center + upperW / 2, 4),
                         P(center + upperW / 2, 20), P(center - upperW / 2, 20)]
            c.append(poly(upper, fil: .white, str: nil))
            c += inkEdges(upper + [upper[0]], width: 1, tone: 0.59)
            for x in [center - upperW / 4, center, center + upperW / 4] {
                c += inkLine([P(x, 6), P(x, 18)], width: 1.5, tone: 0.64)
            }
            c += paintingHipGableRoof(width: upperW + 23, height: 23).map { p in
                var q = p; q.p = p.p.map { P($0.x + center - (upperW + 23) / 2, $0.y - 20) }; return q
            }
        }
        // Flat-topped merlons with gaps, drawn as masonry rather than a rounded castle icon.
        var top = [P(0, 68)]
        let merlons = Int(w / 16), unit = w / Double(merlons)
        for k in 0..<merlons {
            let x = Double(k) * unit
            top += [P(x, 62), P(x + unit * 0.56, 62), P(x + unit * 0.56, 68), P(x + unit, 68)]
        }
        let wall = top + [P(w + 3, foot), P(-3, foot)]
        c.append(poly(wall, fil: .white, str: nil))
        c += inkEdges(top, width: 1.2, tone: 0.66, dry: 0.35)
        c += inkEdges([P(0, 68), P(-3, foot), P(w + 3, foot), P(w, 68)], width: 1.2, tone: 0.58, dry: 0.4)
        c += paintingArchDoor(x: center - 15, foot: foot, width: 30, height: 36, tone: 0.45)
        for side in [-1.0, 1.0] {
            for k in 0..<4 {
                let y = 78 + Double(k) * 8
                let x = center + side * (27 + r() * 13)
                c += inkLine([P(x, y), P(x + side * (18 + r() * 20), y)], width: 0.65, tone: 0.28, dry: 0.5)
                c += inkLine([P(x, y), P(x, y + 5)], width: 0.6, tone: 0.26, dry: 0.5)
            }
        }
        return c
    }
}
