//  ZXColorTokens.swift — 颜色 token: 角色, 不是色相
//
//  视图只问「正文用什么色」「卡面用什么色」, 不问「墨是几号」。角色到色值的映射
//  全部在这里由身份派生 —— 换一套身份 JSON, 所有视图跟着换, 视图代码一个字不改。
//
//  为什么先派生成 `ZXHex` 再转 `Color`: SwiftUI 的 Color 要到上屏才解析, 拿不到确定分量;
//  派生 (混色、叠透明度、挑对比度更高的那一支) 与测试都要在纯数值上做。

import SwiftUI

/// 一套身份在一种外观下的全部颜色角色。经 `theme.color` 取用。
public struct ZXColorTokens: Sendable, Hashable {
    /// 各角色的色值。Canvas 绘制、对比度检查这类需要确定分量的地方用它;
    /// 视图里直接用下面的 `Color` 属性。
    public let values: Values

    public init(values: Values) { self.values = values }

    // MARK: 角色 (与设计系统契约同名)

    /// 强调: 选中、主按钮、方向。单色墨系里就是墨; 纸墨朱印里是朱印。
    public var accent: Color { Color(zxHex: values.accent) }
    /// 压在 accent 上的字与图标。
    public var accentOn: Color { Color(zxHex: values.accentOn) }
    /// 次色: 图表第二组、标签。永远不做第二个主按钮。
    public var secondary: Color { Color(zxHex: values.secondary) }
    /// 页面底 (纸)。
    public var bg: Color { Color(zxHex: values.bg) }
    /// 卡面。
    public var surface: Color { Color(zxHex: values.surface) }
    /// 抬起的一层: 浮层、sheet、减少透明度时的玻璃替身。不透明。
    public var surfaceElevated: Color { Color(zxHex: values.surfaceElevated) }
    /// 控件底 (输入格、chip)。半透明的墨, 放在纸上卡上都成立。
    public var fill: Color { Color(zxHex: values.fill) }
    /// 正文。
    public var textPrimary: Color { Color(zxHex: values.textPrimary) }
    /// 次级文字。
    public var textSecondary: Color { Color(zxHex: values.textSecondary) }
    /// 元信息与禁用态。**只**用于这两种, 它不保证正文对比度。
    public var textTertiary: Color { Color(zxHex: values.textTertiary) }
    /// 分隔线。
    public var separator: Color { Color(zxHex: values.separator) }
    public var success: Color { Color(zxHex: values.success) }
    public var warning: Color { Color(zxHex: values.warning) }
    public var danger: Color { Color(zxHex: values.danger) }
    public var info: Color { Color(zxHex: values.info) }
    /// 中性状态底 (「未开始」「已归档」这类不带情绪的标签)。
    public var neutral: Color { Color(zxHex: values.neutral) }
    /// 压在状态色与 neutral 上的字。
    public var statusOn: Color { Color(zxHex: values.statusOn) }
    /// 玻璃的底色倾向 (17/18 的材质回退里叠一层, 让玻璃带一点纸气)。
    public var glassTint: Color { Color(zxHex: values.glassTint) }

    // MARK: 身份自带的槽 (ZXTheme 旧的平铺属性就是它们的同义访问)

    public var paper: Color { Color(zxHex: values.paper) }
    public var ink: Color { Color(zxHex: values.ink) }
    public var seal: Color { Color(zxHex: values.seal) }
    public var muted: Color { Color(zxHex: values.muted) }
    public var border: Color { Color(zxHex: values.border) }
    public var track: Color { Color(zxHex: values.track) }
    public var rule: Color { Color(zxHex: values.rule) }
    public var night: Color { Color(zxHex: values.night) }
    /// 投影色。浅色是墨 (阴影带一点身份的色温), 深色是夜色 —— 深色下阴影几乎看不见,
    /// 分层主要靠 `zxSurface` 加的发丝线。
    public var shadow: Color { Color(zxHex: values.shadow) }

    public struct Values: Sendable, Hashable {
        public var accent, accentOn, secondary, bg, surface, surfaceElevated, fill: ZXHex
        public var textPrimary, textSecondary, textTertiary, separator: ZXHex
        public var success, warning, danger, info, neutral, statusOn, glassTint: ZXHex
        public var paper, ink, seal, muted, border, track, rule, night, shadow: ZXHex
    }
}

