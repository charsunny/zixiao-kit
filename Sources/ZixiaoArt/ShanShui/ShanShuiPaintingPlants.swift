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

    /// A tree drawn from its own trunk: the trunk bends at random joints and leans, branches
    /// leave at species-specific angles, and the crown takes the species' shape —
    /// pine: near-level limbs with flat layered needle clusters and a flat top (松);
    /// blossom / maple / layered: limbs angled up, a rounded crown of leaf or flower clusters;
    /// bare: crab-claw limbs whose tips hook down (蟹爪); willow: an arching trunk, hanging strands.
    func paintingTree(_ kind: ZXArt.SceneMotif) -> ZXArt.SSCanv {
        if kind == .oldTree { return paintingLegacy(tree06(65, 175, hei: 165, wid: 5)) }
        let bare = kind == .bareTree, pine = kind == .pine, willow = kind == .willow
        let flowering = kind == .blossom
        // Trunk: a random walk upward with a lean; pines and willows bend more.
        let height = (pine ? 168 : 150) + r() * 20
        let lean = (r() - 0.5) * (willow ? 60 : (pine ? 40 : 28))
        var joints: [P] = [P(66, 178)]
        let segments = 5
        for k in 1...segments {
            let t = Double(k) / Double(segments)
            let wander = (r() - 0.5) * (pine || bare ? 16 : 10)
            joints.append(P(66 + lean * pow(t, willow ? 0.7 : 1.3) + wander * (1 - t * 0.5), 178 - height * t))
        }
        let spine = inkCurve(joints)
        func spinePoint(_ t: Double) -> P {
            let i = min(spine.count - 1, max(0, Int(t * Double(spine.count - 1))))
            return spine[i]
        }
        var c: ZXArt.SSCanv = []
        let limbs = willow ? 4 : (pine ? 6 + Int(r() * 3) : 5 + Int(r() * 3))
        var side = r() < 0.5 ? -1.0 : 1.0
        var tips: [(P, Double)] = []
        for k in 0..<limbs {
            let t = (pine ? 0.42 : 0.38) + 0.55 * (Double(k) + r() * 0.5) / Double(limbs)
            let origin = spinePoint(t)
            if r() < 0.7 { side = -side }
            let span = (pine ? 34 + r() * 26 : 26 + r() * 24) * (1.1 - t * 0.6)
            // Pine limbs run nearly level and droop; deciduous limbs rise; bare limbs rise then hook.
            let rise = pine ? -2 + r() * 6 : (bare ? 14 + r() * 14 : 10 + r() * 16)
            let joint = P(origin.x + side * span * 0.5, origin.y - rise * 0.6)
            var tip = P(origin.x + side * span, origin.y - rise)
            if bare { tip = P(tip.x + side * 4, tip.y + 6 + r() * 6) }          // 蟹爪: the tip hooks down
            if pine { tip = P(tip.x, tip.y + 3 + r() * 3) }                      // a pine limb droops at the end
            c += inkLine(inkCurve([origin, joint, tip]), width: max(1.2, 3.6 - t * 2.4), tone: 0.72,
                dry: bare ? 0.45 : 0.3)
            // Twigs: two or three short offshoots.
            for _ in 0..<(2 + Int(r() * 2)) {
                let u = 0.45 + r() * 0.5
                let from = P(origin.x + (tip.x - origin.x) * u, origin.y + (tip.y - origin.y) * u)
                let to = P(from.x + side * (5 + r() * 9), from.y - (pine ? r() * 3 : 6 + r() * 8) + (bare ? 3 : 0))
                c += inkLine([from, to], width: 0.8, tone: 0.6, dry: 0.45)
                tips.append((to, side))
            }
            tips.append((tip, side))
        }
        if !bare && !willow {
            if pine {
                // Flat, layered needle clusters along each limb end, plus a flat crown at the top.
                for (p, _) in tips where r() < 0.8 {
                    c += paintingLeaves(p.x, p.y - 2, width: 34 + r() * 16, height: 10 + r() * 4, needles: true)
                }
                let top = spine.last!
                c += paintingLeaves(top.x, top.y + 4, width: 46, height: 12, needles: true)
            } else {
                // Rounded crown: clusters gather inside an ellipse around the upper trunk.
                let center = spinePoint(0.78)
                for (p, _) in tips {
                    let q = P(p.x + (center.x - p.x) * 0.15, p.y + (center.y - p.y) * 0.15)
                    c += paintingLeaves(q.x, q.y - 3, width: 26 + r() * 14, height: 20 + r() * 10, flowering: flowering)
                }
                c += paintingLeaves(center.x, center.y - 18, width: 40, height: 30, flowering: flowering)
            }
        }
        // Trunk after the crown, a loaded contour with dry bark inside; roots grip the ground.
        c += inkLine(spine, width: pine ? 7.4 : 6.6, tone: 0.85, dry: 0.42, profile: .cone)
        for offset in [-2.0, 1.5] {
            c += inkLine(spine.map { P($0.x + offset, $0.y + 1) }, width: 0.7, tone: 0.52, dry: 0.72)
        }
        if pine {
            for _ in 0..<8 {  // bark scales
                let p = spinePoint(0.1 + r() * 0.7)
                c += inkLine([P(p.x - 2.5, p.y), P(p.x + 2, p.y + 1.5)], width: 0.9, tone: 0.55, dry: 0.5)
            }
        }
        for (dx, dy) in [(-13.0, 4.0), (9, 4), (-6, 6)] {
            c += inkLine([P(65, 167), P(65 + dx * 0.4, 177), P(65 + dx, 178 + dy)], width: 2.3, tone: 0.6)
        }
        if willow {
            let crown = spinePoint(0.9)
            for k in 0..<18 {
                let x = crown.x - 48 + Double(k) * 5.6 + (r() - 0.5) * 5
                let y = crown.y - 6 + pow((Double(k) - 9) / 9, 2) * 26 + r() * 5
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
            (46, 116, 34, 10, 0), (100, 122, 40, 11, 0), (16, 112, 22, 7, 0),
            (132, 96, 28, 9, 30), (66, 92, 32, 10, 40),
        ]
        for leaf in leaves {
            let seed = r() * 10, notch = r() * 2 * Double.pi
            let cy = leaf.y - leaf.raised
            // A raised leaf is seen side-on and tipped: a tilted, flattened bowl, not a flat plate.
            let tilt = leaf.raised > 0 ? (r() < 0.5 ? -1.0 : 1.0) * (0.25 + r() * 0.2) : 0
            let squash = leaf.raised > 0 ? 0.55 : 1.0
            let edge = (0...56).map { i -> P in
                let a = Double(i) / 56 * 2 * Double.pi
                var v = 0.86 + 0.18 * n(a * 2.2 + seed)
                let gap = abs(atan2(sin(a - notch), cos(a - notch)))
                if gap < 0.22 { v *= 0.55 + gap * 2 }          // the notch where the stem joins
                let ex = cos(a) * leaf.rx * v, ey = sin(a) * leaf.ry * v * squash
                return P(leaf.x + ex * cos(tilt) - ey * sin(tilt), cy + ex * sin(tilt) + ey * cos(tilt))
            }
            // 泼墨: leaves are the darkest masses of the pond; raised ones darkest of all.
            let tone = 0.32 + r() * 0.2 + (leaf.raised > 0 ? 0.12 : 0)
            c.append(poly(edge, fil: .white, str: nil))
            c.append(poly(edge, fil: .gray(0, tone), str: nil))
            // A darker loaded stroke along the far rim gives the leaf its curl.
            let rim = Array(edge[30...54])
            c += inkLine(rim, width: 1.6 + r(), tone: min(0.85, tone + 0.3), dry: 0.35)
            // Veins lifted out in paper white, radiating from the stem point.
            for k in 0..<6 {
                let a = Double(k) / 6 * 2 * Double.pi + seed
                let ex = cos(a) * leaf.rx * 0.72, ey = sin(a) * leaf.ry * 0.72 * squash
                c.append(poly([P(leaf.x, cy), P(leaf.x + ex * cos(tilt) - ey * sin(tilt) + 0.9, cy + ex * sin(tilt) + ey * cos(tilt)),
                               P(leaf.x + ex * cos(tilt) - ey * sin(tilt), cy + ex * sin(tilt) + ey * cos(tilt) + 0.9)],
                    fil: C(255, 255, 255, 0.45), str: nil))
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
