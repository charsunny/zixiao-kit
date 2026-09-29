//  ZXTabShell.swift — 根 Tab 壳
//
//  只用系统 TabView, 不自绘 tab bar: iOS 26 起系统 tab bar 自带 Liquid Glass 的悬浮栏、
//  滚动时收起、无障碍与键盘支持, 自绘一条就要把这些全部重做一遍, 而且永远慢系统一拍。
//
//  壳负责三件系统不替你做的事:
//  1. 每个 Tab 一个 NavigationStack, path 由壳持有 —— 切走再切回来, 各自的栈还在。
//  2. 重选当前 Tab: 栈不空就弹回根; 已在根就滚到顶 (经 `\.zxScrollToTop`)。
//     这是 iOS 用户的肌肉记忆, 系统 TabView 在 SwiftUI 里不给这个行为。
//  3. iOS 26 起滚动时收起 tab bar (`tabBarMinimizeBehavior(.onScrollDown)`), 把屏幕让给内容。

import SwiftUI

/// 一个 Tab 的描述。纯数据: 标题、图标、角标; 内容由 `ZXTabShell` 的闭包按 Tab 给出。
public struct ZXTab: Identifiable, Hashable, Sendable {
    /// 稳定的标识, 也是 selection 的值。不要用标题当 id —— 标题会本地化, id 不能变。
    public let id: String
    public let title: String
    /// SF Symbol 名。
    public let systemImage: String
    /// 角标数字; nil 或 0 不显示。
    public let badge: Int?

    public init(id: String, title: String, systemImage: String, badge: Int? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.badge = badge
    }
}

// MARK: - 滚到顶

/// 「滚到顶」请求。壳在用户重选当前 Tab 且已在根页时递增 `generation`;
/// `ZXShellScrollView` 看到它变了就滚到顶。自己写滚动容器的页面也可以读它。
///
/// 为什么是一个递增的数而不是闭包: 方向是壳 → 滚动视图, 壳不知道 (也不该知道) 页面里
/// 有几个滚动视图; 广播一个「第几次请求」, 谁关心谁响应, 值类型还能天然 Sendable。
public struct ZXScrollToTop: Sendable, Hashable {
    public let generation: Int
    public init(generation: Int) { self.generation = generation }
    /// 从未请求过。
    public static let idle = ZXScrollToTop(generation: 0)
}

private struct ZXScrollToTopKey: EnvironmentKey {
    static let defaultValue = ZXScrollToTop.idle
}

public extension EnvironmentValues {
    var zxScrollToTop: ZXScrollToTop {
        get { self[ZXScrollToTopKey.self] }
        set { self[ZXScrollToTopKey.self] = newValue }
    }
}

/// 响应「滚到顶」的 ScrollView。Tab 根页用它代替 ScrollView。
public struct ZXShellScrollView<Content: View>: View {
    let axes: Axis.Set
    let showsIndicators: Bool
    let content: Content

    @Environment(\.zxScrollToTop) private var scrollToTop
    @Environment(\.zxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 顶端锚点的 id。放在内容之前的一个零高视图上, 滚到它就是滚到顶。
    private enum Anchor: Hashable { case top }

    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(axes, showsIndicators: showsIndicators) {
                // ScrollViewReader 在 iOS 17 上就有; 18 的 ScrollPosition 更顺手, 但为一个
                // 「滚到顶」分两条路径不值得。零高锚点不占布局。
                VStack(spacing: 0) {
                    Color.clear.frame(width: 0, height: 0).id(Anchor.top)
                    content
                }
            }
            .onChange(of: scrollToTop) { _, _ in
                withAnimation(theme.motion.adapted(theme.motion.smooth, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(Anchor.top, anchor: .top)
                }
            }
        }
    }
}

// MARK: - 壳

public struct ZXTabShell<Content: View>: View {
    let tabs: [ZXTab]
    let external: Binding<String>?
    /// 各 Tab 的根页, 在 init 里按 Tab 求值 (与 @ViewBuilder 内容的惯常语义一致:
    /// 父视图重算时整个壳重建, 根页随之更新), 这样闭包不必逃逸。
    let roots: [String: Content]