// MARK: - 季节偏色 (T18, V3 §2.7)
//
// 「墨色系不变, 底色随五行之季极淡地偏一点 —— 春青、夏赤、长夏黄、秋白、冬玄。」
// 枚举放在 Design (不是 ZixiaoCalendar): 内核不认识节气, 只认识「偏成什么色」;
// 节气 → 季节的映射是 App 的事 (见 `ZXDay.term`)。

/// 五行之季的偏色。只用来把 `paper` / `surface` (进而 `bg`) 揉一点点过去, 墨 (`ink`)、
/// accent 等其余角色不变 —— 这样任何身份、任何强调色叠上去都还是原来的那一套关系。
public enum ZXSeasonTint: String, CaseIterable, Sendable {
    /// 春属木, 东方色青 (立春–谷雨)。
    case spring
    /// 夏属火, 南方色赤 (立夏–芒种)。
    case summer
    /// 长夏属土, 中央色黄 (夏至–处暑; 五行「长夏」取此段, 不是单指季夏三月, 是因为
    /// 二十四节气本就把季夏、孟秋的物候揉在「夏至后至处暑」这五个节气里, 与《素问》
    /// 长夏配土的位置对得上, App 侧按 `ZXDay.term.index` 落地)。
    case lateSummer
    /// 秋属金, 西方色白 (白露–霜降)。
    case autumn
    /// 冬属水, 北方色玄 (立冬–大寒)。
    case winter

    /// 一季的偏色, 浅深各一支 —— 深色下不是把浅色简单调暗 (那样揉进深纸会发灰糊掉),
    /// 是挑一支在深色里也认得出「是这个季节」的同色系, 与身份 JSON 里「纸墨互换」深色
    /// 显式写值是同一个道理。
    public struct Bias: Sendable, Hashable {
        public let light: ZXHex
        public let dark: ZXHex
        public let rationale: String
    }

    /// 揉的比例: 浅色纸本来就亮, 3.5% 才看得出一点意思; 深色纸底子已经暗,
    /// 同样的比例会把整块底染花, 2% 恰好是「翻页时才留意到」的量。
    public static let lightMixAmount: Double = 0.035
    public static let darkMixAmount: Double = 0.02

    public var bias: Bias {
        // 分量写成 0…255 再除, 比敲一串十六进制少一次心算校验; 数值旁边的注释留十六进制,
        // 方便对着色板核对。
        func c(_ r: Double, _ g: Double, _ b: Double) -> ZXHex {
            ZXHex(red: r / 255, green: g / 255, blue: b / 255)
        }
        switch self {
        case .spring:
            return Bias(light: c(63, 107, 82),   // #3F6B52 嫩竹梢头的青
                        dark: c(46, 82, 69),      // #2E5245 松脂里那点冷青, 不抢墨色的黑
                        rationale: "春属木, 东方色青; 浅色取嫩竹青, 深色取松脂冷青, 同一色相不同明度")
        case .summer:
            return Bias(light: c(168, 80, 58),   // #A8503A 夏花朱槿的赤
                        dark: c(122, 59, 44),     // #7A3B2C 赭石的沉赤
                        rationale: "夏属火, 南方色赤; 浅色取朱槿花赤, 深色取赭石沉赤")
        case .lateSummer:
            return Bias(light: c(169, 138, 60),  // #A98A3C 稻穗初熟的黄
                        dark: c(122, 101, 43),    // #7A652B 黄土的沉黄
                        rationale: "长夏属土, 中央色黄; 浅色取稻穗初熟黄, 深色取黄土沉黄")
        case .autumn:
            return Bias(light: c(139, 138, 126), // #8B8A7E 芦花霜色的浅灰白 (白非纯白)
                        dark: c(107, 106, 96),    // #6B6A60 秋铁的冷灰
                        rationale: "秋属金, 西方色白; 白非纯白, 浅色取芦花霜色, 深色取秋铁冷灰")
        case .winter:
            return Bias(light: c(57, 66, 74),    // #39424A 夜潭的青黑
                        dark: c(30, 37, 43),      // #1E252B 玄水的墨黑
                        rationale: "冬属水, 北方色玄; 浅色取夜潭青黑, 深色取玄水墨黑")
        }
    }
}

// MARK: - 派生

public extension ZXColorTokens {
    /// 墨的几档浓淡。集中在这里, 省得「三级文字到底是 0.4 还是 0.45」散落各处。
    enum InkLevel {
        /// 控件底: 一层几乎看不见的墨, 只够把输入格从纸上托出来。
        public static let fill: Double = 0.07
        /// 三级文字 (元信息、禁用)。
        public static let tertiary: Double = 0.42
        /// 中性状态底: 七分墨。压上纸色字在两种外观、两套身份下都 ≥ 4.5:1。
        public static let neutral: Double = 0.72
        /// 玻璃倾向: 两成半的纸。
        public static let glassTint: Double = 0.25
        /// 深色外观下抬起一层时, 卡面向墨 (此时是浅色) 混多少。
        public static let elevatedLift: Double = 0.05
    }

