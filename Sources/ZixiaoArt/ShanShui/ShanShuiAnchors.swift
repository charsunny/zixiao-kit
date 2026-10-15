//  ShanShuiAnchors.swift — shanshui@2 的意象锚点: 山脊、水、船、人、树、屋、天空带在画里的位置
//
//  给「在画上叠东西」的客户端用 (雨落到水面起涟漪、雪沿山脊 / 枝头 / 屋顶留白、雁与月放进天空带、岚贴着山脊):
//  它们要知道意象在哪, 而画本身只是一堆多边形。锚点随 `ZXArt.Drawing.anchors` 返回, 全部是单位坐标
//  (0…1, 左上为原点, x 乘画布宽、y 乘画布高), 与 `verseLayout` 同一套。
//
//  只记录, 不改构图: 记录发生在 `compose` / `composeV2` 里已经算好的笔画上 (山 / 船 / 水纹整件, 山上的树与屋由 `mountain()`
//  在生成时顺手报一声), 不取随机数、不改取数顺序、不改任何位置与笔画 —— @2 的出图与加锚点之前逐字节相同
//  (`Fixtures/zxart/procedural-v1.json` / `procedural-v2.json` 的指纹, 与 `ZXArtAnchorsTests` 里「记录开 / 关各画一遍逐点相同」)。
//  被 `fit` 平移的山, 它身上的树与屋 (记录时是山的原始坐标) 一起按同一个位移换算; 被 `cull` 去掉的笔画
//  (落在诗句框里的) 不参与: 山脊与水只取剩下的笔画, 树 / 屋 / 船只要有一笔被去掉整件不记。
//
//  shanshui@1 (`compose`) 与 @2 (`composeV2`) 都有锚点; @1 没有诗句框、没有 fit / cull, 其余同 @2 (横幅小组件的构图也记)。
//  花、原作第一屏的 `Drawing.anchors` 为 nil。锚点是「画了什么」的描述, 渲染不读。

import CoreGraphics
import Foundation

// MARK: - 公开的数据形状

public extension ZXArt {
    /// 一幅山水 (@1 / @2) 里的意象锚点 (单位坐标)。每一类可能为空: 画里没有的意象 (例如密度低时没有船) 就没有对应锚点。
    struct Anchors: Sendable, Hashable {
        /// 各山层的山脊折线 (远山、主峰后的次峰、主峰、侧山), 按生成的先后。
        public var ridges: [Ridge] = []
        /// 水纹带: 所有水纹笔画的外框。没有水纹为 nil。
        public var water: WaterBand?
        public var boats: [Boat] = []
        /// 人: @2 里只有船上的渔人 (戴斗笠、持杖)。
        public var figures: [Figure] = []
        public var trees: [Tree] = []
        public var buildings: [Building] = []
        /// 画顶到最高山脊之间的空白带 (放月、雁)。山顶几乎顶到画顶 (< 2% 画高) 时为 nil。
        /// @1 / @2 都从画顶算起 (含顶部留白与 @2 的时钟区)。
        /// 只是「没有山」的范围, 诗句框 / 时钟区另算 (`verseLayout`), 用的人自己避开。
        public var sky: SkyBand?

        public init() {}

        public var isEmpty: Bool {
            ridges.isEmpty && water == nil && boats.isEmpty && figures.isEmpty && trees.isEmpty && buildings.isEmpty
                && sky == nil
        }

        /// 山脊: 山层最上面的一条线 (该山层所有笔画的上包络, 含山顶的树梢), 按 x 递增, 只取画布以内的列。
        public struct Ridge: Sendable, Hashable {
            public enum Role: String, Sendable, Hashable {
                /// 远山 (雾化的那一条)。
                case far
                /// 主峰后、贴外缘的次峰 (高山)。
                case back
                /// 主峰 (高山) / 主山 (江岸)。
                case main
                /// 侧山 (江岸, 密度高时才有)。
                case side
            }
            public var role: Role
            public var points: [SIMD2<Float>]

            public init(role: Role, points: [SIMD2<Float>]) {
                self.role = role
                self.points = points
            }
        }

        public struct WaterBand: Sendable, Hashable {
            public var x: ClosedRange<Double>
            public var y: ClosedRange<Double>

            public init(x: ClosedRange<Double>, y: ClosedRange<Double>) {
                self.x = x
                self.y = y
            }
        }

