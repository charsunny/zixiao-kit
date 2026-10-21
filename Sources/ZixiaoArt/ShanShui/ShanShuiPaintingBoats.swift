// Outlined Chinese river craft for shanshui@5. The first polygon always describes the hull.
import Foundation

struct PaintingBoatForm: Hashable {
    let hull: Int
    let covered: Bool
}

extension ShanShuiEngine {
    func paintingBoatForm(_ kind: ZXArt.SceneMotif) -> PaintingBoatForm {
        let hull = Int(r() * 65_536) % 3
        return .init(hull: hull, covered: kind == .mooredBoat ? r() < 0.5 : hull != 0)
    }

    func paintingBoat(_ kind: ZXArt.SceneMotif, mooring: Bool = true) -> ZXArt.SSCanv {
        let specification = paintingBoatForm(kind), form = specification.hull
        let w = [116.0, 146, 172][form], depth = [9.0, 13, 11][form]
        let covered = specification.covered
        let rail = inkCurve([P(0, 85), P(w * 0.23, 93), P(w * 0.70, 94), P(w, 82)])
        let bottom = inkCurve([P(w, 82), P(w * 0.82, 96 + depth * 0.45),
                              P(w * 0.30, 95 + depth), P(w * 0.08, 96), P(0, 85)])
        let hull = rail + bottom.dropFirst()
        // Paper is an occlusion mask, not a grey hull wash. Boat/water anchors use this contour.
        var c = [poly(hull, fil: .white, str: nil)]
        c += inkLine(rail, width: 1.5, tone: 0.78, dry: 0.32)
        c += inkLine(bottom, width: 1.7, tone: 0.77, dry: 0.4)
        c += inkLine(inkCurve([P(5, 88), P(w * 0.27, 96), P(w * 0.72, 97), P(w - 5, 87)]),
                     width: 0.65, tone: 0.47, dry: 0.45)
        for t in [0.19, 0.77] {
            c += inkLine([P(w * t, 94), P(w * t + 9, 96)], width: 1, tone: 0.57, dry: 0.35)
        }
        let canopy = kind == .boat || kind == .mooredBoat ? covered : kind == .angler && form == 2
        if canopy {
            let x = kind == .angler ? w * 0.14 : w * 0.35
            let length = form == 1 ? w * 0.35 : w * 0.29, height = form == 1 ? 23.0 : 18.0
            let cover = inkCurve([P(x, 93), P(x + 5, 93 - height * 0.75), P(x + 15, 93 - height),
                                  P(x + length - 10, 93 - height), P(x + length, 93)])
            c.append(poly(cover, fil: .white, str: nil))
            c += inkLine(cover, width: 1.1, tone: 0.65, dry: 0.36)
            for k in 0..<4 {
                let dx = Double(k) * (length - 15) / 4
                c += inkLine(inkCurve([P(x + dx + 2, 93), P(x + dx + 5, 93 - height * 0.7), P(x + dx + 14, 93 - height)]),
                             width: 0.65, tone: 0.47, dry: 0.4)
            }
            let mouth = inkCurve([P(x + length - 17, 93), P(x + length - 14, 93 - height * 0.70),
                                  P(x + length - 9, 93 - height * 0.77), P(x + length - 2, 93)])
            c.append(poly(mouth, fil: .gray(0, 0.34), str: nil))
        }
        if kind == .angler {
            let seated = form != 1, scale = 0.72, personX = w * (form == 2 ? 0.61 : 0.32)
            let foot = seated ? 34.0 : 44.0
            func position(_ p: P) -> P { P(personX + (p.x - 44) * scale, 93 + (p.y - foot) * scale) }
            c += paintingPerson(hat: true, pose: seated ? 3 : 1, facingLeft: false).map { p in
                var q = p; q.p = p.p.map(position); q.wid *= scale; return q
            }
            for k in 0..<4 {
                c += inkLine([position(P(39 + Double(k) * 2, 14)), position(P(34 + Double(k) * 3, seated ? 27 : 33))],
                             width: 0.9, tone: 0.56, dry: 0.58)
            }
            let hand = position(P(55, 24)), tip = P(w + 10, form == 1 ? 43 : 53)
            c += inkLine(inkCurve([hand, P((hand.x + tip.x) / 2, tip.y - 3), tip]), width: 0.85, tone: 0.73, dry: 0.32)
            c += inkLine(inkCurve([tip, P(tip.x + 4, 78), P(tip.x + 2, 108)]), width: 0.45, tone: 0.43, dry: 0.38)
        } else if kind == .sail {
            let mast = w * 0.43, sailH = [79.0, 52, 92][form], sailW = [43.0, 40, 57][form]
            let top = 78 - sailH
            c += inkLine([P(mast, 94), P(mast - 1, top - 7)], width: 1.6, tone: 0.78, dry: 0.32)
            func luff(_ t: Double) -> P { P(mast - 9 + t * 3, top + sailH * t) }
            func leech(_ t: Double) -> P { P(mast + sailW * (0.52 + 0.48 * sin(t * .pi * 0.85)), top - 5 + sailH * t) }
            let panels = form == 1 ? 5 : 7
            let edge = (0...panels).map { leech(Double($0) / Double(panels)) }
            let sail = [luff(0)] + edge + [luff(1), luff(0)]
            c.append(poly(sail, fil: .white, str: nil))
            c += inkEdges(sail, width: 0.9, tone: 0.58, dry: 0.35)
            for k in 0...panels {
                let t = Double(k) / Double(panels)
                c += inkLine([luff(t), leech(t)], width: 0.85, tone: 0.62, dry: 0.32)
            }
            c += inkLine([leech(1), P(w * 0.83, 92)], width: 0.55, tone: 0.45, dry: 0.4)
        } else if form == 0 || (kind == .boat && r() < 0.4) {
            let px = w * 0.23, scale = 0.53
            c += paintingPerson(hat: true, pose: form == 0 ? 1 : 3, facingLeft: false).map { p in
                var q = p; q.p = p.p.map { P(px + ($0.x - 44) * scale, 92 + ($0.y - (form == 0 ? 44 : 34)) * scale) }
                q.wid *= scale; return q
            }
            c += inkLine([P(px + 4, 80), P(px - 15, 109)], width: 1, tone: 0.63)
        }
        if kind == .mooredBoat && mooring {
            c += paintingMooring(from: P(0, 85), postFoot: P(-24, 83), size: 1)
            c += inkLine([P(-34, 84), P(-22, 85), P(-12, 83)], width: 0.85, tone: 0.38, dry: 0.5)
        }
        for (start, end, y) in [(0.15, 0.54, 111.0), (0.53, 0.91, 115)] {
            c += inkLine([P(w * start, y), P(w * end, y)], width: 0.7, tone: 0.29, dry: 0.5)
        }
        return c
    }

    /// One rope joins the bow to a knot around an upright bank post. Scene placement supplies
    /// the real shore point; the atlas supplies a small bank immediately beside the hull.
    func paintingMooring(from bow: P, postFoot: P, size: Double) -> ZXArt.SSCanv {
        let knot = postFoot - P(0, 10 * size)
        var c = inkLine([postFoot - P(0, 15 * size), postFoot], width: 2 * size, tone: 0.78, dry: 0.3)
        c += inkLine(inkCurve([bow, (bow + knot) * 0.5 + P(0, 4 * size), knot]), width: 0.7 * size, tone: 0.60, dry: 0.3)
        c += inkLine([knot - P(2 * size, 0), knot + P(2 * size, size)], width: 1.1 * size, tone: 0.75)
        return c
    }
}
