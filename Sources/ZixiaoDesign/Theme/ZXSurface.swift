//  ZXSurface.swift — 层级: 表面、投影、发丝线
//
//  五级抬升 (e0–e4) 只回答一个问题: 这块东西离纸有多远。离得越远, 底色越「抬」、
//  影子越大越淡。深色外观下影子几乎看不见 (暗底上的暗影), 分层就交给一道发丝线 ——
//  这件事在修饰符里自动做, 视图不必 (也不许) 读 colorScheme 自己判断。

import SwiftUI

/// 抬升级别。卡片 e1, 抬起的块 e2, sheet e3, 浮动控件 e4。
public enum ZXElevation: Int, CaseIterable, Sendable, Hashable, Comparable {
    /// 贴在纸上: 卡面色, 不投影。
    case e0
    /// 卡片。
    case e1
    /// 抬起的块 (拖动中的卡、弹出的菜单)。
    case e2
    /// sheet、底部抽屉。
    case e3
    /// 浮动控件 (浮动按钮、工具条)。
    case e4

    public static func < (a: ZXElevation, b: ZXElevation) -> Bool { a.rawValue < b.rawValue }

    /// 投影参数。纯数据, 便于测试与在 Canvas 里复用。
    public struct Shadow: Sendable, Hashable {
        /// 浅色外观下的不透明度; 深色下乘 `darkBoost` (暗底上要更浓才看得出)。
        public let opacity: Double
        public let radius: CGFloat
        public let y: CGFloat
    }

    /// 深色下影子加深的倍数。
    public static let darkBoost: Double = 2.5

    public var shadow: Shadow {
        switch self {
        case .e0: Shadow(opacity: 0, radius: 0, y: 0)
        // e1 刻意很淡: 纸上的卡主要靠卡面与纸的色差分层, 影子只是「确认一下」。
        // 影子一重, 立刻就是上一代 iOS 的卡片味 (GlazePanel 干脆不投影, 也是这个道理)。
        case .e1: Shadow(opacity: 0.05, radius: 3, y: 1)
        case .e2: Shadow(opacity: 0.08, radius: 10, y: 4)
        case .e3: Shadow(opacity: 0.12, radius: 20, y: 8)
        case .e4: Shadow(opacity: 0.16, radius: 28, y: 12)
        }
    }

    /// 这一级在深色外观下是否描发丝线。e0 贴在纸上, 不描。
    public var hairlineInDark: Bool { self != .e0 }
}

public extension View {
    /// 把视图放到某一级表面上: 表面色 + 投影 + (深色下) 发丝线。
    ///
    /// e0/e1 用 `surface`, e2 起用 `surfaceElevated` —— 深色下抬起的层要比卡面亮一档,
    /// 这是暗底上唯一可靠的「近」的信号。
    func zxSurface<S: Shape>(_ level: ZXElevation = .e1, in shape: S) -> some View {
        modifier(ZXSurfaceModifier(level: level, shape: shape))
    }

    /// 默认圆角 (`radius.lg`) 的连续圆角矩形表面。
    func zxSurface(_ level: ZXElevation = .e1) -> some View {
        modifier(ZXSurfaceModifier(level: level, shape: nil as RoundedRectangle?))
    }

    /// 只加这一级的投影 (不铺底色)。自己画了底的视图 (封面、印) 用它对齐层级。
    func zxShadow(_ level: ZXElevation) -> some View {
        modifier(ZXShadowModifier(level: level))
    }
}

private struct ZXSurfaceModifier<S: Shape>: ViewModifier {
    let level: ZXElevation
    /// nil = 用主题的 `radius.lg` 画圆角矩形 (修饰符的默认参数里读不到主题)。
    let shape: S?
    @Environment(\.zxTheme) private var theme

    func body(content: Content) -> some View {
        let fill = level >= .e2 ? theme.color.surfaceElevated : theme.color.surface
        let resolved: AnyShape = shape.map { AnyShape($0) }
            ?? AnyShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        content
            .background {
                resolved
                    .fill(fill)
                    .zxShadow(level)
            }
            .overlay {
                if theme.isDark && level.hairlineInDark {
                    resolved
                        .stroke(theme.color.separator, lineWidth: ZXMetric.hairline)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct ZXShadowModifier: ViewModifier {
    let level: ZXElevation
    @Environment(\.zxTheme) private var theme

    func body(content: Content) -> some View {
        let spec = level.shadow
        let opacity = theme.isDark ? min(spec.opacity * ZXElevation.darkBoost, 0.6) : spec.opacity
        content.shadow(color: theme.color.shadow.opacity(opacity), radius: spec.radius, x: 0, y: spec.y)
    }
}
