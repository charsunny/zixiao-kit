// shanshui@5: terrain is built from connected ridges, with texture following their folds.
import Foundation

extension ShanShuiEngine {
    /// Two or three opaque earth/stone masses. Each owns its contour and descending texture;
    /// paper masks rear faces before the front face is drawn, so washes cannot become ghost hills.
    func paintingSlope(_ style: BankStyle) -> ZXArt.SSCanv {
        let width = 280 + r() * 55
        let height = style == .shoal ? 30 + r() * 17 : (style == .cliff ? 72 + r() * 26 : 48 + r() * 28)
        let count = 2 + Int(r() * 2), flip = r() < 0.5
        let weights = (0..<count).map { _ in 0.65 + r() * 0.85 }
        let sum = weights.reduce(0, +)
        var accumulated = 0.0
        var blocks: [(crest: [P], foot: [P])] = []
        for i in 0..<count {
            let fraction = accumulated / sum
            accumulated += weights[i]
            let left = i == 0 ? 0 : width * (fraction - 0.08)
            let right = i == count - 1 ? width : width * (accumulated / sum + 0.07)
            let span = right - left
            let top = height * (style == .headland ? 0.08 + fraction * 0.48 : 0.08 + r() * 0.28)
            let floor = height * (0.80 + Double(i) * 0.07)
            let crest: [P]
            if style == .cliff {
                // Broad horizontal caps and steep faces, never a row of triangular peaks.
                crest = [P(left, floor - height * 0.10), P(left + span * 0.09, top + height * 0.05),
                    P(left + span * 0.32, top), P(left + span * 0.70, top + height * 0.035),
                    P(left + span * 0.86, top + height * 0.13), P(right, floor - height * 0.08)]
            } else {
                let controls = [P(left, floor - height * 0.12), P(left + span * 0.15, top + height * 0.21),
                    P(left + span * 0.29, top + height * 0.08), P(left + span * (0.43 + r() * 0.08), top + height * 0.11),
                    P(left + span * 0.62, top), P(left + span * 0.81, top + height * 0.07),
                    P(left + span * 0.91, top + height * 0.35), P(right, floor - height * 0.08)]
                crest = style == .shoal ? inkCurve(controls, steps: 4) : controls
            }
            let foot = inkCurve([crest.last!, P(left + span * 0.73, floor + height * 0.05),
                P(left + span * 0.30, floor + height * 0.02), crest[0]])
            blocks.append((crest, foot))
        }
        func top(_ crest: [P], _ x: Double) -> Double {
            for (a, b) in zip(crest, crest.dropFirst()) where x >= a.x && x <= b.x {
                return a.y + (b.y - a.y) * (x - a.x) / max(0.001, b.x - a.x)
            }
            return crest.last!.y
        }
        // First polygon remains the terrain footprint used by support and outline inspection.
        let silhouette = (0...100).map { i -> P in
            let x = width * Double(i) / 100
            let y = blocks.filter { x >= $0.crest.first!.x && x <= $0.crest.last!.x }
                .map { top($0.crest, x) }.min() ?? height
            return P(x, y)
        }
        var c = [poly(silhouette + [P(width, height), P(0, height)], fil: .white, str: nil)]
        for (index, block) in blocks.enumerated() {
            let crest = block.crest, foot = block.foot, left = crest.first!.x, right = crest.last!.x
            let span = right - left, floor = foot.map(\.y).max()!
            c.append(poly(crest + foot, fil: .white, str: nil))
            // One dilute wash confined to the shaded face; no nested shoulder silhouettes.
            let shadeTop = (0...20).map { i -> P in
                let x = left + span * (0.48 + Double(i) / 20 * 0.49)
                let y = top(crest, x)
                return P(x, y + (floor - y) * 0.24)
            }
            c.append(poly(shadeTop + [P(right - span * 0.03, floor - 1), P(left + span * 0.48, floor - 1)],
                          fil: .gray(0, 0.035), str: nil))
            if style == .shoal {
                c += inkLine(crest, width: 1.15, tone: 0.58, dry: 0.65)
            } else {
                c += inkEdges(crest, width: 1.3, tone: 0.60, dry: 0.63)
            }
            for start in stride(from: 1, to: foot.count - 5, by: 8) {
                c += inkLine(Array(foot[start...start + 4]), width: 1.6, tone: 0.65, dry: 0.60)
            }
            // Brush bundles start at different depths, densest beside the descending right face.
            for bundle in 0..<(style == .cliff ? 11 : 14) {
                let u = 0.30 + r() * 0.57
                let x = left + span * u
                let y = top(crest, x), depth = floor - y
                let startY = y + depth * (bundle % 3 == 0 ? 0.06 : 0.20 + r() * 0.38)
                let reach = min(30, depth * (0.22 + r() * 0.38))
                let lean = style == .cliff ? -reach * (0.14 + r() * 0.28) : reach * (0.18 + r() * 0.48)
                for hair in 0..<(3 + Int(r() * 3)) {
                    let dx = Double(hair) * (0.8 + r() * 0.5)
                    let endY = min(floor - 3, startY + reach * (0.7 + r() * 0.3))
                    let line = inkCurve([P(x + dx, startY), P(x + dx + lean * 0.18, startY + (endY - startY) * 0.33),
                                P(x + dx + lean * 0.72, startY + (endY - startY) * 0.72), P(x + dx + lean, endY)])
                    guard line.allSatisfy({ $0.x < right - 2 && $0.y > top(crest, $0.x) }) else { continue }
                    c += inkLine(line, width: hair == 0 ? (style == .cliff ? 4.2 : 1.5) : 0.7,
                        tone: hair == 0 ? 0.43 : 0.28, dry: 0.70, profile: .cone)
                }
            }
            if style == .cliff {
                let x = left + span * 0.81, y = top(crest, x)
                c += inkEdges([P(x, y), P(x - span * 0.035, y + (floor - y) * 0.48),
                               P(x + span * 0.025, floor - 3)], width: 1.3, tone: 0.48, dry: 0.67)
            }
            // 折带 on the low shelf: short angular turns, attached to the shaded contour.
            if style == .headland {
                let x = left + span * 0.72, y = top(crest, x)
                c += inkLine([P(x, y + 2), P(x + 4, y + height * 0.15), P(x - span * 0.12, y + height * 0.21)],
                    width: 1.25, tone: 0.44, dry: 0.6)
            }
            for _ in 0..<(index == 0 ? 2 : 1) {
                let center = left + span * (0.24 + r() * 0.48)
                for k in 0..<(3 + Int(r() * 3)) {
                    let x = center + Double(k) * 3.1, y = top(crest, x) + 0.5
                    c += inkLine([P(x, y), P(x + 2 + r() * 1.5, y - 0.3)],
                        width: 1.1 + r() * 0.6, tone: 0.60 + r() * 0.16, dry: 0.4)
                }
            }
        }
        if flip { c = c.map { var p = $0; p.p = p.p.map { P(width - $0.x, $0.y) }; return p } }
        return c
    }

