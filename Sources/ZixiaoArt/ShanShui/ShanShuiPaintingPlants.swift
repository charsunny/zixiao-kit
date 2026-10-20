// shanshui@5 painting path. Preserve this version when adding future painting styles.
import Foundation

extension ShanShuiEngine {
    /// Unoutlined leaf masses: pale ink underpainting, darker point-and-slash clusters.
    private func paintingLeaves(_ x: Double, _ y: Double, width: Double, height: Double,
                                needles: Bool = false, flowering: Bool = false) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for _ in 0..<6 {
            c += inkBlot(x + (r() - 0.5) * width * 0.65, y + (r() - 0.5) * height * 0.6,
                radius: width * (0.18 + r() * 0.1), squash: height / width * 0.65,
                angle: (r() - 0.5) * 0.4, tone: 0.08 + r() * 0.06)
        }
        for _ in 0..<(needles ? 24 : 32) {
            let a = r() * 2 * Double.pi, rad = sqrt(r())
            let px = x + cos(a) * width * rad / 2, py = y + sin(a) * height * rad / 2
            if needles {
                for k in 0..<3 {
                    let angle = -Double.pi * (0.12 + Double(k) * 0.25 + r() * 0.16)
                    c += inkLine([P(px + cos(angle) * (3 + r() * 4), py + sin(angle) * (3 + r() * 4)), P(px, py)],
                        width: 0.55 + r() * 0.45, tone: 0.45 + r() * 0.35, dry: 0.30)
                }
            } else if flowering {
                // Blossom: pale round flowers (淡墨点花) with a dark dot of stamens; buds darker and smaller.
                let open = r() < 0.75
                c += inkBlot(px, py, radius: open ? 1.9 + r() * 1.1 : 1.0 + r() * 0.5,
                    squash: 0.8 + r() * 0.2, angle: r() * 3, tone: open ? 0.08 + r() * 0.08 : 0.30)
                if open { c += inkBlot(px + 0.2, py + 0.1, radius: 0.45, squash: 0.9, tone: 0.70) }
            } else {
                c += inkBlot(px, py, radius: 1.3 + r() * 2.7,
                    squash: 0.35 + r() * 0.45, angle: -0.8 + r() * 1.5, tone: 0.42 + r() * 0.4)
            }
        }
        return c
    }

    func paintingTree(_ kind: ZXArt.SceneMotif) -> ZXArt.SSCanv {
        if kind == .oldTree { return paintingLegacy(tree06(65, 175, hei: 165, wid: 5)) }
        let bare = kind == .bareTree, pine = kind == .pine, willow = kind == .willow
        let flowering = kind == .blossom, old = kind == .oldTree
        let spine = inkCurve([P(66, 178), P(62, 151), P(67, 123), P(57, 95), P(68, 63), P(78, 32), P(73, 9)])
        var c: ZXArt.SSCanv = []
        // Off-centre branch groups produce the staggered rhythm of a tree, not a symmetric symbol.
        for k in 0..<(willow ? 4 : 7) {
            let right = k % 3 == 0, dir = right ? 1.0 : -1.0
            let y = 124 - Double(k) * 16, x = 65 + Double(k) * 1.8
            let span = (25 + r() * 29) * (1 - Double(k) * 0.065)
            let joint = P(x + dir * span * 0.55, y - 9 - r() * 10)
            let tip = P(x + dir * span, y - 18 - r() * 12)
            c += inkLine(inkCurve([P(x, y + 5), joint, tip]), width: 3.8 - Double(k) * 0.34,
                tone: 0.72, dry: old || bare ? 0.45 : 0.25)
            for j in 0..<3 {
                let end = P(tip.x + Double(j - 1) * 10, tip.y - 14 - r() * 12)
                c += inkLine(inkCurve([joint, P(tip.x + dir * 4, tip.y - 4), end]),
                    width: 1.4 - Double(k) * 0.08, tone: 0.65, dry: 0.42)
                if !bare && !willow {
                    c += paintingLeaves(end.x + dir * 4, end.y - 1, width: pine ? 47 : 34,
                        height: pine ? 15 : 27, needles: pine, flowering: flowering)
                }
            }
        }
        // Trunk is painted after the canopy, with dry bark left inside a stronger contour.
        c += inkLine(spine, width: old ? 8.2 : 6.8, tone: 0.85, dry: 0.42, profile: .cone)
        for offset in [-2.0, 1.5] {
            c += inkLine(spine.map { P($0.x + offset, $0.y + 1) }, width: 0.7, tone: 0.52, dry: 0.72)
        }
        for (dx, dy) in [(-13.0, 4.0), (9, 4), (-6, 6)] {
            c += inkLine([P(65, 167), P(65 + dx * 0.4, 177), P(65 + dx, 178 + dy)], width: 2.3, tone: 0.6)
        }
        if willow {
            for k in 0..<18 {
                let x = 19 + Double(k) * 5.4 + (r() - 0.5) * 5, y = 21 + pow((Double(k) - 9) / 9, 2) * 26 + r() * 5
                let len = 55 + r() * 48
                let line = inkCurve([P(x, y), P(x - 9, y + len * 0.42), P(x - 5, y + len)])
                c += inkLine(line, width: 0.75, tone: 0.48, dry: 0.15)
                for _ in 0..<(6 + Int(r() * 5)) {
                    let t = 0.06 + r() * 0.91
                    c += inkBlot(x - 6 + sin(t * 4) * 2, y + t * len,
                        radius: 1.5 + r() * 1.5, squash: 0.25, angle: -0.7 - r() * 0.5, tone: 0.32 + r() * 0.3)
                }
            }
        }
        return c
    }

    /// A bamboo grove: stalks of unequal height leaning slightly apart, pale far stalks behind
    /// dark near ones, nodes as short dark strokes, and leaves in clustered 个 / 介 groups at the
    /// tips and joints, heavier toward the top.
    func paintingBamboo() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let stalks = 6 + Int(r() * 3)
        for k in 0..<stalks {
            let far = k < stalks / 3
            let x = 20 + Double(k) * (90 / Double(stalks)) + (r() - 0.5) * 8
            let height = (far ? 110 : 130) + r() * 40, lean = (r() - 0.5) * 34
            let tone = far ? 0.28 + r() * 0.1 : 0.55 + r() * 0.25
            c += inkLine([P(x, 175), P(x + lean * 0.4, 175 - height * 0.55), P(x + lean, 175 - height)],
                width: (far ? 1.6 : 2.4) + r() * 0.8, tone: tone, dry: 0.25, profile: .even)
            let nodes = 6
            for j in 1..<nodes {
                let y = 175 - height * Double(j) / Double(nodes), xx = x + lean * Double(j) / Double(nodes)
                c += inkLine([P(xx - 2, y), P(xx + 2.5, y - 0.5)], width: 1.0, tone: min(0.9, tone + 0.2))
            }
            // Leaf clusters: three to five blades fanning from one point, 个 or 介.
            let clusters = far ? 3 : 5 + Int(r() * 3)
            for q in 0..<clusters {
                let t = 0.32 + 0.68 * (Double(q) + r() * 0.6) / Double(clusters)
                let base = P(x + lean * t, 175 - height * t)
                let side = r() < 0.5 ? -1.0 : 1.0
                let blades = 3 + Int(r() * 2.5)
                for b in 0..<blades {
                    let angle = side * (0.35 + Double(b) * 0.42) + (r() - 0.5) * 0.2
                    let length = 20 + r() * 14
                    let tip = P(base.x + sin(angle) * length, base.y + cos(angle) * length * 0.55 - 2)
                    c += inkLine([base, P((base.x + tip.x) / 2, (base.y + tip.y) / 2 + 1), tip],
                        width: 4.2 + r() * 2.2, tone: far ? 0.30 : 0.62 + r() * 0.25, dry: 0.1, profile: .lens)
                }
            }
        }
        return c
    }

    /// Lotus as ink-wash leaves (泼墨荷叶): broad, uneven discs seen in perspective, overlapping,
    /// some lying on the water and some curling up with a dark rim; short stems; one pointed bud
    /// rising above them (小荷才露尖尖角) and an open flower only when there is room.
    func paintingLotus() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let leaves: [(x: Double, y: Double, rx: Double, ry: Double, raised: Double)] = [
            (46, 114, 34, 10, 0), (98, 120, 40, 11, 0), (130, 108, 26, 8, 5),
            (72, 106, 30, 9, 8), (16, 108, 20, 6, 3),
        ]
        for leaf in leaves {
            let seed = r() * 10, notch = r() * 2 * Double.pi
            let cy = leaf.y - leaf.raised
            let edge = (0...56).map { i -> P in
                let a = Double(i) / 56 * 2 * Double.pi
                var v = 0.86 + 0.18 * n(a * 2.2 + seed)
                let gap = abs(atan2(sin(a - notch), cos(a - notch)))
                if gap < 0.22 { v *= 0.55 + gap * 2 }          // the notch where the stem joins
                return P(leaf.x + cos(a) * leaf.rx * v, cy + sin(a) * leaf.ry * v)
            }
            let tone = 0.15 + r() * 0.16 + (leaf.raised > 0 ? 0.05 : 0)
            c.append(poly(edge, fil: .white, str: nil))
            c.append(poly(edge, fil: .gray(0, tone), str: nil))
            // A darker loaded stroke along the far rim gives the leaf its curl.
            let rim = Array(edge[30...54])
            c += inkLine(rim, width: 1.6 + r(), tone: min(0.85, tone + 0.3), dry: 0.35)
            // A few veins from the centre, only on the near half.
            for k in 0..<4 {
                let a = 0.3 + Double(k) * 0.65
                c += inkLine([P(leaf.x, cy), P(leaf.x + cos(a) * leaf.rx * 0.7, cy + sin(a) * leaf.ry * 0.7)],
                    width: 0.5, tone: min(0.7, tone + 0.15), dry: 0.4)
            }
            if leaf.raised > 0 {
                c += inkLine(inkCurve([P(leaf.x + 2, cy + leaf.ry * 0.6), P(leaf.x - 1, leaf.y - leaf.raised * 0.4),
                    P(leaf.x + 1, leaf.y + 4)]), width: 1.0, tone: 0.55, dry: 0.4)
            }
        }
        // The bud: pointed, pale, on a slender stem rising above the leaves.
        let stem = inkCurve([P(84, 108), P(86, 86), P(84, 62)])
        c += inkLine(stem, width: 1.1, tone: 0.55, dry: 0.4)
        let bud = inkCurve([P(84, 60), P(78, 52), P(81, 40), P(84, 32), P(88, 41), P(90, 52), P(84, 60)])
        c.append(poly(bud, fil: .white, str: nil))
        c.append(poly(bud, fil: .gray(0, 0.06), str: nil))
        c += inkLine(Array(bud.prefix(bud.count / 2 + 1)), width: 0.8, tone: 0.55, dry: 0.4)
        c += inkLine(Array(bud.suffix(bud.count / 2)), width: 0.6, tone: 0.40, dry: 0.5)
        c += inkBlot(84, 33, radius: 1.2, squash: 0.7, tone: 0.5)
        // Water line under the leaves.
        for k in 0..<3 {
            let y = 126 + Double(k) * 4, x = 10 + r() * 30
            c += inkLine([P(x, y), P(x + 60 + r() * 50, y + 0.6)], width: 0.6, tone: 0.12, dry: 0.6)
        }
        return c
    }
}
