//  ShanShuiMount.swift — 山: mountain / flatMount (+flatDec) / distMount / rock / foot
//
//  Ported from shan-shui-inf index.html (`var Mount = new function(){…}`).
//  MIT License, (c) 2018 Lingdong Huang — https://github.com/LingDong-/shan-shui-inf
//  Full license text: ZXArtLicenses.swift / LICENSES/.
//
//  原作 `for (j = 0; j < Math.random() * 5; j++)` 这类循环每轮都重新取随机数, 这里用
//  while 逐轮重取, 保持消耗次数一致。

import Foundation
import ZixiaoDesign

extension ShanShuiEngine {
    // MARK: foot

    func foot(_ ptlist: [[P]], xof: Double = 0, yof: Double = 0) -> ZXArt.SSCanv {
        var ftlist: [[P]] = []
        let span = 10
        var ni = 0
        let count = ptlist.count
        if count > 2 {
            for i in 0..<(count - 2) where i == ni {
                ni = min(ni + e.choice([1, 2]), count - 1)
                var a: [P] = [], b: [P] = []
                let row = ptlist[i]
                var j = 0.0
                while j < min(Double(row.count) / 8, 10) {
                    let jj = Int(j)
                    a.append(P(row[jj].x + n(j * 0.1, Double(i)) * 10, row[jj].y))
                    b.append(P(row[row.count - 1 - jj].x - n(j * 0.1, Double(i)) * 10, row[row.count - 1 - jj].y))
                    j += 1
                }
                a.reverse(); b.reverse()
                for jj in 0..<span {
                    let p = Double(jj) / Double(span)
                    let x1 = row[0].x * (1 - p) + ptlist[ni][0].x * p
                    var y1 = row[0].y * (1 - p) + ptlist[ni][0].y * p
                    let x2 = row[row.count - 1].x * (1 - p) + ptlist[ni][row.count - 1].x * p
                    var y2 = row[row.count - 1].y * (1 - p) + ptlist[ni][row.count - 1].y * p
                    let vib = -1.7 * (p - 1) * pow(p, 1.0 / 5)
                    y1 += vib * 5 + n(xof * 0.05, Double(i)) * 5
                    y2 += vib * 5 + n(xof * 0.05, Double(i)) * 5
                    a.append(P(x1, y1))
                    b.append(P(x2, y2))
                }
                ftlist.append(a)
                ftlist.append(b)
            }
        }
        var canv: ZXArt.SSCanv = []
        for ft in ftlist { canv.append(poly(ft, xof: xof, yof: yof, fil: .white, str: nil)) }
        for ft in ftlist {
            let c = C.ink(0.1 + r() * 0.1)
            canv += stroke(ft.map { P($0.x + xof, $0.y + yof) }, wid: 1, col: c)
        }
        return canv
    }

    // MARK: mountain

