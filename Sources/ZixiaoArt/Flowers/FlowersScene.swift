//  FlowersScene.swift — 花卉的参数空间 (genParams)、木本 / 草本、纸、构图与公开 API
//
//  Ported from nonflowers main.js (genParams, woody, herbal, paper, generate).
//  MIT License, (c) 2018 Lingdong Huang — https://github.com/LingDong-/nonflowers
//  Full license text: ZXArtLicenses.swift / LICENSES/.
//
//  随机序列与原网页一致: seed → paper(背景) → paper(画布) → 抛硬币 (木本 / 草本) → genParams
//  → woody / herbal。`Season.none` 时整株与原作逐多边形相同 (见对拍测试); 选了季节预设
//  则在 genParams 之后改写部分参数 (额外取随机数), 构成「梅 / 荷 / 菊 / 兰」式的造型。
//  删减: 原作最后用 squircle 把画面裁成圆角方; 这里满幅, 圆角交给系统 (小组件 / 锁屏)。

import CoreGraphics
import Foundation
import ZixiaoColor

// MARK: - 参数

extension FlowersEngine {
    struct PAR {
        var flowerChance = 0.0, leafChance = 0.0
        var leafType: [Double] = [1, 3]
        var flowerShape: (Double) -> Double = { _ in 0 }
        var leafShape: (Double) -> Double = { _ in 0 }
        var flowerColor = ZXArt.HSVRange(min: [0, 0, 0, 1], max: [0, 0, 0, 1])
        var leafColor = ZXArt.HSVRange(min: [0, 0, 0, 1], max: [0, 0, 0, 1])
        var flowerOpenCurve: (Double, Double) -> Double = { _, _ in 0 }
        var flowerColorCurve: (Double) -> Double = { $0 }
        var leafLength = 0.0, flowerLength = 0.0, pedicelLength = 0.0
        var leafWidth = 0.0, flowerWidth = 0.0
        var stemWidth = 0.0, stemBend = 0.0, stemLength = 0.0, stemCount = 0.0
        var sheathLength = 0.0, sheathWidth = 0.0, shootCount = 0.0, shootLength = 0.0
        var leafPosition = 1
        var flowerPetal = 0.0
        var innerLength = 0.0, innerWidth = 0.0
        var innerShape: (Double) -> Double = { pow(sin(Double.pi * $0), 1) }
        var innerColor = ZXArt.HSVRange(min: [0, 0, 0, 1], max: [0, 0, 0, 1])
        var branchWidth = 0.0, branchTwist = 0.0, branchDepth = 0.0, branchFork = 0.0
        var branchColor = ZXArt.HSVRange(min: [0, 0, 0, 1], max: [0, 0, 0, 1])
        /// 预设用: 子枝颜色 (原作子枝用缺省淡黄色; nil = 原作行为)。
        var childBranchColor: ZXArt.HSVRange? = nil
        /// 株型: 原作的木本 / 草本, 或季节预设自己的造型 (荷、菊)。
        var form: Form = .original
        enum Form { case original, lotus, chrysanthemum }
    }

    /// JS `Math.round` (.5 向 +∞)。
    static func jsRound(_ x: Double) -> Double {
        let f = x.rounded(.down)
        return x - f >= 0.5 ? f + 1 : f
    }

    static func sigmoid(_ x: Double, _ k: Double = 10) -> Double { 1 / (1 + exp(-k * (x - 0.5))) }

    func genParams() -> PAR {
        var P = PAR()
        let randint: (Double, Double) -> Double = { self.e.normRand($0, $1).rounded(.down) }
        let flowerShapeMask: (Double) -> Double = { pow(sin(Double.pi * $0), 0.2) }
        let leafShapeMask: (Double) -> Double = { pow(sin(Double.pi * $0), 0.5) }

        let fc = [e.normRand(0, 0.08), e.normRand(0, 0.03)]
        P.flowerChance = e.choice(fc)
        let lc = [0, e.normRand(0, 0.1), e.normRand(0, 0.1)]
        P.leafChance = e.choice(lc)
        let lt = [[1, randint(2, 5)], [2, randint(3, 7), randint(3, 8)], [2, randint(3, 7), randint(3, 8)]]
        P.leafType = e.choice(lt)

        let flowerShapeNoiseSeed = r() * Double.pi
        let flowerJaggedness = e.normRand(0.5, 8)
        P.flowerShape = { x in self.n(x * flowerJaggedness, flowerShapeNoiseSeed) * flowerShapeMask(x) }

        _ = r() * Double.pi  // leafShapeNoiseSeed (原作算了但没用上 —— 下面误用了 flowerShapeNoiseSeed)
        let leafJaggedness = e.normRand(0.1, 40)
        let leafPointyness = e.normRand(0.5, 1.5)
        let leafShapes: [(Double) -> Double] = [
            { x in self.n(x * leafJaggedness, flowerShapeNoiseSeed) * leafShapeMask(x) },
            { x in pow(sin(Double.pi * x), leafPointyness) },
        ]
        P.leafShape = e.choice(leafShapes)

        let flowerHue0 = (e.normRand(0, 180) - 130 + 360).truncatingRemainder(dividingBy: 360)
        let flowerHue1 = ((flowerHue0 + e.normRand(-70, 70) + 360).truncatingRemainder(dividingBy: 360)).rounded(.down)
        let flowerValue0 = min(1, e.normRand(0.5, 1.3))
        let flowerValue1 = min(1, e.normRand(0.5, 1.3))
        let flowerSaturation0 = e.normRand(0, 1.1 - flowerValue0)
        let flowerSaturation1 = e.normRand(0, 1.1 - flowerValue1)
        let fcMinA = e.normRand(0.8, 1)
        let fcMaxA = e.normRand(0.5, 1)
        P.flowerColor = ZXArt.HSVRange(min: [flowerHue0, flowerSaturation0, flowerValue0, fcMinA],
                                       max: [flowerHue1, flowerSaturation1, flowerValue1, fcMaxA])
        let lcMin = [e.normRand(10, 200), e.normRand(0.05, 0.4), e.normRand(0.3, 0.7), e.normRand(0.8, 1)]
        let lcMax = [e.normRand(10, 200), e.normRand(0.05, 0.4), e.normRand(0.3, 0.7), e.normRand(0.8, 1)]
        P.leafColor = ZXArt.HSVRange(min: lcMin, max: lcMax)

        let cc0 = [e.normRand(-0.5, 0.5), e.normRand(5, 10)]
        _ = [r() * Double.pi, e.normRand(1, 5)]  // curveCoeff1 (未用)
        let cc2 = [r() * Double.pi, e.normRand(5, 15)]
        _ = [r() * Double.pi, e.normRand(1, 5)]  // curveCoeff3 (未用)
        let cc4 = [r() * 0.5, e.normRand(0.8, 1.2)]
        let curves: [(Double, Double) -> Double] = [
            { x, op in x < 0.1 ? 2 + op * cc2[1] : self.n(x * 10, cc2[0]) },
            { x, op in x < cc4[0] ? 0 : 10 - x * ZXArt.mapval(op, 0, 1, 16, 20) * cc4[1] },
        ]
        P.flowerOpenCurve = e.choice(curves)
        let colorCurves: [(Double) -> Double] = [{ x in FlowersEngine.sigmoid(x + cc0[0], cc0[1]) }]
        P.flowerColorCurve = e.choice(colorCurves)

        P.leafLength = e.normRand(30, 100)
        P.flowerLength = e.normRand(5, 55)
        P.pedicelLength = e.normRand(5, 30)
        P.leafWidth = e.normRand(5, 30)
        P.flowerWidth = e.normRand(5, 30)
        P.stemWidth = e.normRand(2, 11)
        P.stemBend = e.normRand(2, 16)
        P.stemLength = e.normRand(300, 400)
        P.stemCount = e.choice([2.0, 3, 4, 5])
        let sl = [0, e.normRand(50, 100)]
        P.sheathLength = e.choice(sl)
        P.sheathWidth = e.normRand(5, 15)
        P.shootCount = e.normRand(1, 7)
        P.shootLength = e.normRand(50, 180)
        P.leafPosition = e.choice([1, 2])
        P.flowerPetal = FlowersEngine.jsRound(ZXArt.mapval(P.flowerWidth, 5, 50, 10, 3))
        P.innerLength = min(e.normRand(0, 20), P.flowerLength * 0.8)
        let iw = [0, e.normRand(1, 8)]
        P.innerWidth = min(e.choice(iw), P.flowerWidth * 0.8)
        let innerHue = e.normRand(0, 60)
        let icMin = [innerHue, e.normRand(0.1, 0.7), e.normRand(0.5, 0.9), e.normRand(0.8, 1)]
        let icMax = [innerHue, e.normRand(0.1, 0.7), e.normRand(0.5, 0.9), e.normRand(0.5, 1)]
        P.innerColor = ZXArt.HSVRange(min: icMin, max: icMax)
        P.branchWidth = e.normRand(0.4, 1.3)
        P.branchTwist = FlowersEngine.jsRound(e.normRand(2, 5))
        P.branchDepth = e.choice([3.0, 4])
        P.branchFork = e.choice([4.0, 5, 6, 7])
        let bh = e.normRand(30, 60), bs = e.normRand(0.05, 0.3), bv = e.normRand(0.7, 0.9)
        P.branchColor = ZXArt.HSVRange(min: [bh, bs, bv, 1], max: [bh, bs, bv, 1])
        return P
    }
}

