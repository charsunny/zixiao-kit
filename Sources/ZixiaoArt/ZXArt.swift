//  ZXArt.swift — 程序化国画 (画屏) 的命名空间与数据形状
//
//  两个生成器移植自 Lingdong Huang 的开源作品 (MIT, 全文见 `ZXArtLicenses.swift` 与仓库根
//  `LICENSES/`):
//  - `ZXArt.ShanShui` ← shan-shui-inf (https://github.com/LingDong-/shan-shui-inf)
//  - `ZXArt.Flowers`  ← nonflowers    (https://github.com/LingDong-/nonflowers)
//
//  约定: 生成是纯函数 —— 同一个 (seed, size, params) 永远得到同一张 `Drawing`; 渲染
//  (`ZXArt.render`) 只读 `Drawing`, 不再取随机数。随机源是原作的 PRNG 与 Perlin 噪声,
//  按原作的调用顺序逐次消耗, 同 seed 与原 JS 取到完全相同的序列 (见 Tests/…/Fixtures/zxart)。
//
//  独立模块 ZixiaoArt: 只依赖 ZixiaoColor 的色值 (`ZXHex`)。配方侧的入口见 `ZXArtProcedural.swift`
//  (`ZXArt.Procedural` + `ZXArt.render(procedural:palette:pixelSize:)`)。

import CoreGraphics
import Foundation
import ZixiaoColor

/// 程序化国画: 山水 (`ShanShui`) 与花卉 (`Flowers`) 两个生成器, 共享的随机源、笔触与渲染器。
public enum ZXArt {}

public extension ZXArt {
    /// 种子。原作从 URL `?seed=` 读字符串, 哈希的是 `JSON.stringify(seed)`; 这里同样以字符串为准,
    /// 整数种子按十进制字符串处理 (`42` ≡ `"42"`), 因此与原作网页 `?seed=42` 同序列。
    struct Seed: Sendable, Hashable, Codable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
                 CustomStringConvertible {
        public let string: String
        public init(_ string: String) { self.string = string }
        public init(_ value: Int) { self.string = String(value) }
        public init(stringLiteral value: String) { self.string = value }
        public init(integerLiteral value: Int) { self.string = String(value) }
        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int.self) { string = String(i) } else { string = try c.decode(String.self) }
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(string)
        }
        public var description: String { string }
    }

    /// 纸 / 墨 / 淡墨三色。原作只用灰阶 (墨 = rgb(100,100,100) 叠透明度、纸 = 白), 渲染时把
    /// 灰阶 g 映射为 `mix(ink, paper, g/255)`; 远山的灰 (200…255) 映射到 `mix(wash, paper, …)`。
    /// 夜色就是把纸墨对调 (深纸浅墨), 不需要另一套算法。
    struct Palette: Sendable, Hashable {
        public var paper: ZXHex
        public var ink: ZXHex
        /// 淡墨 (远山)。缺省是墨 40% 叠在纸上 (配方契约; palette.overlay 不参与)。
        public var wash: ZXHex

        public init(paper: ZXHex, ink: ZXHex, wash: ZXHex? = nil) {
            self.paper = paper
            self.ink = ink
            self.wash = wash ?? ink.opacity(0.4).composited(over: paper)
        }

        /// 纸墨: 纸 #F2EEE4 / 墨 #272E2A。
        public static let paperInk = Palette(paper: ZXHex(red: 0xF2 / 255, green: 0xEE / 255, blue: 0xE4 / 255),
                                             ink: ZXHex(red: 0x27 / 255, green: 0x2E / 255, blue: 0x2A / 255))
        /// 夜色: 纸 #1C211F / 墨 #EEE9DD。
        public static let night = Palette(paper: ZXHex(red: 0x1C / 255, green: 0x21 / 255, blue: 0x1F / 255),
                                          ink: ZXHex(red: 0xEE / 255, green: 0xE9 / 255, blue: 0xDD / 255))

        /// 纸比墨暗 (夜色)。决定叠加方式: 亮纸上用正片叠底, 暗纸上只能正常叠加。
        public var isDark: Bool { paper.relativeLuminance < ink.relativeLuminance }

        /// 原作灰阶 → 本调色板。`gray` 0…255 (0 = 最浓墨, 255 = 纸)。
        func mapGray(_ gray: Double, alpha: Double) -> ZXHex {
            ink.mixed(with: paper, amount: gray / 255).opacity(alpha)
        }

        /// 远山灰 (≈200…255) → 淡墨到纸。
        func mapWash(_ gray: Double, alpha: Double) -> ZXHex {
            wash.mixed(with: paper, amount: (gray - 200) / 55).opacity(alpha)
        }
    }
}

// MARK: - Drawing

