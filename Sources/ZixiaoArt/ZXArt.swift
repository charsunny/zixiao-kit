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
//  独立模块 ZixiaoArt: 只依赖 ZixiaoDesign 的色值 (`ZXHex`)。配方侧的入口见 `ZXArtProcedural.swift`
//  (`ZXArt.Procedural` + `ZXArt.render(procedural:palette:pixelSize:)`)。

import CoreGraphics
import Foundation
import ZixiaoDesign

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
        /// 淡墨 (远山、最淡的一层渲染)。缺省是墨 22% 压在纸上 —— 与原作远山的灰度相当。
        public var wash: ZXHex

        public init(paper: ZXHex, ink: ZXHex, wash: ZXHex? = nil) {
            self.paper = paper
            self.ink = ink
            self.wash = wash ?? ink.opacity(0.22).composited(over: paper)
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

        public init(width: Double, height: Double, background: ZXHex, paper: PaperTexture? = nil,
                    layers: [Layer] = [], quietRect: CGRectCodable? = nil) {
            self.width = width
            self.height = height
            self.background = background
            self.paper = paper
            self.layers = layers
            self.quietRect = quietRect
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

    struct Layer: Sendable {
        public var blend: BlendMode
        public var opacity: Double
        public var filter: LayerFilter?
        public var shapes: [Shape]

        public init(blend: BlendMode = .normal, opacity: Double = 1, filter: LayerFilter? = nil, shapes: [Shape] = []) {
            self.blend = blend
            self.opacity = opacity
            self.filter = filter
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
