// shanshui@5: terrain is built from connected ridges, with texture following their folds.
import Foundation

extension ShanShuiEngine {
    /// A bank (坡石) as landscape painters build it: one main stone, lower companions in front
    /// and sometimes a back stone peeking over. Each stone shows its faces (石分三面): a lit top
    /// left as paper, a fold line where the top turns down, and a shaded front face below it that
    /// carries the texture and the wash. Shoals are long and low with 折带 strokes; earth banks
    /// hang 披麻 strands from the fold; cliffs are flat-topped, square-shouldered and split by
    /// side-brush axe cuts (斧劈).
    func paintingSlope(_ style: BankStyle) -> ZXArt.SSCanv {
        let width = 280 + r() * 50
        let height = style == .shoal ? 36 + r() * 14 : (style == .cliff ? 92 + r() * 26 : 64 + r() * 24)
        let flip = r() < 0.5
        struct Stone { var x0, x1, top, floor: Double; var rank: Int }
        var stones: [Stone] = []
        let mainWidth = width * (style == .shoal ? 0.58 + r() * 0.16 : 0.46 + r() * 0.16)
        let mainX = width * (0.02 + r() * 0.08)
        let main = Stone(x0: mainX, x1: mainX + mainWidth, top: height * (0.10 + r() * 0.06), floor: height, rank: 1)
        if style != .shoal || r() < 0.4 {
            // The back stone rises behind the main one, offset to the gentle side.
            let w = mainWidth * (0.45 + r() * 0.25)
            let x = mainX + mainWidth * (0.30 + r() * 0.40)
            stones.append(Stone(x0: x, x1: min(width, x + w), top: 0,
                floor: height * (0.55 + r() * 0.15), rank: 0))
        }
        stones.append(main)
        var x = main.x1 - mainWidth * (0.22 + r() * 0.16)
        for k in 0..<(1 + Int(r() * 2.4)) {
            let w = width * (0.20 + r() * 0.14) * (k == 0 ? 1 : 0.7)
            guard x + w <= width + 1 else { break }
            let top = height * (0.36 + r() * 0.22 + Double(k) * 0.12)
            stones.append(Stone(x0: x, x1: min(width, x + w), top: top, floor: height * (0.97 + r() * 0.03), rank: 2))
            x += w * (0.55 + r() * 0.30)
        }

        var c: ZXArt.SSCanv = []
        for stone in stones {
            c += paintingStone(x0: stone.x0, x1: stone.x1, top: stone.top, floor: stone.floor,
                style: style, rank: stone.rank)
        }
        if flip { c = c.map { var p = $0; p.p = p.p.map { P(width - $0.x, $0.y) }; return p } }
        return c
    }

