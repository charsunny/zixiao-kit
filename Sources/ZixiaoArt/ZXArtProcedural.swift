//  ZXArtProcedural.swift — 配方 `background.procedural` 的模型与渲染入口
//
//  契约 (poetryhub 画屏配方, 2026-09-30 定稿):
//
//      background.procedural = {
//        generator: "shanshui@1" | "nonflowers@1" | "shanshui@2" | "nonflowers@2" | "shanshui@3",
//        seed: string,
//        variant: shanshui → "高山" | "江岸" | "远山";  nonflowers → "梅" | "荷" | "菊" | "兰" | "自然",
//        params: { density?: number (0.5–1.5), hue?: number (0–360, 仅花), quiet_top?: number (0–0.5),
//                  verse_side?: "left" | "right" | "top" (仅 @2 / 山水 @3), verse_columns?: int, verse_chars?: int (仅 @2 / 山水 @3) }
//      }
//
//  @2 (2026-09-30): 构图给诗留一块「诗句框」(`verseLayout`, 见 ZXArtVerse.swift) —— 竖排是一侧的竖栏,
//  横排是时钟区下的横带 —— 山与花绕开它, 客户端把诗排进这个框。生成器 (随机序列、笔触) 与 @1 相同,
//  只是构图 (山水: `composeV2`; 花: 摆放的区域) 不同。@1 的代码路径一字未动 (山水 @1 / @2 另有只记录的意象锚点,
//  `Drawing.anchors`, 见 ShanShuiAnchors.swift: 不取随机数、不改出图, 指纹与逐位对照测试保证)。
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
import ZixiaoColor

public extension ZXArt {
    /// 配方里的程序化背景。Codable 的键与契约一致 (snake_case)。
    struct Procedural: Sendable, Hashable, Codable {
        /// "shanshui@1" | "nonflowers@1" | "shanshui@2" | "nonflowers@2" | "shanshui@3"
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
            /// 仅 @2 / 山水 @3: 诗句落在哪边 ("left" | "right" | "top"), 缺省 "right"。认不出的值 → 本库不画 (回退纸纹)。
            public var verseSide: String?
            /// 仅 @2 / 山水 @3: 诗句几列 (竖) / 几行 (横), 定诗句框的宽 (竖) / 高 (横)。缺省 2, 夹到 1…4。
            public var verseColumns: Int?
            /// 仅 @2 / 山水 @3: 最长一句几个字, 定诗句框的高 (竖) / 宽 (横)。缺省 7, 夹到 4…10。
            public var verseChars: Int?

            public init(density: Double? = nil, hue: Double? = nil, quietTop: Double? = nil,
                        verseSide: String? = nil, verseColumns: Int? = nil, verseChars: Int? = nil) {
                self.density = density
                self.hue = hue
                self.quietTop = quietTop
                self.verseSide = verseSide
                self.verseColumns = verseColumns
                self.verseChars = verseChars
            }

            enum CodingKeys: String, CodingKey {
                case density, hue
                case quietTop = "quiet_top"
                case verseSide = "verse_side"
                case verseColumns = "verse_columns"
                case verseChars = "verse_chars"
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
        public static let supportedGenerators: Set<String> = ["shanshui@1", "nonflowers@1", "shanshui@2", "nonflowers@2", "shanshui@3"]

        /// 供调用方的缓存键和画屏背景共用; 配方本身不改写。
        public func effectiveGenerator(allowsShanShuiV3: Bool = true) -> String {
            !allowsShanShuiV3 && generator == "shanshui@3" ? "shanshui@2" : generator
        }

        /// 纯函数退回入口: seed / variant / params 逐字段保留, 其他生成器原样返回。
        public func downgraded() -> Procedural {
            var copy = self
            copy.generator = effectiveGenerator(allowsShanShuiV3: false)
            return copy
        }

        enum Resolved {
            case shanshuiV1(ShanShui.Variant)
            case nonflowersV1(Flowers.Season)
            case shanshuiV2(ShanShui.Variant, VerseSide)
            case nonflowersV2(Flowers.Season, VerseSide)
            case shanshuiV3(ShanShui.Variant, VerseSide)
        }

        var resolved: Resolved? {
            switch generator {
            case "shanshui@1":
                return ShanShui.Variant(rawValue: variant).map { .shanshuiV1($0) }
            case "nonflowers@1":
                return Flowers.Season(rawValue: variant).map { .nonflowersV1($0) }
            case "shanshui@2":
                guard let side = resolvedVerseSide else { return nil }
                return ShanShui.Variant(rawValue: variant).map { .shanshuiV2($0, side) }
            case "shanshui@3":
                guard let side = resolvedVerseSide else { return nil }
                return ShanShui.Variant(rawValue: variant).map { .shanshuiV3($0, side) }
            case "nonflowers@2":
                guard let side = resolvedVerseSide else { return nil }
                return Flowers.Season(rawValue: variant).map { .nonflowersV2($0, side) }
            default:
                return nil
            }
        }

