// @3 隔离副本: 保留 @2 的循环、表达式与求值顺序; 只给旧几何附加画法。
//  ShanShuiTreesV3.swift — 构图用的三类树 (tree01V3 / tree02V3 / tree03V3)
//
//  Ported from shan-shui-inf index.html (`var Tree = new function(){…}`).
//  MIT License, (c) 2018 Lingdong Huang — https://github.com/LingDong-/shan-shui-inf
//  Full license text: ZXArtLicenses.swift / LICENSES/.
//
import Foundation
import ZixiaoColor

extension ShanShuiEngine {
    // MARK: tree01V3 — 远处的小树 (两条细线 + 叶团)

    func tree01V3(_ x: Double, _ y: Double, hei: Double = 50, wid: Double = 3,
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
        canv.append(trunkV3(line1, fil: nil, str: col, wid: 1.5))
        canv.append(trunkV3(line2, fil: nil, str: col, wid: 1.5))
        return canv
    }

    // MARK: tree02V3 — 苔点 / 远树团

    static let fun02V3: @Sendable (Double) -> Double = { x in
        x <= 1 ? pow(sin(x * Double.pi) * x, 0.5) : -pow(sin((x - 2) * Double.pi * (x - 2)), 0.5)
    }

    func tree02V3(_ x: Double, _ y: Double, hei: Double = 16, wid: Double = 8, clu: Double = 5,
                col: C = .ink(0.5)) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        var i = 0.0
        while i < clu {
            let bx = x + e.randGaussian() * clu * 4
            let by = y + e.randGaussian() * clu * 4
            let bw = r() * wid * 0.75 + wid * 0.5
            let bl = r() * hei * 0.75 + hei * 0.5
            canv += blob(bx, by, len: bl, wid: bw, ang: Double.pi / 2, col: col, fun: ShanShuiEngine.fun02V3)
            i += 1
        }
        return canv
    }

    // MARK: tree03V3 — 山脚的树 (白底树干 + 叶团)

    func tree03V3(_ x: Double, _ y: Double, hei: Double = 50, wid: Double = 5,
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
        let centerline = zip(line1, line2).map { a, b in P((a.x + b.x) / 2, (a.y + b.y) / 2) }
        canv.append(trunkV3(line1 + line2.reversed(), fil: .white, str: col, wid: 1.5, centerline: centerline))
        canv += blobs
        return canv
    }

}