// MARK: - 木本 / 草本

extension FlowersEngine {
    typealias BranchList = [(Double, [V3])]

    func woody(_ P: PAR) {
        let cwid = 1200.0
        let PL = branch(0, BranchArgs(xof: cwid * 0.5, yof: cwid * 0.7, wid: P.branchWidth, twi: P.branchTwist,
                                      col: P.branchColor, dep: P.branchDepth, frk: P.branchFork),
                        childColor: P.childBranchColor)
        for i in 0..<PL.count where Double(i) / Double(PL.count) > 0.1 {
            let fi = Double(i)
            for j in 0..<PL[i].1.count {
                let pt = PL[i].1[j]
                if r() < P.leafChance {
                    var a = LeafArgs()
                    a.xof = pt.x; a.yof = pt.y
                    a.len = P.leafLength * e.normRand(0.8, 1.2)
                    a.vei = P.leafType
                    a.col = P.leafColor
                    a.rot = V3(e.normRand(-1, 1) * Double.pi, e.normRand(-1, 1) * Double.pi, e.normRand(-1, 1) * 0)
                    a.wid = { x in P.leafShape(x) * P.leafWidth }
                    a.ben = { x in
                        V3(ZXArt.mapval(self.n(x * 1, fi), 0, 1, -1, 1) * 5, 0,
                           ZXArt.mapval(self.n(x * 1, fi + Double.pi), 0, 1, -1, 1) * 5)
                    }
                    leaf(0, a)
                }
                if r() < P.flowerChance {
                    let hr = V3(e.normRand(-1, 1) * Double.pi, e.normRand(-1, 1) * Double.pi, e.normRand(-1, 1) * 0)
                    let Pp = stem(0, StemArgs(xof: pt.x, yof: pt.y, rot: hr, len: P.pedicelLength,
                                              wid: { x in sin(x * Double.pi) * x * 2 + 1 },
                                              col: ZXArt.HSVRange(min: [50, 1, 0.9, 1], max: [50, 1, 0.9, 1]),
                                              ben: { _ in V3(0, 0, 0) }))
                    let op = r()
                    let hhr = ZXArt.V3Math.toeuler(Pp[Pp.count - 1] - Pp[Pp.count - 2])
                    let tip = Pp[Pp.count - 1]
                    flowerHead(P, x: pt.x + tip.x, y: pt.y + tip.y, hhr: hhr, op: op, lengthScale: 1, widthScale: 1)
                }
            }
        }
    }

    private func flowerHead(_ P: PAR, x: Double, y: Double, hhr: V3, op: Double, lengthScale: Double, widthScale: Double) {
        var k = 0.0
        while k < P.flowerPetal {
            var a = LeafArgs()
            a.flo = true
            a.xof = x; a.yof = y
            a.rot = V3(hhr.x, hhr.y, hhr.z + k / P.flowerPetal * Double.pi * 2)
            if let seg = petalSeg { a.seg = seg }
            a.len = P.flowerLength * e.normRand(0.7, 1.3) * lengthScale
            a.wid = { xx in widthScale * P.flowerShape(xx) * P.flowerWidth }
            a.vei = [0]
            a.col = P.flowerColor
            a.cof = P.flowerColorCurve
            a.ben = { xx in V3(P.flowerOpenCurve(xx, op), 0, 0) }
            leaf(1, a)

            var b = LeafArgs()
            b.flo = true
            b.xof = x; b.yof = y
            b.rot = V3(hhr.x, hhr.y, hhr.z + k / P.flowerPetal * Double.pi * 2)
            if let seg = petalSeg { b.seg = max(4, seg / 2) }
            b.len = P.innerLength * e.normRand(0.8, 1.2)
            b.wid = { xx in sin(xx * Double.pi) * 4 }
            b.vei = [0]
            b.col = P.innerColor
            b.cof = { $0 }
            b.ben = { xx in V3(P.flowerOpenCurve(xx, op), 0, 0) }
            leaf(1, b)
            k += 1
        }
    }

