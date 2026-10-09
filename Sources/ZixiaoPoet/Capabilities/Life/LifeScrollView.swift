import ZixiaoPoetCore
//  LifeScrollView.swift — 一生长卷: 叙事 Tab 的根页 (有刻时)
//
//  一条 `ZXShellScrollView` 从第一卷滚到最后一卷: 每卷 封面 → 刻 → 卷末。前沿一条年轨 (覆盖层)
//  标着年份, 点年份跳到那一年, 按住拖动跳卷; 刻旁的年份点开是当年的年谱 sheet。工具栏两个下钻:
//  行迹 (地图) 与 年谱 (编年目录)。宽屏 (iPad) 同一条长卷, 栏宽 720 居中, 年轨仍贴屏幕前沿, 不分栏。
//
//  滚动视图忽略顶端安全区 (卷封面的画伸进导航栏下; 刻与卷末自己让出栏高, 见 `LifeMetrics`),
//  卷封面吸附 (`LifeCoverSnap`), 封面视差与刻的进场在各自的视图里 (`LifeScrollEffects`)。
//
//  包里没有刻 (`ctx.moments == nil`) 时根本不会到这里: `CapabilityRegistry` 退回 `NarrativeWorkspaceView`。

import SwiftUI
import UIKit
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
    /// 各卷封面在内容坐标里的位置, 给吸附用 (引用, 见 `LifeCoverStore`)。
    @State private var coverStore = LifeCoverStore()
    /// 此刻压在导航栏底下的卷封面 (epochSequence)。有就收起顶端的滚动边缘效果, 让画透到栏下。
    @State private var coversUnderBar: Set<Int> = []
    #if DEBUG
    @State private var didRunDebugLaunch = false
    #endif
    /// 年轨: 刻度、在窗口里的框、正在拖经过的卷、刚点中的年份。
    @State private var railLayout: LifeRailLayout?
    @State private var railFrame: CGRect = .zero
    @State private var scrubbing: Int?
    @State private var flashYear: Int?
    @State private var feedback = UISelectionFeedbackGenerator()
    /// 一卷的顶边落在栏下可见高度这一比例之上, 就算「看到了这一卷」。
    private static let currentProbe: CGFloat = 0.4
    /// 长卷内容的坐标空间 (卷封面在内容里的位置)。
    nonisolated static let contentSpace = "life.content"
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
            let probe = metrics.coverBleed + outer.size.height * Self.currentProbe
            ScrollViewReader { proxy in
                ZStack(alignment: .leading) {
                    ZXShellScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            // ForEach 的身份就是锚点: 懒加载里还没实例化的卷, scrollTo 只认得 ForEach 的 id。
                            ForEach(Array(chapters.enumerated()), id: \.element.anchor) { index, chapter in
                                LifeChapterSection(ctx: ctx, chapter: chapter, position: index + 1, metrics: metrics,
                                                   model: model, actions: actions, namespace: readings,
                                                   isFirst: index == 0,
                                                   onCoverFrame: { coverStore.set($0, for: chapter.epochSequence) })
                                    .onGeometryChange(for: Bool.self) { geometry in
                                        let frame = geometry.frame(in: .scrollView)
                                        return frame.minY <= probe && frame.maxY > probe
                                    } action: { isCurrent in
                                        if isCurrent { current = chapter.epochSequence }
                                    }
                                    .onGeometryChange(for: Bool.self) { geometry in
                                        // 封面 (在卷的最上面) 的画盖住导航栏: 顶已到屏顶, 下沿垫字的那层纸
                                        // (`LifeChapterCover.scrimFraction`) 还没升到栏下。字一到栏下就交还系统的边缘效果。
                                        let minY = geometry.frame(in: .scrollView).minY
                                        let art = metrics.coverHeight * (1 - LifeChapterCover.scrimFraction)
                                        return minY <= 0.5 && minY + art > 0
                                    } action: { underBar in
                                        if underBar { coversUnderBar.insert(chapter.epochSequence) }
                                        else { coversUnderBar.remove(chapter.epochSequence) }
                                    }
                            }
                            footer(metrics)
                        }
                        .frame(maxWidth: LifeLayout.contentWidth)
                        .frame(maxWidth: .infinity)
                        .coordinateSpace(.named(Self.contentSpace))
                        .background {
                            if chapters.count > 1 {
                                LifeRailGestureHook(railFrame: railFrame,
                                                    onTap: { tapRail(at: $0, proxy: proxy) },
                                                    onScrub: { scrub($0, at: $1, proxy: proxy) })
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .scrollTargetBehavior(LifeCoverSnap(store: coverStore))
                    .modifier(LifeTopEdgeEffect(hidden: !coversUnderBar.isEmpty))
                    .ignoresSafeArea(.container, edges: .top)
                    if chapters.count > 1 { rail(proxy) }
                }
                .onChange(of: metrics, initial: true) { _, metrics in
                    coverStore.bleed = metrics.coverBleed
                    coverStore.momentAnchor = metrics.momentAnchor
                }
                .task { await debugLaunch(proxy) }
                // 今日页「看这一天」: ctx.lifeNavigation 留下的那一刻。initial: true 让长卷晚于请求建出来时也能接到。
                .onChange(of: ctx.lifeNavigation.pendingMomentID, initial: true) { _, id in
                    guard let id, let chapter = chapters.first(where: { $0.moments.contains { $0.id == id } }) else { return }
                    _ = ctx.lifeNavigation.consumeMoment()
                    route = nil   // 从长卷自己推出的读本里点「看这一天」: 先收回读本
                    Task { @MainActor in
                        // 冷启动时懒加载的卷高还是估计值, 与 debugLaunch 同法: 先到卷, 再对一次刻。
                        for delay in [0, 1000] {
                            try? await Task.sleep(for: .milliseconds(delay))
                            scroll(proxy, to: .chapter(chapter.epochSequence), at: .top)
                            try? await Task.sleep(for: .milliseconds(600))
                            scroll(proxy, to: .moment(id), at: coverStore.momentAnchor)
                        }
                    }
                }
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
        let bleed = proxy.safeAreaInsets.top.rounded()
        let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        let column = min(proxy.size.width, LifeLayout.contentWidth)
        // 封面 (出血带以下) 约占屏高 3/4; 横屏 / 分屏时以栏宽为界, 不让一幅画比它宽得多或窄得多。
        let cover = min(max(screenHeight * 0.75, column * 0.75), column * 1.8)
        // 栏贴着屏幕前沿 (窄屏) 时让出年轨; 宽屏栏居中, 年轨在栏外, 照常留页边。
        let gutter = (proxy.size.width - column) / 2
        let leading = gutter >= LifeLayout.trackInset ? theme.space.margin : LifeLayout.trackInset + theme.space.xs
        return LifeMetrics(coverBleed: bleed, coverHeight: cover.rounded(), viewport: screenHeight.rounded(),
                           readingInset: bleed + theme.space.md,
                           leadingInset: leading, trailingInset: theme.space.margin)
    }

    // MARK: 年轨

    private func rail(_ proxy: ScrollViewProxy) -> some View {
        LifeYearTrack(chapters: chapters, current: current, scrubbing: scrubbing, flashYear: flashYear,
                      onLayout: { railLayout = $0 },
                      select: { scroll(proxy, to: .chapter($0)) },
                      selectYear: { jump(toYear: $0, proxy: proxy) })
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { railFrame = $0 }
            .padding(.vertical, theme.space.lg)
    }

    /// 程序跳转: 先让吸附让开 (`LifeCoverStore.holdSnapping`), 再滚。
    private func scroll(_ proxy: ScrollViewProxy, to anchor: LifeAnchor, at unit: UnitPoint = .top) {
        coverStore.holdSnapping()
        proxy.scrollTo(anchor, anchor: unit)
    }

    /// 点年轨: 最近的年份标签 → 那一年。
    private func tapRail(at y: CGFloat, proxy: ScrollViewProxy) {
        guard let label = railLayout?.label(near: y) else { return }
        feedback.selectionChanged()
        flashYear = label.year
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            if flashYear == label.year { flashYear = nil }
        }
        jump(toYear: label.year, proxy: proxy)
    }

    /// 跳到一年 (`LifeJump`): 同一卷里平滑滚过去; 跨卷先无动画落到那一卷 (懒加载的卷先建出来),
    /// 再滚到那一刻。
    private func jump(toYear year: Int, proxy: ScrollViewProxy) {
        guard let target = LifeJump.resolve(year: year, in: chapters) else { return }
        let anchor = coverStore.momentAnchor
        guard let moment = target.moment else {
            scroll(proxy, to: .chapter(target.chapter))
            return
        }
        let animation = theme.motion.adapted(theme.motion.smooth, reduceMotion: reduceMotion)
        if current == target.chapter {
            withAnimation(animation) { scroll(proxy, to: .moment(moment), at: anchor) }
            return
        }
        scroll(proxy, to: .chapter(target.chapter))
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(animation) { scroll(proxy, to: .moment(moment), at: anchor) }
        }
    }

    /// 按住年轨拖动: y 落在哪一卷的段里就跳到哪一卷 (不带动画, 跟手); 换卷一下选择反馈。
    private func scrub(_ phase: LifeRailScrubPhase, at y: CGFloat, proxy: ScrollViewProxy) {
        guard let layout = railLayout, !chapters.isEmpty else { return }
        switch phase {
        case .began, .changed:
            if phase == .began { feedback.prepare() }
            let sequence = chapters[layout.chapterIndex(at: y)].epochSequence
            guard scrubbing != sequence else { return }
            scrubbing = sequence
            feedback.selectionChanged()
            scroll(proxy, to: .chapter(sequence))
        case .ended:
            scrubbing = nil
        }
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
    /// `-lifeWork <刻 id>` 推入该刻的作品; `-lifeNudge <pt>` / `-lifeNudgeUp <pt>` 落定后再往下 / 往回推若干点 (拍视差)。
    private func debugLaunch(_ proxy: ScrollViewProxy) async {
        #if DEBUG
        guard !didRunDebugLaunch else { return }
        didRunDebugLaunch = true
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
            scroll(proxy, to: .chapter(sequence), at: bottom ? .bottom : .top)
            if let momentID {
                try? await Task.sleep(for: .milliseconds(600))
                scroll(proxy, to: .moment(momentID), at: coverStore.momentAnchor)
            }
        }
        // `-lifeNudge <pt>` / `-lifeNudgeUp <pt>`: 落定后再往下 / 往回推若干点, 拍封面视差的中间态
        // (启动参数的值不能以 - 开头, 会被当成下一个键, 所以往回推单用一个键)。
        let down = defaults.string(forKey: "lifeNudge").flatMap(Double.init)
        let up = defaults.string(forKey: "lifeNudgeUp").flatMap(Double.init).map { -$0 }
        // 只在推完不再触发懒加载时可靠: iOS 18 起程序滚动后 SwiftUI 按视图记位置, 之后任何一次重排
        // (下一卷建出来、当前卷 / 墨点状态变了) 都会把它钉回 scrollTo 的锚位。拍进场视差用 UI 测试拖住。
        if let nudge = down ?? up {
            try? await Task.sleep(for: .milliseconds(400))
            NotificationCenter.default.post(name: LifeRailGestureHook.Coordinator.debugNudge, object: CGFloat(nudge))
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

/// 卷封面在导航栏底下时收起顶端的滚动边缘效果 (iOS 26 的玻璃栏下默认会给内容垫一层),
/// 画直接透到栏下; 封面离开后交还系统。iOS 26 以前没有这层效果, 不用管。
private struct LifeTopEdgeEffect: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(hidden, for: .top)
        } else {
            content
        }
    }
}