public extension ZXArt {
    /// 一张画: 逻辑画布尺寸 + 纸 + 若干图层。全部是值类型, 可跨线程 / 进程边界传递。
    struct Drawing: Sendable {
        /// 逻辑画布 (单位 = 原作的 CSS 像素)。渲染时等比缩放到目标尺寸。
        public var width: Double
        public var height: Double
        /// 纸色 (整张底)。
        public var background: ZXHex
        /// 纸纹 (原作的 512×512 镜像纸纹), 可空。
        public var paper: PaperTexture?
        public var layers: [Layer]
        /// 生成器留下的构图提示 (例如「上方 32% 为留白区」), 给排版用, 渲染不读。
        public var quietRect: CGRectCodable?
        /// @2: 给诗留的框 (逻辑画布坐标), 画绕开了它; 客户端把诗排进这里。@1 为 nil。
        /// 单位坐标版见 `verseLayout` / `ZXArt.Procedural.verseLayout(pixelSize:)` (同一个数)。
        public var verseRect: CGRectCodable?
        /// @2: 诗句框 + 竖排 / 横排 (单位坐标)。@1 为 nil。
        public var verseLayout: VerseLayout?

        public init(width: Double, height: Double, background: ZXHex, paper: PaperTexture? = nil,
                    layers: [Layer] = [], quietRect: CGRectCodable? = nil) {
            self.width = width
            self.height = height
            self.background = background
            self.paper = paper
            self.layers = layers
            self.quietRect = quietRect
        }

        /// @2: 记下诗句框; quietRect 改成「竖幅: 时钟区; 方幅 / 横幅: 诗句框」。
        mutating func setVerse(_ verse: VerseLayout, quietTop: Double) {
            let r = verse.rect(in: CGSize(width: width, height: height))
            verseLayout = verse
            verseRect = CGRectCodable(x: Double(r.minX), y: Double(r.minY), width: Double(r.width), height: Double(r.height))
            quietRect = height >= width * 1.3 ? CGRectCodable(x: 0, y: 0, width: width, height: min(max(quietTop, 0), 0.5) * height)
                                              : verseRect
        }

        /// 形状总数 / 顶点总数 (调试与性能日志用)。
        public var shapeCount: Int { layers.reduce(0) { $0 + $1.shapes.count } }
        public var pointCount: Int { layers.reduce(0) { $0 + $1.shapes.reduce(0) { $0 + $1.points.count } } }
    }

    /// 可 Sendable / Codable 的矩形 (逻辑画布坐标)。
    struct CGRectCodable: Sendable, Hashable, Codable {
        public var x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
        public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }

    enum BlendMode: Sendable, Hashable { case normal, multiply }

    /// 图层级的逐像素滤镜 (nonflowers 的 `Filter.fade` / `Filter.wispy`)。
    /// 噪声坐标是原作图层的像素坐标: `layer = drawing * scale + offset`。
    struct LayerFilter: Sendable {
        public enum Kind: Sendable, Hashable { case fade, wispy }
        public var passes: [Kind]
        public var scale: Double
        public var offsetX: Double
        public var offsetY: Double
        /// 原作 Perlin 表 (4096 项)。滤镜不再取随机数, 只查表。
        public var perlin: [Double]
    }

    /// 雾化 (远山): 图层离屏画在低分辨率上, 按「山脊以下的深度」淡出, 再模糊, 放大贴回。
    /// 山脊是生成时量好的 (每列最高点), 与渲染分块无关 —— 分块并行渲染时各块结果一致。
    struct LayerMist: Sendable, Hashable {
        /// 山脊以下多深 (逻辑单位) 淡到 0。
        public var depth: Double
        /// 模糊半径 (逻辑单位)。
        public var blur: Double
        /// 山脊最高处保留的不透明度 (0…1)。
        public var peakOpacity: Double
        /// 每列山脊的 y (逻辑单位), 列 i 在 x = ridgeX0 + i · ridgeStep; 无形状的列为 +∞。
        public var ridge: [Float]
        public var ridgeX0: Double
        public var ridgeStep: Double
        /// 雾底: 到 `floorY` (逻辑 y) 淡到 0, 往上 `floorDepth` 内平滑过渡 (让整条远山的底边也化进雾里)。
        public var floorY: Double
        public var floorDepth: Double

        public init(depth: Double, blur: Double, peakOpacity: Double = 1, ridge: [Float], ridgeX0: Double, ridgeStep: Double,
                    floorY: Double = .infinity, floorDepth: Double = 1) {
            self.depth = depth
            self.blur = blur
            self.peakOpacity = peakOpacity
            self.ridge = ridge
            self.ridgeX0 = ridgeX0
            self.ridgeStep = ridgeStep
            self.floorY = floorY
            self.floorDepth = floorDepth
        }

        /// 逻辑坐标 (x 的山脊已查好) 处的保留比例 0…1。
        @inline(__always)
        func keep(y: Double, ridgeY: Double) -> Double {
            @inline(__always) func smooth(_ t: Double) -> Double { let u = min(max(t, 0), 1); return u * u * (3 - 2 * u) }
            let a = 1 - smooth((y - ridgeY) / max(depth, 1e-6))
            let b = floorY.isFinite ? 1 - smooth((y - (floorY - floorDepth)) / max(floorDepth, 1e-6)) : 1
            return peakOpacity * a * b
        }