    func herbal(_ P: PAR) {
        let cwid = 1200.0
        let x0 = cwid * 0.5, y0 = cwid * 0.7
        var i = 0.0
        while i < P.stemCount {
            let fi = i
            let rot = V3(Double.pi / 2, 0, e.normRand(-1, 1) * Double.pi)
            let len = P.stemLength * e.normRand(0.7, 1.3)
            let Ps = stem(0, StemArgs(xof: x0, yof: y0, rot: rot, len: len,
                                      wid: { x in P.stemWidth * (pow(sin(x * Double.pi / 2 + Double.pi / 2), 0.5) * self.n(x * 10) * 0.5 + 0.5) },
                                      ben: { x in
                                          V3(ZXArt.mapval(self.n(x * 1, fi), 0, 1, -1, 1) * x * P.stemBend, 0,
                                             ZXArt.mapval(self.n(x * 1, fi + Double.pi), 0, 1, -1, 1) * x * P.stemBend)
                                      }))
            if P.leafPosition == 2 {
                for j in 0..<Ps.count where r() < P.leafChance * 2 {
                    var a = LeafArgs()
                    a.xof = x0 + Ps[j].x; a.yof = y0 + Ps[j].y
                    a.len = 2 * P.leafLength * e.normRand(0.8, 1.2)
                    a.vei = P.leafType
                    a.col = P.leafColor
                    a.rot = V3(e.normRand(-1, 1) * Double.pi, e.normRand(-1, 1) * Double.pi, e.normRand(-1, 1) * 0)
                    a.wid = { x in 2 * P.leafShape(x) * P.leafWidth }
                    a.ben = { x in
                        V3(ZXArt.mapval(self.n(x * 1, fi), 0, 1, -1, 1) * 5, 0,
                           ZXArt.mapval(self.n(x * 1, fi + Double.pi), 0, 1, -1, 1) * 5)
                    }
                    leaf(0, a)
                }
            }
            let tip = Ps[Ps.count - 1]
            let hr = ZXArt.V3Math.toeuler(tip - Ps[Ps.count - 2])
            if P.sheathLength != 0 {
                stem(0, StemArgs(xof: x0 + tip.x, yof: y0 + tip.y, rot: hr, len: P.sheathLength,
                                 wid: { x in P.sheathWidth * (pow(sin(x * Double.pi), 2) - x * 0.5 + 0.5) },
                                 col: ZXArt.HSVRange(min: [60, 0.3, 0.9, 1], max: [60, 0.3, 0.9, 1]),
                                 ben: { _ in V3(0, 0, 0) }))
            }
            var j = 0.0
            while j < max(1, P.shootCount * e.normRand(0.5, 1.5)) {
                let fj = j
                let slen = P.shootLength * e.normRand(0.5, 1.5)
                let Pq = stem(0, StemArgs(xof: x0 + tip.x, yof: y0 + tip.y, rot: hr, len: slen,
                                          wid: { _ in 2 },
                                          col: ZXArt.HSVRange(min: [70, 0.2, 0.9, 1], max: [70, 0.2, 0.9, 1]),
                                          ben: { x in
                                              V3(ZXArt.mapval(self.n(x * 1, fj), 0, 1, -1, 1) * x * 10, 0,
                                                 ZXArt.mapval(self.n(x * 1, fj + Double.pi), 0, 1, -1, 1) * x * 10)
                                          }))
                let op = r()
                let hhr = V3(e.normRand(-1, 1) * Double.pi, e.normRand(-1, 1) * Double.pi, e.normRand(-1, 1) * Double.pi)
                let qt = Pq[Pq.count - 1]
                flowerHead(P, x: x0 + tip.x + qt.x, y: y0 + tip.y + qt.y, hhr: hhr, op: op, lengthScale: 1.5, widthScale: 1.5)
                j += 1
            }
            i += 1
        }
        if P.leafPosition == 1 {
            var k = 0.0
            while k < P.leafChance * 100 {
                let fk = k
                var a = LeafArgs()
                a.xof = x0; a.yof = y0
                a.rot = V3(Double.pi / 3, 0, e.normRand(-1, 1) * Double.pi)
                a.len = 4 * P.leafLength * e.normRand(0.8, 1.2)
                a.wid = { x in 2 * P.leafShape(x) * P.leafWidth }
                a.vei = P.leafType
                a.ben = { x in
                    V3(ZXArt.mapval(self.n(x * 1, fk), 0, 1, -1, 1) * 10, 0,
                       ZXArt.mapval(self.n(x * 1, fk + Double.pi), 0, 1, -1, 1) * 10)
                }
                leaf(0, a)
                k += 1
            }
        }
    }

    /// branch() 带预设子枝色的包装 (childColor 为 nil 时与原作一致)。
    func branch(_ layer: Int, _ a: BranchArgs, childColor: ZXArt.HSVRange?) -> BranchList {
        childColorOverride = childColor
        defer { childColorOverride = nil }
        return branch(layer, a)
    }

    // MARK: paper

    /// `paper({col, tex, spr})` — 返回纹理 (往墨色偏的量)。`visit` 收到原作写进画布的 rgb (对拍用)。
    func paper(col: (Double, Double, Double), tex: Double, spr: Double,
               visit: ((Double, Double, Double) -> Void)? = nil) -> ZXArt.PaperTexture {
        let side = ZXArt.PaperTexture.side
        var shade = [UInt8](repeating: 0, count: side * side)
        func put(_ x: Int, _ y: Int, _ v: UInt8) {
            if x >= 0 && x < side && y >= 0 && y < side { shade[y * side + x] = v }
        }
        for i in 0...(side / 2) {
            for j in 0...(side / 2) {
                var c = 255 - n(Double(i) * 0.1, Double(j) * 0.1) * tex * 0.5
                c -= r() * tex
                var rr = c * col.0, gg = c * col.1, bb = c * col.2
                var spot = false
                if n(Double(i) * 0.04, Double(j) * 0.04, 2) * r() * spr > 0.7 || r() < 0.005 * spr {
                    rr = c * 0.7; gg = c * 0.5; bb = c * 0.2
                    spot = true
                }
                visit?(rr.rounded(.down), gg.rounded(.down), bb.rounded(.down))
                // 原作斑点是棕色 (c·0.7, c·0.5, c·0.2); 映射成偏墨的淡点, 不然镜像平铺的斑点图案太显眼。
                let v: UInt8 = spot ? UInt8(min(255.0, 38 + max(0, 255 - c))) : UInt8(min(max((255 - c).rounded(), 0), 255))
                put(i, j, v); put(side - i, j, v); put(i, side - j, v); put(side - i, side - j, v)
            }
        }
        return ZXArt.PaperTexture(shade: shade, texel: 1, strength: 1)
    }

    /// 原网页的完整随机序列: 背景纸 → 画布纸 → 硬币 → genParams。
    func pageSequence() -> (paper: ZXArt.PaperTexture, woody: Bool, par: PAR) {
        _ = paper(col: (1, 0.99, 0.9), tex: 10, spr: 0)
        let p = paper(col: (0.98, 0.91, 0.74), tex: 20, spr: 1)
        let woody = r() <= 0.5
        return (p, woody, genParams())
    }
}

// MARK: - 季节预设 (nonflowers@1)
//
// 预设在 genParams 之后改写参数 (额外取随机数), 构成「梅 / 荷 / 菊 / 兰」式的造型。荷与菊不用原作的
// 草本株型 (花头朝向随机、叶片乱扭), 而是各自的构图函数 (`lotus` / `chrysanthemum`), 只复用原作的
// 叶 / 茎 / 花瓣原语与着色。改动这里任何取数都会改变 nonflowers@1 的出图 —— 必须另开 @2。

