// Small landscape architecture for shanshui@5; roofs carry the ink, openings keep the paper.
import Foundation

extension ShanShuiEngine {
    /// Four/six-sided pointed roofs and a small hip-and-gable pavilion. Roof rise is about
    /// three fifths of the columns; the eaves extend a fifth of the column span on either side.
    func paintingPavilion() -> ZXArt.SSCanv {
        let form = Int(r() * 65_536) % 3
        let span = form == 1 ? 72.0 : 64.0, mid = span / 2
        let top = 33.0, foot = 83.0
        let columns = form == 1 ? [0.0, 13, 27, span - 27, span - 13, span] : [0.0, 17, span - 17, span]
        var c: ZXArt.SSCanv = []
        for (i, x) in columns.enumerated() {
            let back = i > 0 && i < columns.count - 1
            c += inkLine([P(x, top), P(x, back ? foot - 5 : foot)],
                         width: back ? 1.4 : 2.2, tone: back ? 0.55 : 0.8, dry: 0.3)
        }
        for (a, b) in [(0.0, 17.0), (span - 17, span)] {
            c += inkEdges([P(a, 69), P(b, 66), P(b, 77)], width: 1.1, tone: 0.66, dry: 0.32)
            c += inkLine([P(a, 77), P(b, 74)], width: 1.4, tone: 0.7)
        }
        if form == 2 {
            c += paintingHipGableRoof(width: span + 26, height: 29).map { p in
                var q = p; q.p = p.p.map { P($0.x - 13, $0.y + 3) }; return q
            }
        } else {
            let apex = P(mid, 2), left = P(-13, 30), right = P(span + 13, 30)
            let front = P(mid, 38)
            let outline = [left, P(mid - 17, 20), apex, P(mid + 17, 20), right, front, left]
            c.append(poly(outline, fil: .white, str: nil))
            c.append(poly([apex, right, front], fil: .gray(0, 0.075), str: nil))
            c += inkLine(inkCurve(Array(outline.prefix(5))), width: 1.5, tone: 0.72, dry: 0.32)
            c += inkEdges([left, front, right], width: 2.2, tone: 0.84, dry: 0.3)
            c += inkLine([apex, P(mid, 22), front], width: 1.2, tone: 0.6, dry: 0.35)
            if form == 1 {
                for x in [mid - 24, mid + 24] {
                    c += inkLine([apex, P(mid + (x - mid) * 0.55, 23), P(x, 34)], width: 0.7, tone: 0.44)
                }
            }
            c += inkLine([P(mid, -2), P(mid, 2)], width: 1.5, tone: 0.8)
        }
        c += inkEdges([P(-6, foot + 1), P(span + 6, foot + 1), P(span + 10, foot + 5), P(-10, foot + 5)],
                      width: 1.2, tone: 0.63, dry: 0.4)
        return c
    }

    /// 歇山: a short ridge, exposed triangular gable, and the lower hipped skirt continuing
    /// around it. The upper gable does not run all the way to the outer eave as a simple gable does.
    func paintingHipGableRoof(width w: Double, height h: Double) -> ZXArt.SSCanv {
        let a = P(w * 0.23, 2), b = P(w * 0.70, 2)
        let left = P(0, h - 3), frontR = P(w * 0.81, h + 2), backR = P(w, h - 7)
        let gableL = P(w * 0.60, h * 0.52), gableR = P(w * 0.81, h * 0.48)
        let front = [a, b, gableL, frontR, left]
        let side = [b, gableR, backR, frontR, gableL]
        var c = [poly(front, fil: .white, str: nil), poly(side, fil: .white, str: nil)]
        c.append(poly(front, fil: .gray(0, 0.07), str: nil))
        c.append(poly(side, fil: .gray(0, 0.11), str: nil))
        c.append(poly([b, gableR, gableL], fil: .white, str: nil))
        c += inkEdges([gableL, b, gableR, gableL], width: 1.1, tone: 0.67, dry: 0.3)
        c += inkLine([P(a.x - 3, 0), a, b, P(b.x + 3, 0)], width: 1.8, tone: 0.8, dry: 0.28)
        c += inkLine([a, P(w * 0.14, h * 0.64), left], width: 1.2, tone: 0.66)
        c += inkLine([gableR, P(w * 0.90, h * 0.78), backR], width: 1.2, tone: 0.65)
        c += inkLine([P(-3, h - 6), left, P(w * 0.43, h + 3), frontR], width: 2.4, tone: 0.85, dry: 0.28)
        c += inkLine([frontR, P(w * 0.92, h - 2), P(w + 3, h - 10)], width: 2.1, tone: 0.8, dry: 0.3)
        c += inkLine([gableL, frontR], width: 1, tone: 0.6)
        for k in 1..<12 {
            let t = Double(k) / 12
            let start = a + (b - a) * t
            let end = left + (frontR - left) * t
            c += inkLine([start + P(0, 3), end - P(0, 2)], width: 0.55, tone: 0.38, dry: 0.5)
        }
        return c
    }

