//  ShanShuiArch.swift — 屋舍 / 塔 / 亭 / 船 / 人物 / 电塔
//
//  Ported from shan-shui-inf index.html (`var Arch = …`, `var Man = …`).
//  MIT License, (c) 2018 Lingdong Huang — https://github.com/LingDong-/shan-shui-inf
//  Full license text: ZXArtLicenses.swift / LICENSES/.
//
//  删减: arch02 在单层时有 1/3 概率在屋顶写一行 "Pizza Hut" (原作彩蛋 <text>) —— 随机数照常
//  消耗, 文字不画。

import Foundation

extension ShanShuiEngine {
    private static let one: @Sendable (Double) -> Double = { _ in 1 }

    // MARK: hut

    func hut(_ xoff: Double, _ yoff: Double, hei: Double = 40, wid: Double = 180, tex: Double = 300) -> ZXArt.SSCanv {
        let reso0 = 10, reso1 = 10
        var ptlist: [[P]] = []
        for i in 0..<reso0 {
            var row: [P] = []
            let heir = hei + hei * 0.2 * r()
            for j in 0..<reso1 {
                let nx = wid * (Double(i) / Double(reso0 - 1) - 0.5) * pow(Double(j) / Double(reso1 - 1), 0.7)
                let ny = heir * (Double(j) / Double(reso1 - 1))
                row.append(P(nx, ny))
            }
            ptlist.append(row)
        }
        var canv: ZXArt.SSCanv = []
        canv.append(poly(Array(ptlist[0].dropLast()) + ptlist[ptlist.count - 1].dropLast().reversed(),
                         xof: xoff, yof: yoff, fil: .white, str: nil))
        canv.append(poly(ptlist[0], xof: xoff, yof: yoff, fil: nil, str: .ink(0.3), wid: 2))
        canv.append(poly(ptlist[ptlist.count - 1], xof: xoff, yof: yoff, fil: nil, str: .ink(0.3), wid: 2))
        canv += texture(ptlist, xof: xoff, yof: yoff, tex: tex, wid: 1, len: 0.25,
                        noi: { _ in 5 },
                        col: { _ in C(120, 120, 120, ZXArt.toFixed(0.3 + self.r() * 0.3, 3)) },
                        dis: { self.e.wtrand { $0 * $0 } })
        return canv
    }

    // MARK: box / deco / rail / roof / pagroof

    struct DecoArgs { var pul: P, pur: P, pdl: P, pdr: P }

    func box(_ xoff: Double, _ yoff: Double, hei: Double = 20, wid: Double = 120, rot: Double = 0.7, per: Double = 4,
             tra: Bool = true, bot: Bool = true, wei: Double = 3, dec: (DecoArgs) -> [[P]] = { _ in [] }) -> ZXArt.SSCanv {
        let mid = -wid * 0.5 + wid * rot
        let bmid = -wid * 0.5 + wid * (1 - rot)
        var ptlist: [[P]] = []
        ptlist.append(ZXArt.div([P(-wid * 0.5, -hei), P(-wid * 0.5, 0)], 5))
        ptlist.append(ZXArt.div([P(wid * 0.5, -hei), P(wid * 0.5, 0)], 5))
        if bot {
            ptlist.append(ZXArt.div([P(-wid * 0.5, 0), P(mid, per)], 5))
            ptlist.append(ZXArt.div([P(wid * 0.5, 0), P(mid, per)], 5))
        }
        ptlist.append(ZXArt.div([P(mid, -hei), P(mid, per)], 5))
        if tra {
            if bot {
                ptlist.append(ZXArt.div([P(-wid * 0.5, 0), P(bmid, -per)], 5))
                ptlist.append(ZXArt.div([P(wid * 0.5, 0), P(bmid, -per)], 5))
            }
            ptlist.append(ZXArt.div([P(bmid, -hei), P(bmid, -per)], 5))
        }
        let surf = (rot < 0.5 ? 1.0 : 0.0) * 2 - 1
        ptlist += dec(DecoArgs(pul: P(surf * wid * 0.5, -hei), pur: P(mid, -hei + per),
                               pdl: P(surf * wid * 0.5, 0), pdr: P(mid, per)))
        let polist = [P(-wid * 0.5, -hei), P(wid * 0.5, -hei), P(wid * 0.5, 0), P(mid, per), P(-wid * 0.5, 0)]
        var canv: ZXArt.SSCanv = []
        if !tra { canv.append(poly(polist, xof: xoff, yof: yoff, fil: .white, str: nil)) }
        for pl in ptlist {
            canv += stroke(pl.map { P($0.x + xoff, $0.y + yoff) }, wid: wei, col: .ink(0.4), noi: 1, fun: ShanShuiEngine.one)
        }
        return canv
    }