extension FlowersEngine {
    func applySeason(_ season: ZXArt.Flowers.Season, _ P: inout PAR, woody: inout Bool, density: Double = 0.5) {
        let u = { self.r() }
        func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * u() }
        // density 0…1 (0.5 = 常态) → 数量倍率 0.6…1.4
        let dk = 0.6 + 0.8 * min(max(density, 0), 1)
        switch season {
        case .none:
            return
        case .plum:  // 梅: 老枝、先花后叶、五瓣粉白
            woody = true
            petalSeg = 12
            P.leafChance = 0
            P.flowerChance = range(0.05, 0.08) * dk
            P.flowerPetal = 5
            P.flowerLength = range(9, 13)
            P.flowerWidth = range(9, 12)
            P.flowerShape = { pow(sin(Double.pi * $0), 0.35) }
            let h = range(340, 358)
            P.flowerColor = ZXArt.HSVRange(min: [h, range(0.25, 0.45), 0.95, 0.95], max: [(h + 8).truncatingRemainder(dividingBy: 360), 0.05, 1, 0.9])
            P.flowerOpenCurve = { x, op in x < 0.15 ? 0 : 10 - x * ZXArt.mapval(op, 0, 1, 16, 20) * 1.0 }
            P.innerLength = range(3, 5)
            P.innerColor = ZXArt.HSVRange(min: [48, 0.7, 0.85, 1], max: [52, 0.5, 0.95, 0.9])
            let bh = range(15, 30)
            P.branchColor = ZXArt.HSVRange(min: [bh, 0.4, 0.22, 1], max: [bh, 0.4, 0.22, 1])
            P.childBranchColor = ZXArt.HSVRange(min: [bh, 0.35, 0.3, 1], max: [bh, 0.35, 0.3, 1])
            P.branchWidth = range(1.0, 1.3)
            P.branchDepth = 3
            P.branchFork = range(5, 7).rounded(.down)
            P.branchTwist = 4
        case .lotus:  // 荷: 一枝高擎的花 (杯状两轮瓣) + 一个花苞 (可无) + 一两张斜看的圆叶
            woody = false
            P.form = .lotus
            petalSeg = 16
            P.stemLength = range(400, 460)
            P.stemWidth = range(3.2, 4.2)
            P.stemCount = u() < 0.55 * dk ? 2 : 1          // 第二枝 = 花苞
            P.flowerPetal = (range(8, 10)).rounded(.down)
            P.flowerLength = range(62, 74)
            P.flowerWidth = range(22, 27)
            P.flowerShape = { x in pow(sin(Double.pi * x), 0.55) * (1 - 0.35 * x) + 0.08 * sin(Double.pi * x) }
            let h = range(335, 350)
            // lt: 瓣根 (0) → 瓣尖 (1): 近白 → 粉
            P.flowerColor = ZXArt.HSVRange(min: [h, 0.06, 1, 0.92], max: [(h + 6).truncatingRemainder(dividingBy: 360), 0.55, 0.93, 0.96])
            P.innerLength = range(9, 12)
            P.innerColor = ZXArt.HSVRange(min: [52, 0.75, 0.9, 1], max: [58, 0.5, 0.95, 1])
            P.leafChance = u() < 0.5 * dk ? 2 : 1          // 圆叶张数
            P.leafLength = range(120, 150)                 // 圆叶半径
            P.leafColor = ZXArt.HSVRange(min: [range(95, 110), 0.35, 0.38, 0.95], max: [range(80, 95), 0.25, 0.62, 0.95])
        case .chrysanthemum:  // 菊: 两三枝错落, 花头正面, 三轮细长瓣; 叶互生、裂片整齐
            woody = false
            P.form = .chrysanthemum
            petalSeg = 14
            P.stemCount = u() < 0.5 * dk ? 3 : 2
            P.stemLength = range(340, 420)
            P.stemWidth = range(2.6, 3.4)
            P.flowerPetal = (range(28, 34) * (0.8 + 0.25 * dk)).rounded(.down)
            P.flowerLength = range(44, 52)
            P.flowerWidth = range(2.8, 3.6)
            P.flowerShape = { x in pow(sin(Double.pi * x), 0.6) * (1 - 0.25 * x) }
            let h = range(36, 50)
            P.flowerColor = ZXArt.HSVRange(min: [h - 6, 0.9, 0.78, 1], max: [h + 6, 0.6, 1, 0.92])
            P.innerLength = range(5, 7)
            P.innerColor = ZXArt.HSVRange(min: [35, 0.8, 0.6, 1], max: [42, 0.7, 0.75, 1])
            P.leafChance = (range(3, 4.99) * dk).rounded(.down)   // 每枝叶数
            P.leafLength = range(44, 54)
            P.leafWidth = range(12, 15)
            // 羽状浅裂: 三角波做尖的裂片, 叶基收窄成柄
            P.leafShape = { x in
                let t = (x * 3.5).truncatingRemainder(dividingBy: 1)
                let tri = 1 - abs(t * 2 - 1)
                return pow(sin(Double.pi * x), 0.7) * min(1, x * 6) * (0.5 + 0.5 * pow(tri, 0.8))
            }
            P.leafType = [2, 3, 4]
            P.leafColor = ZXArt.HSVRange(min: [range(95, 115), 0.4, 0.28, 0.95], max: [range(80, 95), 0.35, 0.48, 0.95])
        case .orchid:  // 兰: 长而细的叶丛、疏花、淡绿白
            woody = false
            petalSeg = 16
            P.stemCount = u() < 0.5 ? 1 : 2
            P.stemLength = range(230, 300)
            P.stemWidth = range(2, 3)
            P.stemBend = range(6, 10)
            P.sheathLength = 0
            P.shootCount = range(3, 5)
            P.shootLength = range(30, 60)
            P.flowerPetal = u() < 0.5 ? 5 : 6
            P.flowerLength = range(18, 24)
            P.flowerWidth = range(7, 9)
            P.flowerShape = { pow(sin(Double.pi * $0), 0.5) }
            P.flowerColor = ZXArt.HSVRange(min: [range(70, 90), 0.3, 0.9, 0.95], max: [60, 0.08, 1, 0.9])
            P.innerLength = range(5, 7)
            P.innerColor = ZXArt.HSVRange(min: [320, 0.45, 0.55, 1], max: [330, 0.3, 0.7, 1])
            P.leafPosition = 1
            P.leafChance = range(0.08, 0.1) * dk
            P.leafLength = range(85, 100)
            P.leafWidth = range(4.5, 6)
            P.leafShape = { pow(sin(Double.pi * $0), 0.5) }
            P.leafType = [1, 2]
            P.leafColor = ZXArt.HSVRange(min: [range(95, 115), 0.4, 0.35, 0.95], max: [range(80, 95), 0.3, 0.6, 0.95])
        }
    }

    /// 叶片正对观者、朝画面角度 ψ (y 向下) 伸出的欧拉角 (推导: roteuler 先 z 后 x 再 y;
    /// z = π/2, y = π/2 时 forward = (cos x, −sin x, 0), 叶宽方向在画面内与之垂直)。
    static func flatRot(_ psi: Double, twist: Double = 0, tilt: Double = 0) -> V3 {
        V3(-psi, Double.pi / 2 + tilt, Double.pi / 2 + twist)
    }

    /// 花瓣一轮: `count` 瓣绕花轴均匀排开; `open` = 瓣根张开角 (弧度), `curl` = 其后再弯的角度
    /// (正 = 继续外翻, 负 = 瓣尖内扣)。返回 (瓣, 深度) 供按远近排序。
    struct Petal { var rot: V3; var len: Double; var wid: Double; var open: Double; var curl: Double; var depth: Double }

    func ring(_ P: PAR, axis hhr: V3, count: Int, len: Double, wid: Double, open: Double, curl: Double,
              phase: Double) -> [Petal] {
        var out: [Petal] = []
        for k in 0..<count {
            let th = (Double(k) + phase) / Double(count) * 2 * Double.pi + e.normRand(-0.08, 0.08)
            let rot = V3(hhr.x, hhr.y, hhr.z + th)
            let l = len * e.normRand(0.88, 1.12)
            let o = open * e.normRand(0.9, 1.1)
            // 瓣中段的方向 → 深度 (观者在 −z)
            let mid = ZXArt.V3Math.roteuler(ZXArt.V3Math.roteuler(V3(0, 0, 1), V3(o + curl * 0.5, 0, 0)), rot)
            out.append(Petal(rot: rot, len: l, wid: wid, open: o, curl: curl, depth: mid.z))
        }
        return out
    }

    /// 画一片花瓣 (原作 leaf 的 flo 模式: 颜色按瓣根 → 瓣尖渐变)。
    func petal(_ P: PAR, _ p: Petal, x: Double, y: Double, col: ZXArt.HSVRange, shape: @escaping (Double) -> Double) {
        var a = LeafArgs()
        a.flo = true
        a.xof = x; a.yof = y
        a.rot = p.rot
        a.seg = petalSeg ?? 40
        a.len = p.len
        let w = p.wid
        a.wid = { shape($0) * w }
        a.vei = [0]
        a.col = col
        a.cof = { $0 }
        // 前 15% 段把瓣根张到 open, 其余均匀弯 curl
        let o = p.open, c = p.curl
        a.ben = { xx in V3(xx < 0.15 ? o / 0.15 : c / 0.85, 0, 0) }
        leaf(1, a)
    }

    /// 由远到近画一组花瓣。
    func drawPetals(_ P: PAR, _ petals: [Petal], x: Double, y: Double, col: ZXArt.HSVRange,
                    shape: @escaping (Double) -> Double) {
        let order = petals.indices.sorted { petals[$0].depth != petals[$1].depth ? petals[$0].depth > petals[$1].depth : $0 < $1 }
        for i in order { petal(P, petals[i], x: x, y: y, col: col, shape: shape) }
    }

    /// 二次贝塞尔中心线 (画布坐标, z = 0)。
    static func curve(_ a: (Double, Double), _ c: (Double, Double), _ b: (Double, Double), segments n: Int) -> [V3] {
        (0...n).map { i in
            let t = Double(i) / Double(n), u = 1 - t
            return V3(u * u * a.0 + 2 * u * t * c.0 + t * t * b.0, u * u * a.1 + 2 * u * t * c.1 + t * t * b.1, 0)
        }
    }

    // MARK: 荷

    func lotus(_ P: PAR) {
        let x0 = 600.0, y0 = 840.0
        let side: Double = r() < 0.5 ? -1 : 1   // 花偏哪边; 叶在另一边
        let stemCol = ZXArt.HSVRange(min: [95, 0.3, 0.45, 1], max: [85, 0.25, 0.6, 1])
        // 圆叶 (先画, 在后面)
        let leaves = Int(P.leafChance)
        for k in 0..<leaves {
            let fk = Double(k)
            let R = P.leafLength * (k == 0 ? 1 : 0.72) * e.normRand(0.92, 1.08)
            let cx = x0 - side * (fk == 0 ? e.normRand(70, 130) : -e.normRand(90, 150))
            let cy = y0 - (fk == 0 ? e.normRand(150, 210) : e.normRand(60, 110))
            let base = (x0 + e.normRand(-12, 12), y0)
            let ctrl = ((base.0 + cx) / 2 + e.normRand(-30, 30), (base.1 + cy) / 2)
            let stalk = FlowersEngine.curve((0, 0), (ctrl.0 - base.0, ctrl.1 - base.1), (cx - base.0, cy - base.1), segments: 24)
            tube(0, stalk, xof: base.0, yof: base.1, wid: { _ in P.stemWidth * 0.8 }, col: stemCol, clampShade: true)
            lotusLeaf(0, cx: cx, cy: cy, R: R, tilt: e.normRand(0.38, 0.62), roll: e.normRand(-0.18, 0.18),
                      col: P.leafColor, seed: r() * 10)
        }
        // 花苞 (可无): 较矮的一枝, 花偏的另一侧
        if P.stemCount >= 2 {
            let tx = x0 - side * e.normRand(50, 90), ty = y0 - P.stemLength * e.normRand(0.55, 0.7)
            let stalk = FlowersEngine.curve((0, 0), (e.normRand(-20, 20), (ty - y0) * 0.5), (tx - x0, ty - y0), segments: 30)
            tube(0, stalk, xof: x0, yof: y0, wid: { x in P.stemWidth * (1 - 0.3 * x) }, col: stemCol, clampShade: true)
            let dir = stalk[stalk.count - 1] - stalk[stalk.count - 3]
            let axis = ZXArt.V3Math.toeuler(V3(dir.x, dir.y, -0.25 * ZXArt.V3Math.mag(dir)))
            let petals = ring(P, axis: axis, count: 5, len: P.flowerLength * 0.62, wid: P.flowerWidth * 0.8, open: 0.16,
                              curl: -0.12, phase: 0)
            var bud = P.flowerColor
            bud.min[1] = 0.2; bud.max[1] = 0.62
            drawPetals(P, petals, x: tx, y: ty, col: bud, shape: P.flowerShape)
        }
        // 花: 高擎, 微向观者倾, 两轮杯状瓣 + 黄蕊
        let fx = x0 + side * e.normRand(20, 60), fy = y0 - P.stemLength
        let stalk = FlowersEngine.curve((0, 0), (side * e.normRand(-30, 10), -P.stemLength * 0.5), (fx - x0, fy - y0), segments: 40)
        tube(0, stalk, xof: x0, yof: y0, wid: { x in P.stemWidth * (1.1 - 0.35 * x) }, col: stemCol, clampShade: true)
        let dir = stalk[stalk.count - 1] - stalk[stalk.count - 3]
        let axis = ZXArt.V3Math.toeuler(V3(dir.x, dir.y, -0.55 * ZXArt.V3Math.mag(dir)))
        let n = Int(P.flowerPetal)
        let outer = ring(P, axis: axis, count: n, len: P.flowerLength, wid: P.flowerWidth, open: 0.95, curl: -0.3, phase: 0)
        let inner = ring(P, axis: axis, count: max(5, n - 3), len: P.flowerLength * 0.8, wid: P.flowerWidth * 0.9,
                         open: 0.5, curl: -0.3, phase: 0.5)
        drawPetals(P, outer.filter { $0.depth > 0 }, x: fx, y: fy, col: P.flowerColor, shape: P.flowerShape)
        drawPetals(P, inner.filter { $0.depth > 0 }, x: fx, y: fy, col: P.flowerColor, shape: P.flowerShape)
        // 莲蓬 / 蕊
        let stamens = ring(P, axis: axis, count: 12, len: P.innerLength, wid: 2.2, open: 0.5, curl: 0.2, phase: 0.25)
        drawPetals(P, stamens, x: fx, y: fy, col: P.innerColor, shape: { sin(Double.pi * $0) })
        drawPetals(P, inner.filter { $0.depth <= 0 }, x: fx, y: fy, col: P.flowerColor, shape: P.flowerShape)
        drawPetals(P, outer.filter { $0.depth <= 0 }, x: fx, y: fy, col: P.flowerColor, shape: P.flowerShape)
    }

    /// 荷叶: 浅碗形圆盘 (边缘起伏), 斜看成椭圆; 按法线着色, 放射叶脉, 叶缘描一圈。
    func lotusLeaf(_ layer: Int, cx: Double, cy: Double, R: Double, tilt: Double, roll: Double,
                   col: ZXArt.HSVRange, seed: Double) {
        let nPhi = 30, nRho = 5
        let rot = V3(tilt, 0, roll)
        func local(_ rho: Double, _ phi: Double) -> V3 {
            let wave = 0.07 * R * sin(phi * 5 + seed) * rho * rho
            let bowl = 0.12 * R * rho * rho
            // 圆盘在 xz 平面 (法线 = y), 边缘上翘 (−y)
            let v = V3(R * rho * cos(phi), -(bowl + wave), R * rho * sin(phi))
            return ZXArt.V3Math.roteuler(v, rot)
        }
        var grid: [[V3]] = []
        for i in 0...nRho {
            let rho = Double(i) / Double(nRho)
            grid.append((0..<nPhi).map { j in local(rho, Double(j) / Double(nPhi) * 2 * Double.pi) })
        }
        struct Quad { var pts: [V3]; var depth: Double }
        var quads: [Quad] = []
        for i in 0..<nRho {
            for j in 0..<nPhi {
                let j1 = (j + 1) % nPhi
                let q = [grid[i][j], grid[i + 1][j], grid[i + 1][j1], grid[i][j1]]
                quads.append(Quad(pts: q, depth: (q[0].z + q[1].z + q[2].z + q[3].z) / 4))
            }
        }
        let order = quads.indices.sorted { quads[$0].depth != quads[$1].depth ? quads[$0].depth > quads[$1].depth : $0 < $1 }
        for qi in order {
            let q = quads[qi].pts
            let nrm = ZXArt.V3Math.cross(q[1] - q[0], q[3] - q[0])
            var lt = ZXArt.mapval(abs(ZXArt.V3Math.ang(nrm, V3(0, -1, 0))), 0, Double.pi, 1, 0)
            if lt.isNaN { lt = 0.5 }
            lt = min(max(lt + e.normRand(-0.04, 0.04), 0), 1)
            let h = ZXArt.lerpHue(col.min[0], col.max[0], lt)
            let c = ZXArt.hsv(h, ZXArt.mapval(lt, 0, 1, col.min[1], col.max[1]),
                              ZXArt.mapval(lt, 0, 1, col.min[2], col.max[2]),
                              ZXArt.mapval(lt, 0, 1, col.min[3], col.max[3]))
            polygon(layer, q, xof: cx, yof: cy, col: c, fil: true, str: true)
        }
        // 叶脉: 从叶心放射
        var j = 0
        while j < nPhi {
            let pts = (0...nRho).map { grid[$0][j] }
            polygon(layer, pts, xof: cx, yof: cy, col: ZXArt.hsv(0, 0, 0, e.normRand(0.2, 0.4)), fil: false, str: true)
            j += 2
        }
        // 叶缘
        let rim = grid[nRho] + [grid[nRho][0]]
        polygon(layer, rim, xof: cx, yof: cy, col: ZXArt.fcolor(120, 100, 0, 0.35), fil: false, str: true)
    }

    // MARK: 菊

    func chrysanthemum(_ P: PAR) {
        let x0 = 600.0, y0 = 840.0
        let n = Int(P.stemCount)
        let stemCol = ZXArt.HSVRange(min: [95, 0.28, 0.4, 1], max: [85, 0.22, 0.55, 1])
        // 枝: 由中间向两侧张开, 高低错落 (中间最高)
        var tips: [(x: Double, y: Double, dir: V3)] = []
        var stalks: [[V3]] = []
        // 不对称: 一枝最高、近乎直立, 其余更矮、向两侧斜出 (避免对称的 V 字)
        let tallest = Int((r() * Double(n)).rounded(.down))
        let lean0 = e.normRand(-0.12, 0.12)
        for i in 0..<n {
            let t = n == 1 ? 0 : Double(i) / Double(n - 1) * 2 - 1     // −1…1
            let lean = i == tallest ? lean0 * 0.5 : lean0 + t * e.normRand(0.25, 0.4)
            let len = P.stemLength * (i == tallest ? 1 : e.normRand(0.62, 0.84))
            let end = (sin(lean) * len, -cos(lean) * len)
            let ctrl = (end.0 * 0.25 + e.normRand(-25, 25), end.1 * 0.55)
            let pts = FlowersEngine.curve((0, 0), ctrl, end, segments: 40)
            stalks.append(pts)
            let d = pts[pts.count - 1] - pts[pts.count - 4]
            tips.append((x0 + end.0, y0 + end.1, d))
        }
        // 茎在叶后
        for pts in stalks {
            tube(0, pts, xof: x0, yof: y0, wid: { x in P.stemWidth * (1.05 - 0.35 * x) }, col: stemCol, clampShade: true)
        }
        // 叶: 每枝下部 2/3 互生, 正对观者, 朝外略向上
        for (si, pts) in stalks.enumerated() {
            let count = Int(P.leafChance)
            for k in 0..<count {
                let f = 0.12 + 0.55 * (Double(k) + e.normRand(0, 0.5)) / Double(max(count, 1))
                let idx = min(pts.count - 2, max(1, Int(f * Double(pts.count - 1))))
                let p = pts[idx], q = pts[idx + 1]
                let along = atan2(q.y - p.y, q.x - p.x)          // 茎的走向 (朝上约 −π/2)
                let sgn: Double = (k + si) % 2 == 0 ? 1 : -1
                let psi = along + sgn * e.normRand(0.6, 0.95)      // 与茎成 35°–55°, 朝外上
                var a = LeafArgs()
                a.xof = x0 + p.x; a.yof = y0 + p.y
                a.rot = FlowersEngine.flatRot(psi, twist: e.normRand(-0.25, 0.25), tilt: e.normRand(-0.35, 0.35))
                a.len = P.leafLength * e.normRand(0.8, 1.15) * (1 - 0.35 * f)
                a.seg = 24
                let lw = P.leafWidth * (1 - 0.3 * f)
                let shape = P.leafShape
                a.wid = { x in shape(x) * lw }
                a.vei = P.leafType
                a.col = P.leafColor
                let droop = sgn * e.normRand(0.4, 0.9)
                let cup = e.normRand(-0.6, 0.6)
                a.ben = { x in V3(cup * (0.5 - x), droop * x * 2, 0) }
                leaf(0, a)
            }
        }
        // 花头: 正面朝观者 (略偏), 三轮细瓣, 外轮平展、中轮半开、内轮内扣
        for tip in tips {
            let axis = V3(e.normRand(-0.5, 0.5), e.normRand(-0.4, 0.4), 0)
            let N = Int(P.flowerPetal)
            let L = P.flowerLength * e.normRand(0.9, 1.1)
            let w = P.flowerWidth
            // 四轮: 外轮反卷下垂, 渐内渐短渐收, 最内一轮内扣成球心
            let r1 = ring(P, axis: axis, count: N, len: L, wid: w, open: 1.55, curl: 0.55, phase: 0)
            let r2 = ring(P, axis: axis, count: N, len: L * 0.84, wid: w, open: 1.15, curl: 0.25, phase: 0.5)
            let r3 = ring(P, axis: axis, count: max(12, N * 3 / 4), len: L * 0.64, wid: w * 0.95, open: 0.72,
                          curl: -0.2, phase: 0.25)
            let r4 = ring(P, axis: axis, count: max(10, N / 2), len: L * 0.44, wid: w * 0.9, open: 0.32,
                          curl: -0.55, phase: 0.75)
            for petals in [r1, r2, r3, r4] {
                drawPetals(P, petals, x: tip.x, y: tip.y, col: P.flowerColor, shape: P.flowerShape)
            }
            let core = ring(P, axis: axis, count: 8, len: P.innerLength, wid: 2, open: 0.3, curl: -0.2, phase: 0)
            drawPetals(P, core, x: tip.x, y: tip.y, col: P.innerColor, shape: { sin(Double.pi * $0) })
        }
    }
}

