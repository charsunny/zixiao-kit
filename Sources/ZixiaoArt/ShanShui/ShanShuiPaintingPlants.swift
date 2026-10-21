// shanshui@5 painting path. Preserve this version when adding future painting styles.
import Foundation

extension ShanShuiEngine {
    /// Unoutlined leaf masses: pale ink underpainting, darker point-and-slash clusters.
    enum LeafStyle { case dots, flat, ge }

    private func paintingLeaves(_ x: Double, _ y: Double, width: Double, height: Double,
                                needles: Bool = false, flowering: Bool = false, style: LeafStyle = .dots) -> ZXArt.SSCanv {
        if needles { return paintingPineNeedles(x, y, width: width, height: height) }
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
            } else if style == .flat {
                // 横点: flat horizontal dabs stacked in layers.
                c += inkBlot(px, py, radius: 2.2 + r() * 2.2, squash: 0.28 + r() * 0.12,
                    angle: (r() - 0.5) * 0.25, tone: 0.40 + r() * 0.35)
            } else if style == .ge {
                // 个字点: three short strokes from one point, airy.
                if r() < 0.6 {
                    for k in 0..<3 {
                        let a = -Double.pi / 2 + (Double(k) - 1) * 0.75 + (r() - 0.5) * 0.3
                        c += inkLine([P(px, py), P(px + cos(a) * (3 + r() * 2), py - sin(a) * -(3 + r() * 2))],
                            width: 1.4 + r() * 0.8, tone: 0.45 + r() * 0.35, dry: 0.15, profile: .lens)
                    }
                }
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
        if kind == .oldTree || kind == .bareTree { return paintingWoodyTree(old: kind == .oldTree).canvas }
        if kind == .blossom { return paintingFloweringTree() }
        let bare = kind == .bareTree, pine = kind == .pine, willow = kind == .willow
        let flowering = kind == .blossom
        let leaf: LeafStyle = kind == .layeredTree ? .flat : (kind == .maple ? .ge : .dots)
        // Trunk: a random walk upward with a lean; pines and willows bend more. Now and then a
        // tree leans hard over the water (欹斜) or splits into two stems low down (双干).
        let leaning = !willow && r() < 0.3
        let twin = !pine && !willow && r() < 0.3
        let breadth = 0.75 + r() * 0.6
        let height = (pine ? 132 : 150) * (leaning ? 0.85 : 1) + r() * 20
        let lean = (r() - 0.5) * (willow ? 60 : (pine ? 65 : 28)) + (leaning ? (r() < 0.5 ? -1 : 1) * 55 : 0)
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
        let limbs = willow ? 4 : (pine ? 4 + Int(r() * 3) : 5 + Int(r() * 3))
        var side = r() < 0.5 ? -1.0 : 1.0
        var tips: [(P, Double)] = []
        for k in 0..<limbs {
            let t = (pine ? 0.30 : 0.38) + 0.55 * (Double(k) + r() * 0.5) / Double(limbs)
            let origin = spinePoint(t)
            if r() < 0.7 { side = -side }
            let span = (pine ? 40 + r() * 30 : 26 + r() * 24) * (1.1 - t * 0.6) * breadth
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
                if !pine { tips.append((to, side)) }
            }
            tips.append((tip, side))
        }
        if !bare && !willow {
            if pine {
                // Flat, layered needle clusters along each limb end, plus a flat crown at the top.
                for (p, _) in tips where r() < 0.94 {
                    c += paintingLeaves(p.x, p.y - 2, width: 40 + r() * 16, height: 13 + r() * 5, needles: true)
                }
                let top = spine.last!
                c += paintingLeaves(top.x, top.y + 4, width: 54, height: 16, needles: true)
            } else {
                // Rounded crown: clusters gather inside an ellipse around the upper trunk.
                let center = spinePoint(0.78)
                for (p, _) in tips {
                    let q = P(p.x + (center.x - p.x) * 0.15, p.y + (center.y - p.y) * 0.15)
                    c += paintingLeaves(q.x, q.y - 3, width: (26 + r() * 14) * breadth, height: leaf == .flat ? 12 + r() * 6 : 20 + r() * 10,
                        flowering: flowering, style: leaf)
                }
                c += paintingLeaves(center.x, center.y - 18, width: 40 * breadth, height: leaf == .flat ? 16 : 30,
                    flowering: flowering, style: leaf)
            }
        }
        // Trunk after the crown, a loaded contour with dry bark inside; roots grip the ground.
        c += inkLine(spine, width: pine ? 10.5 : 6.6, tone: 0.85, dry: 0.42, profile: .cone)
        if twin {
            // A second, slimmer stem leaving the trunk low and rising beside it.
            let fork = spinePoint(0.22), side = lean >= 0 ? -1.0 : 1.0
            let stem = inkCurve([fork, P(fork.x + side * 10, fork.y - 40), P(fork.x + side * 16, fork.y - 90)])
            c += inkLine(stem, width: 4.4, tone: 0.8, dry: 0.45, profile: .cone)
            if !bare {
                c += paintingLeaves(stem.last!.x, stem.last!.y - 6, width: 34 * breadth, height: leaf == .flat ? 14 : 24,
                    flowering: flowering, style: leaf)
            }
        }
        for offset in [-2.0, 1.5] {
            c += inkLine(spine.map { P($0.x + offset, $0.y + 1) }, width: 0.7, tone: 0.52, dry: 0.72)
        }
        if pine {
            for k in 0..<15 {
                let t = 0.06 + Double(k) * 0.048
                let p = spinePoint(t), radius = 2.7 * (1 - t * 0.6)
                let scale = [p + P(-radius, -2), p + P(-radius * 0.8, 2), p + P(0, 4),
                    p + P(radius, 1), p + P(radius * 0.7, -2)]
                c += inkLine(scale, width: 0.9, tone: 0.75, dry: 0.38)
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

    func paintingLotus() -> ZXArt.SSCanv { paintingLotusDrawing().canvas }
}