    func deco(_ style: Int, _ a: DecoArgs, hsp: (Int, Double) = (1, 3), vsp: (Int, Double) = (1, 2)) -> [[P]] {
        var plist: [[P]] = []
        let dl = ZXArt.div([a.pul, a.pdl], vsp.1)
        let dr = ZXArt.div([a.pur, a.pdr], vsp.1)
        let du = ZXArt.div([a.pul, a.pur], hsp.1)
        let dd = ZXArt.div([a.pdl, a.pdr], hsp.1)
        if style == 1 || style == 3 {
            let mlu = du[hsp.0], mru = du[du.count - 1 - hsp.0]
            let mld = dd[hsp.0], mrd = dd[du.count - 1 - hsp.0]
            var i = vsp.0
            while i < dl.count - vsp.0 {
                let mml = ZXArt.div([mlu, mld], vsp.1)[i]
                let mmr = ZXArt.div([mru, mrd], vsp.1)[i]
                if style == 1 {
                    plist.append(ZXArt.div([mml, dl[i]], 5))
                    plist.append(ZXArt.div([mmr, dr[i]], 5))
                } else {
                    let mmu = ZXArt.div([mlu, mru], vsp.1)[i]
                    let mmd = ZXArt.div([mld, mrd], vsp.1)[i]
                    plist.append(ZXArt.div([mml, mmr], 5))
                    plist.append(ZXArt.div([mmu, mmd], 5))
                }
                i += vsp.0
            }
            plist.append(ZXArt.div([mlu, mld], 5))
            plist.append(ZXArt.div([mru, mrd], 5))
        } else if style == 2 {
            var i = hsp.0
            while i < du.count - hsp.0 {
                plist.append(ZXArt.div([du[i], dd[i]], 5))
                i += hsp.0
            }
        }
        return plist
    }

    func rail(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 20, wid: Double = 180, rot: Double = 0.7,
              per: Double = 4, seg: Double = 4, wei: Double = 1, tra: Bool = true, fro: Bool = true) -> ZXArt.SSCanv {
        let mid = -wid * 0.5 + wid * rot
        let bmid = -wid * 0.5 + wid * (1 - rot)
        var ptlist: [[P]] = []
        if fro {
            ptlist.append(ZXArt.div([P(-wid * 0.5, 0), P(mid, per)], seg))
            ptlist.append(ZXArt.div([P(mid, per), P(wid * 0.5, 0)], seg))
        }
        if tra {
            ptlist.append(ZXArt.div([P(-wid * 0.5, 0), P(bmid, -per)], seg))
            ptlist.append(ZXArt.div([P(bmid, -per), P(wid * 0.5, 0)], seg))
        }
        if fro {
            ptlist.append(ZXArt.div([P(-wid * 0.5, -hei), P(mid, -hei + per)], seg))
            ptlist.append(ZXArt.div([P(mid, -hei + per), P(wid * 0.5, -hei)], seg))
        }
        if tra {
            ptlist.append(ZXArt.div([P(-wid * 0.5, -hei), P(bmid, -hei - per)], seg))
            ptlist.append(ZXArt.div([P(bmid, -hei - per), P(wid * 0.5, -hei)], seg))
        }
        if tra {
            let open = Int((r() * Double(ptlist.count)).rounded(.down))
            // 原作 `(open + len) % len` 就是 open 本身 —— 同一条去了两次末点。
            ptlist[open] = Array(ptlist[open].dropLast())
            ptlist[open] = Array(ptlist[open].dropLast())
        }
        var canv: ZXArt.SSCanv = []
        let L = ptlist.count
        var i = 0
        while Double(i) < Double(L) / 2 {
            var j = 0
            while j < ptlist[i].count {
                ptlist[i][j].y += (n(Double(i), Double(j) * 0.5, seed) - 0.5) * hei
                let pi2 = (L / 2 + i) % L
                let pj = j % ptlist[pi2].count
                ptlist[pi2][pj].y += (n(Double(i) + 0.5, Double(j) * 0.5, seed) - 0.5) * hei
                var ln = ZXArt.div([ptlist[i][j], ptlist[pi2][pj]], 2)
                ln[0].x += (r() - 0.5) * hei * 0.5
                canv.append(poly(ln, xof: xoff, yof: yoff, fil: nil, str: .ink(0.5), wid: 2))
                j += 1
            }
            i += 1
        }
        for pl in ptlist {
            canv += stroke(pl.map { P($0.x + xoff, $0.y + yoff) }, wid: wei, col: .ink(0.5), noi: 0.5, fun: ShanShuiEngine.one)
        }
        return canv
    }