        /// 船: 船身 (船舷) 的中心、吃水处与长度。
        public struct Boat: Sendable, Hashable {
            /// 船身中心的 x。
            public var x: Double
            /// 船身最低处的 y (船坐在水面上的位置)。
            public var y: Double
            /// 船身长 (占画布宽的份额)。
            public var length: Double
            /// 船头朝左 (原作的 `fli`)。
            public var flipped: Bool

            public init(x: Double, y: Double, length: Double, flipped: Bool) {
                self.x = x
                self.y = y
                self.length = length
                self.flipped = flipped
            }
        }

        public struct Figure: Sendable, Hashable {
            /// 人的中心 x、脚下 y、头顶 y (含斗笠)。
            public var x: Double
            public var baseY: Double
            public var topY: Double
            /// 戴斗笠 (原作的 `hat02`; 书生帽 `hat01` 为 false)。船上的渔人都戴。
            public var wearsStrawHat: Bool

            public init(x: Double, baseY: Double, topY: Double, wearsStrawHat: Bool) {
                self.x = x
                self.baseY = baseY
                self.topY = topY
                self.wearsStrawHat = wearsStrawHat
            }
        }

        public struct Tree: Sendable, Hashable {
            /// 原作的树: `tree01` 细干叶团、`tree02` 山顶 / 山边的灌木丛、`tree03` 弯干大树。
            public enum Kind: String, Sendable, Hashable {
                case tree01, tree02, tree03
            }
            public var kind: Kind
            /// 外框: 中心 x、根部 y (最低)、树梢 y (最高)、宽。
            public var x: Double
            public var baseY: Double
            public var topY: Double
            public var width: Double

            public init(kind: Kind, x: Double, baseY: Double, topY: Double, width: Double) {
                self.kind = kind
                self.x = x
                self.baseY = baseY
                self.topY = topY
                self.width = width
            }
        }

        public struct Building: Sendable, Hashable {
            /// 原作的屋舍: `arch02` 屋 (一到三层)、`arch04` 亭、`arch03` 塔。
            public enum Kind: String, Sendable, Hashable {
                case house, pavilion, pagoda
            }
            public var kind: Kind
            /// 外框: 中心 x、地基 y (最低)、屋顶最高处 y、宽。
            public var x: Double
            public var baseY: Double
            public var roofY: Double
            public var width: Double

            public init(kind: Kind, x: Double, baseY: Double, roofY: Double, width: Double) {
                self.kind = kind
                self.x = x
                self.baseY = baseY
                self.roofY = roofY
                self.width = width
            }
        }

        /// 天空带: 整宽, y 从画顶到最高山脊。
        public struct SkyBand: Sendable, Hashable {
            public var x: ClosedRange<Double>
            public var y: ClosedRange<Double>

            public init(x: ClosedRange<Double> = 0...1, y: ClosedRange<Double>) {
                self.x = x
                self.y = y
            }
        }
    }
}

// MARK: - 构图过程中记下的东西 (内部)

extension ZXArt {
    /// `compose` / `composeV2` / `mountain()` 生成时记下的一件东西: 种类 + 它的笔画 (逻辑坐标, 平移前后各自成立)。
    struct AnchorPiece: Sendable {
        enum Kind: Sendable, Hashable {
            case ridge(Anchors.Ridge.Role)
            case water
            case boat
            case tree(Anchors.Tree.Kind)
            case building(Anchors.Building.Kind)
        }
        var kind: Kind
        var canv: SSCanv
    }
}

extension ShanShuiEngine {
    /// 记一件东西 (记录关着 / 没有笔画时什么也不做)。不取随机数。
    func noteAnchor(_ kind: ZXArt.AnchorPiece.Kind, _ canv: ZXArt.SSCanv) {
        guard anchorLog != nil, !canv.isEmpty else { return }
        anchorLog?.append(ZXArt.AnchorPiece(kind: kind, canv: canv))
    }

    /// 记一件整件的东西 (水纹、船、远山、岸上的树), 原样交回笔画。构图里的调用夹在原来的语句之间。
    @discardableResult
    func noted(_ kind: ZXArt.AnchorPiece.Kind, _ canv: ZXArt.SSCanv) -> ZXArt.SSCanv {
        if anchorLog != nil, !canv.isEmpty { anchorPieces.append(ZXArt.AnchorPiece(kind: kind, canv: canv)) }
        return canv
    }

