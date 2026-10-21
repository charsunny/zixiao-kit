// shanshui@5: terrain is built from connected ridges, with texture following their folds.
import Foundation

extension ShanShuiEngine {
    /// A bank consists of overlapping stones, each drawn with long folded contours.
    /// The only opaque shapes are the stones themselves; there is no full-width paper plinth.
    func paintingSlope(_ style: BankStyle) -> ZXArt.SSCanv {
        let width = 280 + r() * 45
        let height = style == .shoal ? 53 + r() * 17 : (style == .cliff ? 88 + r() * 22 : 69 + r() * 24)
        let count = 2 + Int(r() * 3), flip = r() < 0.5
        var c: ZXArt.SSCanv = []
        for index in 0..<count {
            let progress = Double(index) / Double(count - 1)
            let span = width / (1 + Double(count - 1) * 0.62)
            let left = progress * (width - span), right = left + span
            let top = height * (0.03 + progress * 0.30 + r() * 0.06)
            let floor = height * (0.70 + progress * 0.27)
            let depth = floor - top
            let shoulder = left + span * (0.73 + r() * 0.09)
            let crest = inkCurve([P(left, floor - depth * 0.12),
                P(left + span * 0.20, top + depth * 0.10),
                P(left + span * 0.48, top), P(shoulder, top + depth * 0.06),
                P(right, floor - depth * 0.10)], steps: 10)
            func ridge(_ x: Double) -> Double {
                for (a, b) in zip(crest, crest.dropFirst()) where x >= a.x && x <= b.x {
                    return a.y + (b.y - a.y) * (x - a.x) / max(0.001, b.x - a.x)
                }
                return floor
            }
            let foot = inkCurve([crest.last!, P(left + span * 0.70, floor + 1),
                P(left + span * 0.28, floor - depth * 0.02), crest[0]])
            c.append(poly(crest + foot, fil: .white, str: nil))
            let tone = 0.57 + progress * 0.17
            // Two long runs share the crest. Pressure loads the turn and lifts on the cap.
            c += slopeStroke(Array(crest[0...25]), width: 1.9, tone: tone,
                pressures: [0.3, 0.9, 0.5, 0.36, 0.65])
            c += slopeStroke(Array(crest[23...40]), width: 2.3, tone: tone + 0.04,
                pressures: [0.3, 0.45, 1.25, 0.8, 0.12])
            let foldX = left + span * (0.56 + r() * 0.12)
            let foldY = ridge(foldX) + depth * 0.08
            c += slopeStroke(inkCurve([P(foldX - span * 0.17, foldY), P(foldX, foldY - 1),
                P(foldX + span * 0.055, foldY + depth * 0.28)]), width: 1.45, tone: tone,
                pressures: [0.3, 0.5, 1, 0.6, 0.1])
            if style == .cliff {
                // Broad side-brush axe cuts: short diagonal planes, never vertical hair rows.
                for cut in 0..<(3 + Int(r() * 2)) {
                    let x = left + span * (0.37 + Double(cut) * 0.105 + r() * 0.035)
                    let y = ridge(x) + depth * (0.16 + r() * 0.07)
                    let reach = depth * (0.25 + r() * 0.15)
                    let lean = reach * (0.70 + r() * 0.45)
                    c += slopeStroke(inkCurve([P(x, y), P(x + lean * 0.45, y + reach * 0.45),
                        P(x + lean, y + reach)]), width: 7 + r() * 5, tone: 0.38 + r() * 0.10,
                        pressures: [1.1, 0.85, 0.5, 0.22, 0.03], dry: 0.72)
                }
            } else {
                for bundle in 0..<3 {
                    let x = left + span * (0.30 + Double(bundle) * 0.19 + r() * 0.04)
                    for hair in 0..<(3 + Int(r() * 4)) {
                        let sx = x + Double(hair) * 2.4
                        let sy = ridge(sx) + depth * (0.08 + Double(hair) * 0.025)
                        let reach = depth * (0.15 + r() * 0.25)
                        let run = reach * (style == .shoal ? 1.6 : 0.9)
                        let line = [P(sx, sy), P(sx + run * 0.7, sy + reach * 0.12),
                            P(sx + run, sy + reach)]
                        guard line.last!.x < right - 3 else { continue }
                        c += slopeStroke(inkCurve(line), width: 0.8 + r() * 0.6, tone: 0.30 + r() * 0.20,
                            pressures: [0.5, 0.8, 0.9, 0.45, 0.08], dry: 0.65)
                    }
                }
            }
            // One continuous, feathered wash under the crest; sine-tapered ends and
            // fading adjacent strips avoid both rectangular patches and nested ghost shapes.
            for band in 0..<24 {
                func edge(_ t: Double) -> [P] {
                    (0...32).map { j in
                        let u = Double(j) / 32
                        let x = left + span * (0.16 + u * 0.80)
                        let y = ridge(x) + depth * 0.04
                        let reach = max(0, floor - y) * pow(sin(u * .pi), 0.6)
                        return P(x, y + reach * t)
                    }
                }
                let t = Double(band) / 24
                c.append(poly(edge(t) + edge(Double(band + 1) / 24).reversed(),
                    fil: .gray(0, (0.055 + progress * 0.025) * pow(1 - t, 2)), str: nil))
            }
            // The foot remains open: two or three horizontal water-mouth strokes.
            for k in 0..<(2 + Int(r() * 2)) {
                let x = left + span * (0.12 + Double(k) * 0.28)
                let y = floor + Double(k % 2) * 2.4
                c += slopeStroke([P(x, y), P(x + span * 0.13, y - 0.7), P(x + span * 0.26, y)],
                    width: 1.2, tone: 0.40, pressures: [0.1, 0.6, 0.5, 0.3, 0.05])
            }
            for u in [0.23 + r() * 0.10, 0.72 + r() * 0.06] {
                for k in 0..<(3 + Int(r() * 5)) {
                    let x = left + span * u + Double(k) * 3.3
                    let y = ridge(x) + r() * 1.2
                    c += slopeStroke([P(x, y), P(x + 2.5 + r() * 1.6, y - 0.5)],
                        width: 1.7 + r() * 0.6, tone: 0.85 + r() * 0.09,
                        pressures: [0.5, 1, 1, 0.8, 0.15], dry: 0.25)
                }
            }
        }
        if flip { c = c.map { var p = $0; p.p = p.p.map { P(width - $0.x, $0.y) }; return p } }
        return c
    }