    func roof(_ xoff: Double, _ yoff: Double, hei: Double = 20, wid: Double = 120, rot: Double = 0.7, per: Double = 4,
              cor: Double = 5, wei: Double = 3) -> ZXArt.SSCanv {
        func opf(_ l: [P]) -> [P] { rot < 0.5 ? l.map { P(0 - ($0.x - 0), $0.y) } : l }
        let rrot = rot < 0.5 ? 1 - rot : rot
        let mid = -wid * 0.5 + wid * rrot
        let quat = (mid + wid * 0.5) * 0.5 - mid
        var ptlist: [[P]] = []
        ptlist.append(ZXArt.div(opf([P(-wid * 0.5 + quat, -hei - per / 2), P(-wid * 0.5 + quat * 0.5, -hei / 2 - per / 4),
                                     P(-wid * 0.5 - cor, 0)]), 5))
        ptlist.append(ZXArt.div(opf([P(mid + quat, -hei), P((mid + quat + wid * 0.5) / 2, -hei / 2),
                                     P(wid * 0.5 + cor, 0)]), 5))
        ptlist.append(ZXArt.div(opf([P(mid + quat, -hei), P(mid + quat / 2, -hei / 2 + per / 2), P(mid + cor, per)]), 5))
        ptlist.append(ZXArt.div(opf([P(-wid * 0.5 - cor, 0), P(mid + cor, per)]), 5))
        ptlist.append(ZXArt.div(opf([P(wid * 0.5 + cor, 0), P(mid + cor, per)]), 5))
        ptlist.append(ZXArt.div(opf([P(-wid * 0.5 + quat, -hei - per / 2), P(mid + quat, -hei)]), 5))
        var canv: ZXArt.SSCanv = []
        let polist = opf([P(-wid * 0.5, 0), P(-wid * 0.5 + quat, -hei - per / 2), P(mid + quat, -hei), P(wid * 0.5, 0), P(mid, per)])
        canv.append(poly(polist, xof: xoff, yof: yoff, fil: .white, str: nil))
        for pl in ptlist {
            canv += stroke(pl.map { P($0.x + xoff, $0.y + yoff) }, wid: wei, col: .ink(0.4), noi: 1, fun: ShanShuiEngine.one)
        }
        return canv
    }