    /// 记一座山: 山脊 (`final` = placed / fit 之后) 加 `mountain()` 报上来的树与屋 (按同一个平移换算)。
    func notedMountain(_ role: ZXArt.Anchors.Ridge.Role, raw: ZXArt.SSCanv, final: ZXArt.SSCanv) {
        let onMountain = takeAnchorLog()
        guard anchorLog != nil else { return }
        let (dx, dy) = ShanShuiEngine.translation(from: raw, to: final)
        anchorPieces.append(ZXArt.AnchorPiece(kind: .ridge(role), canv: final))
        for piece in onMountain {
            anchorPieces.append(ZXArt.AnchorPiece(kind: piece.kind, canv: ShanShuiEngine.shifted(piece.canv, dx: dx, dy: dy)))
        }
    }

    /// 取走并清空 `mountain()` 生成时记下的树与屋 (它们还是山的原始坐标)。
    func takeAnchorLog() -> [ZXArt.AnchorPiece] {
        guard let log = anchorLog else { return [] }
        anchorLog = []
        return log
    }

    /// `placed` / `fit` 都是纯平移: 取第一个有限点的位移, 好把山身上的树与屋换算到同一个位置。
    static func translation(from a: ZXArt.SSCanv, to b: ZXArt.SSCanv) -> (dx: Double, dy: Double) {
        for (pa, pb) in zip(a, b) {
            for (va, vb) in zip(pa.p, pb.p) where va.x.isFinite && va.y.isFinite && vb.x.isFinite && vb.y.isFinite {
                return (vb.x - va.x, vb.y - va.y)
            }
        }
        return (0, 0)
    }
}

// MARK: - 换算成锚点

extension ZXArt.Anchors {
    /// 山脊折线的取样间隔 (逻辑单位)。
    static let ridgeStep = 4.0
    /// 天空带至少多高 (画高的份额) 才算。
    static let minSkyHeight = 0.02

    /// 记下的东西 → 锚点。`blocked` 是 `composeV2` 的诗句框禁区: 与 `cull` 一样, 落了点在里面的笔画不算已画。
    static func build(pieces: [ZXArt.AnchorPiece], width W: Double, height H: Double,
                      blocked: (Double, Double) -> Bool) -> ZXArt.Anchors {
        var out = ZXArt.Anchors()
        guard W > 0, H > 0 else { return out }
        var water: Extent?
        for piece in pieces {
            let drawn = piece.canv.filter { poly in
                !poly.p.contains { $0.x.isFinite && $0.y.isFinite && blocked($0.x, $0.y) }
            }
            // 树 / 屋 / 船是整件: 有一笔被去掉就不记。
            let whole = drawn.count == piece.canv.count
            switch piece.kind {
            case .ridge(let role):
                let line = envelope(of: drawn, step: ridgeStep).compactMap { v -> SIMD2<Float>? in
                    let x = v.x / W, y = v.y / H
                    guard (0...1).contains(x) else { return nil }
                    return SIMD2<Float>(Float(x), Float(min(max(y, 0), 1)))
                }
                if line.count >= 2 { out.ridges.append(Ridge(role: role, points: line)) }
            case .water:
                if let e = Extent(drawn) { water = water.map { $0.union(e) } ?? e }
            case .tree(let kind):
                guard whole, let e = Extent(drawn), let p = e.placement(width: W, height: H) else { continue }
                out.trees.append(Tree(kind: kind, x: p.x, baseY: p.base, topY: p.top, width: p.width))
            case .building(let kind):
                guard whole, let e = Extent(drawn), let p = e.placement(width: W, height: H) else { continue }
                out.buildings.append(Building(kind: kind, x: p.x, baseY: p.base, roofY: p.top, width: p.width))
            case .boat:
                // boat01 = 人 (若干笔) + 船身 (最后两笔: 填充 + 描边)。
                guard whole, drawn.count >= 3, let hull = Extent(Array(drawn.suffix(2))),
                      let h = hull.placement(width: W, height: H) else { continue }
                // 船身朝哪边画 (xoff 在船头一端): 人坐在船头一侧。
                let man = Array(drawn.dropLast(2))
                out.boats.append(Boat(x: h.x, y: h.base, length: h.width, flipped: Self.isFlipped(man: man, hull: hull)))
                if let m = Extent(man), let p = m.placement(width: W, height: H) {
                    out.figures.append(Figure(x: p.x, baseY: p.base, topY: p.top, wearsStrawHat: true))
                }
            }
        }
        if let water {
            let x0 = min(max(water.minX / W, 0), 1), x1 = min(max(water.maxX / W, 0), 1)
            let y0 = min(max(water.minY / H, 0), 1), y1 = min(max(water.maxY / H, 0), 1)
            if x1 > x0, y1 > y0 { out.water = WaterBand(x: x0...x1, y: y0...y1) }
        }
        let highest = out.ridges.flatMap(\.points).map { Double($0.y) }.min()
        if let highest, highest >= minSkyHeight { out.sky = SkyBand(y: 0...highest) }
        return out
    }

