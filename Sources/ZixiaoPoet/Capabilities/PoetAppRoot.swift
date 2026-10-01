//  PoetAppRoot.swift — 由编成装配界面。
//
//  这里没有任何 if poet == ... 的分支：胶囊里放什么、分离钮是谁、
//  哪个能力寄居在哪个能力里，全部由 composition.json 说了算。

import SwiftUI
import ZixiaoDesign

public struct PoetAppRoot: View {
    @State private var ctx: CompositionContext
    @State private var selection: CapabilityID
    @State private var searchPath = NavigationPath()
    @Environment(\.zxTheme) private var zxTheme

    public init(context: CompositionContext) {
        _ctx = State(initialValue: context)
        _selection = State(initialValue: Self.initialTab(context))
    }

    /// 设计迭代用：`-tab itinerary` 直接落到某个能力，省去在模拟器里手点。
    /// 只在 DEBUG 生效，发布包里这段不存在。
    private static func initialTab(_ ctx: CompositionContext) -> CapabilityID {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "tab"),
           let id = CapabilityID(rawValue: raw) { return id }
        #endif
        return ctx.composition.capsuleTabs.first?.id ?? .daily
    }

    public var body: some View {
        content
            .tint(ctx.theme.accent)
            // shim 跟着环境里的主题走 (身份 / 强调色 / 粗体文本变化时重建; 浅深由动态色自己解析)。
            .onChange(of: zxTheme.color, initial: true) { syncTheme() }
            .onChange(of: zxTheme.type) { syncTheme() }
            // 账号与用户数据由 PoetAppBoot 启动 (`startSession`); 这里只拉只读骨架。
            .task { await ctx.store.bootstrap() }
    }

    private func syncTheme() {
        PoetThemeResolver.sync(zxTheme)
        ctx.theme = Theme(zxTheme)
    }

    @ViewBuilder private var content: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            TabView(selection: $selection) {
                // 胶囊：2–4 个，按编成的 order 排
                ForEach(ctx.composition.capsuleTabs, id: \.id) { tab in
                    Tab(tab.placement.label, systemImage: tab.id.symbol, value: tab.id) {
                        CapabilityRegistry.root(tab.id, ctx)
                    }
                }
                // 分离圆钮：系统只由 role: .search 承载，所以它只能是检索类能力。
                // 搜索零态提供作品、地点、人物和年份的具体线索。
                if let hero = ctx.composition.heroTab {
                    Tab(hero.placement.label, systemImage: hero.id.symbol,
                        value: hero.id, role: .search) {
                        NavigationStack(path: $searchPath) {
                            CapabilityRegistry.root(hero.id, ctx)
                        }
                    }
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
        } else { legacy }
        #else
        legacy
        #endif
    }

    /// iOS 25 及以下：没有胶囊也没有分离钮，检索降级成普通 tab。
    private var legacy: some View {
        TabView(selection: $selection) {
            ForEach(ctx.composition.capsuleTabs, id: \.id) { tab in
                CapabilityRegistry.root(tab.id, ctx)
                    .tabItem { Label(tab.placement.label, systemImage: tab.id.symbol) }
                    .tag(tab.id)
            }
            if let hero = ctx.composition.heroTab {
                NavigationStack { CapabilityRegistry.root(hero.id, ctx) }
                    .tabItem { Label(hero.placement.label, systemImage: hero.id.symbol) }
                    .tag(hero.id)
            }
        }
    }
}

enum CapabilityRegistry {
    @MainActor @ViewBuilder
    static func root(_ id: CapabilityID, _ ctx: CompositionContext) -> some View {
        switch id {
        case .daily:     NavigationStack { DailyView(ctx: ctx) }
        case .itinerary: ItineraryView(ctx: ctx)
        case .corpus:    CorpusView(ctx: ctx)
        case .search:    SearchZeroStateView(ctx: ctx)
        case .profile:   NavigationStack { ProfileView(ctx: ctx) }
        case .network:   NavigationStack { NetworkView(ctx: ctx) }
        case .context:   ContextView(ctx: ctx)
        case .epochs:    NavigationStack { LifeOverviewView(ctx: ctx) }
        }
    }
}