    func paintingRootMoss(_ root: P) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for k in 0..<(3 + Int(r() * 5)) {
            let p = root + P(-7 + Double(k) * 2.7, 1 + r() * 1.5)
            c += slopeStroke([p, p + P(2.5 + r(), -0.4)], width: 1.6, tone: 0.88,
                pressures: [0.4, 1, 0.9, 0.5, 0.1], dry: 0.25)
        }
        return c
    }

    /// Pressure belongs to the long gesture, not to each short polygon edge.
    private func slopeStroke(_ points: [P], width: Double, tone: Double,
                             pressures: [Double], dry: Double = 0.42) -> ZXArt.SSCanv {
        // Even a two-point moss dab needs an interior loaded section between its lifted ends.
        let samples = zip(points, points.dropFirst()).flatMap { a, b -> [P] in
            let steps = max(4, Int(hypot(b.x - a.x, b.y - a.y) / 2))
            return (0..<steps).map { a + (b - a) * (Double($0) / Double(steps)) }
        } + [points.last!]
        let path = samples.enumerated().map { index, p -> SIMD3<Double> in
            let t = Double(index) / Double(max(1, samples.count - 1)) * Double(pressures.count - 1)
            let i = min(pressures.count - 2, Int(t)), f = t - Double(i)
            return SIMD3(p.x, p.y, pressures[i] * (1 - f) + pressures[i + 1] * f)
        }
        let stroke = ZXArt.Brush.stroke(path, style: .init(width: width, tone: tone, dry: dry,
            side: 0.2, bristles: width > 4 ? 7 : 3, rough: 0.25, fade: 0.42, profile: .even), seed: inkSeed())
        var c = [poly(stroke.body.map { P(Double($0.x), Double($0.y)) },
            fil: .gray(0, tone * (dry > 0.6 ? 0.32 : 0.78)), str: nil)]
        for hair in stroke.bristles {
            for run in hair.runs {
                c.append(poly(run.map { P(Double($0.x), Double($0.y)) }, fil: nil,
                    str: .gray(0, Double(hair.alpha)), wid: Double(hair.width)))
            }
        }
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
