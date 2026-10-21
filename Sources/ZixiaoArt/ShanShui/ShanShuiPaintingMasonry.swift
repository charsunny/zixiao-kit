// Broken brickwork and city walls for shanshui@5. Earlier cartoon assets remain version-frozen.
import Foundation

extension ShanShuiEngine {
    func paintingRuins() -> ZXArt.SSCanv {
        let count = 2 + Int(r() * 65_536) % 3
        var c: ZXArt.SSCanv = [], x = 0.0
        for k in 0..<count {
            let width = 26 + r() * 20, height = 22 + r() * 41
            let top = 73 - height, step = 5.0
            let crest = [P(x, top + 9), P(x + width * 0.19, top + 9), P(x + width * 0.19, top),
                         P(x + width * 0.56, top), P(x + width * 0.56, top + step),
                         P(x + width * 0.77, top + step), P(x + width * 0.77, top + 17), P(x + width, top + 17)]
            let face = crest + [P(x + width - 3, 73), P(x + 2, 73)]
            c.append(poly(face, fil: .white, str: nil))
            let side = [P(x + width, top + 17), P(x + width + 5, top + 13), P(x + width + 2, 71), P(x + width - 3, 73)]
            c += [poly(side, fil: .white, str: nil), poly(side, fil: .gray(0, 0.065), str: nil)]
            c += inkEdges(crest, width: 1.4, tone: 0.64, dry: 0.46)
            c += inkLine([P(x, top + 9), P(x + 2, 73)], width: 1, tone: 0.52, dry: 0.52)
            c += inkEdges([P(x + width, top + 17), P(x + width - 3, 73)], width: 1.2, tone: 0.6, dry: 0.45)
            for j in 0..<Int((height - 20) / 7) {
                let y = top + 22 + Double(j) * 7, start = x + 3 + r() * 4
                c += inkLine([P(start, y), P(x + width - 5, y)], width: 0.6, tone: 0.31, dry: 0.5)
                let joint = x + width * (j % 2 == 0 ? 0.38 : 0.65)
                c += inkLine([P(joint, y), P(joint, y + 6)], width: 0.6, tone: 0.32, dry: 0.45)
            }
            for dx in [-5.0, 0, 7] {
                let root = P(x + width * 0.35, top + 1)
                c += inkLine([root, P(root.x + dx, root.y - 6 - r() * 7)], width: 0.75, tone: 0.63, dry: 0.45, profile: .tip)
            }
            if k > 0 {
                c += inkEdges([P(x - 11, 72), P(x - 9, 67), P(x - 2, 67), P(x, 72)], width: 0.7, tone: 0.4, dry: 0.5)
            }
            c += inkLine([P(x - 2, 75), P(x + width + 5, 75)], width: 0.9, tone: 0.3, dry: 0.6)
            x += width + 11 + r() * 14
        }
        return c
    }

    func paintingCityGate() -> ZXArt.SSCanv {
        let form = Int(r() * 65_536) % 3
        let w = [150.0, 187, 226][form], center = w / 2
        let doubleEave = form != 0, foot = 112.0, towerW = form == 2 ? 100.0 : 83.0
        var c: ZXArt.SSCanv = []
        // Timber gate tower stands on the masonry terrace; a second roof shelters the upper bay.
        let tower = [P(center - towerW / 2, 32), P(center + towerW / 2, 32),
                     P(center + towerW / 2, 64), P(center - towerW / 2, 64)]
        c.append(poly(tower, fil: .white, str: nil))
        for fraction in [-0.5, -0.25, 0, 0.25, 0.5] {
            let x = center + towerW * fraction
            c += inkLine([P(x, 32), P(x, 64)], width: 1.4, tone: 0.72, dry: 0.3)
        }
        c += inkLine([P(center - towerW / 2, 55), P(center + towerW / 2, 55)], width: 1.3, tone: 0.6)
        c += paintingHipGableRoof(width: towerW + 25, height: 29).map { p in
            var q = p; q.p = p.p.map { P($0.x + center - (towerW + 25) / 2, $0.y + 3) }; return q
        }
        if doubleEave {
            let upperW = towerW * 0.67
            let upper = [P(center - upperW / 2, 4), P(center + upperW / 2, 4),
                         P(center + upperW / 2, 20), P(center - upperW / 2, 20)]
            c.append(poly(upper, fil: .white, str: nil))
            c += inkEdges(upper + [upper[0]], width: 1, tone: 0.59)
            for x in [center - upperW / 4, center, center + upperW / 4] {
                c += inkLine([P(x, 6), P(x, 18)], width: 1.5, tone: 0.64)
            }
            c += paintingHipGableRoof(width: upperW + 23, height: 23).map { p in
                var q = p; q.p = p.p.map { P($0.x + center - (upperW + 23) / 2, $0.y - 20) }; return q
            }
        }
        // Flat-topped merlons with gaps, drawn as masonry rather than a rounded castle icon.
        var top = [P(0, 68)]
        let merlons = Int(w / 16), unit = w / Double(merlons)
        for k in 0..<merlons {
            let x = Double(k) * unit
            top += [P(x, 62), P(x + unit * 0.56, 62), P(x + unit * 0.56, 68), P(x + unit, 68)]
        }
        let wall = top + [P(w + 3, foot), P(-3, foot)]
        c.append(poly(wall, fil: .white, str: nil))
        c += inkEdges(top, width: 1.2, tone: 0.66, dry: 0.35)
        c += inkEdges([P(0, 68), P(-3, foot), P(w + 3, foot), P(w, 68)], width: 1.2, tone: 0.58, dry: 0.4)
        c += paintingArchDoor(x: center - 15, foot: foot, width: 30, height: 36, tone: 0.45)
        for side in [-1.0, 1.0] {
            for k in 0..<4 {
                let y = 78 + Double(k) * 8
                let x = center + side * (27 + r() * 13)
                c += inkLine([P(x, y), P(x + side * (18 + r() * 20), y)], width: 0.65, tone: 0.28, dry: 0.5)
                c += inkLine([P(x, y), P(x, y + 5)], width: 0.6, tone: 0.26, dry: 0.5)
            }
        }
        return c
    }
}
