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
    init(identity: ZXIdentity, colorScheme: ColorScheme, accentName: String? = nil) {
        let dark = colorScheme == .dark
        let s = dark ? identity.palette.dark : identity.palette.light
        let alternate = accentName.flatMap { identity.palette.accents?[$0] }
        let accent = alternate.map { dark ? $0.dark : $0.light } ?? s.accent
        let solidAccent = accent.composited(over: s.paper)
        let accentOn = solidAccent.contrast(with: s.paper) >= solidAccent.contrast(with: s.ink) ? s.paper : s.ink

        self.init(values: Values(
            accent: accent,
            accentOn: accentOn,
            secondary: s.secondary ?? s.muted,
            bg: s.paper,
            surface: s.surface,
            surfaceElevated: dark ? s.surface.mixed(with: s.ink, amount: InkLevel.elevatedLift) : s.surface,
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
            neutral: s.ink.opacity(InkLevel.neutral).composited(over: s.paper),
            statusOn: s.paper,
            glassTint: s.paper.opacity(InkLevel.glassTint),
            paper: s.paper,
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
