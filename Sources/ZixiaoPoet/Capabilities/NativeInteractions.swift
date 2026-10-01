//  NativeInteractions.swift — 能力视图共用的小件 (不是 shim)
//
//  这里只放「读主题 token 的通用件」: 转场、分节标题、栏宽、操作按钮样式、载入 / 失败态、
//  同一身份按另一种外观重解析。

import SwiftUI
import ZixiaoDesign

// MARK: - 读本转场

extension View {
    func readingTransitionSource<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        modifier(ReadingTransitionSource(id: id, namespace: namespace))
    }
    func readingTransition<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        modifier(ReadingTransition(id: id, namespace: namespace))
    }
}

private struct ReadingTransitionSource<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *), !reduceMotion {
            content.matchedTransitionSource(id: id, in: namespace)
        } else { content }
    }
}

private struct ReadingTransition<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *), !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else { content }
    }
}

// MARK: - 分节标题

/// 页内一节的标题 + 右侧附件 (「全部」链接、计数)。字与色全部来自主题;
/// 无障碍大字号下附件折到标题下方。分栏小标签用 kit 的 `SectionLabel`, 这一级是更大的节标题。
struct NativeSectionHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: theme.space.sm) { heading; styledAccessory }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: theme.space.md) {
                    heading
                    Spacer(minLength: theme.space.xs)
                    styledAccessory
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var heading: some View {
        Text(title).font(theme.type.title2).tracking(theme.type.tracking(for: .title2))
            .foregroundStyle(theme.color.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
    private var styledAccessory: some View {
        accessory.font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
    }
}

extension NativeSectionHeader where Accessory == EmptyView {
    init(_ title: String) { self.title = title; self.accessory = EmptyView() }
}

/// 分栏标签 + 右侧「全部」链接。书架、书房各节共用: 标签是 kit 的 `SectionLabel`
/// (身份记号 + 强调色小字), 链接保证 44pt 点按区。
struct ShelfHeader<Destination: View>: View {
    let title: String
    var linkTitle = "全部"
    let accessibilityLabel: String
    @ViewBuilder var destination: () -> Destination
    @Environment(\.zxTheme) private var theme
    var body: some View {
        HStack(alignment: .center, spacing: theme.space.sm) {
            ZixiaoDesign.SectionLabel(title)
            NavigationLink(destination: destination) {
                HStack(spacing: theme.space.xs) {
                    Text(linkTitle)
                    Image(systemName: "chevron.right").font(theme.type.caption)
                }
                .font(theme.type.subhead)
                .foregroundStyle(theme.color.accent)
                .frame(minHeight: PoetLayout.minHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

/// 分组列表 (`List` + `Section`) 的节头: 系统节头的字是系统字族, 这里换成身份的操作层字。
struct ListSectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    @Environment(\.zxTheme) private var theme
    var body: some View {
        Text(text).font(theme.type.footnote.weight(.medium))
            .foregroundStyle(theme.color.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 栏宽与按钮

/// 页面级的几个固有尺寸。ZX token 里没有「读本栏宽」(页面级尺度由产品定, kit gap 已记),
/// 这里是具名常量, 不是间距。
enum PoetLayout {
    /// 读本正文的最大栏宽 (宽屏上不让一行拉得太长)。
    static let readingWidth: CGFloat = 760
    /// 最小点按区。
    static let minHitTarget: CGFloat = 44
}

extension View {
    func poetReadableWidth(_ width: CGFloat = PoetLayout.readingWidth) -> some View {
        frame(maxWidth: width)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder func poetActionStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// iOS 26 的大标题下面可以直接挂一行副标题。低版本没有这个 API，调用方自己在内容区补一行。
    /// 新代码请直接用 `.zxNavigationTitle(_:subtitle:role:)`。
    @ViewBuilder func poetNavigationSubtitle(_ text: String) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { self.navigationSubtitle(text) } else { self }
        #else
        self
        #endif
    }
}

/// iOS 26 是否有 navigationSubtitle —— 决定日期挂在导航栏还是画进内容区。
@MainActor public var hasNavigationSubtitle: Bool {
    if #available(iOS 26.0, *) { return true } else { return false }
}

/// One optical sampling container for adjacent custom navigation surfaces.
struct PoetGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: ZXSpaceTokens.standard.md) { content }
        } else { content }
    }
}

// MARK: - 载入 / 失败

struct LoadFailureView: View {
    var title = "暂时无法载入"
    var message = "请检查网络连接后重试。"
    var retry: () async -> Void
    @State private var retrying = false
    @Environment(\.zxTheme) private var theme
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
                .font(theme.type.title3)
                .foregroundStyle(theme.color.textPrimary)
        } description: {
            Text(message).font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
        } actions: {
            Button(retrying ? "正在重试…" : "重试") {
                Task { retrying = true; await retry(); retrying = false }
            }
            .font(theme.type.headline)
            .poetActionStyle()
            .disabled(retrying)
        }
        .tint(theme.color.accent)
    }
}

struct LoadingStateView: View {
    var label = "正在载入…"
    @Environment(\.zxTheme) private var theme
    /// 载入态占位的最小高度 (固有尺寸: 不让列表在载入时塌成一条线)。
    private static let minHeight: CGFloat = 140
    var body: some View {
        ProgressView {
            Text(label).font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
        }
        .tint(theme.color.accent)
        .frame(maxWidth: .infinity, minHeight: Self.minHeight)
        .accessibilityLabel(label)
    }
}

/// 一行错误提示: 形状 (图标) + 字, 不只靠颜色示警。字取 `ZXCoreError` 等的 `errorDescription`。
struct PoetErrorLine: View {
    let message: String
    @Environment(\.zxTheme) private var theme
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(theme.type.footnote)
            .foregroundStyle(theme.color.danger)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

// MARK: - 外观重解析

extension ZXTheme {
    /// 同一身份、同一支备选强调色、同一粗体设置, 按另一种外观重新解析 (夜读局部强制深色、
    /// 图版查看器的暗场用)。
    ///
    /// `.zxTheme(identity)` 只按 App 根的外观解析一次; 子树里 `.environment(\.colorScheme, .dark)`
    /// 不会让环境里的 ZXTheme 跟着变。ZXTheme 也不保留 accentName (kit gap), 只能按解析出的
    /// 强调色反查调色板里的备选名。季节偏色反查不到 (诗人应用不用)。
    func poetResolved(for scheme: ColorScheme) -> ZXTheme {
        guard scheme != colorScheme else { return self }
        let resolved = color.values.accent
        let accentName = identity.palette.accents?
            .first { (isDark ? $0.value.dark : $0.value.light) == resolved }?.key
        return ZXTheme(identity, colorScheme: scheme, accentName: accentName,
                       legibilityWeight: type.legibilityWeight, space: space, radius: radius, motion: motion)
    }
}
