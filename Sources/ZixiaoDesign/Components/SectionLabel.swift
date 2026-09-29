//  SectionLabel.swift — 分栏标签
//
//  PoetKit 的教训: 上一版是「小字 + 横贯全宽的细线」, 那条线是「鬼画符感」的来源之一 ——
//  极简靠留白分栏, 不靠线。所以这里只有字, 以及身份 `slots.marker` 指定的一个小记号。

import SwiftUI

public struct SectionLabel: View, Sendable {
    let text: String
    let trailing: String?

    @Environment(\.zxTheme) private var theme
    @Environment(\.legibilityWeight) private var legibilityWeight

    public init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            SectionMarker(marker: theme.identity.slots.marker, color: theme.seal)
            Text(text)
                .font(theme.uiFont(13, weight: .medium, relativeTo: .footnote, legibilityWeight: legibilityWeight))
                .tracking(0.5)                  // 中文加宽到 3 就散气了, 0.5 刚好透气
                .foregroundStyle(theme.accent)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(theme.uiFont(13, relativeTo: .footnote, legibilityWeight: legibilityWeight))
                    .foregroundStyle(theme.muted)
            }
        }
    }
}

/// 分节记号。方印点是「一屏唯一的朱砂」的缩写: 不画满四字印 (那要 54pt 才认得出),
/// 只留印的「方」这个意思。圆点是更不确定的标记 (PoetKit 里给行迹多为推定的诗人)。
private struct SectionMarker: View {
    let marker: ZXIdentity.Slots.Marker?
    let color: Color
    @ScaledMetric(relativeTo: .footnote) private var side: CGFloat = 6

    var body: some View {
        switch marker {
        case .sealSquare:
            RoundedRectangle(cornerRadius: side * 0.2, style: .continuous)
                .fill(color).frame(width: side, height: side)
                .accessibilityHidden(true)
        case .dot:
            Circle().fill(color).frame(width: side, height: side)
                .accessibilityHidden(true)
        case .brushDot:
            // 飞白一点: 椭圆略斜, 像笔锋落纸一顿
            Ellipse().fill(color).frame(width: side * 1.3, height: side * 0.9)
                .rotationEffect(.degrees(-20))
                .accessibilityHidden(true)
        case nil:
            EmptyView()
        }
    }
}

#if DEBUG
#Preview("分栏标签") {
    PreviewPage {
        SectionLabel("今日宜读")
        SectionLabel("书架", trailing: "共 12 部")
    }
}
#endif
