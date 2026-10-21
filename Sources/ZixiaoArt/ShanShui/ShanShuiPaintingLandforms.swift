// shanshui@5: terrain is built from connected ridges, with texture following their folds.
import Foundation

extension ShanShuiEngine {
    /// A bank is one continuous slope, not four copies of a stone asset.
    func paintingSlope(_ style: BankStyle) -> ZXArt.SSCanv {
        let flip = r() < 0.5
        let height = style == .shoal ? 34.0 : (style == .cliff ? 100 : 72)
        let crest = inkCurve([P(0, height * 0.86), P(24, height * 0.55), P(60, height * 0.38),
            P(91, height * 0.10), P(119, height * 0.18), P(149, height * 0.42),
            P(184, height * 0.57), P(220, height * 0.70), P(268, height * 0.91), P(300, height)])
        let bottom = inkCurve([P(300, height), P(243, height + 5), P(181, height + 9),
            P(119, height + 13), P(52, height + 7), P(0, height * 0.86)])
        var c = [poly(crest + bottom, fil: .white, str: nil),
                 poly(crest + bottom, fil: .gray(0, 0.045), str: nil)]
        // 折带 / 披麻: long broken fibres bend with the low bank; cliff planes use broad side strokes.
        for k in 0..<48 {
            let i = 2 + Int(r() * Double(crest.count - 5)), p = crest[i]
            let reach = max(2, height + 3 - p.y) * (0.25 + r() * 0.65)
            let dx = (style == .cliff ? -0.25 : -0.75) * reach
            let line = inkCurve([P(p.x, p.y + 2), P(p.x + dx * 0.25, p.y + reach * 0.42),
                P(p.x + dx, p.y + reach * 0.8), P(p.x + dx + 8, p.y + reach)])
            c += inkLine(line, width: style == .cliff ? 2.0 + r() * 4 : 0.65 + r() * 1.0,
                tone: k % 7 == 0 ? 0.46 : 0.12 + r() * 0.17, dry: 0.65)
        }
        for start in stride(from: 1, to: crest.count - 5, by: 7) {
            c += inkLine(Array(crest[start...min(start + 5, crest.count - 1)]),
                width: style == .shoal ? 1.2 : 2.0, tone: 0.62, dry: 0.42)
        }
        // Uneven moss groups on the shoulders, with open passages between them.
        for cluster in [0.18, 0.34, 0.63] {
            let i = Int(cluster * Double(crest.count - 1)), p = crest[i]
            for _ in 0..<(3 + Int(r() * 5)) {
                c += inkBlot(p.x + (r() - 0.5) * 19, p.y + r() * 5,
                    radius: 0.8 + r() * 1.7, squash: 0.44, tone: 0.65 + r() * 0.25)
            }
        }
        for (x, span) in [(8.0, 36.0), (77, 62), (185, 47), (258, 25)] {
            c += inkLine(inkCurve([P(x, height + 5), P(x + span * 0.5, height + 7), P(x + span, height + 5)]),
                width: 1.7, tone: 0.56, dry: 0.62)
        }
        if flip { c = c.map { poly in var p = poly; p.p = poly.p.map { P(300 - $0.x, $0.y) }; return p } }
        return c
    }

    /// 矾头 and stacked shoulders, with dry folds flowing down from the ridge.
    /// This path does not call legacy mountain(), whose uniform tree rim is frozen for older versions.
    func paintingMassif(_ profile: PaintingMountainProfile) -> ZXArt.SSCanv {
        let width = profile.width * (profile.form == .monumental ? 0.74 : 1)
        let height = profile.height
        let ridge = (0...90).map { i -> P in
            let t = Double(i) / 90
            let elevation = profile.elevation(at: t)
            let grain = (n(t * 34, 4) - 0.5) * 9 * sin(t * .pi)
            return P(width * t, height * (1 - elevation) + grain)
        }
        let outline = ridge + [P(width * 0.88, height + 8), P(width * 0.12, height + 8)]
        var c = [poly(outline, fil: .white, str: nil)]
        c += inkSurface(outline, textured: true)
        for start in stride(from: 0, to: ridge.count - 3, by: 5) {
            c += inkLine(Array(ridge[start...min(start + 4, ridge.count - 1)]), width: 1.4 + r(), tone: 0.62, dry: 0.48)
        }
        // 主脉: each buttress starts on its own shoulder, not at an arbitrary rectangle edge.
        for u in [0.22, 0.34, 0.49, 0.63, 0.77] {
            let p = ridge[Int(u * 90)], reach = (height - p.y) * (0.55 + r() * 0.3)
            guard reach > 25 else { continue }
            let bend = (u < 0.5 ? -1.0 : 1.0) * width * (0.04 + r() * 0.05)
            for k in 0..<7 {
                let offset = Double(k) * (1.3 + r() * 1.4)
                let path = inkCurve([P(p.x + offset, p.y + 8),
                    P(p.x + bend * 0.3 + offset, p.y + reach * 0.26),
                    P(p.x + bend * 0.5 + offset, p.y + reach * 0.62),
                    P(p.x + bend + offset * 0.5, p.y + reach)])
                c += inkLine(path, width: k == 0 ? 3.4 : 0.9 + r(),
                             tone: k == 0 ? 0.48 : 0.17 + r() * 0.13, dry: 0.68)
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
