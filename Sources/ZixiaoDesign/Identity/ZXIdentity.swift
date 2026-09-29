//  ZXIdentity.swift — 身份层 (L3) 的数据形状
//
//  沿用 PoetKit `Identity` 的思路: 内核只提供插槽, 产品负责填。内核不认识任何一套
//  具体的颜色, 只认识 paper / ink / seal 这些槽 —— 颜色一律来自随包或 App 注入的
//  身份 JSON。与 PoetKit 的差别是浅深两套调色板都显式写在 JSON 里: 深色该怎么
//  「翻」是设计决定 (比如单色墨系的纸墨互换), 不该由代码替设计师推导。

import Foundation

public struct ZXIdentity: Decodable, Sendable, Hashable {
    /// 这套身份的名字 (给人看的, 如「单色墨系」)。
    public let name: String
    /// 写不出理由的配色就是皮肤, 不是身份。这个字段必填, 就是为了逼出理由。
    public let rationale: String
    public let palette: Palette
    public let type: TypeSpec
    public let slots: Slots

    public init(name: String, rationale: String, palette: Palette, type: TypeSpec, slots: Slots) {
        self.name = name
        self.rationale = rationale
        self.palette = palette
        self.type = type
        self.slots = slots
    }

    // MARK: 调色板

    public struct Palette: Decodable, Sendable, Hashable {
        public let light: Swatch
        public let dark: Swatch
        /// 备选强调色 (如系列里各诗人的身份色)。键是给人看的色名, 由 App 选用;
        /// 内核不知道哪支色属于谁。
        public let accents: [String: Pair]?

        public init(light: Swatch, dark: Swatch, accents: [String: Pair]? = nil) {
            self.light = light
            self.dark = dark
            self.accents = accents
        }
    }

    /// 一种外观下的全部颜色槽。
    public struct Swatch: Decodable, Sendable, Hashable {
        /// 纸: 页面底色。
        public let paper: ZXHex
        /// 墨: 正文与一切记号。层级靠它的透明度表达, 见 `ZXTheme.ink(_:)`。
        public let ink: ZXHex
        /// 卡面 / 书页: 压在纸上的一层。
        public let surface: ZXHex
        /// 次级文字。
        public let muted: ZXHex
        /// 边线。
        public let border: ZXHex
        /// 进度槽、条形图的底。
        public let track: ZXHex
        /// 强调: 选中、方向、少量身份标识。单色系里它就是墨。
        public let accent: ZXHex
        /// 印泥。一屏里最稀有的颜色。
        public let seal: ZXHex
        /// 分隔细线。
        public let rule: ZXHex
        /// 夜色: 最深的一层底 (夜读、全屏沉浸)。
        public let night: ZXHex

        // 以下五槽是 token 分组 (`ZXColorTokens`) 引入的, 一律可选:
        // 已经写好的身份 JSON (包括 App 与 PoetKit 各自的那些) 不补也能解码,
        // 缺席时由 `ZXColorTokens` 按「墨 / 印」回落 —— 见那里的派生表。

        /// 次色: 图表的第二组数据、标签。不是第二个主按钮。
        public let secondary: ZXHex?
        /// 状态: 成功 / 完成。
        public let success: ZXHex?
        /// 状态: 提醒。
        public let warning: ZXHex?
        /// 状态: 危险 / 错误。
        public let danger: ZXHex?
        /// 状态: 提示信息。
        public let info: ZXHex?

        public init(paper: ZXHex, ink: ZXHex, surface: ZXHex, muted: ZXHex, border: ZXHex,
                    track: ZXHex, accent: ZXHex, seal: ZXHex, rule: ZXHex, night: ZXHex,
                    secondary: ZXHex? = nil, success: ZXHex? = nil, warning: ZXHex? = nil,
                    danger: ZXHex? = nil, info: ZXHex? = nil) {
            self.paper = paper; self.ink = ink; self.surface = surface; self.muted = muted
            self.border = border; self.track = track; self.accent = accent; self.seal = seal
            self.rule = rule; self.night = night
            self.secondary = secondary; self.success = success; self.warning = warning
            self.danger = danger; self.info = info
        }
    }

    /// 浅深成对的一支色。
    public struct Pair: Decodable, Sendable, Hashable {
        public let light: ZXHex
        public let dark: ZXHex
        public init(light: ZXHex, dark: ZXHex) { self.light = light; self.dark = dark }
    }

    // MARK: 字

    /// 三个角色各自的字族描述, 形如「Source Han Serif CN Bold」「system」。
    /// 描述而不是 PostScript 名: 身份 JSON 是给设计师写的, 由 `ZXFace` 负责落到随包字体。
    public struct TypeSpec: Decodable, Sendable, Hashable {
        public let display: String
        public let body: String
        public let ui: String
        public init(display: String, body: String, ui: String) {
            self.display = display; self.body = body; self.ui = ui
        }
    }

    // MARK: 插槽 (与 PoetKit Slots 同形, 便于 PoetKit 日后直接依赖本包)

    public struct Slots: Decodable, Sendable, Hashable {
        public enum Rule: String, Decodable, Sendable {
            case verticalHairline = "vertical-hairline", frame, none
        }
        public enum Marker: String, Decodable, Sendable {
            case sealSquare = "seal-square", dot, brushDot = "brush-dot"
        }
        /// 纸面质地的名字 (如 paper-xuan)。质地贴图由 App 提供, 内核只转交这个名字。
        public let surface: String?
        /// 版面界行的画法。
        public let rule: Rule?
        /// 分节标记的形状, `SectionLabel` 按它画。
        public let marker: Marker?
        /// 印文。内置的设计语言身份一律留空 —— 印文是产品的名号, 由产品自己填。
        public let sealText: String?