// MARK: - 公开 API

public extension ZXArt {
    /// 花卉 (移植 nonflowers)。
    enum Flowers {
        public enum Season: String, Sendable, Hashable, Codable, CaseIterable {
            /// 原作的参数空间 (不存在的花)。
            case none = "自然"
            case plum = "梅"
            case lotus = "荷"
            case chrysanthemum = "菊"
            case orchid = "兰"
        }

        public enum Layout: String, Sendable, Hashable, Codable {
            /// 按长宽比: 宽 → 小组件 (花在右), 近方 → 居中, 高 → 花笺 (上方留白)。
            case auto, widget, square, portrait
        }

        public struct Params: Sendable, Hashable {
            public var palette: Palette
            /// 花色色相 (0…360)。nil = 原作 / 预设的颜色。
            public var hue: Double?
            public var season: Season
            public var layout: Layout
            /// 花笺顶部留白 (画布高度的份额)。
            public var quietTop: Double
            public var paperTexture: Bool
            /// 0…1 (0.5 = 常态): 花 / 叶的多少 (只作用于季节预设; `.none` 保持原作参数)。
            public var density: Double
            /// @2: 给诗留的框 (单位坐标)。nil = @1 的摆放; 非 nil = 花绕开诗句框摆放 (`placeV2`)。
            public var verse: VerseLayout?