    func mountain(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei hIn: Double? = nil, wid wIn: Double? = nil,
                  tex: Double = 200, veg: Bool = true) -> ZXArt.SSCanv {
        let hei = hIn ?? 100 + r() * 400
        let wid = wIn ?? 400 + r() * 200
        var canv: ZXArt.SSCanv = []
        var ptlist: [[P]] = []
        let h = hei, w = wid
        let reso0 = 10, reso1 = 50
        var hoff = 0.0
        for j in 0..<reso0 {
            hoff += (r() * yoff) / 100
            var row: [P] = []
            row.reserveCapacity(reso1)
            for i in 0..<reso1 {
                let x = (Double(i) / Double(reso1) - 0.5) * Double.pi
                var y = cos(x)
                y *= n(x + 10, Double(j) * 0.15, seed)
                let p = 1 - Double(j) / Double(reso0)
                row.append(P((x / Double.pi) * w * p, -y * h * p + hoff))
            }
            ptlist.append(row)
        }

        func vegetate(_ treeFunc: (Double, Double) -> ZXArt.SSCanv, _ growth: (Int, Int) -> Bool,
                      _ proof: ([P], Int) -> Bool) {
            var veglist: [P] = []
            for i in 0..<ptlist.count {
                for j in 0..<ptlist[i].count where growth(i, j) { veglist.append(ptlist[i][j]) }
            }
            for i in 0..<veglist.count where proof(veglist, i) {
                canv += treeFunc(veglist[i].x, veglist[i].y)
            }
        }
        let always: ([P], Int) -> Bool = { _, _ in true }

        // RIM
        vegetate({ x, y in
            self.tree02(x + xoff, y + yoff - 5, clu: 2,
                        col: .ink(self.n(0.01 * x, 0.01 * y) * 0.5 * 0.3 + 0.5))
        }, { i, j in
            let ns = self.n(Double(j) * 0.1, seed)
            return i == 0 && ns * ns * ns < 0.1 && abs(ptlist[i][j].y) / h > 0.2
        }, always)

        // WHITE BG
        canv.append(poly(ptlist[0] + [P(0, Double(reso0) * 4)], xof: xoff, yof: yoff, fil: .white, str: nil))
        // OUTLINE
        canv += stroke(ptlist[0].map { P($0.x + xoff, $0.y + yoff) }, wid: 3, col: .ink(0.3), noi: 1)
        canv += foot(ptlist, xof: xoff, yof: yoff)
        let sha = e.choice([0.0, 0, 0, 0, 5])
        canv += texture(ptlist, xof: xoff, yof: yoff, tex: tex, sha: sha)

        // TOP
        vegetate({ x, y in
            self.tree02(x + xoff, y + yoff, col: .ink(self.n(0.01 * x, 0.01 * y) * 0.5 * 0.3 + 0.5))
        }, { i, j in
            let ns = self.n(Double(i) * 0.1, Double(j) * 0.1, seed + 2)
            return ns * ns * ns < 0.1 && abs(ptlist[i][j].y) / h > 0.5
        }, always)

        if veg {
            // MIDDLE
            vegetate({ x, y in
                var ht = ((h + y) / h) * 70
                ht = ht * 0.3 + self.r() * ht * 0.7
                let tw = self.r() * 3 + 1
                return self.tree01(x + xoff, y + yoff, hei: ht, wid: tw,
                                   col: .ink(self.n(0.01 * x, 0.01 * y) * 0.5 * 0.3 + 0.3))
            }, { i, j in
                let ns = self.n(Double(i) * 0.2, Double(j) * 0.05, seed)
                return j % 2 != 0 && ns * ns * ns * ns < 0.012 && abs(ptlist[i][j].y) / h < 0.3
            }, { veglist, i in
                var counter = 0
                for j in 0..<veglist.count {
                    let dx = veglist[i].x - veglist[j].x, dy = veglist[i].y - veglist[j].y
                    if i != j && dx * dx + dy * dy < 30 * 30 { counter += 1 }
                    if counter > 2 { return true }
                }
                return false
            })

            // BOTTOM
            vegetate({ x, y in
                var ht = ((h + y) / h) * 120
                ht = ht * 0.5 + self.r() * ht * 0.5
                let bc = self.r() * 0.1
                let bp = 1.0
                return self.tree03(x + xoff, y + yoff, hei: ht, ben: { pow($0 * bc, bp) },
                                   col: .ink(self.n(0.01 * x, 0.01 * y) * 0.5 * 0.3 + 0.3))
            }, { i, j in
                let ns = self.n(Double(i) * 0.2, Double(j) * 0.05, seed)
                return (j == 0 || j == ptlist[i].count - 1) && ns * ns * ns * ns < 0.012
            }, always)
        }

        // BOTT ARCH
        vegetate({ x, y in
            let tt = self.e.choice([0, 0, 1, 1, 1, 2])
            if tt == 1 {
                let w = self.e.normRand(40, 70)
                let sto = self.e.choice([1.0, 2, 2, 3])
                let rot = self.r()
                let sty = self.e.choice([1, 2, 3])
                return self.arch02(x + xoff, y + yoff, seed, wid: w, rot: rot, sto: sto, sty: sty)
            } else if tt == 2 {
                return self.arch04(x + xoff, y + yoff, seed, sto: self.e.choice([1.0, 1, 1, 2, 2]))
            }
            return []
        }, { i, j in
            let ns = self.n(Double(i) * 0.2, Double(j) * 0.05, seed + 10)
            return i != 0 && (j == 1 || j == ptlist[i].count - 2) && ns * ns * ns * ns < 0.008
        }, always)

        // TOP ARCH
        vegetate({ x, y in
            let sto = self.e.choice([5.0, 7])
            let w = 40 + self.r() * 20
            return self.arch03(x + xoff, y + yoff, seed, wid: w, sto: sto)
        }, { i, j in
            i == 1 && abs(Double(j) - Double(ptlist[i].count) / 2) < 1 && self.r() < 0.02
        }, always)

        // TRANSM
        vegetate({ x, y in
            let t = self.transmissionTower01(x + xoff, y + yoff, seed)
            return self.drawTowers ? t : []
        }, { i, j in
            let ns = self.n(Double(i) * 0.2, Double(j) * 0.05, seed + 20 * Double.pi)
            return i % 2 == 0 && (j == 1 || j == ptlist[i].count - 2) && ns * ns * ns * ns < 0.002
        }, always)

        // BOTT ROCK
        vegetate({ x, y in
            let rw = 20 + self.r() * 20
            let rh = 20 + self.r() * 20
            return self.rock(x + xoff, y + yoff, seed, hei: rh, wid: rw, sha: 2)
        }, { i, j in
            (j == 0 || j == ptlist[i].count - 1) && self.r() < 0.1
        }, always)

        return canv
    }