        /// @2 的诗句边: 缺省 right; 认不出的值为 nil。
        var resolvedVerseSide: VerseSide? {
            guard let raw = params.verseSide else { return .right }
            return VerseSide(rawValue: raw)
        }

        /// @2: 这张画在 `pixelSize` 上给诗留的框 (单位坐标)。@1 / 画不出的配方为 nil —— 调用方照旧按
        /// style.layout 与安全区排字。纯函数, 不生成画 (桌面组件的字与背景分开画, 字这边只需要框)。
        public func verseLayout(pixelSize: CGSize) -> VerseLayout? {
            guard pixelSize.width >= 1, pixelSize.height >= 1, let kind = resolved else { return nil }
            let side: VerseSide
            switch kind {
            case .shanshuiV1, .nonflowersV1: return nil
            case .shanshuiV2(_, let s), .nonflowersV2(_, let s), .shanshuiV3(_, let s): side = s
            }
            let frame = Frame(pixelSize: pixelSize)
            let quiet = min(max(params.quietTop ?? frame.defaultQuietTop, 0), 0.5)
            return ZXArt.verseLayout(side: side, frame: frame,
                                     aspect: Double(pixelSize.width / pixelSize.height), quietTop: quiet,
                                     columns: params.verseColumns, chars: params.verseChars)
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
    static func drawing(procedural p: Procedural, palette: Palette, pixelSize: CGSize,
                        allowsShanShuiV3: Bool = true) -> Drawing? {
        traced(procedural: p, palette: palette, pixelSize: pixelSize, allowsShanShuiV3: allowsShanShuiV3)?.drawing
    }
}

extension ZXArt {
    /// 配方 → (画, 生成器统计)。参数映射 (与 web 预览对齐, 改了就要升版本):
    /// - density: 契约 0.5–1.5 (缺省 1) → 生成器 `density − 0.5`, 夹到 0…1 (1.0 ≡ 生成器 0.5)
    /// - quiet_top: 缺省 0.32, 夹到 0…0.5
    /// - hue: 只作用于 nonflowers
    /// - 纸纹总是画 (不透明底; 配方的暗化遮罩由客户端叠在上面)
    /// - 版式按像素长宽比: 高/宽 ≥ 1.3 竖幅, 宽/高 > 1.3 横幅, 其余方幅
    static func traced(procedural recipe: Procedural, palette: Palette, pixelSize: CGSize,
                       allowsShanShuiV3: Bool = true) -> (drawing: Drawing, trace: Trace)? {
        let p = allowsShanShuiV3 ? recipe : recipe.downgraded()
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
        case .shanshuiV2(let variant, _):
            guard let verse = p.verseLayout(pixelSize: pixelSize) else { return nil }
            var params = ShanShui.Params(palette: palette, density: density, variant: variant, quietTop: quiet)
            params.verse = verse
            return ShanShui.generateTraced(seed: seed, size: pixelSize, params: params)
        case .shanshuiV3(let variant, _):
            guard let verse = p.verseLayout(pixelSize: pixelSize) else { return nil }
            let params = ShanShui.Params(palette: palette, density: density, variant: variant, quietTop: quiet)
            return ShanShui.generateV3Traced(seed: seed, size: pixelSize, params: params, verse: verse)
        case .nonflowersV2(let season, _):
            guard let verse = p.verseLayout(pixelSize: pixelSize) else { return nil }
            let layout: Flowers.Layout = frame == .wide ? .widget : (frame == .portrait ? .portrait : .square)
            var params = Flowers.Params(palette: palette, hue: p.params.hue, season: season, layout: layout,
                                        quietTop: quiet, density: density)
            params.verse = verse
            return Flowers.generateTraced(seed: seed, size: pixelSize, params: params)
        }
    }
}

public extension ZXArt {

    /// 配方 → 位图 (`pixelSize` 像素, 如锁屏 1206×2622、中号小组件 1062×498)。
    /// 不认识的 generator / 版本 / variant 返回 nil (调用方回退纸纹)。线程安全, 可在后台线程 / 小组件扩展里调用。
    static func render(procedural p: Procedural, palette: Palette, pixelSize: CGSize,
                       allowsShanShuiV3: Bool = true) -> CGImage? {
        guard let d = drawing(procedural: p, palette: palette, pixelSize: pixelSize, allowsShanShuiV3: allowsShanShuiV3) else { return nil }
        return render(d, pixelWidth: Int(pixelSize.width.rounded()), pixelHeight: Int(pixelSize.height.rounded()))
    }

    /// 同上, 直接给纸 / 墨 / 淡墨 (wash 缺省 = 墨 40% 叠在纸上)。
    static func render(procedural p: Procedural, paper: ZXHex, ink: ZXHex, wash: ZXHex? = nil,
                       pixelSize: CGSize, allowsShanShuiV3: Bool = true) -> CGImage? {
        render(procedural: p, palette: Palette(paper: paper, ink: ink, wash: wash), pixelSize: pixelSize,
               allowsShanShuiV3: allowsShanShuiV3)
    }
}