            public init(palette: Palette = .paperInk, hue: Double? = nil, season: Season = .none, layout: Layout = .auto,
                        quietTop: Double = 0.32, paperTexture: Bool = true, density: Double = 0.5,
                        verse: VerseLayout? = nil) {
                self.palette = palette
                self.hue = hue
                self.season = season
                self.layout = layout
                self.quietTop = quietTop
                self.paperTexture = paperTexture
                self.density = density
                self.verse = verse
            }

            /// @2 的摆放 → (k, tx, ty): 原作 1200² 画布坐标 × k + (tx, ty) = 逻辑坐标。改这里要升版本 (@3)。
            /// - 横带 (top): 花在横带之下满宽的区域里, 同 @1 (按包围盒等比放大, 底对齐、居中)。
            /// - 横幅 (widget): 花在竖栏另一侧的区域里, 同上。
            /// - 竖幅 / 方幅的竖栏: 「L 形」—— 花底对齐画面下沿, 诗栏下沿以上的部分必须落在画栏里, 以下可以
            ///   伸到诗栏之下。取满足这个条件的最大 k (≤ 包围盒放得下的上限, ≤ 2.4; 放不下时二分 30 次),
            ///   水平位置取画栏居中, 再夹进可行范围。`pts` 是原作坐标的顶点 (已夹到 0…1199)。
            static func placeV2(_ verse: VerseLayout, layout: Layout, W: Double, H: Double, quietTop: Double,
                                bounds: (xmin: Double, xmax: Double, ymin: Double, ymax: Double),
                                pts: [SIMD2<Double>]) -> (k: Double, tx: Double, ty: Double) {
                let (xmin, xmax, ymin, ymax) = bounds
                let bw = max(xmax - xmin, 1), bh = max(ymax - ymin, 1)
                let vx0 = Double(verse.rect.minX) * W, vx1 = Double(verse.rect.maxX) * W
                let vy1 = Double(verse.rect.maxY) * H
                let g = 0.03 * min(W, H)
                let portrait = layout == .portrait
                let bottom = portrait ? 0.965 * H : 0.95 * H
                let yTop = portrait ? quietTop * H + 0.04 * H : 0.05 * H
                let right = (vx0 + vx1) / 2 > W / 2
                func fitted(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> (Double, Double, Double) {
                    let k = min(max(x1 - x0, 0) / bw, max(y1 - y0, 0) / bh, 2.4)
                    return (k, (x0 + x1) / 2 - (xmin + xmax) / 2 * k, y1 - ymax * k)
                }
                if layout == .widget {
                    return right ? fitted(0.05 * W, yTop, vx0 - g, bottom) : fitted(vx1 + g, yTop, 0.95 * W, bottom)
                }
                if verse.side == .top {
                    return fitted(0.06 * W, vy1 + g, 0.94 * W, bottom)
                }
                let xl = 0.05 * W, xr = 0.95 * W, ey = vy1 + g
                // 画栏的中线 (花偏好的水平位置)
                let mid = right ? (xl + vx0 - g) / 2 : (vx1 + g + xr) / 2
                func place(_ k: Double) -> Double? {
                    let ty = bottom - ymax * k
                    var hiMax = -Double.infinity, hiMin = Double.infinity
                    for p in pts where p.y * k + ty < ey {
                        hiMax = max(hiMax, p.x)
                        hiMin = min(hiMin, p.x)
                    }
                    var lo = xl - xmin * k, hi = xr - xmax * k
                    if right, hiMax.isFinite { hi = min(hi, vx0 - g - hiMax * k) }
                    if !right, hiMin.isFinite { lo = max(lo, vx1 + g - hiMin * k) }
                    guard lo <= hi else { return nil }
                    return min(max(mid - (xmin + xmax) / 2 * k, lo), hi)
                }
                let kmax = min((xr - xl) / bw, (bottom - yTop) / bh, 2.4)
                var k = kmax
                var tx = place(kmax)
                if tx == nil {
                    var a = 0.0, b = kmax
                    for _ in 0..<30 {
                        let c = (a + b) / 2
                        if place(c) != nil { a = c } else { b = c }
                    }
                    k = a
                    tx = place(a)
                }
                return (k, tx ?? (mid - (xmin + xmax) / 2 * k), bottom - ymax * k)
            }
        }