    /// 人在船身的哪一侧: boat01 里人在船头一端 (xoff + 20·sca·dir), 船身从 xoff 往 dir 方向伸 ——
    /// 不翻转时船身在人的右边。
    private static func isFlipped(man: [ZXArt.SSPoly], hull: Extent) -> Bool {
        guard let m = Extent(man) else { return false }
        return (m.minX + m.maxX) / 2 > (hull.minX + hull.maxX) / 2
    }

    /// 一件东西的外框 (逻辑坐标, 只看有限点)。
    struct Extent {
        var minX: Double, maxX: Double, minY: Double, maxY: Double

        init?(_ canv: ZXArt.SSCanv) {
            var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
            for poly in canv {
                for v in poly.p where v.x.isFinite && v.y.isFinite {
                    minX = min(minX, v.x); maxX = max(maxX, v.x)
                    minY = min(minY, v.y); maxY = max(maxY, v.y)
                }
            }
            guard minX.isFinite, minY.isFinite else { return nil }
            self.minX = minX; self.maxX = maxX; self.minY = minY; self.maxY = maxY
        }

        func union(_ o: Extent) -> Extent {
            var e = self
            e.minX = min(minX, o.minX); e.maxX = max(maxX, o.maxX)
            e.minY = min(minY, o.minY); e.maxY = max(maxY, o.maxY)
            return e
        }

        /// 单位坐标的中心 x / 最低 y / 最高 y / 宽。中心不在画布内 (看不见) 为 nil; 最高与宽夹在画布内。
        func placement(width W: Double, height H: Double) -> (x: Double, base: Double, top: Double, width: Double)? {
            let x = (minX + maxX) / 2 / W, base = maxY / H
            guard (0...1).contains(x), (0...1).contains(base) else { return nil }
            let top = min(max(minY / H, 0), base)
            return (x, base, top, min((maxX - minX) / W, 1))
        }
    }

    /// 上包络: 每隔 `step` 取一列, 列上所有可见笔画的最高点 (最小 y), 空列不取。折线按开放线段算
    /// (描边的首尾回到起点, 不能当多边形闭合)。
    static func envelope(of canv: ZXArt.SSCanv, step: Double) -> [(x: Double, y: Double)] {
        var minX = Double.infinity, maxX = -Double.infinity
        let visible = canv.filter { poly in
            isVisible(poly) && poly.p.count >= 2 && poly.p.allSatisfy { $0.x.isFinite && $0.y.isFinite }
        }
        for poly in visible { for v in poly.p { minX = min(minX, v.x); maxX = max(maxX, v.x) } }
        guard minX.isFinite, step > 0 else { return [] }
        let x0 = (minX / step).rounded(.down) * step
        let n = Int(((maxX - x0) / step).rounded(.up)) + 1
        var top = [Double](repeating: .infinity, count: n)
        for poly in visible {
            for k in 0..<(poly.p.count - 1) {
                let a = poly.p[k], b = poly.p[k + 1]
                let lo = min(a.x, b.x), hi = max(a.x, b.x)
                var i = Int(((lo - x0) / step).rounded(.up))
                let last = Int(((hi - x0) / step).rounded(.down))
                while i <= last {
                    if i >= 0, i < n {
                        let x = x0 + Double(i) * step
                        let t = hi > lo ? (x - a.x) / (b.x - a.x) : 0
                        let y = hi > lo ? a.y + (b.y - a.y) * t : min(a.y, b.y)
                        if y < top[i] { top[i] = y }
                    }
                    i += 1
                }
            }
        }
        return (0..<n).compactMap { top[$0].isFinite ? (x0 + Double($0) * step, top[$0]) : nil }
    }

    /// 渲染会不会画出这一笔 (与 `ZXArt.appendShapes` 同一条规则: 有可见的填充或描边)。
    static func isVisible(_ poly: ZXArt.SSPoly) -> Bool {
        (poly.fil.map { $0.a > 0 } ?? false) || (poly.wid > 0 && (poly.str.map { $0.a > 0 } ?? false))
    }
}