    /// Round-headed masonry opening. Its feet remain at the same ground level as the wall.
    func paintingArchDoor(x: Double, foot: Double, width: Double, height: Double, tone: Double = 0.48) -> ZXArt.SSCanv {
        let radius = width / 2, spring = foot - height + radius
        let arc = (0...16).map { i -> P in
            let a = Double.pi + Double(i) / 16 * Double.pi
            return P(x + radius + cos(a) * radius, spring + sin(a) * radius)
        }
        let edge = [P(x, foot)] + arc + [P(x + width, foot)]
        var c = [poly(edge, fil: .gray(0, tone), str: nil)]
        c += inkLine(edge, width: 1.2, tone: 0.70, dry: 0.3)
        return c
    }

    func paintingTempleGate() -> ZXArt.SSCanv {
        let doors = r() < 0.48 ? 1 : 3
        let wallSpan = 16 + Double(Int(r() * 65_536) % 3) * 13
        let bodyW = doors == 1 ? 64.0 : 118.0, h = 80.0
        var c: ZXArt.SSCanv = []
        // Low flanking walls have their own tiled coping, below the main eaves.
        for (l, rr) in [(-wallSpan, 4.0), (bodyW - 4, bodyW + wallSpan)] {
            let wall = [P(l, 55), P(rr, 55), P(rr, h), P(l, h)]
            c.append(poly(wall, fil: .white, str: nil))
            c += inkEdges([P(l, h), P(l, 55), P(rr, 55), P(rr, h)], width: 1, tone: 0.5)
            c += inkLine([P(l - 3, 53), P(rr + 3, 53)], width: 2.3, tone: 0.78)
        }
        let wall = [P(0, 33), P(bodyW, 33), P(bodyW, h), P(0, h)]
        c.append(poly(wall, fil: .white, str: nil))
        c += inkEdges([P(0, 33), P(0, h), P(bodyW, h), P(bodyW, 33)], width: 1.3, tone: 0.68)
        c += paintingArchDoor(x: bodyW / 2 - 12, foot: h, width: 24, height: 35)
        if doors == 3 {
            for x in [12.0, bodyW - 30] { c += paintingArchDoor(x: x, foot: h, width: 18, height: 28, tone: 0.36) }
        }
        c += paintingHipGableRoof(width: bodyW + 22, height: 31).map { p in
            var q = p; q.p = p.p.map { P($0.x - 11, $0.y) }; return q
        }
        for k in 0..<3 {
            let inset = Double(k) * 4
            c += inkLine([P(-5 - inset, h + 3 + Double(k) * 4), P(bodyW + 5 + inset, h + 3 + Double(k) * 4)],
                         width: 1.1, tone: 0.60 - Double(k) * 0.09, dry: 0.4)
        }
        return c
    }

    func paintingPagoda() -> ZXArt.SSCanv {
        let levels = [5, 7, 9, 13][Int(r() * 65_536) % 4]
        let dense = levels == 13 || (levels >= 7 && r() < 0.45)
        let pitch = dense ? 12.0 : 24.0
        let bottom = 22 + Double(levels - 1) * pitch + (dense ? 28 : 23)
        var c: ZXArt.SSCanv = []
        for k in (0..<levels).reversed() {
            let t = Double(k) / Double(levels - 1), y = 22 + Double(k) * pitch
            let half = 11 + 20 * pow(t, 0.8), wallHalf = half * 0.70
            let floor = k == levels - 1 ? bottom : y + pitch
            let wall = [P(50 - wallHalf, y), P(50 + wallHalf, y), P(50 + wallHalf, floor), P(50 - wallHalf, floor)]
            c.append(poly(wall, fil: .white, str: nil))
            c.append(poly([P(50 + wallHalf * 0.25, y), wall[1], wall[2], P(50 + wallHalf * 0.25, floor)],
                          fil: .gray(0, 0.08), str: nil))
            c += inkEdges([wall[0], wall[3], wall[2], wall[1]], width: 0.9, tone: 0.59, dry: 0.3)
            if !dense || k == levels - 1 {
                c += paintingArchDoor(x: 47, foot: floor - 3, width: 6, height: dense ? 17 : 12, tone: 0.48)
            }
            let roof = [P(50 - half - 5, y + 2), P(50 - half * 0.66, y - 2),
                        P(50 - half * 0.48, y - 6), P(50 + half * 0.48, y - 6),
                        P(50 + half * 0.66, y - 2), P(50 + half + 5, y + 2)]
            c.append(poly(roof, fil: .white, str: nil))
            c.append(poly(roof, fil: .gray(0, 0.12), str: nil))
            c += inkEdges(roof, width: 0.8, tone: 0.58, dry: 0.35)
            c += inkLine([P(50 - half - 5, y), P(50, y + 4), P(50 + half + 5, y)], width: 1.7, tone: 0.8, dry: 0.3)
        }
        c += inkLine([P(50, 0), P(50, 16)], width: 1.3, tone: 0.8)
        for y in [4.0, 8, 12] { c += inkLine([P(47.5, y), P(52.5, y)], width: 1.2, tone: 0.72) }
        c += inkLine([P(24, bottom + 3), P(76, bottom + 3)], width: 1.6, tone: 0.65)
        return c
    }
}