        /// 逻辑画布短边 (原作画布 600)。
        public static let logicalShortSide: Double = 600

        public static func generate(seed: Seed, size: CGSize, params: Params = Params()) -> Drawing {
            generateTraced(seed: seed, size: size, params: params).drawing
        }

        /// generate + 生成器原始输出 (1200² 原作画布坐标) 的统计 (跨平台对拍金标用)。
        static func generateTraced(seed: Seed, size: CGSize, params: Params) -> (drawing: Drawing, trace: ZXArt.Trace) {
            let aspect = size.width > 0 && size.height > 0 ? Double(size.width / size.height) : 1
            let W: Double, H: Double
            if aspect >= 1 { H = logicalShortSide; W = logicalShortSide * aspect } else { W = logicalShortSide; H = logicalShortSide / aspect }
            let layout: Layout
            if params.layout != .auto {
                layout = params.layout
            } else {
                layout = aspect > 1.3 ? .widget : (aspect < 0.77 ? .portrait : .square)
            }

            let engine = FlowersEngine(seed: seed)
            let page = engine.pageSequence()
            var par = page.par
            var woody = page.woody
            engine.applySeason(params.season, &par, woody: &woody, density: params.density)
            if let hue = params.hue {
                let d = par.flowerColor.max[0] - par.flowerColor.min[0]
                par.flowerColor.min[0] = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
                par.flowerColor.max[0] = ((hue + max(-30, min(30, d))).truncatingRemainder(dividingBy: 360) + 360)
                    .truncatingRemainder(dividingBy: 360)
            }
            switch par.form {
            case .lotus: engine.lotus(par)
            case .chrysanthemum: engine.chrysanthemum(par)
            case .original: if woody { engine.woody(par) } else { engine.herbal(par) }
            }
            var trace = ZXArt.Trace(logicalWidth: W, logicalHeight: H, prngAfter: engine.e.state)
            for p in engine.polys { trace.add(p.p.map { ($0.x, $0.y) }) }

            // 原作 Layer.bound: 1200² 图层内有像素的范围。
            var xmin = Double.infinity, xmax = -Double.infinity, ymin = Double.infinity, ymax = -Double.infinity
            for p in engine.polys {
                for v in p.p where v.x.isFinite && v.y.isFinite {
                    let x = min(max(v.x, 0), 1199), y = min(max(v.y, 0), 1199)
                    xmin = min(xmin, x); xmax = max(xmax, x); ymin = min(ymin, y); ymax = max(ymax, y)
                }
            }
            if !xmin.isFinite { xmin = 500; xmax = 700; ymin = 500; ymax = 840 }
            let bw = max(xmax - xmin, 1), bh = max(ymax - ymin, 1)

            let k: Double, tx: Double, ty: Double
            if let verse = params.verse {
                var pts: [SIMD2<Double>] = []
                for p in engine.polys {
                    for v in p.p where v.x.isFinite && v.y.isFinite {
                        pts.append(SIMD2(min(max(v.x, 0), 1199), min(max(v.y, 0), 1199)))
                    }
                }
                (k, tx, ty) = Params.placeV2(verse, layout: layout, W: W, H: H, quietTop: params.quietTop,
                                             bounds: (xmin, xmax, ymin, ymax), pts: pts)
            } else {
            let region: CGRect
            switch layout {
            case .widget:
                region = CGRect(x: 0.50 * W, y: 0.05 * H, width: 0.46 * W, height: 0.91 * H)
            case .portrait:
                let top = params.quietTop * H + 0.04 * H
                region = CGRect(x: 0.06 * W, y: top, width: 0.88 * W, height: 0.965 * H - top)
            case .square, .auto:
                let top = max(0.08 * H, params.quietTop * H + 0.03 * H)
                region = CGRect(x: 0.08 * W, y: top, width: 0.84 * W, height: 0.94 * H - top)
            }
            k = min(Double(region.width) / bw, Double(region.height) / bh, 2.4)
            tx = Double(region.midX) - (xmin + xmax) / 2 * k
            ty = Double(region.maxY) - ymax * k
            }

            let pal = params.palette
            let dark = pal.isDark
            func color(_ c: FColor) -> ZXHex {
                let a = min(max(c.a, 0), 1)
                if c.r <= 0 && c.g <= 0 && c.b <= 0 { return pal.ink.opacity(a) }
                if dark && c.r == 120 && c.g == 100 && c.b == 0 { return pal.ink.opacity(a * 0.8) }
                return ZXHex(red: min(max(c.r, 0), 255) / 255, green: min(max(c.g, 0), 255) / 255,
                             blue: min(max(c.b, 0), 255) / 255, alpha: a)
            }
            var shapes0: [Shape] = [], shapes1: [Shape] = []
            shapes0.reserveCapacity(engine.polys.count)
            let lw = Float(k)
            for p in engine.polys where p.p.count >= 2 {
                var pts: [SIMD2<Float>] = []
                pts.reserveCapacity(p.p.count)
                var ok = true
                for v in p.p {
                    let x = v.x * k + tx, y = v.y * k + ty
                    if !x.isFinite || !y.isFinite { ok = false; break }
                    pts.append(SIMD2<Float>(Float(x), Float(y)))
                }
                if !ok { continue }
                let c = color(p.col)
                let s = Shape(points: pts, fill: p.fil ? c : nil, stroke: p.str ? c : nil, lineWidth: lw)
                if p.layer == 0 { shapes0.append(s) } else { shapes1.append(s) }
            }
            let perlin = engine.e.perlinValues
            let f0 = LayerFilter(passes: [.fade, .wispy], scale: 1 / k, offsetX: -tx / k, offsetY: -ty / k, perlin: perlin)
            let f1 = LayerFilter(passes: [.wispy], scale: 1 / k, offsetX: -tx / k, offsetY: -ty / k, perlin: perlin)
            let layers = [
                Layer(blend: dark ? .normal : .multiply, filter: f0, shapes: shapes0),
                Layer(blend: .normal, filter: f1, shapes: shapes1),
            ]
            let quiet: CGRectCodable = layout == .widget
                ? CGRectCodable(x: 0, y: 0, width: 0.48 * W, height: H)
                : CGRectCodable(x: 0, y: 0, width: W, height: params.quietTop * H)
            var paper = page.paper
            paper.tint = pal.ink
            paper.strength = dark ? 0.6 : 1
            trace.transform = [k, tx, ty]
            var d = Drawing(width: W, height: H, background: pal.paper,
                            paper: params.paperTexture ? paper : nil, layers: layers, quietRect: quiet)
            if let verse = params.verse { d.setVerse(verse, quietTop: params.quietTop) }
            return (d, trace)
        }
    }
}
