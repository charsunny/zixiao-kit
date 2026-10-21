// Small landscape architecture for shanshui@5; roofs carry the ink, openings keep the paper.
import Foundation

extension ShanShuiEngine {
    /// 四柱攒尖亭: curved hips, lifted corners, dark eaves and a low open balustrade.
    func paintingPavilion() -> ZXArt.SSCanv {
        let eave = inkCurve([P(0, 37), P(17, 44), P(52, 46), P(87, 44), P(104, 37)])
        let left = inkCurve([P(0, 37), P(25, 31), P(44, 16), P(52, 6)])
        let right = inkCurve([P(52, 6), P(60, 16), P(79, 31), P(104, 37)])
        let roof = left + right + eave.reversed()
        var c = [poly(roof, fil: .white, str: nil), poly(roof, fil: .gray(0, 0.22), str: nil)]
        for x in [14.0, 34, 70, 90] {
            c += inkLine([P(x, 45), P(x, 87)], width: x == 14 || x == 90 ? 2.1 : 1.2, tone: 0.75)
        }
        c += inkLine(left, width: 1.5, tone: 0.73, dry: 0.35)
        c += inkLine(right, width: 1.5, tone: 0.73, dry: 0.35)
        c += inkLine(eave, width: 3.2, tone: 0.88, dry: 0.32)
        for x in [24.0, 41, 64, 81] {
            c += inkLine(inkCurve([P(52, 9), P(50 + (x - 52) * 0.45, 30), P(x, 43)]),
                width: 0.8, tone: 0.48, dry: 0.45)
        }
        c += inkBlot(52, 4, radius: 2.0, squash: 0.8, tone: 0.8)
        for pair in [(14.0, 34.0), (70, 90)] {
            for y in [73.0, 82] { c += inkLine([P(pair.0, y), P(pair.1, y)], width: 1.1, tone: 0.66) }
            c += inkLine([P((pair.0 + pair.1) / 2, 73), P((pair.0 + pair.1) / 2, 83)], width: 0.8, tone: 0.6)
        }
        c += inkLine([P(8, 88), P(96, 88)], width: 2.3, tone: 0.75, dry: 0.45)
        c += inkLine([P(4, 93), P(100, 93)], width: 1.4, tone: 0.55, dry: 0.5)
        return c
    }

    func paintingTempleGate() -> ZXArt.SSCanv {
        var c = paintingOldGateBase()
        // Three dark bays beneath a long roof; no Western arch or ornamental tower.
        for x in [36.0, 72, 108] {
            c.append(poly([P(x, 66), P(x + 19, 66), P(x + 19, 92), P(x, 92)], fil: .gray(0, 0.70), str: nil))
        }
        c += inkLine([P(14, 104), P(150, 104)], width: 1.3, tone: 0.7)
        c += inkLine([P(8, 110), P(156, 110)], width: 1.2, tone: 0.55)
        return c
    }

    func paintingPagoda() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let levels = 5
        for k in (0..<levels).reversed() {
            let y = 18 + Double(k) * 27, half = 13 + Double(k) * 4.0
            let wall = [P(50 - half * 0.62, y), P(50 + half * 0.62, y),
                        P(50 + half * 0.62, y + 26), P(50 - half * 0.62, y + 26)]
            c.append(poly(wall, fil: .white, str: nil))
            c.append(poly(wall, fil: .gray(0, 0.12), str: nil))
            c += inkEdges([wall[0], wall[3], wall[2], wall[1]], width: 1.0, tone: 0.58)
            c += inkLine([P(50, y + 11), P(50, y + 21)], width: 3.0, tone: 0.8)
            let roof = inkCurve([P(50 - half - 5, y + 3), P(50 - half * 0.5, y - 1),
                P(50, y - 9), P(50 + half * 0.5, y - 1), P(50 + half + 5, y + 3)])
            c.append(poly(roof, fil: .gray(0, 0.45), str: nil))
            c += inkLine(roof, width: 1.2, tone: 0.75, dry: 0.35)
            c += inkLine([P(50 - half - 5, y + 3), P(50, y + 6), P(50 + half + 5, y + 3)],
                         width: 2.0, tone: 0.85, dry: 0.3)
        }
        c += inkLine([P(50, 0), P(50, 10)], width: 1.4, tone: 0.8)
        c += inkBlot(50, 3, radius: 2, squash: 0.8, tone: 0.8)
        c += inkLine([P(18, 154), P(82, 154)], width: 2.0, tone: 0.7)
        return c
    }
}
