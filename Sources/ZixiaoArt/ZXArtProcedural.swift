//  ZXArtProcedural.swift — 配方 `background.procedural` 的模型与渲染入口
//
//  契约 (poetryhub 画屏配方, 2026-09-30 定稿):
//
//      background.procedural = {
//        generator: "shanshui@1" | "nonflowers@1",
//        seed: string,
//        variant: shanshui → "高山" | "江岸" | "远山";  nonflowers → "梅" | "荷" | "菊" | "兰" | "自然",
//        params: { density?: number (0.5–1.5), hue?: number (0–360, 仅花), quiet_top?: number (0–0.5) }
//      }
//
//  配色取 style.palette 的 paper / ink; wash 缺省 = ink 以 40% 叠在 paper 上。
//  未知 generator / 版本 / variant → `render` 返回 nil, 调用方回退纸纹 (配方原样保留)。
//
//  版本规则 (务必遵守):
//  - "@1" 冻结为当前出图: 同一 (generator@1, seed, variant, params, palette, 像素尺寸) 永远得到同一张图。
//  - 任何会改变出图的改动 (构图、取随机数的顺序、预设参数、渲染的雾化 / 批量规则、纸纹……) 都必须
//    新开 "@2": 新增代码路径, 保留 @1 的代码路径不动, 让已发布的配方继续复现原图。
//  - 只有「不改变任何像素」的改动 (纯重构、提速且出图逐字节不变) 才可以留在 @1。
//    `ZXArtProceduralFixtureTests` (Fixtures/zxart/procedural-v1.json) 记录了 @1 的几何指纹, 改动后若指纹变了就说明
//    需要升版本。

import CoreGraphics
import Foundation
import ZixiaoDesign

public extension ZXArt {
    /// 配方里的程序化背景。Codable 的键与契约一致 (snake_case)。
    struct Procedural: Sendable, Hashable, Codable {
        /// "shanshui@1" | "nonflowers@1"
        public var generator: String
        public var seed: String
        /// 山水: "高山" | "江岸" | "远山"; 花: "梅" | "荷" | "菊" | "兰" | "自然"
        public var variant: String
        public var params: Params

        public struct Params: Sendable, Hashable, Codable {
            /// 0.5–1.5, 缺省 1。山水: 次峰 / 皴笔 / 水纹 / 船 / 近岸的多少; 花: 花与叶的多少。
            public var density: Double?
            /// 0–360, 仅花: 花色色相。
            public var hue: Double?
            /// 0–0.5: 顶部留白 (锁屏时钟 + 诗句) 占画面高度的份额。缺省 0.32。花的横幅 (中号小组件) 不用它,
            /// 花在右侧、左侧留白; 山水横幅两者都用 (主体在右下)。
            public var quietTop: Double?

            public init(density: Double? = nil, hue: Double? = nil, quietTop: Double? = nil) {
                self.density = density
                self.hue = hue
                self.quietTop = quietTop
            }

            enum CodingKeys: String, CodingKey {
                case density, hue
                case quietTop = "quiet_top"
            }
        }

        public init(generator: String, seed: String, variant: String, params: Params = Params()) {
            self.generator = generator
            self.seed = seed
            self.variant = variant
            self.params = params
        }

        enum CodingKeys: String, CodingKey { case generator, seed, variant, params }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            generator = try c.decode(String.self, forKey: .generator)
            // 契约是字符串; 容忍数字种子 (42 ≡ "42", 与原作网页 ?seed=42 同序列)。
            if let s = try? c.decode(String.self, forKey: .seed) {
                seed = s
            } else {
                seed = String(try c.decode(Int.self, forKey: .seed))
            }
            variant = try c.decode(String.self, forKey: .variant)
            params = try c.decodeIfPresent(Params.self, forKey: .params) ?? Params()
        }

        /// 生成器名 ("shanshui" / "nonflowers")。
        public var generatorName: String { String(generator.split(separator: "@", maxSplits: 1).first ?? "") }
        /// 版本号 ("@1" → 1); 没写版本或写错 → nil。
        public var version: Int? {
            let parts = generator.split(separator: "@", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return Int(parts[1])
        }

        /// 本库能否渲染 (生成器、版本、variant 都认识)。
        public var isSupported: Bool { resolved != nil }

        /// 支持的生成器版本 (客户端可据此决定是否回退纸纹)。
        public static let supportedGenerators: Set<String> = ["shanshui@1", "nonflowers@1"]

        enum Resolved {
            case shanshuiV1(ShanShui.Variant)
            case nonflowersV1(Flowers.Season)
        }

        var resolved: Resolved? {
            switch generator {
            case "shanshui@1":
                return ShanShui.Variant(rawValue: variant).map { .shanshuiV1($0) }
            case "nonflowers@1":
                return Flowers.Season(rawValue: variant).map { .nonflowersV1($0) }
            default:
                return nil
            }
        }
    }

