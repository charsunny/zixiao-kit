//  Theme.swift — 过渡 shim: PoetKit 的 `Theme` API, 值全部来自 ZXTheme
//
//  M1 只换底层, 不改视图: 18 个能力视图仍然写 `theme.paper` / `theme.accent` /
//  `theme.secondaryInk`, 这些值现在由 App 注入的 `ZXTheme` (`.zxTheme(ZXIdentity...)`) 解析而来。
//  shim 自己不加载任何身份 —— 它只读环境里那一份。M2 把视图改成直接读 `@Environment(\.zxTheme)`,
//  用法清零后由架构师删掉这个文件。
//
//  为什么颜色要做成随外观变化的动态色, 而不是取当下那一份 ZXTheme 的值:
//  夜读 (`PoemDetailView`) 在局部用 `.environment(\.colorScheme, .dark)` 强制深色,
//  那一段视图树之外的 ZXTheme 仍是浅色; 动态色按所在位置的外观解析, 才不会在夜读页上写出浅色的墨。

import SwiftUI
import UIKit
import ZixiaoDesign

@available(*, deprecated, message: "M2: use ZXTheme (@Environment(\\.zxTheme))")
@MainActor
public struct Theme {
    /// 解析出这份 shim 的那套主题 (注入时的外观)。
    public let zx: ZXTheme
    private let light: ZXColorTokens.Values
    private let dark: ZXColorTokens.Values

    /// 从环境里的 ZXTheme 建 shim。另一种外观按同一身份、同一支备选强调色、同一粗体设置补算。
    public init(_ zx: ZXTheme) {
        self.zx = zx
        let accentName = PoetThemeResolver.accentName(of: zx)
        let other = ZXTheme(zx.identity, colorScheme: zx.isDark ? .light : .dark, accentName: accentName,
                            legibilityWeight: zx.type.legibilityWeight)
        light = zx.isDark ? other.color.values : zx.color.values
        dark = zx.isDark ? zx.color.values : other.color.values
    }

    public var paper: Color { dynamic(\.paper) }
    public var ink: Color { dynamic(\.ink) }
    public var accent: Color { dynamic(\.accent) }
    public var seal: Color { dynamic(\.seal) }
    public var rule: Color { dynamic(\.rule) }
    public var night: Color { dynamic(\.night) }
    /// 卡面。
    public var surface: Color { dynamic(\.surface) }
    public var secondaryInk: Color { dynamic(\.textSecondary) }
    /// 读本的纸。ZX 身份里没有单独的「读本纸」, 取页面底 (paper)。
    public var readingPaper: Color { dynamic(\.paper) }
    /// 主角卡的釉 (原汝窑天青): 纸上染 5% 的墨, 与 `ZixiaoDesign.GlazePanel(glaze: .wash)` 同一调子。
    var wash: Color {
        Self.color(light: light.ink.opacity(0.05).composited(over: light.paper),
                   dark: dark.ink.opacity(0.05).composited(over: dark.paper))
    }

    private func dynamic(_ role: KeyPath<ZXColorTokens.Values, ZXHex>) -> Color {
        Self.color(light: light[keyPath: role], dark: dark[keyPath: role])
    }

    private static func color(light: ZXHex, dark: ZXHex) -> Color {
        let day = UIColor(zxHex: light), night = UIColor(zxHex: dark)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? night : day })
    }
}

/// 非视图代码 (`PoetFont` 等静态取值) 读主题的地方。`PoetAppBoot` / `PoetAppRoot` 从环境里同步进来;
/// 同步之前是 ZixiaoDesign 的环境默认值 —— 与没注入主题的视图看到的一样, 不另外加载身份。
@MainActor
public enum PoetThemeResolver {
    public private(set) static var current: ZXTheme = EnvironmentValues().zxTheme

    public static func sync(_ theme: ZXTheme) {
        current = theme
    }

    /// 这份主题用的是身份里哪一支备选强调色 (`palette.accents` 的键); 用默认 accent 时为 nil。
    /// ZXTheme 不保留 accentName (kit gap), 只能按解析出的色值反查。
    static func accentName(of theme: ZXTheme) -> String? {
        let resolved = theme.color.values.accent
        return theme.identity.palette.accents?
            .first { (theme.isDark ? $0.value.dark : $0.value.light) == resolved }?.key
    }
}

extension UIColor {
    convenience init(zxHex hex: ZXHex) {
        self.init(red: hex.red, green: hex.green, blue: hex.blue, alpha: hex.alpha)
    }
}

// MARK: - 旧的色值工具 (现存视图仍在用; M2 换成 theme token 后删)

@available(*, deprecated, message: "M2: use ZXTheme color tokens")
extension Color {
    /// Semantic colors resolve with the current appearance, including inside Canvas.
    static func adaptive(light: String, dark: String) -> Color {
        let day = UIColor(Color(hex: light))
        let night = UIColor(Color(hex: dark))
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? night : day
        })
    }

    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt64(s, radix: 16) ?? 0
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

extension Color {
    /// Text or symbols placed directly on this color. The fill can itself be dynamic,
    /// so resolve it in the active traits before choosing dark ink or light paper.
    var onFill: Color {
        let fill = UIColor(self)
        return Color(uiColor: UIColor { traits in
            fill.resolvedColor(with: traits).contrastingForeground
        })
    }
}

private extension UIColor {
    struct RGB {
        let red, green, blue: CGFloat

        var luminance: CGFloat {
            func linear(_ value: CGFloat) -> CGFloat {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        var color: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }

        func contrastRatio(with other: RGB) -> CGFloat {
            let lighter = max(luminance, other.luminance)
            let darker = min(luminance, other.luminance)
            return (lighter + 0.05) / (darker + 0.05)
        }
    }

    var opaqueRGB: RGB {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: nil)
        return RGB(red: red, green: green, blue: blue)
    }

    /// 压在填充色上的字: 两头 (近黑的墨 / 近白的纸) 里对比度更高的那一支。
    var contrastingForeground: UIColor {
        let fill = opaqueRGB
        let darkInk = RGB(red: 23.0 / 255.0, green: 24.0 / 255.0, blue: 25.0 / 255.0)
        let lightPaper = RGB(red: 255.0 / 255.0, green: 254.0 / 255.0, blue: 251.0 / 255.0)
        return darkInk.contrastRatio(with: fill) >= lightPaper.contrastRatio(with: fill)
            ? darkInk.color
            : lightPaper.color
    }
}
