import ZixiaoColor
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
        /// 增强对比度的可选完整色板；旧身份缺省沿用普通色板。
        public let highContrastLight: Swatch?
        public let highContrastDark: Swatch?

        public init(light: Swatch, dark: Swatch, accents: [String: Pair]? = nil,
                    highContrastLight: Swatch? = nil, highContrastDark: Swatch? = nil) {
            self.light = light
            self.dark = dark
            self.accents = accents
            self.highContrastLight = highContrastLight
            self.highContrastDark = highContrastDark
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
    case yaqing
    case moonWhite = "moon-white"
    case xiangLeaf = "xiang-leaf"
    case canglang
    case ousi
    case qingdai = "qingdai"
    case rouge
}

public enum ZXIdentityError: Error, Sendable, Equatable {
    case missingResource(String)
}

public extension ZXIdentity {
    /// 把设计语言的配色套入产品，字族、材质、标记与印文仍归产品所有。
    func applyingPalette(_ palette: ZXIdentity) -> ZXIdentity {
        ZXIdentity(name: "\(name) · \(palette.name)",
                   rationale: "\(rationale)\n配色：\(palette.rationale)",
                   palette: palette.palette, type: type, slots: slots)
    }

    func applyingPalette(_ bundled: ZXBundledIdentity) throws -> ZXIdentity {
        applyingPalette(try Self.bundled(bundled))
    }

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
