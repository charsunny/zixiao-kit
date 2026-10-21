// shanshui@5: terrain is built from connected ridges, with texture following their folds.
import Foundation

extension ShanShuiEngine {
    /// Seeded shores: separate low shoals, angular bluffs, or descending rock shelves.
    func paintingSlope(_ style: BankStyle) -> ZXArt.SSCanv {
        let width = 270 + r() * 70
        let height = style == .shoal ? 24 + r() * 20 : (style == .cliff ? 75 + r() * 35 : 52 + r() * 32)
        let flip = r() < 0.5
        let sections = style == .headland ? 3 : 2 + Int(r() * 2)
        let lengths = (0..<sections).map { _ in 0.7 + r() * 0.8 }
        let total = lengths.reduce(0, +)
        var controls = [P(0, height * (style == .headland ? 0.35 : 0.88))]
        var x = 0.0
        for k in 0..<sections {
            let span = width * lengths[k] / total
            let peak = x + span * (0.24 + r() * 0.32)
            switch style {
            case .shoal:
                let top = height * (0.08 + r() * 0.48)
                controls += [P(x + span * 0.12, height * (0.65 + r() * 0.2)),
                    P(peak, top), P(x + span * 0.82, top + height * (0.15 + r() * 0.18)),
                    P(x + span, height * (0.78 + r() * 0.20))]
            case .cliff:
                let top = height * (0.05 + r() * 0.36)
                controls += [P(peak, top), P(x + span * 0.63, top + height * (0.04 + r() * 0.10)),
                    P(x + span * 0.75, top + height * (0.02 + r() * 0.10)),
                    P(x + span * 0.86, height * (0.48 + r() * 0.17)),
                    P(x + span, height * (0.63 + r() * 0.17))]
            case .headland:
                let top = height * (0.04 + Double(k) * 0.24 + r() * 0.09)
                controls += [P(peak, top), P(x + span * 0.74, top + height * (0.04 + r() * 0.07)),
                    P(x + span, top + height * (0.20 + r() * 0.08))]
            }
            x += span
        }
        let crest: [P]
        if style == .shoal { crest = inkCurve(controls) }
        else {
            // Straight, unequal ledges preserve the angular faces instead of rounding every rock.
            crest = zip(controls, controls.dropFirst()).flatMap { a, b in
                (0..<6).map { i in let t = Double(i) / 6; return P(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t) }
            } + [controls.last!]
        }
        let bottom = inkCurve([crest.last!, P(width * (0.77 + r() * 0.10), height + 4 + r() * 8),
            P(width * (0.37 + r() * 0.18), height + 6 + r() * 10),
            P(width * (0.08 + r() * 0.12), height + r() * 5), crest[0]])
        let outline = crest + bottom
        var c = [poly(outline, fil: .white, str: nil)]
        // inkSurface supplies only the dilute base. Fibres below own the texture, avoiding two
        // full layers of hatching; darker washes sit beneath selected shoulders, not over the bank.
        c += inkSurface(outline, textured: false, shadowWash: false)
        for k in 0..<sections {
            let i = min(crest.count - 2, Int((Double(k) + 0.55) / Double(sections) * Double(crest.count - 1)))
            let p = crest[i], extent = min(width - p.x, width * (0.10 + r() * 0.12))
            let depth = max(2, height - p.y) * (0.35 + r() * 0.35)
            let wash = inkCurve([p, P(p.x + extent * 0.4, p.y + depth * 0.25),
                P(p.x + extent, min(height, p.y + depth)), P(p.x + extent * 0.15, p.y + depth * 0.7)])
            c.append(poly(wash, fil: .gray(0, style == .cliff ? 0.06 : 0.025), str: nil))
        }
        func top(at x: Double) -> Double {
            for (a, b) in zip(crest, crest.dropFirst()) where a.x <= x && x <= b.x {
                return a.y + (b.y - a.y) * (x - a.x) / max(0.001, b.x - a.x)
            }
            return height
        }
        // 披麻: sparse fibres follow the slope in one direction, without a hooked tail.
        let count = style == .shoal ? 18 : (style == .cliff ? 24 : 20)
        for k in 0..<count {
            let px = width * (0.10 + r() * 0.80), py = top(at: px) + 2 + r() * 3
            let available = max(0, height - py)
            let reach = available * (0.28 + pow(r(), 1.4) * 0.66)
            guard reach > 3 else { continue }
            let lean = style == .cliff ? 0.05 + r() * 0.12 : 0.30 + r() * 0.40
            let direction = top(at: px + 2) > top(at: px - 2) ? 1.0 : -1.0
            let edge = direction > 0 ? width - px - 2 : px - 2
            let dx = direction * min(edge, reach * lean)
            let line = (0...18).map { i -> P in
                let t = Double(i) / 18
                return P(px + dx * (0.7 * t + 0.3 * t * t), py + reach * t)
            }
            guard line.allSatisfy({ $0.y >= top(at: $0.x) }) else { continue }
            let shade = min(1, 0.30 + 0.45 * px / width + 0.25 * reach / max(1, available))
            c += inkLine(line, width: style == .cliff ? 0.7 + r() * 2.0 : 0.4 + r() * 0.6,
                tone: k % 6 == 0 ? 0.48 : (0.16 + r() * 0.25) * shade, dry: 0.65)
        }
        var start = 1
        while start < crest.count - 3 {
            let run = 2 + Int(r() * 5)
            c += inkLine(Array(crest[start...min(start + run, crest.count - 1)]),
                width: style == .shoal ? 0.8 + r() * 0.5 : 1.2 + r() * 0.9,
                tone: 0.40 + r() * 0.23, dry: 0.52)
            start += run + (style == .shoal ? 5 : 2) + Int(r() * 6)
        }
        for _ in 0..<(2 + Int(r() * 3)) {
            let p = crest[2 + Int(r() * Double(crest.count - 4))]
            for _ in 0..<(2 + Int(r() * 4)) {
                let mx = min(width - 1, max(1, p.x + (r() - 0.5) * 13))
                c += inkBlot(mx, top(at: mx) + 1 + r() * 3,
                    radius: 0.7 + r() * 1.4, squash: 0.44, tone: 0.55 + r() * 0.30)
            }
        }
        // Broken water-facing edges, leaving passages between the shoals.
        for _ in 0..<(2 + Int(r() * 3)) {
            let x = width * (0.04 + r() * 0.78), span = width * (0.06 + r() * 0.13)
            c += inkLine([P(x, height + 3), P(x + span * 0.5, height + 4), P(x + span, height + 3)],
                width: 1.1, tone: 0.40, dry: 0.65)
        }
        if flip { c = c.map { poly in var p = poly; p.p = poly.p.map { P(width - $0.x, $0.y) }; return p } }
        return c
    }