        /// 从形状的边量出每列最高点 (逻辑单位, 步长 `step`)。
        public static func ridge(of shapes: [Shape], step: Double) -> (ridge: [Float], x0: Double) {
            var minX = Float.infinity, maxX = -Float.infinity
            for sh in shapes { for p in sh.points { minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x) } }
            guard minX.isFinite, step > 0 else { return ([], 0) }
            let x0 = (Double(minX) / step).rounded(.down) * step
            let n = Int(((Double(maxX) - x0) / step).rounded(.up)) + 1
            var r = [Float](repeating: .infinity, count: n)
            for sh in shapes {
                let pts = sh.points
                guard pts.count >= 2 else { continue }
                for k in 0..<pts.count {
                    let a = pts[k], b = pts[(k + 1) % pts.count]
                    let lo = Swift.min(a.x, b.x), hi = Swift.max(a.x, b.x)
                    var i = Int(((Double(lo) - x0) / step).rounded(.up))
                    let i1 = Int(((Double(hi) - x0) / step).rounded(.down))
                    while i <= i1 {
                        let x = Float(x0 + Double(i) * step)
                        let t = hi > lo ? (x - a.x) / (b.x - a.x) : 0
                        let y = hi > lo ? a.y + (b.y - a.y) * t : Swift.min(a.y, b.y)
                        if i >= 0 && i < n && y < r[i] { r[i] = y }
                        i += 1
                    }
                }
            }
            return (r, x0)
        }

        /// x 处的山脊 (线性插值)。
        func ridgeY(at x: Double) -> Double {
            guard !ridge.isEmpty else { return .infinity }
            let f = (x - ridgeX0) / ridgeStep
            let i = Int(f.rounded(.down))
            if i < 0 { return Double(ridge[0]) }
            if i >= ridge.count - 1 { return Double(ridge[ridge.count - 1]) }
            let a = Double(ridge[i]), b = Double(ridge[i + 1])
            if !a.isFinite { return b }
            if !b.isFinite { return a }
            let t = f - Double(i)
            return a + (b - a) * t
        }
    }

    struct Layer: Sendable {
        public var blend: BlendMode
        public var opacity: Double
        public var filter: LayerFilter?
        public var mist: LayerMist?
        public var shapes: [Shape]

        public init(blend: BlendMode = .normal, opacity: Double = 1, filter: LayerFilter? = nil,
                    mist: LayerMist? = nil, shapes: [Shape] = []) {
            self.blend = blend
            self.opacity = opacity
            self.filter = filter
            self.mist = mist
            self.shapes = shapes
        }
    }

    /// 一个多边形 / 折线。`fill` 为空则不填; `stroke` 为空或 `lineWidth == 0` 则不描。
    /// 与 SVG `<polyline>` 同义: 填充时隐式闭合, 描边时不闭合 (除非 `closed`)。
    struct Shape: Sendable {
        public var points: [SIMD2<Float>]
        public var fill: ZXHex?
        public var stroke: ZXHex?
        public var lineWidth: Float
        public var closed: Bool

        public init(points: [SIMD2<Float>], fill: ZXHex?, stroke: ZXHex?, lineWidth: Float, closed: Bool = false) {
            self.points = points
            self.fill = fill
            self.stroke = stroke
            self.lineWidth = lineWidth
            self.closed = closed
        }
    }

    /// 纸纹: 512×512 镜像平铺的一块。每个纹素是「往墨色偏多少」(0 = 纸, 1 = 墨) ——
    /// 这样同一块纹理在纸墨 / 夜色两套调色板下都成立。
    struct PaperTexture: Sendable {
        public static let side = 512
        /// side × side, 行优先。
        public var shade: [UInt8]
        /// 纹素边长 (逻辑单位)。原作是 1 CSS 像素。
        public var texel: Double
        /// 深浅的整体强度 (乘在 shade 上)。
        public var strength: Double
        /// 纹素往哪个颜色偏 (生成器填调色板的墨色)。
        public var tint: ZXHex

        public init(shade: [UInt8], texel: Double = 1, strength: Double = 1,
                    tint: ZXHex = ZXHex(red: 0, green: 0, blue: 0)) {
            self.shade = shade
            self.texel = texel
            self.strength = strength
            self.tint = tint
        }
    }
}

// MARK: - Trace (跨平台对拍)

extension ZXArt {
    /// 生成器原始输出的统计: 多边形数 / 点数 / 坐标和 + 生成结束时的 PRNG 状态。web 端 (JS 移植)
    /// 用同样的配方跑出同样的数, 证明构图逐步一致 (见 Tests/ZixiaoArtTests/Fixtures/zxart/procedural-v1.json)。
    struct Trace: Sendable, Hashable {
        var logicalWidth: Double
        var logicalHeight: Double
        var prngAfter: Double
        var polys = 0
        var points = 0
        var sumX = 0.0
        var sumY = 0.0
        /// 花: 原作画布 → 逻辑画布的缩放与平移 [k, tx, ty]; 山水为空。
        var transform: [Double] = []

        mutating func add(_ pts: [(Double, Double)]) {
            polys += 1
            for (x, y) in pts where x.isFinite && y.isFinite {
                points += 1
                sumX += x
                sumY += y
            }
        }
    }
}
