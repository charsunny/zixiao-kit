import ZixiaoColor
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

    // MARK: token 分组 (设计系统契约)

    /// 颜色角色, 全部由身份派生。见 `ZXColorTokens` 的派生表。
    public let color: ZXColorTokens
    /// 字号阶。display / 标题用身份的展示字族, 其余用正文字族。
    public let type: ZXTypeTokens
    /// 间距尺。
    public let space: ZXSpaceTokens
    /// 圆角阶。
    public let radius: ZXRadiusTokens
    /// 动效。
    public let motion: ZXMotionTokens

    // MARK: 平铺属性 (早于 token 分组的 API, 与 `color` 组同义, 保留以免下游改代码)

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
    // (`color.ink` / `color.paper` 是给 token 组的完整性留的, 视图里仍用这两个函数。)
    private let paperHex: ZXHex
    private let inkHex: ZXHex

    /// - Parameters:
    ///   - accentName: 选用身份里 `palette.accents` 的一支备选强调色 (如系列里的诗人身份色);
    ///     找不到就用调色板默认的 accent。
    ///   - seasonTint: 季节偏色 (T18, V3 §2.7); nil (默认) 不偏, 与加这个参数之前行为一致。
    ///     App 按 `ZXDay.term` 映射出五行之季, 设备关了「季节色」开关时也传 nil。
    ///   - legibilityWeight: 系统「粗体文本」开关。传进来后 `type` 组的字会跟着加粗
    ///     (随包宋体不会自己响应这个开关)。`zxTheme(_ identity:)` 会自动从环境取。
    ///   - space / radius / motion: 尺度。默认是标准尺; 产品要更圆、更慢, 换一套传进来。
    public nonisolated init(_ identity: ZXIdentity, colorScheme: ColorScheme, accentName: String? = nil,
                            seasonTint: ZXSeasonTint? = nil, contrast: ColorSchemeContrast = .standard,
                            legibilityWeight: LegibilityWeight? = nil,
                            space: ZXSpaceTokens = .standard,
                            radius: ZXRadiusTokens = .standard,
                            motion: ZXMotionTokens = .defaults) {
        self.identity = identity
        self.colorScheme = colorScheme
        let color = ZXColorTokens(identity: identity, colorScheme: colorScheme, accentName: accentName,
                                  seasonTint: seasonTint, contrast: contrast)
        self.color = color
        paperHex = color.values.paper
        inkHex = color.values.ink
        surface = color.surface
        muted = color.muted
        border = color.border
        track = color.track
        accent = color.accent
        seal = color.seal
        rule = color.rule
        night = color.night
        displayFace = ZXFace(descriptor: identity.type.display)
        bodyFace = ZXFace(descriptor: identity.type.body)
        uiFace = ZXFace(descriptor: identity.type.ui)
        type = ZXTypeTokens(displayFace: displayFace, bodyFace: bodyFace, uiFace: uiFace,
                            legibilityWeight: legibilityWeight)
        self.space = space
        self.radius = radius
        self.motion = motion
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
    ///
    /// - Parameter seasonTint: 季节偏色 (T18); nil (默认) 不偏。App 传当前节气映射出的季,
    ///   或者设备关了「季节色」开关时传 nil —— 这里也随外观切换一起重新解析, 不需要单独处理。
    func zxTheme(_ identity: ZXIdentity, accentName: String? = nil, seasonTint: ZXSeasonTint? = nil) -> some View {
        modifier(ZXThemeResolver(identity: identity, accentName: accentName, seasonTint: seasonTint))
    }
}

private struct ZXThemeResolver: ViewModifier {
    let identity: ZXIdentity
    let accentName: String?
    let seasonTint: ZXSeasonTint?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.environment(\.zxTheme, ZXTheme(identity, colorScheme: colorScheme, accentName: accentName,
                                               seasonTint: seasonTint, contrast: contrast, legibilityWeight: legibilityWeight))
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
