//  InkDivider.swift — 分隔线
//
//  系统 Divider 的颜色是系统分隔色, 与身份无关; 这里取身份的 rule 槽。
//  分隔线能不用就不用 (见 SectionLabel 的说明), 真要用时给两种:
//  一道发丝线, 或两头淡出的「墨痕」—— 后者像毛笔拖过, 用在题记与正文之间这类有仪式感的地方。

import SwiftUI

public struct InkDivider: View, Sendable {
    public enum Style: Sendable, Hashable {
        /// 通长发丝线。
        case hairline
        /// 两头淡出。
        case tapered
    }

    let axis: Axis
    let style: Style

    @Environment(\.zxTheme) private var theme
    @Environment(\.displayScale) private var displayScale

    public init(_ axis: Axis = .horizontal, style: Style = .hairline) {
        self.axis = axis
        self.style = style
    }

    public var body: some View {
        // 至少一个物理像素: @2x 屏上半点正好一像素, @3x 屏上是一个半, 都看得见。
        let thickness = max(ZXMetric.hairline, 1 / displayScale)
        Rectangle()
            .fill(fill)
            .frame(width: axis == .vertical ? thickness : nil,
                   height: axis == .horizontal ? thickness : nil)
            .frame(maxWidth: axis == .horizontal ? .infinity : nil,
                   maxHeight: axis == .vertical ? .infinity : nil)
            .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        switch style {
        case .hairline:
            return AnyShapeStyle(theme.rule)
        case .tapered:
            let stops = [theme.rule.opacity(0), theme.rule, theme.rule, theme.rule.opacity(0)]
            return axis == .horizontal
                ? AnyShapeStyle(LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing))
                : AnyShapeStyle(LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom))
        }
    }
}

#if DEBUG
#Preview("分隔线") {
    PreviewPage {
        Text("发丝线").font(ZXFont.serif(15))
        InkDivider()
        Text("墨痕").font(ZXFont.serif(15))
        InkDivider(style: .tapered)
        HStack {
            Text("左")
            InkDivider(.vertical).frame(height: 40)
            Text("右")
        }
    }
}
#endif
