//  EmptyState.swift — 空态
//
//  空态是一页里最安静的时刻, 给一句古语比给一个灰色图标更像这套产品。
//  古语与出处由调用方传入: 用哪句话是产品的编辑决定, 不是内核的。

import SwiftUI

public struct EmptyState<Actions: View>: View {
    let title: String
    let quote: String?
    let source: String?
    let systemImage: String?
    let actions: Actions

    @Environment(\.zxTheme) private var theme
    @Environment(\.legibilityWeight) private var legibilityWeight

    /// - Parameters:
    ///   - title: 一句说明发生了什么 (「书架还空着」)。
    ///   - quote: 古语 (「学而时习之」)。
    ///   - source: 出处 (「论语 · 学而」), 前面自动加破折号。
    ///   - systemImage: 可选图标; 单色系里示警靠形状不靠颜色, 报错类空态建议给一个。
    ///   - actions: 可选操作按钮。
    public init(_ title: String, quote: String? = nil, source: String? = nil,
                systemImage: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.quote = quote
        self.source = source
        self.systemImage = systemImage
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(.title2, weight: .light))
                    .foregroundStyle(theme.ink(0.35))
                    .accessibilityHidden(true)
            }
            if let quote {
                Text(quote)
                    .font(theme.bodyFont(19, relativeTo: .title3, legibilityWeight: legibilityWeight))
                    .foregroundStyle(theme.ink(0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }
            if let source {
                Text("—— \(source)")
                    .font(theme.uiFont(13, relativeTo: .footnote, legibilityWeight: legibilityWeight))
                    .foregroundStyle(theme.muted)
            }
            Text(title)
                .font(theme.uiFont(15, relativeTo: .subheadline, legibilityWeight: legibilityWeight))
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, quote == nil ? 0 : 6)
            actions
                .padding(.top, 4)
        }
        .frame(maxWidth: 320)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

public extension EmptyState where Actions == EmptyView {
    init(_ title: String, quote: String? = nil, source: String? = nil, systemImage: String? = nil) {
        self.init(title, quote: quote, source: source, systemImage: systemImage) { EmptyView() }
    }
}

#if DEBUG
#Preview("空态") {
    PreviewPage {
        EmptyState("书架还空着", quote: "学而时习之，不亦说乎", source: "论语 · 学而") {
            Button("去书库看看") {}
        }
        EmptyState("暂时无法载入", systemImage: "wifi.exclamationmark")
    }
}
#endif

extension EmptyState: Sendable where Actions: Sendable {}