    func pagroof(_ xoff: Double, _ yoff: Double, hei: Double = 20, wid: Double = 120, rot: Double = 0.7, per: Double = 4,
                 cor: Double = 10, sid: Int = 4, wei: Double = 3) -> ZXArt.SSCanv {
        var ptlist: [[P]] = []
        var polist: [P] = [P(0, -hei)]
        var canv: ZXArt.SSCanv = []
        for i in 0..<sid {
            let t = (Double(i) * 1.0) / Double(sid - 1) - 0.5
            let fx = wid * t
            let fy = per * (1 - abs(t) * 2)
            let fxx = (wid + cor) * t
            if i > 0 { ptlist.append([ptlist[ptlist.count - 1][2], P(fxx, fy)]) }
            ptlist.append([P(0, -hei), P(fx * 0.5, (-hei + fy) * 0.5), P(fxx, fy)])
            polist.append(P(fxx, fy))
        }
        canv.append(poly(polist, xof: xoff, yof: yoff, fil: .white, str: nil))
        for pl in ptlist {
            canv += stroke(ZXArt.div(pl, 5).map { P($0.x + xoff, $0.y + yoff) }, wid: wei, col: .ink(0.4), noi: 1,
                           fun: ShanShuiEngine.one)
        }
        return canv
    }

    // MARK: arch01…04

    func arch01(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 70, wid: Double = 180,
                rot: Double = 0.7, per: Double = 5) -> ZXArt.SSCanv {
        let p = 0.4 + r() * 0.2
        let h0 = hei * p, h1 = hei * (1 - p)
        var canv: ZXArt.SSCanv = []
        canv += hut(xoff, yoff - hei, hei: h0, wid: wid)
        canv += box(xoff, yoff, hei: h1, wid: (wid * 2) / 3, per: per, bot: false)
        canv += rail(xoff, yoff, seed, hei: 10, wid: wid, per: per * 2, seg: Double(ZXArt.or0(3 + r() * 3)), tra: true, fro: false)
        let mcnt = e.choice([0, 1, 1, 2])
        if mcnt == 1 {
            let mx = xoff + e.normRand(-wid / 3, wid / 3)
            let fli = e.choice([true, false])
            canv += man(mx, yoff, sca: 0.42, fli: fli)
        } else if mcnt == 2 {
            canv += man(xoff + e.normRand(-wid / 4, -wid / 5), yoff, sca: 0.42, fli: false)
            canv += man(xoff + e.normRand(wid / 5, wid / 4), yoff, sca: 0.42, fli: true)
        }
        canv += rail(xoff, yoff, seed, hei: 10, wid: wid, per: per * 2, seg: Double(ZXArt.or0(3 + r() * 3)), tra: false, fro: true)
        return canv
    }