    // MARK: flatMount

    struct Bound { var xmin: Double, xmax: Double, ymin: Double, ymax: Double }

    func flatMount(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei hIn: Double? = nil, wid wIn: Double? = nil,
                   tex: Double = 80, cho: Double = 0.5, dec: Bool = true) -> ZXArt.SSCanv {
        let hei = hIn ?? 40 + r() * 400
        let wid = wIn ?? 400 + r() * 200
        var canv: ZXArt.SSCanv = []
        var ptlist: [[P]] = []
        let reso0 = 5, reso1 = 50
        var hoff = 0.0
        var flat: [[P]] = []
        for j in 0..<reso0 {
            hoff += (r() * yoff) / 100
            ptlist.append([])
            flat.append([])
            for i in 0..<reso1 {
                let x = (Double(i) / Double(reso1) - 0.5) * Double.pi
                var y = cos(x * 2) + 1
                y *= n(x + 10, Double(j) * 0.1, seed)
                let p = 1 - (Double(j) / Double(reso0)) * 0.6
                let nx = (x / Double.pi) * wid * p
                var ny = -y * hei * p + hoff
                let h = 100.0
                if ny < -h * cho + hoff {
                    ny = -h * cho + hoff
                    if flat[flat.count - 1].count % 2 == 0 { flat[flat.count - 1].append(P(nx, ny)) }
                } else {
                    if flat[flat.count - 1].count % 2 == 1, let prev = ptlist[ptlist.count - 1].last {
                        flat[flat.count - 1].append(prev)
                    }
                }
                ptlist[ptlist.count - 1].append(P(nx, ny))
            }
        }
        canv.append(poly(ptlist[0] + [P(0, Double(reso0) * 4)], xof: xoff, yof: yoff, fil: .white, str: nil))
        canv += stroke(ptlist[0].map { P($0.x + xoff, $0.y + yoff) }, wid: 3, col: .ink(0.3), noi: 1)
        canv += texture(ptlist, xof: xoff, yof: yoff, tex: tex, wid: 2, dis: {
            if self.r() > 0.5 { return 0.1 + 0.4 * self.r() } else { return 0.9 - 0.4 * self.r() }
        })
        var gr1: [P] = [], gr2: [P] = []
        var fi = 0
        while fi < flat.count {
            if flat[fi].count >= 2 { gr1.append(flat[fi][0]); gr2.append(flat[fi][flat[fi].count - 1]) }
            fi += 2
        }
        if gr1.isEmpty { return canv }
        var wb = (gr1[0].x, gr2[0].x)
        for i in 0..<3 {
            let p = 0.8 - Double(i) * 0.2
            gr1.insert(P(wb.0 * p, gr1[0].y - 5), at: 0)
            gr2.insert(P(wb.1 * p, gr2[0].y - 5), at: 0)
        }
        wb = (gr1[gr1.count - 1].x, gr2[gr2.count - 1].x)
        for i in 0..<3 {
            let p = 0.6 - Double(i * i) * 0.1
            gr1.append(P(wb.0 * p, gr1[gr1.count - 1].y + 1))
            gr2.append(P(wb.1 * p, gr2[gr2.count - 1].y + 1))
        }
        let d = 5.0
        gr1 = ZXArt.div(gr1, d)
        gr2 = ZXArt.div(gr2, d)
        gr1.reverse()
        var grlist = gr1 + gr2 + [gr1[0]]
        // 原作: grlist 的首尾是同一个数组对象, 下面的 *= 会作用两次。
        let last = grlist.count - 1
        for i in 0..<grlist.count {
            if i == last { grlist[last] = grlist[0] }
            let v = (1 - abs(Double(i).truncatingRemainder(dividingBy: d) - d / 2) / (d / 2)) * 0.12
            grlist[i].x *= 1 - v + n(grlist[i].y * 0.5) * v
        }
        grlist[0] = grlist[last]
        canv.append(poly(grlist, xof: xoff, yof: yoff, fil: .white, str: nil, wid: 2))
        canv += stroke(grlist.map { P($0.x + xoff, $0.y + yoff) }, wid: 3, col: .ink(0.2))
        var bd = Bound(xmin: .nan, xmax: .nan, ymin: .nan, ymax: .nan)
        for (k, p) in grlist.enumerated() {
            if k == 0 || p.x < bd.xmin { bd.xmin = p.x }
            if k == 0 || p.x > bd.xmax { bd.xmax = p.x }
            if k == 0 || p.y < bd.ymin { bd.ymin = p.y }
            if k == 0 || p.y > bd.ymax { bd.ymax = p.y }
        }
        // dec = false: 竖幅构图不要原作的随机点景 (树 / 石 / 屋), 由构图自己布置。
        if dec { canv += flatDec(xoff, yoff, bd) }
        return canv
    }