    /// 矾头 and stacked shoulders, with dry folds flowing down from the ridge.
    /// This path does not call legacy mountain(), whose uniform tree rim is frozen for older versions.
    func paintingMassif(_ profile: PaintingMountainProfile, terraced: Bool = false) -> ZXArt.SSCanv {
        let width = profile.width * (profile.form == .clustered ? 0.88 : 0.64)
        let height = profile.height
        var ridge = (0...90).map { i -> P in
            let t = Double(i) / 90
            let elevation = profile.elevation(at: t)
            let grain = (n(t * 34, 4) - 0.5) * 9 * sin(t * .pi)
            return P(width * t, height * (1 - elevation) + grain)
        }
        if terraced, let summit = ridge.map(\.y).min() {
            // Cut the actual rock silhouette. The small terrace will share this bearing plane.
            let level = summit + height * 0.055
            var cut: [P] = []
            for (a, b) in zip(ridge, ridge.dropFirst()) {
                cut.append(P(a.x, max(a.y, level)))
                if (a.y < level) != (b.y < level) {
                    cut.append(P(a.x + (b.x - a.x) * (level - a.y) / (b.y - a.y), level))
                }
            }
            cut.append(ridge.last!)
            ridge = cut
        }
        func ridgeY(_ x: Double) -> Double {
            for (a, b) in zip(ridge, ridge.dropFirst()) where a.x <= x && x <= b.x {
                return a.y + (b.y - a.y) * (x - a.x) / max(0.001, b.x - a.x)
            }
            return height
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
                let crestY = ridgeY(cx)
                let available = height - crestY
                guard available > height * 0.22 else { continue }
                let top = crestY + available * (0.04 + level * 0.72 + r() * 0.09)
                let rx = width * (0.08 + r() * 0.065), ry = available * (0.15 + r() * 0.18)
                let controls = [P(cx - rx, top + ry * 0.5), P(cx - rx * 0.58, top + ry * 0.12),
                    P(cx - rx * 0.3, top + ry * 0.15), P(cx, top),
                    P(cx + rx * 0.48, top + ry * 0.26), P(cx + rx, top + ry * 0.72)]
                let cap = zip(controls, controls.dropFirst()).flatMap { a, b in
                    (0..<5).map { i -> P in
                        let t = Double(i) / 5, x = a.x + (b.x - a.x) * t
                        return P(x, max(ridgeY(x) + 1, a.y + (b.y - a.y) * t))
                    }
                } + [controls.last!]
                // Shoulder wash follows its broken ridge, then loses ink into the parent body.
                // Thin adjacent strips fade down; there is no closed rounded foot contour.
                let wash = 0.09 + r() * 0.035
                for band in 0..<18 {
                    func edge(_ t: Double) -> [P] {
                        cap.enumerated().map { index, p in
                            let u = Double(index) / Double(cap.count - 1)
                            let reach = ry * (1.2 + 0.35 * n(p.x * 0.035, top * 0.025))
                            return P(p.x, min(height + 2, p.y + reach * t * pow(sin(u * .pi), 0.45)))
                        }
                    }
                    let t = Double(band) / 18
                    c.append(poly(edge(t) + edge(Double(band + 1) / 18).reversed(),
                        fil: .gray(0, wash * pow(1 - t, 1.7)), str: nil))
                }
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
                let p = P(width * t, ridgeY(width * t)), treeH = 3 + r() * 8
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
