import SwiftUI
import ZixiaoDesign

/// 阅读器从 `ZXTheme` 取出的那几样: 颜色 + 字体。
///
/// 为什么不把 `ZXTheme` 一路传进 Canvas 的绘制函数: `ZXTheme` 是 `@MainActor` 的,
/// 而 Canvas 的绘制闭包不保证在主线程上跑; 在主线程上一次性把颜色解析成 `Color` 值、
/// 把字体解析成 `Font` 值, 下游就只拿 Sendable 值类型, 不用逐处推敲隔离。
/// 颜色与字全部来自主题与 `ZXFont`, 这里不写死任何色值或字体名。
public struct ZXReaderStyle: Sendable, Hashable {
    public var paper: Color
    public var ink: Color
    public var accent: Color
    public var seal: Color
    /// 界栏 (乌丝栏) 的线色。
    public var rule: Color
    /// 系统「粗体文本」开关; 自定义字体不会自己响应, 要显式传给 `ZXFont`。
    public var legibilityWeight: LegibilityWeight?

    @MainActor
    public init(theme: ZXTheme, legibilityWeight: LegibilityWeight? = nil) {
        paper = theme.paper()
        ink = theme.ink()
        accent = theme.accent
        seal = theme.seal
        // 界栏用墨的 0.16 而不是身份的 `rule`: 身份里的 rule 是界面分隔线, 落在纸上几乎看不见;
        // 乌丝栏是版面的一部分, 按「层级只靠墨的浓淡」取一档 (与 Flutter 版同值), 两套身份下都站得住。
        rule = theme.ink(0.16)
        self.legibilityWeight = legibilityWeight
    }

    /// 墨的浓淡, 语义同 `ZXTheme.ink(_:)`。
    public func ink(_ alpha: Double) -> Color { ink.opacity(alpha) }
    public func paper(_ alpha: Double) -> Color { paper.opacity(alpha) }

    /// 随 Dynamic Type 缩放的宋体 (横排正文、栏里的字)。
    public func serif(_ size: CGFloat, weight: Font.Weight = .regular,
                      relativeTo textStyle: Font.TextStyle = .body) -> Font {
        ZXFont.serif(size, weight: weight, relativeTo: textStyle, legibilityWeight: legibilityWeight)
    }

    /// 定长宋体: 竖排格子是按字号算好的, 字若随 Dynamic Type 变大就会撑出格子、压到界栏。
    /// 竖排的大小由阅读器自己的字号设置控制。
    public func fixedSerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        ZXFont.serif(size, weight: weight, relativeTo: nil, legibilityWeight: legibilityWeight)
    }

    /// 秋鸿楷 (子集字体, 只用于题字一类的短字, 见 `ZXFonts.kaiName`)。
    public func kai(_ size: CGFloat, relativeTo textStyle: Font.TextStyle? = .body) -> Font {
        ZXFont.kai(size, relativeTo: textStyle)
    }
}
