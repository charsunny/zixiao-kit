//  ZXTheme.swift — 身份 + 外观 → 可直接上屏的颜色与字
//
//  与 PoetKit `Theme` 的区别: PoetKit 把纸、墨交给系统语义色 (systemGroupedBackground /
//  label), 只取身份里的 accent 与 seal; 这里纸墨也来自身份 —— 单色墨系的全部层级
//  就是纸与墨的透明度, 交给系统色等于丢掉了身份本身。

import SwiftUI

/// 某套身份在某种外观下解析出的主题。
///
/// 为什么是 `@MainActor`: 主题只在视图里用, 字体解析会碰 UIKit 的字体度量;
/// 钉在主线程, 调用方就不必逐个推敲哪些成员能跨线程读。
/// 构造器是 `nonisolated` 的 —— 只存 Sendable 值, 这样 Environment 的默认值
/// (非隔离上下文) 也能造一个出来。
@MainActor
public struct ZXTheme: Sendable {
    public let identity: ZXIdentity
    public let colorScheme: ColorScheme

    public let surface: Color
    public let muted: Color
    public let border: Color
    public let track: Color
    public let accent: Color
    public let seal: Color
    public let rule: Color
    public let night: Color

    public let displayFace: ZXFace
    public let bodyFace: ZXFace
    public let uiFace: ZXFace

    // 纸与墨不直接暴露成属性: 层级只能经 `ink(_:)` / `paper(_:)` 表达,
    // 省得同一处有人写 `theme.ink.opacity(0.6)`、有人写 `theme.ink(0.6)`。
    private let paperHex: ZXHex
    private let inkHex: ZXHex

    /// - Parameters:
    ///   - accentName: 选用身份里 `palette.accents` 的一支备选强调色 (如系列里的诗人身份色);
    ///     找不到就用调色板默认的 accent。
    public nonisolated init(_ identity: ZXIdentity, colorScheme: ColorScheme, accentName: String? = nil) {
        self.identity = identity
        self.colorScheme = colorScheme
        let dark = colorScheme == .dark
        let s = dark ? identity.palette.dark : identity.palette.light
        paperHex = s.paper
        inkHex = s.ink
        surface = Color(zxHex: s.surface)
        muted = Color(zxHex: s.muted)
        border = Color(zxHex: s.border)
        track = Color(zxHex: s.track)
        let alternate = accentName.flatMap { identity.palette.accents?[$0] }
        accent = Color(zxHex: alternate.map { dark ? $0.dark : $0.light } ?? s.accent)
        seal = Color(zxHex: s.seal)
        rule = Color(zxHex: s.rule)
        night = Color(zxHex: s.night)
        displayFace = ZXFace(descriptor: identity.type.display)
        bodyFace = ZXFace(descriptor: identity.type.body)
        uiFace = ZXFace(descriptor: identity.type.ui)
    }

    /// 墨。画面里一切记号的颜色; `alpha` 是层级 —— 1 是正文与最强的一笔,
    /// 0.55 是次要, 0.08 是底纹。深色外观下同一个 α 落在纸色上, 层级关系守恒。
    public func ink(_ alpha: Double = 1) -> Color {
        Color(zxHex: inkHex).opacity(alpha)
    }

    /// 纸。`ink` 的反面: 页面底色, 以及墨块上的反白字与图标。
    public func paper(_ alpha: Double = 1) -> Color {
        Color(zxHex: paperHex).opacity(alpha)
    }

    /// 是否深色外观。组件偶尔需要知道 (比如封面阴影在深色底上看不见, 干脆不画)。
    public var isDark: Bool { colorScheme == .dark }

    // MARK: 字
    //
    // `relativeTo` 传 nil 得到定长字 (不随 Dynamic Type), 只给尺寸固定的「物」用。

    /// 展示字: 大标题、书名、题字。
    public func displayFont(_ size: CGFloat = 28, relativeTo style: Font.TextStyle? = .title,
                            legibilityWeight: LegibilityWeight? = nil) -> Font {
        displayFace.font(size, weight: .bold, relativeTo: style, legibilityWeight: legibilityWeight)
    }

    /// 正文字: 原文、诗句、长段落。
    public func bodyFont(_ size: CGFloat = 17, weight: Font.Weight = .regular,
                         relativeTo style: Font.TextStyle? = .body,
                         legibilityWeight: LegibilityWeight? = nil) -> Font {
        bodyFace.font(size, weight: weight, relativeTo: style, legibilityWeight: legibilityWeight)
    }

    /// 操作层字: 标签、按钮、元信息。
    public func uiFont(_ size: CGFloat = 13, weight: Font.Weight = .regular,
                       relativeTo style: Font.TextStyle? = .footnote,
                       legibilityWeight: LegibilityWeight? = nil) -> Font {
        uiFace.font(size, weight: weight, relativeTo: style, legibilityWeight: legibilityWeight)
    }
}

// MARK: - 环境

private struct ZXThemeKey: EnvironmentKey {
    /// 默认: 单色墨系浅色。没注入主题的界面落在纸墨两色上, 不会冒出别家的色相。
    static let defaultValue = ZXTheme(.fallback, colorScheme: .light)
}

public extension EnvironmentValues {
    var zxTheme: ZXTheme {
        get { self[ZXThemeKey.self] }
        set { self[ZXThemeKey.self] = newValue }
    }
}

public extension View {
    /// 注入一个已解析的主题 (外观固定, 不随系统切换; 适合预览、截图、强制浅色的页面)。
    func zxTheme(_ theme: ZXTheme) -> some View {
        environment(\.zxTheme, theme)
    }

    /// 注入一套身份, 按当前外观解析, 并随系统浅深切换重新解析。
    ///
    /// 这是 App 根视图该用的入口。Flutter 版吃过亏: 颜色在构建时按当时的亮度烤死,
    /// 外观一切换, 缓存的页面全都不跟着变。这里每次外观变化都重新解析。
    func zxTheme(_ identity: ZXIdentity, accentName: String? = nil) -> some View {
        modifier(ZXThemeResolver(identity: identity, accentName: accentName))
    }
}

private struct ZXThemeResolver: ViewModifier {
    let identity: ZXIdentity
    let accentName: String?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.zxTheme, ZXTheme(identity, colorScheme: colorScheme, accentName: accentName))
    }
}

// MARK: - 色值 → Color

extension Color {
    /// 身份色值上屏。取名 `zxHex` 而不是 `hex`: PoetKit 已有 public `Color(hex:)`,
    /// 两个包同时 import 时同名会二义。
    init(zxHex hex: ZXHex) {
        self.init(.sRGB, red: hex.red, green: hex.green, blue: hex.blue, opacity: hex.alpha)
    }
}