    /// 画屏的版式: 由像素长宽比决定 (与生成器无关)。
    enum Frame: String, Sendable, Hashable {
        /// 高 / 宽 ≥ 1.3: 锁屏 / 壁纸 / 花笺。
        case portrait
        /// 宽 / 高 > 1.3: 中号小组件 (1062×498、1012×476)。主体靠右, 左侧留给诗句。
        case wide
        /// 其余: 小号 (510×510)、大号 (1062×1116) 小组件。
        case square

        public init(pixelSize: CGSize) {
            let w = max(Double(pixelSize.width), 1), h = max(Double(pixelSize.height), 1)
            if h / w >= 1.3 { self = .portrait } else if w / h > 1.3 { self = .wide } else { self = .square }
        }

        /// 缺省顶部留白: 各版式统一 0.32 (与 web 端预览对齐)。横幅另把左侧 42% (山水) / 48% (花) 留给诗句。
        public var defaultQuietTop: Double { 0.32 }
    }

    /// 生成画 (矢量, 可交给 `ZXArtCanvas` 或 `render(_:pixelWidth:pixelHeight:)`)。
    /// 不认识的配方返回 nil。纯函数, 线程安全。
    static func drawing(procedural p: Procedural, palette: Palette, pixelSize: CGSize) -> Drawing? {
        traced(procedural: p, palette: palette, pixelSize: pixelSize)?.drawing
    }
}

extension ZXArt {
    /// 配方 → (画, 生成器统计)。参数映射 (与 web 预览对齐, 改了就要升版本):
    /// - density: 契约 0.5–1.5 (缺省 1) → 生成器 `density − 0.5`, 夹到 0…1 (1.0 ≡ 生成器 0.5)
    /// - quiet_top: 缺省 0.32, 夹到 0…0.5
    /// - hue: 只作用于 nonflowers
    /// - 纸纹总是画 (不透明底; 配方的暗化遮罩由客户端叠在上面)
    /// - 版式按像素长宽比: 高/宽 ≥ 1.3 竖幅, 宽/高 > 1.3 横幅, 其余方幅
    static func traced(procedural p: Procedural, palette: Palette, pixelSize: CGSize) -> (drawing: Drawing, trace: Trace)? {
        guard let kind = p.resolved, pixelSize.width >= 1, pixelSize.height >= 1 else { return nil }
        let frame = Frame(pixelSize: pixelSize)
        let quiet = min(max(p.params.quietTop ?? frame.defaultQuietTop, 0), 0.5)
        // 契约 density 0.5–1.5 (1 = 常态) → 生成器内部 0…1 (0.5 = 常态)
        let density = min(max((p.params.density ?? 1) - 0.5, 0), 1)
        let seed = Seed(p.seed)
        switch kind {
        case .shanshuiV1(let variant):
            return ShanShui.generateTraced(seed: seed, size: pixelSize,
                                           params: .init(palette: palette, density: density, variant: variant, quietTop: quiet))
        case .nonflowersV1(let season):
            let layout: Flowers.Layout = frame == .wide ? .widget : (frame == .portrait ? .portrait : .square)
            return Flowers.generateTraced(seed: seed, size: pixelSize,
                                          params: .init(palette: palette, hue: p.params.hue, season: season, layout: layout,
                                                        quietTop: quiet, density: density))
        }
    }
}

public extension ZXArt {

    /// 配方 → 位图 (`pixelSize` 像素, 如锁屏 1206×2622、中号小组件 1062×498)。
    /// 不认识的 generator / 版本 / variant 返回 nil (调用方回退纸纹)。线程安全, 可在后台线程 / 小组件扩展里调用。
    static func render(procedural p: Procedural, palette: Palette, pixelSize: CGSize) -> CGImage? {
        guard let d = drawing(procedural: p, palette: palette, pixelSize: pixelSize) else { return nil }
        return render(d, pixelWidth: Int(pixelSize.width.rounded()), pixelHeight: Int(pixelSize.height.rounded()))
    }

    /// 同上, 直接给纸 / 墨 / 淡墨 (wash 缺省 = 墨 40% 叠在纸上)。
    static func render(procedural p: Procedural, paper: ZXHex, ink: ZXHex, wash: ZXHex? = nil,
                       pixelSize: CGSize) -> CGImage? {
        render(procedural: p, palette: Palette(paper: paper, ink: ink, wash: wash), pixelSize: pixelSize)
    }
}
