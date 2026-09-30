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
import ZixiaoDesign

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

// MARK: - 季节预设

extension FlowersEngine {
    func applySeason(_ season: ZXArt.Flowers.Season, _ P: inout PAR, woody: inout Bool) {
        let u = { self.r() }
        func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * u() }
        switch season {
        case .none:
            return
        case .plum:  // 梅: 老枝、先花后叶、五瓣粉白
            woody = true
            P.leafChance = 0
            P.flowerChance = range(0.05, 0.08)
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
        case .lotus:  // 荷: 一两枝长梗、大圆叶、粉瓣
            woody = false
            P.stemCount = u() < 0.6 ? 1 : 2
            P.stemLength = range(340, 400)
            P.stemWidth = range(3.5, 5)
            P.stemBend = range(2, 4)
            P.sheathLength = 0
            P.shootCount = 1
            P.shootLength = range(40, 60)
            P.flowerPetal = (range(9, 12)).rounded(.down)
            P.flowerLength = range(42, 52)
            P.flowerWidth = range(18, 24)
            P.flowerShape = { pow(sin(Double.pi * $0), 0.35) }
            P.flowerColor = ZXArt.HSVRange(min: [range(330, 345), 0.45, 0.95, 0.95], max: [350, 0.06, 1, 0.9])
            P.flowerOpenCurve = { x, op in x < 0.1 ? 2 + op * 8 : 1.5 }
            P.innerLength = range(6, 9)
            P.innerColor = ZXArt.HSVRange(min: [50, 0.7, 0.9, 1], max: [55, 0.5, 0.95, 1])
            P.leafPosition = 1
            P.leafChance = range(0.025, 0.04)
            P.leafLength = range(45, 55)
            P.leafWidth = range(26, 32)
            P.leafShape = { pow(sin(Double.pi * $0), 0.6) }
            P.leafType = [2, 4, 3]
            P.leafColor = ZXArt.HSVRange(min: [range(95, 110), 0.35, 0.4, 0.95], max: [range(80, 95), 0.25, 0.65, 0.95])
        case .chrysanthemum:  // 菊: 多而细的瓣、金黄、锯齿叶
            woody = false
            P.stemCount = u() < 0.5 ? 2 : 3
            P.shootCount = range(1, 2)
            P.shootLength = range(30, 60)
            P.sheathLength = 0
            P.flowerPetal = (range(16, 22)).rounded(.down)
            P.flowerLength = range(24, 32)
            P.flowerWidth = range(4.5, 6.5)
            P.flowerShape = { pow(sin(Double.pi * $0), 0.7) }
            let h = range(36, 50)
            P.flowerColor = ZXArt.HSVRange(min: [h, 0.8, 0.95, 1], max: [h + 8, 0.45, 1, 0.9])
            P.flowerOpenCurve = { x, op in x < 0.1 ? 2 + op * 10 : self.n(x * 10, 1.3) }
            P.innerLength = range(4, 7)
            P.innerColor = ZXArt.HSVRange(min: [35, 0.8, 0.7, 1], max: [40, 0.7, 0.8, 1])
            P.leafPosition = 2
            P.leafChance = range(0.035, 0.05)
            P.leafLength = range(28, 36)
            P.leafWidth = range(9, 13)
            let jag = range(8, 14)
            P.leafShape = { x in self.n(x * jag, 0.7) * pow(sin(Double.pi * x), 0.5) }
            P.leafColor = ZXArt.HSVRange(min: [range(95, 115), 0.35, 0.35, 0.95], max: [range(80, 95), 0.3, 0.55, 0.95])
        case .orchid:  // 兰: 长而细的叶丛、疏花、淡绿白
            woody = false
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
            P.leafChance = range(0.08, 0.1)
            P.leafLength = range(85, 100)
            P.leafWidth = range(4.5, 6)
            P.leafShape = { pow(sin(Double.pi * $0), 0.5) }
            P.leafType = [1, 2]
            P.leafColor = ZXArt.HSVRange(min: [range(95, 115), 0.4, 0.35, 0.95], max: [range(80, 95), 0.3, 0.6, 0.95])
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

            public init(palette: Palette = .paperInk, hue: Double? = nil, season: Season = .none, layout: Layout = .auto,
                        quietTop: Double = 0.32, paperTexture: Bool = true) {
                self.palette = palette
                self.hue = hue
                self.season = season
                self.layout = layout
                self.quietTop = quietTop
                self.paperTexture = paperTexture
            }
        }

        /// 逻辑画布短边 (原作画布 600)。
        public static let logicalShortSide: Double = 600

        public static func generate(seed: Seed, size: CGSize, params: Params = Params()) -> Drawing {
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
            engine.applySeason(params.season, &par, woody: &woody)
            if let hue = params.hue {
                let d = par.flowerColor.max[0] - par.flowerColor.min[0]
                par.flowerColor.min[0] = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
                par.flowerColor.max[0] = ((hue + max(-30, min(30, d))).truncatingRemainder(dividingBy: 360) + 360)
                    .truncatingRemainder(dividingBy: 360)
            }
            if woody { engine.woody(par) } else { engine.herbal(par) }

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

            let region: CGRect
            switch layout {
            case .widget:
                region = CGRect(x: 0.50 * W, y: 0.05 * H, width: 0.46 * W, height: 0.91 * H)
            case .portrait:
                let top = params.quietTop * H + 0.04 * H
                region = CGRect(x: 0.06 * W, y: top, width: 0.88 * W, height: 0.965 * H - top)
            case .square, .auto:
                region = CGRect(x: 0.08 * W, y: 0.08 * H, width: 0.84 * W, height: 0.86 * H)
            }
            let k = min(Double(region.width) / bw, Double(region.height) / bh, 2.4)
            let tx = Double(region.midX) - (xmin + xmax) / 2 * k
            let ty = Double(region.maxY) - ymax * k

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
            let quiet: CGRectCodable? = layout == .portrait
                ? CGRectCodable(x: 0, y: 0, width: W, height: params.quietTop * H)
                : (layout == .widget ? CGRectCodable(x: 0, y: 0, width: 0.48 * W, height: H) : nil)
            var paper = page.paper
            paper.tint = pal.ink
            paper.strength = dark ? 0.6 : 1
            return Drawing(width: W, height: H, background: pal.paper,
                           paper: params.paperTexture ? paper : nil, layers: layers, quietRect: quiet)
        }
    }
}
