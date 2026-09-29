//  ZXSpaceTokens.swift — 间距与圆角
//
//  间距是一把尺, 不是一堆数: 视图里需要 20 就用 `margin`, 需要 20 以外的值就把
//  尺上的几格加起来 (`lg + xs`), 不要临时发明 18。尺子统一了, 两个人写的页面
//  拼在一起才不会差出一两点的「毛边」。

import CoreGraphics

/// 间距。经 `theme.space` 取用。
public struct ZXSpaceTokens: Sendable, Hashable {
    public let xxs: CGFloat
    public let xs: CGFloat
    public let sm: CGFloat
    public let md: CGFloat
    public let lg: CGFloat
    public let xl: CGFloat
    public let xxl: CGFloat
    public let xxxl: CGFloat
    /// 屏幕左右边距。
    public let margin: CGFloat

    public init(xxs: CGFloat = 2, xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 16,
                xl: CGFloat = 24, xxl: CGFloat = 32, xxxl: CGFloat = 48, margin: CGFloat = 20) {
        self.xxs = xxs; self.xs = xs; self.sm = sm; self.md = md; self.lg = lg
        self.xl = xl; self.xxl = xxl; self.xxxl = xxxl; self.margin = margin
    }

    /// 标准尺。所有身份共用: 间距是版面的节奏, 不是身份的颜色。
    public static let standard = ZXSpaceTokens()
}

/// 圆角。经 `theme.radius` 取用。
///
/// 最大一级 `xl` 取 20 (与 `ZXMetric.panelRadius` 同值): 线装书、印这类方正的东西旁边,
/// 太圆的卡会显得软。要更圆的产品换一套 `ZXRadiusTokens` 传进主题, 不在视图里改数。
public struct ZXRadiusTokens: Sendable, Hashable {
    public let xs: CGFloat
    public let sm: CGFloat
    public let md: CGFloat
    public let lg: CGFloat
    public let xl: CGFloat
    /// 胶囊。给 `RoundedRectangle` 用的「足够大」; 能用 `Capsule()` 时优先用它。
    public let pill: CGFloat

    public init(xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 16,
                xl: CGFloat = 20, pill: CGFloat = 999) {
        self.xs = xs; self.sm = sm; self.md = md; self.lg = lg; self.xl = xl; self.pill = pill
    }

    public static let standard = ZXRadiusTokens()

    /// 嵌套圆角, 见 `ZXRadius.nested(in:padding:)`。
    public func nested(in parent: CGFloat, padding: CGFloat) -> CGFloat {
        ZXRadius.nested(in: parent, padding: padding)
    }
}

public enum ZXRadius: Sendable {
    /// 嵌套圆角: 内层圆角 = 外层圆角 − 内边距 (不小于 0)。
    ///
    /// 为什么: 内外两层用同一个圆角时, 两条弧线的圆心不重合, 转角处的间隙会比直边宽,
    /// 看上去内层像是「没放正」。让两条弧同心, 间隙处处等宽。
    public static func nested(in parent: CGFloat, padding: CGFloat) -> CGFloat {
        max(parent - padding, 0)
    }
}
