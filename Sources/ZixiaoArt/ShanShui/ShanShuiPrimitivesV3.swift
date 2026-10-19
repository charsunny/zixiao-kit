// @3 笔触 / 皴 / 水: 独立于冻结原语; 旧轮廓仅作构图骨架。
// MIT derived layout math: (c) 2018 Lingdong Huang; see ZXArtLicenses.swift.
import Foundation

extension ShanShuiEngine {
    func strokeV3(_ ptlist: [P], xof: Double = 0, yof: Double = 0, wid: Double = 2,
                col: C = C(200, 200, 200, 0.9), noi: Double = 0.5, out: Double = 1,
                fun: (Double) -> Double = ShanShuiEngine.sinFun,
                profile: ZXArt.Brush.Profile? = nil, dry: Double = 0.42) -> ZXArt.SSCanv {
        if ptlist.isEmpty { return [] }
        let n0 = r() * 10
        let cnt = ptlist.count
        var v0: [P] = [], v1: [P] = []
        if cnt > 2 {
            v0.reserveCapacity(cnt); v1.reserveCapacity(cnt)
            for i in 1..<(cnt - 1) {
                var w = wid * fun(Double(i) / Double(cnt))
                w = w * (1 - noi) + w * noi * n(Double(i) * 0.5, n0)
                let a1 = atan2(ptlist[i].y - ptlist[i - 1].y, ptlist[i].x - ptlist[i - 1].x)
                let a2 = atan2(ptlist[i].y - ptlist[i + 1].y, ptlist[i].x - ptlist[i + 1].x)
                var a = (a1 + a2) / 2
                if a < a2 { a += Double.pi }
                v0.append(P(ptlist[i].x + w * cos(a), ptlist[i].y + w * sin(a)))
                v1.append(P(ptlist[i].x - w * cos(a), ptlist[i].y - w * sin(a)))
            }
        }
        var vtx: [P] = []
        vtx.reserveCapacity(v0.count + v1.count + 3)
        vtx.append(ptlist[0])
        vtx += v0
        vtx.append(ptlist[cnt - 1])
        vtx += v1.reversed()
        vtx.append(ptlist[0])
        var legacy = poly(xof == 0 && yof == 0 ? vtx : vtx.map { P($0.x + xof, $0.y + yof) }, fil: col, str: col, wid: out)
        // 原 n0 的 32 位量化是本笔唯一随机种子。保留上面的旧轮廓以冻结 fit / cull。
        let seed = UInt32((n0 / 10 * 4_294_967_296).rounded(.down))
        let chosen = profile ?? profileV3(fun)
        let tone = ZXArt.Brush.unit(col.a * (1 - col.r / 255))
        let style = ZXArt.Brush.Style(width: max(0.25, wid * 1.65), tone: tone, dry: dry, wet: 0.28,
                                      side: 0.72, darkDirection: SIMD2(1, 0.35), rough: noi * 0.32,
                                      profile: chosen)
        let centerline = profile == .tip ? cunCenterlineV3(ptlist, seed: seed) : ptlist
        legacy.paintV3 = .stroke(pathV3(centerline.map { P($0.x + xof, $0.y + yof) },
                                       origin: legacy.p[0], style: style, seed: seed, keepsFill: false))
        return [legacy]
    }

    func textureV3(_ ptlist: [[P]], xof: Double = 0, yof: Double = 0, tex: Double = 400, wid: Double = 1.5,
                 len: Double = 0.2, sha: Double = 0,
                 noi: (Double) -> Double = { 30 / $0 },
                 col: ((Double) -> C)? = nil,
                 dis: (() -> Double)? = nil) -> ZXArt.SSCanv {
        let colF: (Double) -> C = col ?? { _ in C.ink(self.r() * 0.3) }
        let disF: () -> Double = dis ?? {
            if self.r() > 0.5 { return (1.0 / 3) * self.r() } else { return (1.0 * 2) / 3 + (1.0 / 3) * self.r() }
        }
        let reso0 = ptlist.count, reso1 = ptlist[0].count
        var texlist: [[P]] = []
        var i = 0.0
        while i < tex {
            let mid = ZXArt.or0(disF() * Double(reso1))
            let hlen = Int((r() * (Double(reso1) * len)).rounded(.down))
            let start = min(max(mid - hlen, 0), reso1)
            let end = min(max(mid + hlen, 0), reso1)
            let layer = (i / tex) * Double(reso0 - 1)
            var row: [P] = []
            if start < end {
                row.reserveCapacity(end - start)
                let lf = Int(layer.rounded(.down)), lc = Int(layer.rounded(.up))
                let p = layer - layer.rounded(.down)
                for j in start..<end {
                    let x = ptlist[lf][j].x * p + ptlist[lc][j].x * (1 - p)
                    let y = ptlist[lf][j].y * p + ptlist[lc][j].y * (1 - p)
                    let nx = noi(layer + 1) * (n(x, Double(j) * 0.5) - 0.5)
                    let ny = noi(layer + 1) * (n(y, Double(j) * 0.5) - 0.5)
                    row.append(P(x + nx, y + ny))
                }
            }
            texlist.append(row)
            i += 1
        }
        var canv: ZXArt.SSCanv = []
        func off(_ l: [P]) -> [P] { l.map { P($0.x + xof, $0.y + yof) } }
        if sha != 0 {
            var j = 0
            while j < texlist.count {
                canv += strokeV3(off(texlist[j]), wid: sha, col: .gray(100, 0.1), profile: .tip, dry: 0.8)
                j += 1 + 1
            }
        }
        var j = Int(sha)
        let step = 1 + Int(sha)
        while j < texlist.count {
            let c = colF(Double(j) / Double(texlist.count))
            canv += strokeV3(off(texlist[j]), wid: wid, col: c, profile: .tip, dry: 0.6 + 0.2 * Double(j % 7) / 6)
            j += step
        }
        return canv
    }

    func waterV3(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 2, len: Double = 800,
               clu: Int = 10) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        var ptlist: [[P]] = []
        var yk = 0.0
        for _ in 0..<clu {
            var row: [P] = []
            let xk = (r() - 0.5) * (len / 8)
            yk += r() * 5
            let lk = len / 4 + r() * (len / 4)
            let reso = 5.0
            var j = -lk
            while j < lk {
                row.append(P(j + xk, sin(j * 0.2) * hei * n(j * 0.1) - 20 + yk))
                j += reso
            }
            ptlist.append(row)
        }
        for j in 1..<ptlist.count {
            let c = C.ink(0.3 + r() * 0.3)
            var line = strokeV3(ptlist[j].map { P($0.x + xoff, $0.y + yoff) }, wid: 1, col: C.gray(100, c.a * 0.2), profile: .brush, dry: 0.7)
            for k in line.indices { line[k].fil = c; line[k].str = c }
            if j > 3 { line = line.map { var p = $0; p.paintV3 = .omit; return p } }
            canv += line
        }
        return canv
    }

}
