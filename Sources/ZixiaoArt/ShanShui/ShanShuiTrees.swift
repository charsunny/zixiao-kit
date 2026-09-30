//  ShanShuiTrees.swift — 树 (tree01…tree08) 与枝干 / 小枝 / 树皮
//
//  Ported from shan-shui-inf index.html (`var Tree = new function(){…}`).
//  MIT License, (c) 2018 Lingdong Huang — https://github.com/LingDong-/shan-shui-inf
//  Full license text: ZXArtLicenses.swift / LICENSES/.
//
//  注意 barkify: 原作的 `div()` 把末点作为「原数组元素的引用」返回, 随后对它 `+=` 噪声 ——
//  这会改到调用方的树干点 (tree04/05/06 的主干轮廓因此带上树皮抖动)。这里用 inout + 下标
//  回写复现这个副作用。

import Foundation
import ZixiaoDesign

extension ShanShuiEngine {
    private func leafAlpha(_ col: C) -> Double { col.a }

    // MARK: tree01 — 远处的小树 (两条细线 + 叶团)

    func tree01(_ x: Double, _ y: Double, hei: Double = 50, wid: Double = 3,
                col: C = .ink(0.5)) -> ZXArt.SSCanv {
        let reso = 10.0
        var nslist: [(Double, Double)] = []
        for i in 0..<10 { nslist.append((n(Double(i) * 0.5), n(Double(i) * 0.5, 0.5))) }
        var canv: ZXArt.SSCanv = []
        var line1: [P] = [], line2: [P] = []
        for i in 0..<10 {
            let fi = Double(i)
            let nx = x
            let ny = y - (fi * hei) / reso
            if fi >= reso / 4 {
                var j = 0.0
                while j < (reso - fi) / 5 {
                    let bx = nx + (r() - 0.5) * wid * 1.2 * (reso - fi)
                    let by = ny + (r() - 0.5) * wid
                    let len = r() * 20 * (reso - fi) * 0.2 + 10
                    let bw = r() * 6 + 3
                    let ang = ((r() - 0.5) * Double.pi) / 6
                    let c = C(col.r, col.g, col.b, ZXArt.toFixed(r() * 0.2 + col.a, 1))
                    canv += blob(bx, by, len: len, wid: bw, ang: ang, col: c)
                    j += 1
                }
            }
            line1.append(P(nx + (nslist[i].0 - 0.5) * wid - wid / 2, ny))
            line2.append(P(nx + (nslist[i].1 - 0.5) * wid + wid / 2, ny))
        }
        canv.append(poly(line1, fil: nil, str: col, wid: 1.5))
        canv.append(poly(line2, fil: nil, str: col, wid: 1.5))
        return canv
    }

    // MARK: tree02 — 苔点 / 远树团

    static let fun02: @Sendable (Double) -> Double = { x in
        x <= 1 ? pow(sin(x * Double.pi) * x, 0.5) : -pow(sin((x - 2) * Double.pi * (x - 2)), 0.5)
    }