    @State private var ownSelection: String
    @State private var paths: [String: NavigationPath] = [:]
    @State private var scrollRequests: [String: Int] = [:]
    @Environment(\.zxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - tabs: Tab 列表, 顺序即显示顺序。
    ///   - selection: 外部持有的选中 Tab id (深链、恢复状态用); nil 则壳自己持有, 默认第一个。
    ///   - content: 每个 Tab 的根页。壳会把它包进这个 Tab 自己的 NavigationStack;
    ///     根页里用 `NavigationLink(value:)` + `.navigationDestination(for:)` 推页。
    public init(tabs: [ZXTab], selection: Binding<String>? = nil,
                @ViewBuilder content: (ZXTab) -> Content) {
        self.tabs = tabs
        self.external = selection
        var roots: [String: Content] = [:]
        for tab in tabs { roots[tab.id] = content(tab) }
        self.roots = roots
        _ownSelection = State(initialValue: selection?.wrappedValue ?? tabs.first?.id ?? "")
    }

    private var current: String { external?.wrappedValue ?? ownSelection }

    /// 给 TabView 的选中绑定。
    ///
    /// 为什么自己包一层: TabView 的 setter 在用户点**已选中**的 Tab 时也会被调用 (值不变),
    /// 这是 SwiftUI 里唯一能听到「重选」的地方。
    private var selection: Binding<String> {
        Binding(
            get: { current },
            set: { newValue in
                if newValue == current {
                    reselect(newValue)
                } else if let external {
                    external.wrappedValue = newValue
                } else {
                    ownSelection = newValue
                }
            }
        )
    }

    /// 重选: 栈不空 → 弹回根; 已在根 → 请求滚到顶。
    private func reselect(_ id: String) {
        if let path = paths[id], !path.isEmpty {
            withAnimation(theme.motion.adapted(theme.motion.smooth, reduceMotion: reduceMotion)) {
                paths[id] = NavigationPath()
            }
        } else {
            scrollRequests[id, default: 0] += 1
        }
    }

    private func path(for id: String) -> Binding<NavigationPath> {
        Binding(get: { paths[id] ?? NavigationPath() }, set: { paths[id] = $0 })
    }

    @ViewBuilder
    private func stack(for tab: ZXTab) -> some View {
        NavigationStack(path: path(for: tab.id)) {
            roots[tab.id]
        }
        .environment(\.zxScrollToTop, ZXScrollToTop(generation: scrollRequests[tab.id] ?? 0))
    }

    public var body: some View {
        if #available(iOS 18.0, *) {
            let view = TabView(selection: selection) {
                ForEach(tabs) { tab in
                    Tab(tab.title, systemImage: tab.systemImage, value: tab.id) {
                        stack(for: tab)
                    }
                    .badge(tab.badge ?? 0)
                    .accessibilityIdentifier("zx.tab.\(tab.id)")
                }
            }
            if #available(iOS 26.0, *) {
                view.tabBarMinimizeBehavior(.onScrollDown)
            } else {
                view
            }
        } else {
            TabView(selection: selection) {
                ForEach(tabs) { tab in
                    stack(for: tab)
                        .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                        .badge(tab.badge ?? 0)
                        .tag(tab.id)
                }
            }
        }
    }
}

// MARK: - 预览

#if DEBUG
private struct ZXTabShellPreviewRoot: View {
    let tab: ZXTab
    @Environment(\.zxTheme) private var theme

    var body: some View {
        ZXShellScrollView {
            LazyVStack(alignment: .leading, spacing: theme.space.md) {
                ForEach(1...30, id: \.self) { i in
                    NavigationLink(value: i) {
                        HStack {
                            Text("\(tab.title) · 第 \(i) 条").font(theme.type.body)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(theme.type.footnote)
                        }
                        .foregroundStyle(theme.color.textPrimary)
                        .padding(theme.space.lg)
                        .zxSurface(.e1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, theme.space.margin)
        }
        .background(theme.color.bg)
        .navigationTitle(tab.title)
        .navigationDestination(for: Int.self) { i in
            Text("第 \(i) 条").font(theme.type.title2).foregroundStyle(theme.color.textPrimary)
        }
    }
}

#Preview("Tab 壳") {
    PreviewPage {
        ZXTabShell(tabs: [
            ZXTab(id: "today", title: "今日", systemImage: "sun.horizon"),
            ZXTab(id: "study", title: "书斋", systemImage: "books.vertical", badge: 2),
            ZXTab(id: "me", title: "我的", systemImage: "person"),
        ]) { tab in
            ZXTabShellPreviewRoot(tab: tab)
        }
        .frame(height: 460)
    }
}
#endif
