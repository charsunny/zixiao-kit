// Rural dwellings for shanshui@5. Walls stay paper; roof edges, joinery and doors carry the ink.
import Foundation

extension ShanShuiEngine {
    /// 瓦屋: one to three bays, a visible gable and a short return wall. A level front sill
    /// meets the bank; the return recedes only a little, rather than tipping the whole house.
    func paintingHouse() -> ZXArt.SSCanv {
        let bays = 1 + Int(r() * 65_536) % 3
        let w = 38.0 * Double(bays) + 10, d = 21 + r() * 12
        let eave = 33.0, foot = 70 + r() * 5, rise = 10.0
        let front = [P(0, eave), P(w, eave), P(w, foot), P(0, foot)]
        let side = [P(w, eave), P(w + d, eave - rise), P(w + d, foot - rise), P(w, foot)]
        var c = [poly(side, fil: .white, str: nil), poly(front, fil: .white, str: nil)]
        c.append(poly(side, fil: .gray(0, 0.055), str: nil))
        c += inkLine([P(0, eave), P(0, foot), P(w, foot), P(w + d, foot - rise), P(w + d, eave - rise)],
                     width: 1.1, tone: 0.63, dry: 0.32)
        c += inkLine([P(w, eave), P(w, foot)], width: 1.2, tone: 0.64, dry: 0.3)
        let door = Int(r() * Double(bays)) % bays
        for k in 0..<bays {
            let x = 5 + Double(k) * 38
            if k == door {
                let open = r() < 0.65
                let opening = [P(x + 6, 43), P(x + 26, 43), P(x + 26, foot), P(x + 6, foot)]
                c.append(poly(opening, fil: .gray(0, open ? 0.44 : 0.045), str: nil))
                c += inkLine(opening + [opening[0]], width: 0.85, tone: 0.63, dry: 0.3)
                if !open {
                    c += inkLine([P(x + 16, 44), P(x + 16, foot)], width: 0.8, tone: 0.7)
                }
            } else {
                let frame = [P(x + 7, 44), P(x + 26, 44), P(x + 26, 59), P(x + 7, 59), P(x + 7, 44)]
                c += inkLine(frame, width: 1.0, tone: 0.63, dry: 0.3)
                for dx in [12.0, 17, 22] {
                    c += inkLine([P(x + dx, 45), P(x + dx, 58)], width: 0.6, tone: 0.49, dry: 0.35)
                }
            }
        }
        if r() < 0.65 { // One small opening in the gable wall, following that plane.
            c += inkLine([P(w + 7, 44), P(w + d - 6, 39), P(w + d - 6, 51), P(w + 7, 56), P(w + 7, 44)],
                         width: 0.8, tone: 0.52, dry: 0.35)
        }
        let ridgeL = P(d * 0.55, 4), ridgeR = P(w + d * 0.55, 4)
        let roof = [ridgeL, ridgeR, P(w + 7, eave + 1), P(-9, eave + 1)]
        let gable = [ridgeR, P(w + d + 7, eave - rise), P(w + 7, eave + 1)]
        c += [poly(gable, fil: .white, str: nil), poly(roof, fil: .white, str: nil)]
        c.append(poly(roof, fil: .gray(0, 0.065), str: nil))
        c += inkLine([P(ridgeL.x - 3, 1), ridgeL, ridgeR, P(ridgeR.x + 3, 1)], width: 1.7, tone: 0.78, dry: 0.3)
        c += inkLine([ridgeL, P(-9, eave + 1)], width: 1.1, tone: 0.64)
        c += inkLine([ridgeR, P(w + d + 7, eave - rise), P(w + 7, eave + 1), ridgeR], width: 1.1, tone: 0.7)
        c += inkLine([P(-12, eave - 1), P(-6, eave + 2), P(w + 7, eave + 2), P(w + d + 9, eave - rise - 1)],
                     width: 2.1, tone: 0.85, dry: 0.28)
        let tiles = 9 + bays * 4
        for k in 1..<tiles {
            let t = Double(k) / Double(tiles)
            c += inkLine([P(ridgeL.x + w * t, 6), P(-8 + (w + 15) * t, eave)],
                         width: 0.55, tone: 0.40, dry: 0.48)
        }
        c += inkLine([P(-3, foot + 3), P(w + 3, foot + 3), P(w + d + 3, foot - rise + 2)],
                     width: 1.2, tone: 0.55, dry: 0.45)
        return c
    }

    /// 茅舍: a single low earthen room, an open grass shelter, or a lean-to porch.
    /// Loose thatch extends past its poles; no tile ridge, masonry plinth or row of urban bays.
    func paintingHut() -> ZXArt.SSCanv {
        let form = Int(r() * 65_536) % 3
        let w = form == 2 ? 104.0 : 78.0
        let roofY = form == 1 ? 30.0 : 39.0, foot = 72.0
        let peakL = P(24, form == 2 ? 12 : 3), peakR = P(w - 27, 5)
        let roof = [peakL, peakR, P(w + 9, roofY + 1), P(-7, roofY + 2)]
        var c: ZXArt.SSCanv = []
        if form != 1 {
            let end = form == 2 ? w * 0.61 : w - 7
            let wall = [P(8, roofY), P(end, roofY), P(end, foot), P(8, foot)]
            c += [poly(wall, fil: .white, str: nil)]
            c += inkLine([P(8, roofY), P(8, foot), P(end, foot), P(end, roofY)], width: 1.2, tone: 0.58, dry: 0.45)
            let x = form == 2 ? 27.0 : 40.0
            c.append(poly([P(x, roofY + 8), P(x + 17, roofY + 8), P(x + 17, foot), P(x, foot)],
                          fil: .gray(0, 0.45), str: nil))
            if form == 0 {
                c += inkLine([P(17, 48), P(29, 48), P(29, 58), P(17, 58), P(17, 48)], width: 1, tone: 0.53)
            }
        }
        for x in (form == 1 ? [9.0, 28, w - 25, w - 7] : [w - 5]) {
            c += inkLine([P(x, roofY - 1), P(x + 0.6, foot)], width: 1.5, tone: 0.7, dry: 0.35)
        }
        if form == 1 {
            c += inkLine([P(10, 60), P(29, 60)], width: 1.6, tone: 0.65)
            c += inkLine([P(w - 26, 60), P(w - 7, 60)], width: 1.6, tone: 0.65)
        }
        c += [poly(roof, fil: .white, str: nil), poly(roof, fil: .gray(0, 0.06), str: nil)]
        c += inkLine([P(-7, roofY + 1), peakL, peakR, P(w + 9, roofY)], width: 1.5, tone: 0.64, dry: 0.5)
        c += inkLine([P(-8, roofY + 2), P(w * 0.38, roofY + 4), P(w + 9, roofY + 1)], width: 2.5, tone: 0.67, dry: 0.52)
        for k in 0..<29 {
            let t = Double(k) / 28
            let x = -9 + (w + 20) * t
            let top = peakL + (peakR - peakL) * t
            let end = P(x, roofY + 2 + r() * 5)
            c += inkLine([top + P(0, r() * 6), (top + end) * 0.5 + P(1, 0), end],
                         width: 0.7 + r() * 0.6, tone: 0.33 + r() * 0.22, dry: 0.58)
        }
        for x in [3.0, w * 0.4, w - 9] {
            c += inkLine([P(x, foot + 1), P(x + 12, foot + 1)], width: 0.9, tone: 0.35, dry: 0.55)
        }
        return c
    }
}
