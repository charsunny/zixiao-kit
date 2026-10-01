//  PoetAppRoot.swift — 由编成装配界面。
//
//  这里没有任何 if poet == ... 的分支：胶囊里放什么、分离钮是谁、
//  哪个能力寄居在哪个能力里，全部由 composition.json 说了算。
//
//  根壳交给 kit 的 `ZXTabShell` (与玄览同法): 系统 TabView + iOS 26 悬浮栏, 每个 Tab 一个由壳持有的
//  NavigationStack, 重选当前 Tab 回根 / 滚到顶, 滚动时收起 Tab 栏。编成里的 hero 能力 (检索类)
//  映射成 `ZXTab(isSearch: true)` —— iOS 18 起 `Tab(role: .search)`, 26 起是 Tab 栏右侧分离的搜索钮,
//  17 回退普通 Tab (壳负责)。Tab 的顺序与名字一律取编成。

import SwiftUI
import ZixiaoDesign

public struct PoetAppRoot: View {
    @State private var ctx: CompositionContext
    @State private var selection: String
    @Environment(\.zxTheme) private var theme

    public init(context: CompositionContext) {
        _ctx = State(initialValue: context)
        _selection = State(initialValue: Self.initialTab(context).rawValue)
    }

    /// 设计迭代用：`-tab itinerary` 直接落到某个能力，省去在模拟器里手点。
    /// 只在 DEBUG 生效，发布包里这段不存在。
    private static func initialTab(_ ctx: CompositionContext) -> CapabilityID {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "tab"),
           let id = CapabilityID(rawValue: raw),
           ctx.composition.capsuleTabs.contains(where: { $0.id == id }) || ctx.composition.heroTab?.id == id {
            return id
        }
        #endif
        return ctx.composition.capsuleTabs.first?.id ?? .daily
    }

    /// 编成 → Tab 列表: 胶囊按 order, hero (至多一个, 只能是检索类) 放最后做搜索 Tab。
    private var tabs: [ZXTab] {
        var tabs = ctx.composition.capsuleTabs.map { tab in
            ZXTab(id: tab.id.rawValue, title: tab.placement.label, systemImage: tab.id.symbol)
        }
        if let hero = ctx.composition.heroTab {
            tabs.append(ZXTab(id: hero.id.rawValue, title: hero.placement.label,
                              systemImage: hero.id.symbol, isSearch: true))
        }
        return tabs
    }

    public var body: some View {
        ZXTabShell(tabs: tabs, selection: $selection) { tab in
            if let id = CapabilityID(rawValue: tab.id) {
                CapabilityRegistry.root(id, ctx)
            }
        }
        // 全局 tint 走身份的 accent, Tab 栏与系统控件的高亮不落回系统蓝。
        .tint(theme.color.accent)
        // 账号与用户数据由 PoetAppBoot 启动 (`startSession`); 这里只拉只读骨架。
        .task { await ctx.store.bootstrap() }
    }
}

enum CapabilityRegistry {
    /// 各能力的 Tab 根页。壳已给每个 Tab 一个 NavigationStack, 根页不再自带导航容器 ——
    /// 包括 NavigationSplitView: 它放进 NavigationStack 里整页不渲染 (iOS 27 模拟器实测空白)。
    /// 作品 (`CorpusView`) 与生平 / 背景 (`NarrativeWorkspaceView`) 都是栈内的窄屏根页 / 宽屏两栏。
    @MainActor @ViewBuilder
    static func root(_ id: CapabilityID, _ ctx: CompositionContext) -> some View {
        switch id {
        case .daily:     DailyView(ctx: ctx)
        case .itinerary: ItineraryView(ctx: ctx)
        case .corpus:    CorpusView(ctx: ctx)
        case .search:    SearchZeroStateView(ctx: ctx)
        case .profile:   ProfileView(ctx: ctx)
        case .network:   NetworkView(ctx: ctx)
        case .context:   ContextView(ctx: ctx)
        case .epochs:    LifeOverviewView(ctx: ctx)
        }
    }
}