    private func paintingStone(x0: Double, x1: Double, top: Double, floor: Double,
                               style: BankStyle, rank: Int) -> ZXArt.SSCanv {
        let w = x1 - x0, h = floor - top
        let cliff = style == .cliff, shoal = style == .shoal
        // One side rises gently (the back of the slope), the other turns down steeply toward the
        // water. Cliffs turn both shoulders sharply; the top stays nearly level.
        let gentleLeft = r() < 0.5
        let rise = cliff ? 0.07 + r() * 0.06 : 0.16 + r() * 0.14
        let fall = cliff ? 0.05 + r() * 0.05 : 0.08 + r() * 0.08
        let left = gentleLeft ? rise : fall, right = gentleLeft ? fall : rise
        var keys = [P(x0, floor - h * 0.04),
                    P(x0 + w * left * 0.45, top + h * (cliff ? 0.30 : 0.42) + h * r() * 0.12),
                    P(x0 + w * left, top + h * r() * 0.06)]
        let bumps = cliff ? 1 + Int(r() * 2) : 1 + Int(r() * 3)
        for k in 1...bumps {
            let u = left + (1 - left - right) * Double(k) / Double(bumps + 1)
            keys.append(P(x0 + w * (u + (r() - 0.5) * 0.06), top + h * r() * (cliff ? 0.05 : shoal ? 0.10 : 0.16)))
        }
        keys += [P(x1 - w * right, top + h * (0.03 + r() * 0.10)),
                 P(x1 - w * right * 0.35, top + h * (cliff ? 0.30 : 0.45) + h * r() * 0.15),
                 P(x1, floor - h * 0.02)]
        // Cliffs keep their corners; earth and shoals are rounded by the brush.
        let crest = cliff ? densify(keys, step: 3) : inkCurve(keys, steps: 8)
        func ridge(_ x: Double) -> Double {
            for (a, b) in zip(crest, crest.dropFirst()) where x >= min(a.x, b.x) && x <= max(a.x, b.x) {
                return abs(b.x - a.x) < 0.001 ? min(a.y, b.y) : a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
            }
            return floor
        }
        let base = inkCurve([crest.last!, P(x0 + w * 0.70, floor + 1.5), P(x0 + w * 0.30, floor + 0.5), crest[0]], steps: 8)
        var c = [poly(crest + base, fil: .white, str: nil)]

        // The fold where the lit top turns into the face, roughly parallel to the crest.
        let drop = h * (shoal ? 0.38 + r() * 0.12 : cliff ? 0.16 + r() * 0.08 : 0.22 + r() * 0.10)
        let foldFrom = x0 + w * (left * (0.55 + r() * 0.3))
        let foldTo = x0 + w * (0.58 + r() * 0.30)
        let fold = (0...20).map { i -> P in
            let x = foldFrom + (foldTo - foldFrom) * Double(i) / 20
            let wobble = (n(x * 0.05, Double(rank) + 7) - 0.5) * h * 0.08
            return P(x, min(floor - 2, ridge(x) + drop + wobble))
        } + [P(foldTo + w * 0.04, min(floor - 1, ridge(foldTo) + drop + h * (cliff ? 0.30 : 0.18)))]
        func faceTop(_ x: Double) -> Double {
            guard x >= foldFrom, x <= foldTo else { return min(floor, ridge(x) + drop * 1.1) }
            let i = min(19, Int((x - foldFrom) / max(0.001, foldTo - foldFrom) * 20))
            return fold[i].y
        }

        // Wash on the face: strongest just under the fold, fading toward the foot.
        let washTone = (cliff ? 0.10 : 0.075) + Double(rank) * 0.012
        for band in 0..<14 {
            func edge(_ t: Double) -> [P] {
                (0...28).map { j in
                    let u = Double(j) / 28, x = x0 + w * (0.04 + u * 0.92)
                    let y = faceTop(x)
                    let taper = pow(sin(u * .pi), 0.5)
                    return P(x, y + max(0, floor - y) * t * taper)
                }
            }
            let t = Double(band) / 14
            c.append(poly(edge(t) + edge(Double(band + 1) / 14).reversed(),
                fil: .gray(0, washTone * pow(1 - t, 1.6)), str: nil))
        }

        // Texture hangs from the fold. The shaded side (the steep one) carries more strokes.
        let shadeLeft = !gentleLeft
        let groups = cliff ? 3 + Int(r() * 3) : 2 + Int(r() * 3)
        for g in 0..<groups {
            var u = (Double(g) + 0.3 + r() * 0.5) / Double(groups)
            u = shadeLeft ? pow(u, 1.4) : 1 - pow(1 - u, 1.4)
            let gx = x0 + w * (0.08 + u * 0.84)
            if cliff {
                // 斧劈: a loaded side-brush wedge, heavy at the fold and dragged down and aside.
                let sy = faceTop(gx) + 1
                let reach = (floor - sy) * (0.40 + r() * 0.35)
                guard reach > 4 else { continue }
                let lean = reach * (0.25 + r() * 0.35) * (gx < x0 + w / 2 ? -1 : 1)
                c += slopeStroke(inkCurve([P(gx, sy), P(gx + lean * 0.4, sy + reach * 0.5), P(gx + lean, sy + reach)]),
                    width: 6 + r() * 6, tone: 0.40 + r() * 0.14, pressures: [1.2, 0.9, 0.55, 0.25, 0.03], dry: 0.70)
                c += slopeStroke([P(gx + 3, sy + reach * 0.1), P(gx + 3 + lean * 0.9, sy + reach * 0.95)],
                    width: 1.1, tone: 0.55, pressures: [0.8, 1, 0.7, 0.4, 0.05], dry: 0.5)
            } else if shoal {
                // 折带: short strokes laid along the face, turning down at their ends.
                for k in 0..<(2 + Int(r() * 2)) {
                    let sy = faceTop(gx) + 2 + Double(k) * h * 0.13
                    guard sy < floor - 2 else { break }
                    let run = w * (0.08 + r() * 0.08)
                    c += slopeStroke([P(gx, sy), P(gx + run, sy + 0.5), P(gx + run + 2, min(floor - 1, sy + h * 0.10))],
                        width: 0.9 + r() * 0.5, tone: 0.34 + r() * 0.14, pressures: [0.4, 0.9, 0.8, 0.5, 0.08], dry: 0.62)
                }
            } else {
                // 披麻: a bundle of strands hanging from the fold, leaning with the slope.
                let lean = (gx < x0 + w / 2 ? -1.0 : 1.0) * (0.10 + r() * 0.20)
                for k in 0..<(3 + Int(r() * 4)) {
                    let sx = gx + Double(k) * (2.2 + r() * 1.2)
                    let sy = faceTop(sx) + r() * 2
                    let reach = (floor - sy) * (0.25 + r() * 0.45)
                    guard reach > 3 else { continue }
                    c += slopeStroke(inkCurve([P(sx, sy), P(sx + reach * lean * 0.3, sy + reach * 0.5),
                        P(sx + reach * lean, sy + reach)]), width: 0.7 + r() * 0.6, tone: 0.30 + r() * 0.16,
                        pressures: [0.6, 1, 0.8, 0.45, 0.05], dry: 0.62)
                }
            }
        }

        // Contour last: two or three long runs, loaded at the turns, lifted along the top.
        let tone = 0.60 + Double(rank) * 0.08
        let n1 = crest.count / 3 + Int(r() * Double(crest.count / 6))
        let n2 = crest.count * 2 / 3 + Int(r() * Double(crest.count / 6))
        let runs = [Array(crest[0...min(crest.count - 1, n1 + 1)]),
                    Array(crest[n1...min(crest.count - 1, n2 + 1)]),
                    Array(crest[n2...])]
        for (i, run) in runs.enumerated() where run.count > 1 {
            c += slopeStroke(run, width: (cliff ? 2.3 : 1.9) * (rank == 0 ? 0.8 : 1), tone: tone,
                pressures: i == 1 ? [0.5, 0.35, 0.45, 0.6, 0.3] : [0.35, 1.0, 0.75, 0.5, 0.15], dry: 0.40)
        }
        c += slopeStroke(fold, width: 1.3, tone: tone - 0.10, pressures: [0.15, 0.7, 0.5, 0.8, 0.1], dry: 0.5)

        // 点苔: dark horizontal dabs in clusters on the crest and its turns.
        for _ in 0..<(rank == 0 ? 1 : 1 + Int(r() * 2)) {
            let cx = x0 + w * (0.12 + r() * 0.76)
            for k in 0..<(3 + Int(r() * 4)) {
                let mx = cx + Double(k) * (2.6 + r() * 1.4) - 6
                guard mx > x0 + 2, mx < x1 - 2 else { continue }
                let my = ridge(mx) + r() * 1.5
                c += slopeStroke([P(mx, my), P(mx + 2.2 + r() * 1.4, my - 0.4)], width: 1.6 + r() * 0.6,
                    tone: 0.86 + r() * 0.08, pressures: [0.5, 1, 1, 0.8, 0.15], dry: 0.22)
            }
        }
        // The foot of front stones opens into water or ground with a few level strokes.
        if rank > 0 {
            for k in 0..<(1 + Int(r() * 2)) {
                let sx = x0 + w * (0.10 + Double(k) * 0.40 + r() * 0.15)
                let sy = floor + 1 + Double(k) * 1.8
                c += slopeStroke([P(sx, sy), P(sx + w * 0.12, sy - 0.6), P(sx + w * 0.24, sy)],
                    width: 1.1, tone: 0.38, pressures: [0.1, 0.6, 0.5, 0.3, 0.05])
            }
        }
        return c
    }

    private func densify(_ points: [P], step: Double) -> [P] {
        zip(points, points.dropFirst()).flatMap { a, b -> [P] in
            let count = max(1, Int(hypot(b.x - a.x, b.y - a.y) / step))
            return (0..<count).map { a + (b - a) * (Double($0) / Double(count)) }
        } + [points.last!]
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