    func flatDec(_ xoff: Double, _ yoff: Double, _ g: Bound) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        let mid = (g.ymin + g.ymax) / 2
        let tt = e.choice([0, 0, 1, 2, 3, 4])

        var j = 0.0
        while j < r() * 5 {
            let rx = xoff + e.normRand(g.xmin, g.xmax)
            let ry = yoff + mid + e.normRand(-10, 10) + 10
            let rs = r() * 100
            let rw = 10 + r() * 20, rh = 10 + r() * 20
            canv += rock(rx, ry, rs, hei: rh, wid: rw, sha: 2)
            j += 1
        }
        j = 0
        while j < Double(e.choice([0, 0, 1, 2])) {
            let xr = xoff + e.normRand(g.xmin, g.xmax)
            let yr = yoff + mid + e.normRand(-5, 5) + 20
            var k = 0.0
            while k < 2 + r() * 3 {
                let tx = xr + min(max(e.normRand(-30, 30), g.xmin), g.xmax)
                canv += tree08(tx, yr, hei: 60 + r() * 40)
                k += 1
            }
            j += 1
        }
        if tt == 0 {
            j = 0
            while j < r() * 3 {
                let rx = xoff + e.normRand(g.xmin, g.xmax)
                let ry = yoff + mid + e.normRand(-5, 5) + 20
                let rs = r() * 100
                let rw = 50 + r() * 20, rh = 40 + r() * 20
                canv += rock(rx, ry, rs, hei: rh, wid: rw, sha: 5)
                j += 1
            }
        }
        if tt == 1 {
            let pmin = r() * 0.5
            let pmax = r() * 0.5 + 0.5
            let xmin = g.xmin * (1 - pmin) + g.xmax * pmin
            let xmax = g.xmin * (1 - pmax) + g.xmax * pmax
            var i = xmin
            while i < xmax {
                let tx = xoff + i + 20 * e.normRand(-1, 1)
                canv += tree05(tx, yoff + mid + 20, hei: 100 + r() * 200)
                i += 30
            }
            j = 0
            while j < r() * 4 {
                let rx = xoff + e.normRand(g.xmin, g.xmax)
                let ry = yoff + mid + e.normRand(-5, 5) + 20
                let rs = r() * 100
                let rw = 50 + r() * 20, rh = 40 + r() * 20
                canv += rock(rx, ry, rs, hei: rh, wid: rw, sha: 5)
                j += 1
            }
        } else if tt == 2 {
            var i = 0.0
            while i < Double(e.choice([1, 1, 1, 1, 2, 2, 3])) {
                let xr = e.normRand(g.xmin, g.xmax)
                let yr = mid
                canv += tree04(xoff + xr, yoff + yr + 20)
                j = 0
                while j < r() * 2 {
                    let rx = xoff + max(g.xmin, min(g.xmax, xr + e.normRand(-50, 50)))
                    let ry = yoff + yr + e.normRand(-5, 5) + 20
                    let rs = j * i * r() * 100
                    let rw = 50 + r() * 20, rh = 40 + r() * 20
                    canv += rock(rx, ry, rs, hei: rh, wid: rw, sha: 5)
                    j += 1
                }
                i += 1
            }
        } else if tt == 3 {
            var i = 0.0
            while i < Double(e.choice([1, 1, 1, 1, 2, 2, 3])) {
                let tx = xoff + e.normRand(g.xmin, g.xmax)
                canv += tree06(tx, yoff + mid, hei: 60 + r() * 60)
                i += 1
            }
        } else if tt == 4 {
            let pmin = r() * 0.5
            let pmax = r() * 0.5 + 0.5
            let xmin = g.xmin * (1 - pmin) + g.xmax * pmin
            let xmax = g.xmin * (1 - pmax) + g.xmax * pmax
            var i = xmin
            while i < xmax {
                let tx = xoff + i + 20 * e.normRand(-1, 1)
                let ty = yoff + mid + e.normRand(-1, 1) + 0
                canv += tree07(tx, ty, hei: e.normRand(40, 80))
                i += 20
            }
        }
        var i = 0.0
        while i < 50 * r() {
            let tx = xoff + e.normRand(g.xmin, g.xmax)
            let ty = yoff + e.normRand(g.ymin, g.ymax)
            canv += tree02(tx, ty)
            i += 1
        }
        let ts = e.choice([0, 0, 0, 0, 1])
        if ts == 1 && tt != 4 {
            let ax = xoff + e.normRand(g.xmin, g.xmax)
            let ay = yoff + mid + 20
            let aseed = r()
            let aw = e.normRand(160, 200)
            let ah = e.normRand(80, 100)
            let ap = r()
            canv += arch01(ax, ay, aseed, hei: ah, wid: aw, per: ap)
        }
        return canv
    }

    // MARK: distMount

    func distMount(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 300, len: Double = 2000,
                   seg: Double = 5) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        let span = 10.0
        var ptlist: [[P]] = []
        var i = 0.0
        while i < len / span / seg {
            var row: [P] = []
            var j = 0.0
            while j < seg + 1 {
                let k = i * seg + j
                row.append(P(xoff + k * span,
                             yoff - hei * n(k * 0.05, seed) * pow(sin((Double.pi * k) / (len / span)), 0.5)))
                j += 1
            }
            j = 0
            while j < seg / 2 + 1 {
                let k = i * seg + j * 2
                row.insert(P(xoff + k * span,
                             yoff + 24 * n(k * 0.05, 2, seed) * pow(sin((Double.pi * k) / (len / span)), 1)), at: 0)
                j += 1
            }
            ptlist.append(row)
            i += 1
        }
        func getCol(_ x: Double, _ y: Double) -> C {
            let c = Double(ZXArt.or0(n(x * 0.02, y * 0.02, yoff) * 55 + 200))
            return C(c, c, c, 1)
        }
        for row in ptlist {
            var p = poly(row, fil: getCol(row[row.count - 1].x, row[row.count - 1].y), str: nil, wid: 1)
            p.wash = true
            canv.append(p)
            let T = ZXArt.triangulate(row, area: 100, convex: true, optimize: false)
            for t in T {
                let m = ZXArt.midPt(t)
                let co = getCol(m.x, m.y)
                var q = poly(t, fil: co, str: co, wid: 1)
                q.wash = true
                canv.append(q)
            }
        }
        return canv
    }

    // MARK: rock

    func rock(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 80, wid: Double = 100,
              tex: Double = 40, sha: Double = 10) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        let reso0 = 10, reso1 = 50
        var ptlist: [[P]] = []
        for i in 0..<reso0 {
            var nslist: [Double] = []
            for j in 0..<reso1 { nslist.append(n(Double(i), Double(j) * 0.2, seed)) }
            ZXArt.loopNoise(&nslist)
            var row: [P] = []
            for j in 0..<reso1 {
                let a = (Double(j) / Double(reso1)) * Double.pi * 2 - Double.pi / 2
                let hc = hei * cos(a), ws = wid * sin(a)
                var l = (wid * hei) / (hc * hc + ws * ws).squareRoot()
                l *= 0.7 + 0.3 * nslist[j]
                let p = 1 - Double(i) / Double(reso0)
                let nx = cos(a) * l * p
                var ny = -sin(a) * l * p
                if Double.pi < a || a < 0 { ny *= 0.2 }
                ny += hei * (Double(i) / Double(reso0)) * 0.2
                row.append(P(nx, ny))
            }
            ptlist.append(row)
        }
        canv.append(poly(ptlist[0] + [P(0, 0)], xof: xoff, yof: yoff, fil: .white, str: nil))
        canv += stroke(ptlist[0].map { P($0.x + xoff, $0.y + yoff) }, wid: 3, col: .ink(0.3), noi: 1)
        canv += texture(ptlist, xof: xoff, yof: yoff, tex: tex, wid: 3, sha: sha,
                        col: { _ in C(180, 180, 180, ZXArt.toFixed(0.3 + self.r() * 0.3, 3)) },
                        dis: { self.r() > 0.5 ? 0.15 + 0.15 * self.r() : 0.85 - 0.15 * self.r() })
        return canv
    }
}