    /// 矾头 and stacked shoulders, with dry folds flowing down from the ridge.
    /// This path does not call legacy mountain(), whose uniform tree rim is frozen for older versions.
    func paintingMassif(_ profile: PaintingMountainProfile) -> ZXArt.SSCanv {
        let width = profile.width * (profile.form == .clustered ? 0.88 : 0.64)
        let height = profile.height
        let ridge = (0...90).map { i -> P in
            let t = Double(i) / 90
            let elevation = profile.elevation(at: t)
            let grain = (n(t * 34, 4) - 0.5) * 9 * sin(t * .pi)
            return P(width * t, height * (1 - elevation) + grain)
        }
        let outline = ridge + [P(width * 0.88, height + 8), P(width * 0.12, height + 8)]
        var c = [poly(outline, fil: .white, str: nil)]
        c += inkSurface(outline, textured: true, shadowWash: false)
        for start in stride(from: 0, to: ridge.count - 3, by: 5) {
            c += inkLine(Array(ridge[start...min(start + 4, ridge.count - 1)]), width: 1.4 + r(), tone: 0.62, dry: 0.48)
        }
        // 山块叠起: short convex shoulders overlap in unequal tiers. The folds stop and
        // resume at ledges; they never run in parallel from summit to foot.
        for tier in 0..<4 {
            let level = Double(tier) / 4
            let shoulders = tier % 2 == 0 ? [0.37, 0.66] : [0.24, 0.54, 0.76]
            for u in shoulders where r() > 0.14 {
                let cx = width * (u + (r() - 0.5) * 0.045)
                let crestY = ridge[Int(u * 90)].y
                let available = height - crestY
                guard available > height * 0.22 else { continue }
                let top = crestY + available * (0.04 + level * 0.72 + r() * 0.09)
                let rx = width * (0.08 + r() * 0.065), ry = available * (0.15 + r() * 0.18)
                let cap = inkCurve([P(cx - rx, top + ry * 0.5), P(cx - rx * 0.58, top + ry * 0.12),
                    P(cx - rx * 0.3, top + ry * 0.15), P(cx, top),
                    P(cx + rx * 0.48, top + ry * 0.26), P(cx + rx, top + ry * 0.72)])
                let foot = inkCurve([cap.last!, P(cx + rx * 0.7, top + ry * 1.65),
                    P(cx - rx * 0.5, top + ry * 1.8), cap[0]])
                // No opaque oval masks: dry ridges and dilute ink join the parent mountain.
                c.append(poly(cap + foot, fil: .gray(0, 0.025 + r() * 0.025), str: nil))
                c += inkSurface(cap + foot, textured: true, shadowWash: false)
                let startIndex = Int(r() * 6)
                c += inkLine(Array(cap[startIndex...min(cap.count - 1, startIndex + 12)]),
                    width: 1.2 + r(), tone: 0.48 + r() * 0.16, dry: 0.63)
                // Broken hemp fibres curl down the shaded right face, with a dry broad accent.
                for k in 0..<12 {
                    let offset = r() * rx * 0.7
                    let start = P(cx + offset, top + ry * 0.2 + r() * ry * 0.22)
                    let endY = min(height + 2, top + ry * (0.65 + r() * 0.85))
                    let path = inkCurve([start, P(start.x + rx * 0.25, top + ry * 0.68),
                        P(start.x + rx * 0.1, endY - ry * 0.12), P(start.x - rx * 0.2, endY)])
                    c += inkLine(path, width: k % 4 == 0 ? 3.5 + r() * 3 : 0.6 + r(),
                        tone: k % 4 == 0 ? 0.30 + r() * 0.13 : 0.25 + r() * 0.22, dry: 0.7)
                }
                if tier % 2 == 1 {
                    for _ in 0..<4 {
                        let q = cap[Int(r() * Double(cap.count - 1))]
                        c += inkBlot(q.x, q.y, radius: 1 + r() * 1.5, squash: 0.4, tone: 0.75)
                    }
                }
            }
        }
        // Ridge groves have unequal density; distant trees are tiny dabs, without drawn branches.
        for u in [0.19, 0.39, 0.71, 0.81] where r() < 0.85 {
            let count = 3 + Int(r() * 6)
            for k in 0..<count {
                let t = min(0.94, u + Double(k) * 0.009)
                let p = ridge[Int(t * 90)], treeH = 3 + r() * 8
                c += inkBlot(p.x, p.y - treeH * 0.35, radius: treeH * 0.45,
                    squash: 0.38, angle: .pi / 2, tone: 0.5 + r() * 0.3)
            }
        }
        return c
    }

    /// A path appears by reserved paper between broken banks, opening toward the viewer.
    func paintingFootpath() -> ZXArt.SSCanv {
        let left = inkCurve([P(38, 0), P(60, 24), P(32, 61), P(43, 100), P(5, 145)])
        let right = inkCurve([P(41, 0), P(65, 24), P(43, 61), P(64, 100), P(37, 145)])
        var c = [poly(left + right.reversed(), fil: .white, str: nil)]
        for edge in [left, right] {
            for start in stride(from: 0, to: edge.count - 4, by: 6) {
                c += inkLine(Array(edge[start...start + 3]), width: 0.85, tone: 0.36, dry: 0.65)
            }
        }
        return c
    }
}