        public init(surface: String? = nil, rule: Rule? = nil, marker: Marker? = nil, sealText: String? = nil) {
            self.surface = surface; self.rule = rule; self.marker = marker; self.sealText = sealText
        }
    }
}

// MARK: - 加载

/// 随包身份。原始值就是 `Resources/identities/` 下的文件名。
/// 内核里的身份是「设计语言」, 不是产品: 代码与文件名都只用设计语言命名,
/// 哪个产品用哪一套、印文写什么, 由 App 决定。
public enum ZXBundledIdentity: String, CaseIterable, Sendable {
    /// 单色墨系: 纸墨两色, 层级全靠透明度。环境默认值用它, 因为它不带任何色相,
    /// 忘了注入主题的界面也不会显出别家的颜色。
    case monochromeInk = "monochrome-ink"
    /// 纸墨朱印: 暖纸、墨绿黑、朱印强调。
    case paperInkSeal = "paper-ink-seal"
}

public enum ZXIdentityError: Error, Sendable, Equatable {
    case missingResource(String)
}

public extension ZXIdentity {
    /// 从 JSON 数据解码。颜色写错 (不是 #RRGGBB / #RRGGBBAA) 会在这里就失败,
    /// 而不是等到画面上出现一块黑。
    static func decode(from data: Data) throws -> ZXIdentity {
        try JSONDecoder().decode(ZXIdentity.self, from: data)
    }

    /// 从文件加载 (App 自带的身份放自己的 bundle, 用这个入口)。
    static func load(from url: URL) throws -> ZXIdentity {
        try decode(from: Data(contentsOf: url))
    }

    /// 加载随包身份。
    static func bundled(_ which: ZXBundledIdentity) throws -> ZXIdentity {
        // SPM 的 `.process` 会把资源子目录拍平, Xcode 与命令行的行为也不完全一致,
        // 所以子目录与根目录都找一遍。
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: which.rawValue, withExtension: "json", subdirectory: "identities")
            ?? bundle.url(forResource: which.rawValue, withExtension: "json")
        else { throw ZXIdentityError.missingResource("\(which.rawValue).json") }
        return try load(from: url)
    }

    /// 环境默认身份。随包 JSON 由测试保证能解码; 真的坏了就是打包事故,
    /// 直接停下比静默画出一套错色更容易被发现。
    static let fallback: ZXIdentity = {
        do { return try bundled(.monochromeInk) } catch {
            preconditionFailure("随包身份 \(ZXBundledIdentity.monochromeInk.rawValue).json 缺失或损坏: \(error)")
        }
    }()
}

// MARK: - 色值

/// 一个十六进制色值。解码时就校验, 身份 JSON 里写错一位会立刻报错。
public struct ZXHex: Decodable, Sendable, Hashable, CustomStringConvertible {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    /// 接受 `#RRGGBB` 与 `#RRGGBBAA` (井号可省)。
    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8,
              s.allSatisfy(\.isHexDigit),
              let value = UInt64(s, radix: 16)
        else { return nil }
        let rgb = s.count == 8 ? value >> 8 : value
        red = Double((rgb >> 16) & 0xFF) / 255
        green = Double((rgb >> 8) & 0xFF) / 255
        blue = Double(rgb & 0xFF) / 255
        alpha = s.count == 8 ? Double(value & 0xFF) / 255 : 1
    }

    /// 直接给分量 (0…1)。派生色 (混色、叠透明度) 用; 越界的分量夹回 0…1。
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
        self.red = clamp(red)
        self.green = clamp(green)
        self.blue = clamp(blue)
        self.alpha = clamp(alpha)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let hex = ZXHex(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "不是合法色值: \(raw)")
        }
        self = hex
    }

    public var description: String {
        let c = [red, green, blue].map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
        return alpha < 1 ? "#\(c)\(String(format: "%02X", Int((alpha * 255).rounded())))" : "#\(c)"
    }
}

// MARK: - 派生运算
//
// 为什么放在色值上而不是 Color 上: SwiftUI 的 Color 解析要等到上屏 (还要看环境),
// 拿不到确定的分量; token 派生与对比度检查都要在纯数值上做, 测试才能不起 UI 就验证。

public extension ZXHex {
    /// 同一支色换一个不透明度 (乘在原有 alpha 上)。
    func opacity(_ alpha: Double) -> ZXHex {
        ZXHex(red: red, green: green, blue: blue, alpha: self.alpha * alpha)
    }

    /// 把自己按自身 alpha 叠到不透明的 `base` 上, 得到一支不透明色。
    /// 「墨 72% 压在纸上」这类颜色要当底色用时 (上面还要压字), 必须先落成不透明的,
    /// 否则换一张底 (卡面、夜色) 就变了颜色, 对比度也跟着失守。
    func composited(over base: ZXHex) -> ZXHex {
        let a = alpha
        return ZXHex(red: red * a + base.red * (1 - a),
                     green: green * a + base.green * (1 - a),
                     blue: blue * a + base.blue * (1 - a),
                     alpha: 1)
    }

    /// 向 `other` 混 `amount` (0…1), 保留自己的 alpha。
    func mixed(with other: ZXHex, amount: Double) -> ZXHex {
        let t = min(max(amount, 0), 1)
        return ZXHex(red: red + (other.red - red) * t,
                     green: green + (other.green - green) * t,
                     blue: blue + (other.blue - blue) * t,
                     alpha: alpha)
    }

    /// WCAG 2 相对亮度 (忽略 alpha; 半透明色请先 `composited(over:)`)。
    var relativeLuminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }

    /// WCAG 2 对比度 (1…21)。正文要 ≥ 4.5, 18pt 以上与图标 ≥ 3。
    func contrast(with other: ZXHex) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