    func tree02(_ x: Double, _ y: Double, hei: Double = 16, wid: Double = 8, clu: Double = 5,
                col: C = .ink(0.5)) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        var i = 0.0
        while i < clu {
            let bx = x + e.randGaussian() * clu * 4
            let by = y + e.randGaussian() * clu * 4
            let bw = r() * wid * 0.75 + wid * 0.5
            let bl = r() * hei * 0.75 + hei * 0.5
            canv += blob(bx, by, len: bl, wid: bw, ang: Double.pi / 2, col: col, fun: ShanShuiEngine.fun02)
            i += 1
        }
        return canv
    }

    // MARK: tree03 — 山脚的树 (白底树干 + 叶团)

    func tree03(_ x: Double, _ y: Double, hei: Double = 50, wid: Double = 5,
                ben: (Double) -> Double = { _ in 0 }, col: C = .ink(0.5)) -> ZXArt.SSCanv {
        let reso = 10.0
        var nslist: [(Double, Double)] = []
        for i in 0..<10 { nslist.append((n(Double(i) * 0.5), n(Double(i) * 0.5, 0.5))) }
        var canv: ZXArt.SSCanv = []
        var blobs: ZXArt.SSCanv = []
        var line1: [P] = [], line2: [P] = []
        for i in 0..<10 {
            let fi = Double(i)
            let nx = x + ben(fi / reso) * 100
            let ny = y - (fi * hei) / reso
            if fi >= reso / 5 {
                var j = 0.0
                while j < (reso - fi) * 2 {
                    let shapeV = log(50 * ((reso - fi) / reso) + 1) / 3.95
                    let ox = r() * wid * 2 * shapeV
                    let bx = nx + ox * e.choice([-1.0, 1.0])
                    let by = ny + (r() - 0.5) * wid * 2
                    let bw = r() * 6 + 3
                    let ang = ((r() - 0.5) * Double.pi) / 6
                    let c = C(col.r, col.g, col.b, ZXArt.toFixed(r() * 0.2 + col.a, 3))
                    blobs += blob(bx, by, len: ox * 2, wid: bw, ang: ang, col: c)
                    j += 1
                }
            }
            line1.append(P(nx + (((nslist[i].0 - 0.5) * wid - wid / 2) * (reso - fi)) / reso, ny))
            line2.append(P(nx + (((nslist[i].1 - 0.5) * wid + wid / 2) * (reso - fi)) / reso, ny))
        }
        canv.append(poly(line1 + line2.reversed(), fil: .white, str: col, wid: 1.5))
        canv += blobs
        return canv
    }

    // MARK: branch / twig / barkify

    /// 返回两侧轮廓 (trlist1, trlist2), 局部坐标。
    func branch(hei: Double = 300, wid: Double = 6, ang angIn: Double = 0, det: Double = 10,
                ben: Double = Double.pi * 0.2) -> [[P]] {
        var nx = 0.0, ny = 0.0
        var tlist: [P] = [P(nx, ny)]
        var a0 = 0.0
        let g = 3.0
        for _ in 0..<3 {
            let mag = ben / 2 + (r() * ben) / 2
            a0 += mag * e.choice([-1.0, 1.0])
            nx += (cos(a0) * hei) / g
            ny -= (sin(a0) * hei) / g
            tlist.append(P(nx, ny))
        }
        let ta = atan2(tlist[tlist.count - 1].y, tlist[tlist.count - 1].x)
        for i in 0..<tlist.count {
            let a = atan2(tlist[i].y, tlist[i].x)
            let d = (tlist[i].x * tlist[i].x + tlist[i].y * tlist[i].y).squareRoot()
            tlist[i] = P(d * cos(a - ta + angIn), d * sin(a - ta + angIn))
        }
        var tr1: [P] = [], tr2: [P] = []
        let span = det
        let tl = Double(tlist.count - 1) * span
        var lx = 0.0, ly = 0.0
        var i = 0.0
        while i < tl {
            let lastp = tlist[Int((i / span).rounded(.down))]
            let nextp = tlist[Int((i / span).rounded(.up))]
            let p = i.truncatingRemainder(dividingBy: span) / span
            let px = lastp.x * (1 - p) + nextp.x * p
            let py = lastp.y * (1 - p) + nextp.y * p
            let ang = atan2(py - ly, px - lx)
            let woff = ((n(i * 0.3) - 0.5) * wid * hei) / 80
            var b = 0.0
            if p == 0 { b = r() * wid }
            let nw = wid * (((tl - i) / tl) * 0.5 + 0.5)
            tr1.append(P(px + cos(ang + Double.pi / 2) * (nw + woff + b), py + sin(ang + Double.pi / 2) * (nw + woff + b)))
            tr2.append(P(px + cos(ang - Double.pi / 2) * (nw - woff + b), py + sin(ang - Double.pi / 2) * (nw - woff + b)))
            lx = px; ly = py
            i += 1
        }
        return [tr1, tr2]
    }

    func twig(_ tx: Double, _ ty: Double, _ dep: Double, dir: Double = 1, sca: Double = 1, wid: Double = 1,
              ang: Double = 0, lea: (Bool, Double) = (true, 12)) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        var twlist: [P] = []
        let tl = 10
        let hs = r() * 0.5 + 0.5
        _ = e.choice([0])  // randChoice([fun2])
        let a0 = ((r() * Double.pi) / 6) * dir + ang
        for i in 0..<tl {
            let fi = Double(i)
            let tf = -1 / pow(fi / Double(tl) + 1, 5) + 1
            let mx = dir * tf * 50 * sca * hs
            let my = -fi * 5 * sca
            let a = atan2(my, mx)
            let d = pow(mx * mx + my * my, 0.5)
            let nx = cos(a + a0) * d
            let ny = sin(a + a0) * d
            twlist.append(P(nx + tx, ny + ty))
            if (i == tl / 3 || i == (tl * 2) / 3) && dep > 0 {
                let ndir = dir * e.choice([-1.0, 1.0])
                canv += twig(nx + tx, ny + ty, dep - 1, dir: ndir, sca: sca * 0.8, wid: wid, ang: ang, lea: lea)
            }
            if i == tl - 1 && lea.0 {
                for j in 0..<5 {
                    let dj = (Double(j) - 2.5) * 5
                    let bx = nx + tx + cos(ang) * dj * wid
                    let by = ny + ty + (sin(ang) * dj - lea.1 / (dep + 1)) * wid
                    let bw = (6 + 3 * r()) * wid
                    let bl = (15 + 12 * r()) * wid
                    let ba = ang / 2 + Double.pi / 2 + Double.pi * 0.2 * (r() - 0.5)
                    canv += blob(bx, by, len: bl, wid: bw, ang: ba, col: .ink(0.5 + dep * 0.2), fun: ShanShuiEngine.fun02)
                }
            }
        }
        canv += stroke(twlist, wid: 1, col: .ink(0.5), fun: { cos(($0 * Double.pi) / 2) })
        return canv
    }

    private func bark(_ x: Double, _ y: Double, _ wid: Double, _ ang: Double) -> ZXArt.SSCanv {
        let len = 10 + 10 * r()
        let noi = 0.5
        let reso = 20.0
        var lalist: [(Double, Double)] = []
        for i in 0...20 {
            let p = (Double(i) / reso) * 2
            let xo = len / 2 - abs(p - 1) * len
            let yo = (ShanShuiEngine.blobFun(p) * wid) / 2
            lalist.append(((xo * xo + yo * yo).squareRoot(), atan2(yo, xo)))
        }
        var nslist: [Double] = []
        let n0 = r() * 10
        for i in 0...20 { nslist.append(n(Double(i) * 0.05, n0)) }
        ZXArt.loopNoise(&nslist)
        var brk: [P] = []
        for i in 0..<lalist.count {
            let ns = nslist[i] * noi + (1 - noi)
            brk.append(P(x + cos(lalist[i].1 + ang) * lalist[i].0 * ns, y + sin(lalist[i].1 + ang) * lalist[i].0 * ns))
        }
        let fr = r()
        return stroke(brk, wid: 0.8, col: .ink(0.4), noi: 0, out: 0, fun: { sin(($0 + fr) * Double.pi * 3) })
    }

    /// `barkify(x, y, trlist)` — 会改写 trlist (见文件头)。
    func barkify(_ x: Double, _ y: Double, _ trlist: inout [[P]]) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        let t0 = trlist[0], t1 = trlist[1]
        if t0.count > 3 {
            for i in 2..<(t0.count - 1) {
                let a0 = atan2(t0[i].y - t0[i - 1].y, t0[i].x - t0[i - 1].x)
                let a1 = atan2(t1[i].y - t1[i - 1].y, t1[i].x - t1[i - 1].x)
                let p = r()
                let nx = t0[i].x * (1 - p) + t1[i].x * p
                let ny = t0[i].y * (1 - p) + t1[i].y * p
                if r() < 0.2 {
                    canv += blob(nx + x, ny + y, len: 15, wid: 6 - abs(p - 0.5) * 10, ang: (a0 + a1) / 2,
                                 col: .ink(0.6), noi: 1)
                } else {
                    canv += bark(nx + x, ny + y, 5 - abs(p - 0.5) * 10, (a0 + a1) / 2)
                }
                if r() < 0.05 {
                    let jl = r() * 2 + 2
                    let xya = e.choice([(t0[i].x, t0[i].y, a0), (t1[i].x, t1[i].y, a1)])
                    var j = 0.0
                    while j < jl {
                        let bx = xya.0 + x + cos(xya.2) * (j - jl / 2) * 4
                        let by = xya.1 + y + sin(xya.2) * (j - jl / 2) * 4
                        canv += blob(bx, by, len: 4 + 6 * r(), wid: 4, ang: a0 + Double.pi / 2, col: .ink(0.6))
                        j += 1
                    }
                }
            }
        }
        // trflist = trlist[0] ++ reverse(trlist[1]); 记下每个点来自哪里, 以便回写。
        let n0c = t0.count, n1c = t1.count
        func source(_ k: Int) -> (Int, Int) { k < n0c ? (0, k) : (1, n1c - 1 - (k - n0c)) }
        let total = n0c + n1c
        var groups: [[Int]] = [[]]
        for k in 0..<total {
            if r() < 0.5 { groups.append([]) } else { groups[groups.count - 1].append(k) }
        }
        for (gi, g) in groups.enumerated() {
            let pts = g.map { k -> P in let s = source(k); return trlist[s.0][s.1] }
            var rg = ZXArt.div(pts, 4)
            for j in 0..<rg.count {
                rg[j].x += (n(Double(gi), Double(j) * 0.1, 1) - 0.5) * (15 + 5 * e.randGaussian())
                rg[j].y += (n(Double(gi), Double(j) * 0.1, 2) - 0.5) * (15 + 5 * e.randGaussian())
            }
            if let last = g.last, !rg.isEmpty {
                // div 的末点就是原数组元素本身 → 调用方的 trlist 也被改了。
                let s = source(last)
                trlist[s.0][s.1] = rg[rg.count - 1]
            }
            canv += stroke(rg.map { P($0.x + x, $0.y + y) }, wid: 1.5, col: .ink(0.7), out: 0)
        }
        return canv
    }

    // MARK: tree04 / tree05 — 大树

    private static let sin1: @Sendable (Double) -> Double = { _ in sin(1) }

    func tree04(_ x: Double, _ y: Double, hei: Double = 300, wid: Double = 6, col: C = .ink(0.5)) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        var txcanv: ZXArt.SSCanv = []
        var twcanv: ZXArt.SSCanv = []
        var tr = branch(hei: hei, wid: wid, ang: -Double.pi / 2)
        txcanv += barkify(x, y, &tr)
        let trlist = tr[0] + tr[1].reversed()
        var trmlist: [P] = []
        let L = Double(trlist.count)
        for i in 0..<trlist.count {
            let fi = Double(i)
            if (fi >= L * 0.3 && fi <= L * 0.7 && r() < 0.1) || fi == L / 2 - 1 {
                let ba = Double.pi * 0.2 - Double.pi * 1.4 * (fi > L / 2 ? 1 : 0)
                var br = branch(hei: hei * (r() + 1) * 0.3, wid: wid * 0.5, ang: ba)
                br[0].removeFirst(); br[1].removeFirst()
                let o = trlist[i]
                var copy = [br[0].map { P($0.x + o.x, $0.y + o.y) }, br[1].map { P($0.x + o.x, $0.y + o.y) }]
                txcanv += barkify(x, y, &copy)
                for j in 0..<br[0].count {
                    if r() < 0.2 || j == br[0].count - 1 {
                        twcanv += twig(br[0][j].x + o.x + x, br[0][j].y + o.y + y, 1,
                                       dir: ba > -Double.pi / 2 ? 1 : -1, sca: (0.5 * hei) / 300, wid: hei / 300,
                                       ang: ba > -Double.pi / 2 ? ba : ba + Double.pi)
                    }
                }
                let bl = br[0] + br[1].reversed()
                trmlist += bl.map { P($0.x + o.x, $0.y + o.y) }
            } else {
                trmlist.append(trlist[i])
            }
        }
        canv.append(poly(trmlist, xof: x, yof: y, fil: .white, str: col, wid: 0))
        trmlist.removeFirst()
        trmlist.removeLast()
        let sc = C.ink(0.4 + r() * 0.1)
        canv += stroke(trmlist.map { P($0.x + x, $0.y + y) }, wid: 2.5, col: sc, noi: 0.9, out: 0, fun: ShanShuiEngine.sin1)
        canv += txcanv
        canv += twcanv
        return canv
    }

    func tree05(_ x: Double, _ y: Double, hei: Double = 300, wid: Double = 5, col: C = .ink(0.5)) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        var txcanv: ZXArt.SSCanv = []
        var twcanv: ZXArt.SSCanv = []
        var tr = branch(hei: hei, wid: wid, ang: -Double.pi / 2, ben: 0)
        txcanv += barkify(x, y, &tr)
        let trlist = tr[0] + tr[1].reversed()
        var trmlist: [P] = []
        let L = Double(trlist.count)
        for i in 0..<trlist.count {
            let fi = Double(i)
            let p = abs(fi - L * 0.5) / (L * 0.5)
            if (fi >= L * 0.2 && fi <= L * 0.8 && i % 3 == 0 && r() > p) || fi == L / 2 - 1 {
                let bar = r() * 0.2
                let ba = -bar * Double.pi - (1 - bar * 2) * Double.pi * (fi > L / 2 ? 1 : 0)
                var br = branch(hei: hei * (0.3 * p - r() * 0.05), wid: wid * 0.5, ang: ba, ben: 0.5)
                br[0].removeFirst(); br[1].removeFirst()
                let o = trlist[i]
                for j in 0..<br[0].count where j % 20 == 0 || j == br[0].count - 1 {
                    twcanv += twig(br[0][j].x + o.x + x, br[0][j].y + o.y + y, 0,
                                   dir: ba > -Double.pi / 2 ? 1 : -1, sca: (0.2 * hei) / 300, wid: hei / 300,
                                   ang: ba > -Double.pi / 2 ? ba : ba + Double.pi, lea: (true, 5))
                }
                let bl = br[0] + br[1].reversed()
                trmlist += bl.map { P($0.x + o.x, $0.y + o.y) }
            } else {
                trmlist.append(trlist[i])
            }
        }
        canv.append(poly(trmlist, xof: x, yof: y, fil: .white, str: col, wid: 0))
        trmlist.removeFirst()
        trmlist.removeLast()
        let sc = C.ink(0.4 + r() * 0.1)
        canv += stroke(trmlist.map { P($0.x + x, $0.y + y) }, wid: 2.5, col: sc, noi: 0.9, out: 0, fun: ShanShuiEngine.sin1)
        canv += txcanv
        canv += twcanv
        return canv
    }

    // MARK: tree06 — 分形老树

    func tree06(_ x: Double, _ y: Double, hei: Double = 100, wid: Double = 6, col: C = .ink(0.5)) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        var txcanv: ZXArt.SSCanv = []
        var twcanv: ZXArt.SSCanv = []

        func fracTree(_ xoff: Double, _ yoff: Double, _ dep: Double, hei: Double = 300, wid: Double = 5,
                      ang: Double = 0, ben: Double = Double.pi * 0.2) -> [P] {
            var tr = branch(hei: hei, wid: wid, ang: ang, det: hei / 20, ben: ben)
            txcanv += barkify(xoff, yoff, &tr)
            let trlist = tr[0] + tr[1].reversed()
            var trmlist: [P] = []
            let L = Double(trlist.count)
            let half = Double(ZXArt.or0(L / 2))
            for i in 0..<trlist.count {
                let fi = Double(i)
                if ((r() < 0.025 && fi >= L * 0.2 && fi <= L * 0.8) || fi == half - 1 || fi == half + 1) && dep > 0 {
                    let bar = 0.02 + r() * 0.08
                    let ba = bar * Double.pi - bar * 2 * Double.pi * (fi > L / 2 ? 1 : 0)
                    let o = trlist[i]
                    let brlist = fracTree(o.x + xoff, o.y + yoff, dep - 1,
                                          hei: hei * (0.7 + r() * 0.2), wid: wid * 0.6, ang: ang + ba, ben: 0.55)
                    for j in 0..<brlist.count where r() < 0.03 {
                        twcanv += twig(brlist[j].x + o.x + xoff, brlist[j].y + o.y + yoff, 2,
                                       dir: ba > 0 ? 1 : -1, sca: 0.3, ang: ba * (r() * 0.5 + 0.75), lea: (false, 0))
                    }
                    trmlist += brlist.map { P($0.x + o.x, $0.y + o.y) }
                } else {
                    trmlist.append(trlist[i])
                }
            }
            return trmlist
        }

        var trmlist = fracTree(x, y, 3, hei: hei, wid: wid, ang: -Double.pi / 2, ben: 0)
        canv.append(poly(trmlist, xof: x, yof: y, fil: .white, str: col, wid: 0))
        trmlist.removeFirst()
        trmlist.removeLast()
        let sc = C.ink(0.4 + r() * 0.1)
        canv += stroke(trmlist.map { P($0.x + x, $0.y + y) }, wid: 2.5, col: sc, noi: 0.9, out: 0, fun: ShanShuiEngine.sin1)
        canv += txcanv
        canv += twcanv
        return canv
    }

    // MARK: tree07 — 点叶树 (三角剖分着色)

    static let fun07: @Sendable (Double) -> Double = { x in
        x <= 1 ? 2.75 * x * pow(1 - x, 1 / 1.8) : 2.75 * (x - 2) * pow(x - 1, 1 / 1.8)
    }

    func tree07(_ x: Double, _ y: Double, hei: Double = 60, wid: Double = 4,
                ben: (Double) -> Double = { $0.squareRoot() * 0.2 }, col: C = .ink(1)) -> ZXArt.SSCanv {
        let reso = 10.0
        var nslist: [(Double, Double)] = []
        for i in 0..<10 { nslist.append((n(Double(i) * 0.5), n(Double(i) * 0.5, 0.5))) }
        var canv: ZXArt.SSCanv = []
        var line1: [P] = [], line2: [P] = []
        var T: [[P]] = []
        for i in 0..<10 {
            let fi = Double(i)
            let nx = x + ben(fi / reso) * 100
            let ny = y - (fi * hei) / reso
            if fi >= reso / 4 {
                let bx = nx + (r() - 0.5) * wid * 1.2 * (reso - fi) * 0.5
                let by = ny + (r() - 0.5) * wid * 0.5
                let bl = r() * 50 + 20
                let bw = r() * 12 + 12
                let ba = (-r() * Double.pi) / 6
                let bpl = blobPoints(bx, by, len: bl, wid: bw, ang: ba, fun: ShanShuiEngine.fun07)
                T += ZXArt.triangulate(bpl, area: 50, convex: true, optimize: false)
            }
            line1.append(P(nx + (nslist[i].0 - 0.5) * wid - wid / 2, ny))
            line2.append(P(nx + (nslist[i].1 - 0.5) * wid + wid / 2, ny))
        }
        T = ZXArt.triangulate(line1 + line2.reversed(), area: 50, convex: true, optimize: true) + T
        for t in T {
            let m = ZXArt.midPt(t)
            let c = Double(ZXArt.or0(n(m.x * 0.02, m.y * 0.02) * 200 + 50))
            let co = C.gray(c, 0.8)
            canv.append(poly(t, fil: co, str: co, wid: 0))
        }
        return canv
    }

    // MARK: tree08 — 枯枝

    func tree08(_ x: Double, _ y: Double, hei: Double = 80, wid: Double = 1, col: C = .ink(0.5)) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        var twcanv: ZXArt.SSCanv = []
        let ang = e.normRand(-1, 1) * Double.pi * 0.2
        let tr = branch(hei: hei, wid: wid, ang: -Double.pi / 2 + ang, det: hei / 20, ben: Double.pi * 0.2)
        let trlist = tr[0] + tr[1].reversed()

        func fracTree(_ xoff: Double, _ yoff: Double, _ dep: Double, ang: Double = -Double.pi / 2,
                      len: Double = 15, ben: Double = 0) -> ZXArt.SSCanv {
            let fun: (Double) -> Double = dep == 0 ? { cos(0.5 * Double.pi * $0) } : { _ in 1 }
            let spt = P(xoff, yoff)
            let ept = P(xoff + cos(ang) * len, yoff + sin(ang) * len)
            let bsign = e.choice([1.0, -1.0])
            var trm = ZXArt.div([P(xoff, yoff), P(xoff + len, yoff)], 10)
            let tc = Double(trm.count)
            for i in 0..<trm.count { trm[i].y += bsign * sin((Double(i) / tc) * Double.pi) * 2 }
            for i in 0..<trm.count {
                let d = ZXArt.distance(trm[i], spt)
                let a = atan2(trm[i].y - spt.y, trm[i].x - spt.x)
                trm[i] = P(spt.x + d * cos(a + ang), spt.y + d * sin(a + ang))
            }
            var tcanv: ZXArt.SSCanv = stroke(trm, wid: 0.8, col: .ink(0.5), fun: fun)
            if dep != 0 {
                let nben = ben + e.choice([-1.0, 1.0]) * Double.pi * 0.001 * dep * dep
                if r() < 0.5 {
                    let c1 = [e.normRand(-1, 0.5), e.normRand(0.5, 1)]
                    let a1 = ang + ben + Double.pi * e.choice(c1) * 0.2
                    let l1 = len * e.normRand(0.8, 0.9)
                    tcanv += fracTree(ept.x, ept.y, dep - 1, ang: a1, len: l1, ben: nben)
                    let c2 = [e.normRand(-1, -0.5), e.normRand(0.5, 1)]
                    let a2 = ang + ben + Double.pi * e.choice(c2) * 0.2
                    let l2 = len * e.normRand(0.8, 0.9)
                    tcanv += fracTree(ept.x, ept.y, dep - 1, ang: a2, len: l2, ben: nben)
                } else {
                    tcanv += fracTree(ept.x, ept.y, dep - 1, ang: ang + ben, len: len * e.normRand(0.8, 0.9), ben: nben)
                }
            }
            return tcanv
        }

        for i in 0..<trlist.count {
            if r() < 0.2 {
                let dep = (4 * r()).rounded(.down)
                let a = -Double.pi / 2 - ang * r()
                twcanv += fracTree(x + trlist[i].x, y + trlist[i].y, dep, ang: a)
            } else if i == trlist.count / 2 {
                twcanv += fracTree(x + trlist[i].x, y + trlist[i].y, 3, ang: -Double.pi / 2 + ang)
            }
        }
        canv.append(poly(trlist, xof: x, yof: y, fil: .white, str: col, wid: 0))
        let sc = C.ink(0.6 + r() * 0.1)
        canv += stroke(trlist.map { P($0.x + x, $0.y + y) }, wid: 2.5, col: sc, noi: 0.9, out: 0, fun: ShanShuiEngine.sin1)
        canv += twcanv
        return canv
    }
}
