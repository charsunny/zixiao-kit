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
                controls += [P(peak, top), P(x + span * 0.62, top + height * (0.18 + r() * 0.14)),
                    P(x + span * 0.75, top + height * (0.08 + r() * 0.10)),
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
        func top(at x: Double) -> Double {
            for (a, b) in zip(crest, crest.dropFirst()) where a.x <= x && x <= b.x {
                return a.y + (b.y - a.y) * (x - a.x) / max(0.001, b.x - a.x)
            }
            return height
        }
        func floor(at x: Double) -> Double {
            for (a, b) in zip(bottom, bottom.dropFirst()) where min(a.x, b.x) <= x && x <= max(a.x, b.x) {
                if abs(b.x - a.x) > 0.001 { return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x) }
            }
            return height + 5
        }
        func surface(_ x: Double, _ depth: Double) -> P {
            let x = min(width, max(0, x)), y = top(at: x)
            return P(x, y + max(0, floor(at: x) - y) * depth)
        }
        // Reserve the lit top; a connected dilute face makes the bank read as earth, not a few
        // floating strokes. The darker wash sits lower and on the back of each unequal shoulder.
        let faceTop = (0...100).map { i -> P in
            let x = width * Double(i) / 100
            return surface(x, 0.09 + 0.035 * sin(Double(i) * 0.23))
        }
        let faceFoot = (0...100).map { surface(width * Double($0) / 100, 0.98) }
        c.append(poly(faceTop + faceFoot.reversed(), fil: .gray(0, 0.085), str: nil))
        let lower = (0...100).map { i -> P in
            let x = width * Double(i) / 100
            return surface(x, 0.30 + 0.08 * n(x * 0.025, 3))
        }
        c.append(poly(lower + faceFoot.reversed(), fil: .gray(0, 0.045), str: nil))
        var sectionX = 0.0
        for spanWeight in lengths {
            let span = width * spanWeight / total
            let left = sectionX + span * (0.25 + r() * 0.12)
            let right = sectionX + span * (0.88 + r() * 0.10)
            for pass in 0..<2 {
                let upper = (0...24).map { i -> P in
                    let t = Double(i) / 24, x = left + (right - left) * t
                    let belly = sin(t * .pi)
                    return surface(x, 0.82 - belly * (pass == 0 ? 0.66 : 0.42))
                }
                let lower = (0...24).map { i -> P in
                    let t = Double(i) / 24
                    return surface(left + (right - left) * t, 0.82 + sin(t * .pi) * 0.12)
                }
                c.append(poly(upper + lower.reversed(), fil: .gray(0, style == .cliff ? 0.075 : 0.055), str: nil))
            }
            sectionX += span
        }
        if style == .cliff {
            // 斧劈: unequal oblique planes, loaded on one edge and split into dry side strokes.
            // Each patch has width as well as length; no row of parallel hanging vertical lines.
            for _ in 0..<(7 + Int(r() * 4)) {
                let x = width * (0.14 + r() * 0.72)
                let start = surface(x, 0.13 + r() * 0.13)
                let reach = max(0, floor(at: x) - start.y) * (0.28 + r() * 0.43)
                let dx = -reach * (0.45 + r() * 0.65)
                let breadth = 5 + r() * 11
                guard reach > 6, x + dx > 2 else { continue }
                let plane = [start, P(x + breadth, start.y + reach * 0.10),
                    P(x + dx + breadth * 0.45, start.y + reach * 0.92), P(x + dx, start.y + reach)]
                guard plane.allSatisfy({ $0.x < width && $0.y >= top(at: $0.x) && $0.y <= floor(at: $0.x) }) else { continue }
                c.append(poly(plane, fil: .gray(0, 0.10 + r() * 0.10), str: nil))
                for hair in 0..<3 {
                    let offset = Double(hair) * breadth * 0.24
                    let fraction = 0.60 + r() * 0.38
                    let line = (0...12).map { i -> P in
                        let t = Double(i) / 12 * fraction
                        return P(x + offset + dx * (0.85 * t + 0.15 * t * t), start.y + reach * t)
                    }
                    c += inkLine(line, width: hair == 0 ? 2.5 + r() * 3.5 : 0.65 + r(),
                        tone: hair == 0 ? 0.42 + r() * 0.15 : 0.22 + r() * 0.13, dry: 0.72)
                }
            }
        } else {
            // 披麻: groups collect on the shaded shoulders, with open lit passages between them.
            // Analytic single-direction curves preserve the accepted no-hook stroke endings.
            for group in 0..<7 {
                let center = width * (0.08 + (Double(group) + r() * 0.7) / 7 * 0.84)
                let strands = 3 + Int(r() * 3)
                for k in 0..<strands {
                    let px = min(width - 3, max(3, center + (r() - 0.5) * width * 0.07))
                    let start = surface(px, 0.10 + r() * 0.20)
                    let available = floor(at: px) - start.y
                    let reach = available * (0.24 + r() * 0.58)
                    guard reach > 3 else { continue }
                    let direction = top(at: px + 2) > top(at: px - 2) ? 1.0 : -1.0
                    let edge = direction > 0 ? width - px - 2 : px - 2
                    let dx = direction * min(edge, reach * (0.35 + r() * 0.55))
                    let line = (0...18).map { i -> P in
                        let t = Double(i) / 18
                        return P(px + dx * (0.65 * t + 0.35 * t * t), start.y + reach * t)
                    }
                    guard line.allSatisfy({ $0.y >= top(at: $0.x) && $0.y <= floor(at: $0.x) }) else { continue }
                    c += inkLine(line, width: k == 0 ? 1.2 + r() * 0.8 : 0.5 + r() * 0.6,
                        tone: k == 0 ? 0.46 + r() * 0.13 : 0.20 + r() * 0.20, dry: 0.62)
                }
            }
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
        // 坡脚压墨: a linked but broken dark foot remains above the last dissolving fringe.
        // Its bends follow the ground plane; it is neither a straight waterline nor another ridge.
        var footX = width * 0.025
        while footX < width * 0.96 {
            let span = min(width * (0.08 + r() * 0.13), width * 0.98 - footX)
            let line = (0...12).map { i -> P in
                let t = Double(i) / 12, x = footX + span * t
                let y = height * 0.80 + 2.5 * n(x * 0.035, 9)
                return P(x, min(floor(at: x) - 1, max(top(at: x) + 1, y)))
            }
            c += inkLine(line, width: 1.9 + r() * 1.2, tone: 0.70 + r() * 0.14, dry: 0.48)
            footX += span + width * (0.015 + r() * 0.025)
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
