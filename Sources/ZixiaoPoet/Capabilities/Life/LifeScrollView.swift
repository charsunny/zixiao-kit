//  LifeScrollView.swift — 一生长卷: 叙事 Tab 的根页 (有刻时)
//
//  一条 `ZXShellScrollView` 从第一卷滚到最后一卷: 每卷 封面 → 刻 → 卷末。前沿一条年轨 (覆盖层)
//  拖动跳卷; 刻旁的年份点开是当年的年谱 sheet。工具栏两个下钻: 行迹 (地图) 与 年谱 (编年目录)。
//  宽屏 (iPad) 同一条长卷, 栏宽 720 居中, 年轨仍贴屏幕前沿, 不分栏。
//
//  包里没有刻 (`ctx.moments == nil`) 时根本不会到这里: `CapabilityRegistry` 退回 `NarrativeWorkspaceView`。

import SwiftUI
import ZixiaoDesign

struct LifeScrollView: View {
    let ctx: CompositionContext
    let moments: PoetMoments
    let capability: CapabilityID
    @State private var model = LifeScrollModel()
    @State private var route: LifeRoute?
    @State private var sheetYear: LifeYear?
    /// 当前看到的卷 (epochSequence), 由各卷的位置算出; 年轨据此高亮。
    @State private var current: Int?
    /// 一卷的顶边落在视口这一比例之上, 就算「看到了这一卷」。
    private static let currentProbe: CGFloat = 0.4
    private nonisolated static let space = "life.scroll"
    @Namespace private var readings
    @Environment(\.zxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var chapters: [PoetMoments.Chapter] { moments.chapters }
    private var title: String { ctx.composition.placement(capability)?.label ?? ctx.narrativeLabel }
    private var networkLabel: String {
        ctx.composition.lenses(hostedIn: capability).first { $0.id == .network }?.placement.label
            ?? ctx.composition.placement(.network)?.label ?? "交游"
    }
    private var allWorkIDs: [UUID] {
        let fromMoments = chapters.flatMap(\.moments).compactMap(\.workId)
        let fromShelves = chapters.compactMap { chapter in
            ctx.guide?.chapters.first { $0.id == chapter.epochSequence }?.workIDs
        }.flatMap { $0 }
        return fromMoments + fromShelves
    }

    var body: some View {
        GeometryReader { outer in
            let metrics = metrics(for: outer)
            let probe = outer.size.height * Self.currentProbe
            ScrollViewReader { proxy in
                ZXShellScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // ForEach 的身份就是锚点: 懒加载里还没实例化的卷, scrollTo 只认得 ForEach 的 id。
                        ForEach(Array(chapters.enumerated()), id: \.element.anchor) { index, chapter in
                            LifeChapterSection(ctx: ctx, chapter: chapter, position: index + 1, metrics: metrics,
                                               model: model, actions: actions, namespace: readings)
                                .onGeometryChange(for: Bool.self) { geometry in
                                    let frame = geometry.frame(in: .named(Self.space))
                                    return frame.minY <= probe && frame.maxY > probe
                                } action: { isCurrent in
                                    if isCurrent { current = chapter.epochSequence }
                                }
                        }
                        footer(metrics)
                    }
                    .frame(maxWidth: LifeLayout.contentWidth)
                    .frame(maxWidth: .infinity)
                }
                .coordinateSpace(.named(Self.space))
                .overlay(alignment: .leading) {
                    if chapters.count > 1 {
                        LifeYearTrack(chapters: chapters, current: current) { sequence in
                            proxy.scrollTo(LifeAnchor.chapter(sequence), anchor: .top)
                        }
                        .padding(.vertical, theme.space.lg)
                    }
                }
                .task { await debugLaunch(proxy) }
            }
        }
        .background(theme.paper())
        .foregroundStyle(theme.color.textPrimary)
        .zxNavigationTitle(title, role: .root)
        .toolbar { toolbar }
        .navigationDestination(item: $route) { destination($0) }
        .sheet(item: $sheetYear) { item in yearSheet(item.year) }
        .task { await model.prefetch(allWorkIDs, guide: ctx.guide, store: ctx.store) }
    }

    // MARK: 版面

    private func metrics(for proxy: GeometryProxy) -> LifeMetrics {
        let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        let column = min(proxy.size.width, LifeLayout.contentWidth)
        // 封面约占屏高 3/4; 横屏 / 分屏时以栏宽为界, 不让一幅画比它宽得多或窄得多。
        let cover = min(max(screenHeight * 0.75, column * 0.75), column * 1.8)
        // 栏贴着屏幕前沿 (窄屏) 时让出年轨; 宽屏栏居中, 年轨在栏外, 照常留页边。
        let gutter = (proxy.size.width - column) / 2
        let leading = gutter >= LifeLayout.trackInset ? theme.space.margin : LifeLayout.trackInset + theme.space.xs
        return LifeMetrics(coverHeight: cover.rounded(), leadingInset: leading, trailingInset: theme.space.margin)
    }

    // MARK: 动作

    private var actions: LifeActions {
        LifeActions(
            open: { route = $0 },
            openYear: { year in if ctx.hasChronicleData { sheetYear = LifeYear(year: year) } },
            openWork: { id, source in
                Task {
                    if let poem = await model.resolve(id, store: ctx.store) { route = .poem(poem, source: source) }
                }
            })
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            // 这一页的朱色留给卷封面的印与刻的墨点; 工具钮用墨。
            if ctx.hasItineraryData {
                Button("行迹") { route = .map }
                    .tint(theme.color.textPrimary)
                    .accessibilityHint("在地图上看行迹")
            }
            if ctx.hasChronicleData {
                Button("年谱") { route = .chronicle }
                    .tint(theme.color.textPrimary)
                    .accessibilityHint("按年查阅事目")
            }
        }
    }

    @ViewBuilder private func destination(_ route: LifeRoute) -> some View {
        switch route {
        case .map:
            AnyView(LifeMapView(ctx: ctx).zxNavigationTitle("行迹", role: .secondary))
        case .chronicle:
            AnyView(ChronicleList(ctx: ctx, upTo: ctx.composition.poet.death)
                .zxNavigationTitle("年谱", role: .secondary))
        case .network:
            AnyView(NetworkView(ctx: ctx).zxNavigationTitle(networkLabel, role: .secondary))
        case .poem(let poem, let source):
            PoemDetailView(ctx: ctx, poem: poem).readingTransition(source, in: readings)
        case .sources:
            if let guide = ctx.guide { AnyView(GuideSourcesView(ctx: ctx, guide: guide)) }
        case .artwork(let id):
            if let artwork = ctx.artworks.first(where: { $0.id == id }) {
                ArtworkDetailView(ctx: ctx, artwork: artwork).readingTransition(id, in: readings)
            }
        }
    }

    private func yearSheet(_ year: Int) -> some View {
        NavigationStack {
            ChronicleEventsView(ctx: ctx, year: year)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { sheetYear = nil }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(theme.color.textPrimary)
    }

    /// 长卷尾: 资料与纪年说明 (原叙事工作区目录里的那一项, 长卷里放到最后)。
    @ViewBuilder private func footer(_ metrics: LifeMetrics) -> some View {
        if ctx.guide != nil {
            Button { route = .sources } label: {
                HStack {
                    Text("资料与纪年说明").font(theme.type.footnote)
                    Spacer()
                    Image(systemName: "chevron.right").font(theme.type.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(theme.color.textSecondary)
                .frame(minHeight: LifeUI.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, metrics.leadingInset)
            .padding(.trailing, metrics.trailingInset)
            .padding(.bottom, theme.space.xxxl)
        }
    }

    // MARK: 设计迭代 (DEBUG)

    /// 截图用的启动参数 (与 `-tab` / `-lens` 同法, 只在 DEBUG 生效):
    /// `-chapter N` 滚到分期序号为 N 的卷 (`-lifeAnchor bottom` 则卷尾贴底); `-lifeMoment <id>` 滚到某一刻; `-lifeYear <年>` 打开当年年谱;
    /// `-lifeWork <刻 id>` 推入该刻的作品。
    private func debugLaunch(_ proxy: ScrollViewProxy) async {
        #if DEBUG
        let defaults = UserDefaults.standard
        let chapter = defaults.string(forKey: "chapter").flatMap(Int.init)
        let momentID = defaults.string(forKey: "lifeMoment")
        let target = momentID.flatMap { id in chapters.first { $0.moments.contains { $0.id == id } } }
        guard let sequence = target?.epochSequence ?? chapter else { return await debugOpen() }
        try? await Task.sleep(for: .milliseconds(500))
        // `-lifeAnchor bottom`: 卷尾贴视口底 (看桩卷的回退目录与卷末)。
        let bottom = defaults.string(forKey: "lifeAnchor") == "bottom"
        // 冷启动时懒加载的卷高还是估计值, 第一次可能落空; 隔一会儿再对一次。
        for delay in [0, 1000] {
            try? await Task.sleep(for: .milliseconds(delay))
            proxy.scrollTo(LifeAnchor.chapter(sequence), anchor: bottom ? .bottom : .top)
            if let momentID {
                try? await Task.sleep(for: .milliseconds(600))
                proxy.scrollTo(LifeAnchor.moment(momentID), anchor: .top)
            }
        }
        await debugOpen()
        #endif
    }

    private func debugOpen() async {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let year = defaults.string(forKey: "lifeYear").flatMap(Int.init) {
            try? await Task.sleep(for: .milliseconds(800))
            sheetYear = LifeYear(year: year)
        }
        if let id = defaults.string(forKey: "lifeWork"), let moment = moments.moment(id: id), let work = moment.workId {
            try? await Task.sleep(for: .milliseconds(800))
            if let poem = await model.resolve(work, store: ctx.store) { route = .poem(poem, source: moment.id) }
        }
        #endif
    }
}