    /// 按身份与外观派生全部角色。
    ///
    /// | 角色 | 来源 | 缺席时 |
    /// |---|---|---|
    /// | accent | `accentName` 选中的备选色 → 调色板 accent | — |
    /// | accentOn | 纸与墨里, 与 accent 对比度更高的那一支 | — |
    /// | secondary | swatch.secondary | muted |
    /// | bg / surface | paper / surface | — |
    /// | surfaceElevated | 浅色 = surface; 深色 = surface 向墨混 5% | — |
    /// | fill | 墨 7% | — |
    /// | textPrimary / Secondary / Tertiary | 墨 / muted / 墨 42% | — |
    /// | separator | rule | — |
    /// | success / warning / info | 同名槽 | 墨 |
    /// | danger | swatch.danger | seal (印的朱) |
    /// | neutral | 墨 72% 压在纸上 (不透明) | — |
    /// | statusOn | 纸 | — |
    /// | glassTint | 纸 25% | — |
    ///
    /// accentOn 为什么「挑」而不是写死纸: 备选强调色 (如系列里的青、绿) 由 App 按名字选,
    /// 深色下它们是浅色, 纸 (此时是深色) 压上去才读得清; 挑对比度更高的一支, 任何
    /// accent 都不会配出看不清的字。
    ///
    /// - Parameter seasonTint: 季节偏色 (T18, V3 §2.7)。只揉 `paper` / `surface`
    ///   (进而 `bg` / `surfaceElevated` / `neutral` / `statusOn` / `glassTint` 这些从纸派生的角色),
    ///   墨、accent、状态色等其余角色原样不变 —— "墨色系不变, 底色随季极淡地偏一点"。
    ///   nil (默认) 就是不偏, 与加这个参数之前逐字节相同。
    init(identity: ZXIdentity, colorScheme: ColorScheme, accentName: String? = nil,
        seasonTint: ZXSeasonTint? = nil) {
        let dark = colorScheme == .dark
        let s = dark ? identity.palette.dark : identity.palette.light
        let alternate = accentName.flatMap { identity.palette.accents?[$0] }
        let accent = alternate.map { dark ? $0.dark : $0.light } ?? s.accent

        let paper: ZXHex
        let surface: ZXHex
        if let seasonTint {
            let bias = dark ? seasonTint.bias.dark : seasonTint.bias.light
            let amount = dark ? ZXSeasonTint.darkMixAmount : ZXSeasonTint.lightMixAmount
            paper = s.paper.mixed(with: bias, amount: amount)
            surface = s.surface.mixed(with: bias, amount: amount)
        } else {
            paper = s.paper
            surface = s.surface
        }

        let solidAccent = accent.composited(over: paper)
        let accentOn = solidAccent.contrast(with: paper) >= solidAccent.contrast(with: s.ink) ? paper : s.ink

        self.init(values: Values(
            accent: accent,
            accentOn: accentOn,
            secondary: s.secondary ?? s.muted,
            bg: paper,
            surface: surface,
            surfaceElevated: dark ? surface.mixed(with: s.ink, amount: InkLevel.elevatedLift) : surface,
            fill: s.ink.opacity(InkLevel.fill),
            textPrimary: s.ink,
            textSecondary: s.muted,
            textTertiary: s.ink.opacity(InkLevel.tertiary),
            separator: s.rule,
            // 缺席时状态色回落到墨 / 印: 单色系的状态本来就靠符号区分, 回落到墨不会错;
            // 危险回落到印, 因为一屏里唯一有资格「喊」的颜色就是那一方朱。
            success: s.success ?? s.ink,
            warning: s.warning ?? s.ink,
            danger: s.danger ?? s.seal,
            info: s.info ?? s.ink,
            neutral: s.ink.opacity(InkLevel.neutral).composited(over: paper),
            statusOn: paper,
            glassTint: paper.opacity(InkLevel.glassTint),
            paper: paper,
            ink: s.ink,
            seal: s.seal,
            muted: s.muted,
            border: s.border,
            track: s.track,
            rule: s.rule,
            night: s.night,
            shadow: dark ? s.night : s.ink
        ))
    }
}