    func arch02(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 10, wid: Double = 50, rot: Double = 0.3,
                per: Double = 5, sto: Double = 3, sty: Int = 1, rai: Bool = false) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        var hoff = 0.0
        let hsps: [(Int, Double)] = [(0, 0), (1, 5), (1, 5), (1, 4)]
        let vsps: [(Int, Double)] = [(0, 0), (1, 2), (1, 2), (1, 3)]
        var i = 0.0
        while i < sto {
            canv += box(xoff, yoff - hoff, hei: hei, wid: wid * pow(0.85, i), rot: rot, per: per, tra: false, wei: 1.5,
                        dec: { a in self.deco(sty, a, hsp: hsps[sty], vsp: vsps[sty]) })
            if rai {
                canv += rail(xoff, yoff - hoff, i * 0.2, hei: hei / 2, wid: wid * pow(0.85, i) * 1.1, rot: rot, per: per,
                             wei: 0.5, tra: false)
            }
            if sto == 1 && r() < 1.0 / 3 {
                // pla = [1, "Pizza Hut"] — 彩蛋文字不画。
            }
            canv += roof(xoff, yoff - hoff - hei, hei: hei, wid: wid * pow(0.9, i), rot: rot, per: per, wei: 1.5)
            hoff += hei * 1.5
            i += 1
        }
        return canv
    }

    func arch03(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 10, wid: Double = 50, rot: Double = 0.7,
                per: Double = 5, sto: Double = 7) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        var hoff = 0.0
        var i = 0.0
        while i < sto {
            canv += box(xoff, yoff - hoff, hei: hei, wid: wid * pow(0.85, i), rot: rot, per: per / 2, tra: false, wei: 1.5,
                        dec: { a in self.deco(1, a, hsp: (1, 4), vsp: (1, 2)) })
            canv += rail(xoff, yoff - hoff, i * 0.2, hei: hei / 2, wid: wid * pow(0.85, i) * 1.1, rot: rot, per: per / 2,
                         seg: 5, wei: 0.5, tra: false)
            canv += pagroof(xoff, yoff - hoff - hei, hei: hei * 1.5, wid: wid * pow(0.9, i), rot: rot, per: per, wei: 1.5)
            hoff += hei * 1.5
            i += 1
        }
        return canv
    }

    func arch04(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 15, wid: Double = 30, rot: Double = 0.7,
                per: Double = 5, sto: Double = 2) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        var hoff = 0.0
        var i = 0.0
        while i < sto {
            canv += box(xoff, yoff - hoff, hei: hei, wid: wid * pow(0.85, i), rot: rot, per: per / 2, tra: true, wei: 1.5)
            canv += rail(xoff, yoff - hoff, i * 0.2, hei: hei / 3, wid: wid * pow(0.85, i) * 1.2, rot: rot, per: per / 2,
                         seg: 3, wei: 0.5, tra: true)
            canv += pagroof(xoff, yoff - hoff - hei, hei: hei * 1, wid: wid * pow(0.9, i), rot: rot, per: per, wei: 1.5)
            hoff += hei * 1.2
            i += 1
        }
        return canv
    }

    // MARK: boat / tower

    func boat01(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, len: Double = 120, sca: Double = 1,
                fli: Bool = false) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        let dir: Double = fli ? -1 : 1
        canv += man(xoff + 20 * sca * dir, yoff, sca: 0.5 * sca, hat: .hat02, ite: .stick01, fli: !fli,
                    len: [0, 30, 20, 30, 10, 30, 30, 30, 30])
        var p1: [P] = [], p2: [P] = []
        var i = 0.0
        while i < len * sca {
            p1.append(P(i * dir, pow(sin((i / len) * Double.pi), 0.5) * 7 * sca))
            p2.append(P(i * dir, pow(sin((i / len) * Double.pi), 0.5) * 10 * sca))
            i += 5 * sca
        }
        let plist = p1 + p2.reversed()
        canv.append(poly(plist, xof: xoff, yof: yoff, fil: .white, str: .white))
        canv += stroke(plist.map { P(xoff + $0.x, yoff + $0.y) }, wid: 1, col: .ink(0.4), fun: { sin($0 * Double.pi * 2) })
        return canv
    }

    func transmissionTower01(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 100, wid: Double = 20) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        func quick(_ pl: [P]) -> ZXArt.SSCanv {
            stroke(ZXArt.div(pl, 5).map { P($0.x + xoff, $0.y + yoff) }, wid: 1, col: .ink(0.4), fun: { _ in 0.5 })
        }
        let p00 = P(-wid * 0.05, -hei), p01 = P(wid * 0.05, -hei)
        let p10 = P(-wid * 0.1, -hei * 0.9), p11 = P(wid * 0.1, -hei * 0.9)
        let p20 = P(-wid * 0.2, -hei * 0.5), p21 = P(wid * 0.2, -hei * 0.5)
        let p30 = P(-wid * 0.5, 0), p31 = P(wid * 0.5, 0)
        let bch: [(Double, Double)] = [(0.7, -0.85), (1, -0.675), (0.7, -0.5)]
        for b in bch {
            canv += quick([P(-b.0 * wid, b.1 * hei), P(b.0 * wid, b.1 * hei)])
            canv += quick([P(-b.0 * wid, b.1 * hei), P(0, (b.1 - 0.05) * hei)])
            canv += quick([P(b.0 * wid, b.1 * hei), P(0, (b.1 - 0.05) * hei)])
            canv += quick([P(-b.0 * wid, b.1 * hei), P(-b.0 * wid, (b.1 + 0.1) * hei)])
            canv += quick([P(b.0 * wid, b.1 * hei), P(b.0 * wid, (b.1 + 0.1) * hei)])
        }
        let l10 = ZXArt.div([p00, p10, p20, p30], 5)
        let l11 = ZXArt.div([p01, p11, p21, p31], 5)
        for i in 0..<(l10.count - 1) {
            canv += quick([l10[i], l11[i + 1]])
            canv += quick([l11[i], l10[i + 1]])
        }
        canv += quick([p00, p01])
        canv += quick([p10, p11])
        canv += quick([p20, p21])
        canv += quick([p00, p10, p20, p30])
        canv += quick([p01, p11, p21, p31])
        return canv
    }

    // MARK: Man

    enum Hat { case hat01, hat02 }
    enum Item { case none, stick01 }

    private func tranpoly(_ p0: P, _ p1: P, _ ptlist: [P]) -> [P] {
        let plist = ptlist.map { P(-$0.x, $0.y) }
        let ang = atan2(p1.y - p0.y, p1.x - p0.x) - Double.pi / 2
        let scl = ZXArt.distance(p0, p1)
        return plist.map { v in
            let d = ZXArt.distance(v, P(0, 0))
            let a = atan2(v.y, v.x)
            return P(p0.x + d * scl * cos(ang + a), p0.y + d * scl * sin(ang + a))
        }
    }

    private func flipper(_ l: [P]) -> [P] { l.map { P(-$0.x, $0.y) } }

    private func hat01(_ p0: P, _ p1: P, fli: Bool) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        let seed = r()
        let f: ([P]) -> [P] = fli ? flipper : { $0 }
        let shape = [P(-0.3, 0.5), P(0.3, 0.8), P(0.2, 1), P(0, 1.1), P(-0.3, 1.15), P(-0.55, 1), P(-0.65, 0.5)]
        canv.append(poly(tranpoly(p0, p1, f(shape)), fil: .ink(0.8), str: .ink(0.8)))
        var q: [P] = []
        for i in 0..<10 {
            let fi = Double(i)
            q.append(P(-0.3 - n(fi * 0.2, seed) * fi * 0.1, 0.5 - fi * 0.3))
        }
        canv.append(poly(tranpoly(p0, p1, f(q)), str: .ink(0.8), wid: 1))
        return canv
    }

    private func hat02(_ p0: P, _ p1: P, fli: Bool) -> ZXArt.SSCanv {
        _ = r()
        let f: ([P]) -> [P] = fli ? flipper : { $0 }
        let shape = [P(-0.3, 0.5), P(-1.1, 0.5), P(-1.2, 0.6), P(-1.1, 0.7), P(-0.3, 0.8), P(0.3, 0.8), P(1.0, 0.7),
                     P(1.3, 0.6), P(1.2, 0.5), P(0.3, 0.5)]
        return [poly(tranpoly(p0, p1, f(shape)), fil: .ink(0.8), str: .ink(0.8))]
    }

    private func stick01(_ p0: P, _ p1: P, fli: Bool) -> ZXArt.SSCanv {
        let seed = r()
        let f: ([P]) -> [P] = fli ? flipper : { $0 }
        var q: [P] = []
        let l = 12.0
        for i in 0..<12 {
            let fi = Double(i)
            q.append(P(-n(fi * 0.1, seed) * 0.1 * sin((fi / l) * Double.pi) * 5, 0 + fi * 0.3))
        }
        return [poly(tranpoly(p0, p1, f(q)), str: .ink(0.5), wid: 1)]
    }

    /// 骨架父链 (原作用嵌套对象 + Object.keys 求): 0 → 1 → {2, 5 → 6, 7 → 8}; 0 → 3 → 4。
    private static let chains: [[Int]] = [[0], [0, 1], [0, 1, 2], [0, 3], [0, 3, 4], [0, 1, 5], [0, 1, 5, 6], [0, 1, 7], [0, 1, 7, 8]]

    func man(_ xoff: Double, _ yoffIn: Double, sca: Double = 0.5, hat: Hat = .hat01, ite: Item = .none, fli: Bool = true,
             ang angIn: [Double]? = nil, len lenIn: [Double] = [0, 30, 20, 30, 30, 30, 30, 30, 30]) -> ZXArt.SSCanv {
        let ang: [Double]
        if let a = angIn {
            ang = a
        } else {
            let a2 = e.normRand(0, 0)
            let a3 = (Double.pi / 4) * r()
            let a4 = ((Double.pi * 3) / 4) * r()
            let a7 = (-Double.pi * 3) / 4 - (Double.pi / 4) * r()
            ang = [0, -Double.pi / 2, a2, a3, a4, (Double.pi * 3) / 4, -Double.pi / 4, a7, -Double.pi / 4]
        }
        let len = lenIn.map { $0 * sca }
        var yoff = yoffIn
        func grot(_ ind: Int) -> Double {
            var rot = 0.0
            for p in ShanShuiEngine.chains[ind] { rot += ang[p] }
            return rot
        }
        func gpos(_ ind: Int) -> P {
            var pos = P(0, 0)
            for p in ShanShuiEngine.chains[ind] {
                let a = grot(p)
                pos.x += len[p] * cos(a)
                pos.y += len[p] * sin(a)
            }
            return pos
        }
        let pts = (0..<ang.count).map { gpos($0) }
        yoff -= pts[4].y
        let yo = yoff
        let sgn: Double = fli ? -1 : 1
        func toGlobal(_ v: P) -> P { P(sgn * v.x + xoff, v.y + yo) }

        var canv: ZXArt.SSCanv = []
        func cloth(_ plist: [P], _ fun: (Double) -> Double) -> ZXArt.SSCanv {
            var c: ZXArt.SSCanv = []
            let tlist = ZXArt.bezmh(plist, 2)
            _ = r()  // expand(): n0 = Math.random()*10 (unused)
            let (t1, t2raw) = ZXArt.tubify(tlist, fun)
            let t2 = Array(t2raw.reversed())  // tlist2.reverse() 原地反转, 下面的描边也用反转后的
            c.append(poly((t1 + t2).map(toGlobal), fil: .white, str: .white))
            c += stroke(t1.map(toGlobal), wid: 1, col: .ink(0.5))
            c += stroke(t2.map(toGlobal), wid: 1, col: .ink(0.6))
            return c
        }
        let fsleeve: (Double) -> Double = { x in
            sca * 8 * (sin(0.5 * x * Double.pi) * pow(sin(x * Double.pi), 0.1) + (1 - x) * 0.4)
        }
        let fbody: (Double) -> Double = { x in
            sca * 11 * (sin(0.5 * x * Double.pi) * pow(sin(x * Double.pi), 0.1) + (1 - x) * 0.5)
        }
        let fhead: (Double) -> Double = { x in sca * 7 * pow(0.25 - pow(x - 0.5, 2), 0.3) }

        if ite == .stick01 { canv += stick01(toGlobal(pts[8]), toGlobal(pts[6]), fli: fli) }
        canv += cloth([pts[1], pts[7], pts[8]], fsleeve)
        canv += cloth([pts[1], pts[0], pts[3], pts[4]], fbody)
        canv += cloth([pts[1], pts[5], pts[6]], fsleeve)
        canv += cloth([pts[1], pts[2]], fhead)

        let hlist = ZXArt.bezmh([pts[1], pts[2]], 2)
        _ = r()  // expand() n0
        var (h1, h2) = ZXArt.tubify(hlist, fhead)
        h1.removeFirst(Int((Double(h1.count) * 0.1).rounded(.down)))
        h2.removeFirst(Int((Double(h2.count) * 0.95).rounded(.down)))
        canv.append(poly((h1 + h2.reversed()).map(toGlobal), fil: .ink(0.6), str: .ink(0.6)))

        switch hat {
        case .hat01: canv += hat01(toGlobal(pts[1]), toGlobal(pts[2]), fli: fli)
        case .hat02: canv += hat02(toGlobal(pts[1]), toGlobal(pts[2]), fli: fli)
        }
        return canv
    }
}
