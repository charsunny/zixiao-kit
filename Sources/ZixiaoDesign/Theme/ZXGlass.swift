//  ZXGlass.swift — 玻璃 (浮动层)
//
//  玻璃只给浮在内容之上的东西: 工具条、浮动按钮、胶囊控件。不给卡片、不给正文底 ——
//  玻璃后面透出滚动的正文, 17pt 的字就游起来了 (GlazePanel 的说明里讲过同一件事)。
//  也不叠玻璃: 玻璃上再放玻璃, 两层折射互相打架。
//
//  三条路径:
//  - iOS 26 起: 系统 `glassEffect` (Liquid Glass)。
//  - iOS 17/18: `ultraThinMaterial` + 一层纸气 (glassTint) + 发丝线, 模拟「一片有边的薄玻璃」。
//  - 减少透明度: 不透明的 `surfaceElevated` + 发丝线。用户关掉透明就是要读得清, 不给半透明。

import SwiftUI

public extension View {
    /// 把视图放在一片玻璃上。
    ///
    /// - Parameters:
    ///   - shape: 玻璃的形状 (胶囊、圆、圆角矩形)。
    ///   - interactive: 可交互的玻璃 (iOS 26 按下时会有光学反馈)。按钮、胶囊控件传 true。
    ///   - tint: 着色。只给「这是主操作」的那一片; nil 为无色玻璃。
    func zxGlass<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(ZXGlassModifier(shape: shape, interactive: interactive, tint: tint))
    }

    /// 胶囊玻璃。
    func zxGlass(interactive: Bool = false, tint: Color? = nil) -> some View {
        zxGlass(in: Capsule(), interactive: interactive, tint: tint)
    }
}

private struct ZXGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?
    @Environment(\.zxTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(tint ?? theme.color.surfaceElevated, in: shape)
                .overlay { shape.stroke(theme.color.separator, lineWidth: ZXMetric.hairline).allowsHitTesting(false) }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(tint.map { $0.opacity(0.35) } ?? theme.color.glassTint)
                    }
                    .zxShadow(.e4)
                }
                .overlay { shape.stroke(theme.color.separator, lineWidth: ZXMetric.hairline).allowsHitTesting(false) }
        }
    }
}
