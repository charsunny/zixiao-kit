//  DailyView.swift — 今日: 一张报纸的头版
//
//  整页只有一个主角 —— 今日一刻 (`TodayHeroView`, 选法见 `TodayPick`)。其下三个配角各占一行:
//  此刻在哪 (小地图 → 本卷行迹) / 继续读 (有阅读记录才出现) / 本周 (七个小格, 点一天就地换成那天的一刻)。
//  年谱联不上、又没有缓存时, 画面退成当前一卷的卷封面画 + 一句「今日的一页暂时翻不开」。

import CoreLocation
import SwiftUI
import ZixiaoDesign

struct DailyView: View {
    let ctx: CompositionContext

    /// 正在看的日子 (今天, 或本周 / 日历里点开的那天)。
    @State private var selectedDate = Date.now
    @State private var followingToday = true
    @State private var lunar = PoetLunarDay.of()
    @State private var pick: TodayPick?
    @State private var phase: Phase = .loading
    @State private var otherCount: Int?
    @State private var weekMarks: Set<String> = []
    @State private var linkedDays: [Int: Set<Int>] = [:]
    @State private var resumePoem: Poem?
    @State private var openingWork = false
    @State private var route: TodayRoute?
    @State private var sheet: TodaySheet?
    @State private var picking = false
    @Namespace private var readings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zxTheme) private var theme

    enum Phase: Equatable { case loading, loaded, empty, failed }

    private var title: String { ctx.composition.placement(.daily)?.label ?? "今日" }
    /// 干支年与农历 (如「丙午年 · 八月十九」)。iOS 26 起进导航栏副标题槽位, 以下由 `DailySubtitleFallback` 顶在内容上。
    private var subtitle: String { "\(lunar.sexagenary)年 · \(lunar.label)" }
    private var isToday: Bool { DailyRotation.calendar.isDateInToday(selectedDate) }
    private var selectedKey: String { TodayPickStore.dateKey(selectedDate) }
    private var app: String { ctx.composition.app.appSlug }
    private var usesArchive: Bool { ctx.composition.enabledDailyCards.contains(.onThisDay) }
    private var week: [TodayWeekDay] { TodayWeekDay.week(containing: .now) }

    var body: some View {
        ScrollViewReader { proxy in
        ZXShellScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: theme.space.xxl) {
                VStack(alignment: .leading, spacing: theme.space.sm) {
                    if !isToday { previewBar }
                    hero
                }
                if let pick, phase == .loaded, let coordinate = coordinate(of: pick), let place = pick.placeLabel {
                    Button { route = .map(pick.chapter) } label: {
                        TodayPlaceRow(coordinate: coordinate, place: place, chapterTitle: pick.chapterTitle)
                    }
                    .buttonStyle(.plain)
                    .disabled(!ctx.hasItineraryData)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("此刻在哪，\(place)\(pick.chapterTitle.map { "，\($0)" } ?? "")")
                    .accessibilityHint(ctx.hasItineraryData ? "打开本卷行迹地图" : "")
                }
                if let resume = ctx.userData.reading.first, let poem = resumePoem, poem.id == resume.poemId {
                    Button { route = .poem(poem, source: "resume") } label: {
                        TodayResumeRow(title: ctx.workTitle(poem), progress: resume.progress, finished: resume.finished)
                    }
                    .buttonStyle(.plain)
                    .readingTransitionSource("resume", in: readings)
                }
                if phase != .failed || pick != nil {
                    TodayWeekStrip(days: week, todayKey: TodayPickStore.dateKey(.now), selectedKey: selectedKey,
                                   marked: weekMarks) { day in selectDate(day.date) }
                    .id(Self.weekAnchor)
                }
            }
            .padding(.horizontal, theme.space.margin)
            .padding(.top, theme.space.sm)
            .padding(.bottom, theme.space.xxl)
            .poetReadableWidth()
        }
        .task { await debugScroll(proxy) }
        }
        .background(theme.paper())
        .zxNavigationTitle(title, subtitle: subtitle, role: .root)
        .modifier(DailySubtitleFallback(text: subtitle))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { picking = true } label: {
                    Image(systemName: isToday ? "calendar" : "calendar.badge.clock")
                }.accessibilityLabel("选择日子")
            }
        }
        .sheet(isPresented: $picking) { DateSelectionView(date: $selectedDate) }
        .sheet(item: $sheet) { sheetContent($0) }
        .navigationDestination(item: $route) { destination($0) }
        .refreshable { await loadDay() }
        .onChange(of: selectedDate) { _, date in followingToday = DailyRotation.calendar.isDateInToday(date) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, followingToday, !isToday { selectedDate = .now }
        }
        .task(id: ctx.userData.reading.first?.poemId) { await loadResume() }
        .task(id: selectedKey) { await loadDay() }
        .task { await loadWeekMarks() }
        .task { debugLaunch() }
    }

    // MARK: 主角

    @ViewBuilder private var hero: some View {
        if let pick {
            TodayHeroView(ctx: ctx, pick: pick, referenceYear: lunar.lunar.year, isToday: isToday,
                          otherCount: otherCount, namespace: readings, isOpeningWork: openingWork,
                          read: { Task { await openWork(pick) } },
                          seeDay: seeDayAction(pick),
                          showOthers: {
                              if let month = pick.month, let day = pick.day {
                                  sheet = .day(month: month, day: day, excluding: pick.eventIDs)
                              }
                          })
            .id(pick.id)
            .transition(.opacity)
        } else {
            switch phase {
            case .failed: offline
            case .empty: emptyDay
            case .loading, .loaded: loadingPlate
            }
        }
    }

    private var loadingPlate: some View {
        RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
            .fill(theme.color.fill)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                ProgressView {
                    Text("正在翻阅年谱…").font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                }.tint(theme.muted)
            }
    }

    /// 离线又没有缓存: 当前一卷的卷封面画 + 幽灵空态。
    private var offline: some View {
        VStack(alignment: .leading, spacing: theme.space.xl) {
            if let cover = coverChapter {
                ScreenArtView(.forPlace(cover.seed, epoch: cover.epoch, season: cover.season), aspect: 4.0 / 3.0)
                    .overlay(alignment: .bottomLeading) {
                        Text(cover.title)
                            .font(theme.uiFont(13, weight: .medium))
                            .foregroundStyle(theme.color.textSecondary)
                            .padding(theme.space.lg)
                            .accessibilityHidden(true)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
                    .accessibilityHidden(true)
            }
            ZXGhostState("今日的一页暂时翻不开", message: "年谱需要联网翻检。连上网络后再试一次。",
                         actionTitle: "重试", systemImage: "arrow.clockwise") {
                Task { await loadDay() }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyDay: some View {
        VStack(alignment: .leading, spacing: theme.space.sm) {
            Text("年谱未留下这几天的记载").font(theme.type.title3).foregroundStyle(theme.color.textPrimary)
            Text("明日再来翻一页，或在本周里换一天。")
                .font(theme.type.body).foregroundStyle(theme.color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 看的不是今天: 一行说明 + 「回到今天」。
    private var previewBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("在看\(lunar.label)这一天")
                .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
            Spacer()
            Button { selectDate(.now) } label: {
                Label("回到今天", systemImage: "arrow.uturn.backward")
                    .font(theme.type.footnote.weight(.semibold))
                    .frame(minHeight: LifeUI.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.color.textPrimary)
        }
    }

    /// 离线态的卷封面: 最近一次的一刻所在的卷; 没有就按日轮换。
    private var coverChapter: (seed: String, epoch: Int, season: ZXSeasonTint?, title: String)? {
        let recent = TodayPickStore.latest(app: app)
        if let chapters = ctx.moments?.chapters, !chapters.isEmpty {
            let chapter = chapters.first { $0.epochSequence == recent?.chapter }
                ?? chapters[DailyRotation.dayNumber(selectedDate) % chapters.count]
            return (chapter.placeSeed, chapter.epochSequence,
                    chapter.seasonTint.flatMap(ZXSeasonTint.init(rawValue:)), chapter.title)
        }
        let epochs = ctx.lifeEpochs
        guard !epochs.isEmpty else { return nil }
        let epoch = epochs.first { $0.sequence == recent?.chapter }
            ?? epochs[DailyRotation.dayNumber(selectedDate) % epochs.count]
        return ("\(ctx.composition.poet.slug)-\(epoch.sequence)", epoch.sequence, nil, epoch.label)
    }

    // MARK: 动作

    private func seeDayAction(_ pick: TodayPick) -> (() -> Void)? {
        switch pick.kind {
        case .moment:
            if let id = pick.momentID, ctx.moments != nil,
               ctx.composition.capsuleTabs.contains(where: { $0.id == .itinerary }) {
                return { ctx.lifeNavigation.show(moment: id) }
            }
            fallthrough
        case .event:
            guard let year = pick.year, ctx.hasChronicleData else { return nil }
            return { sheet = .year(year) }
        case .reading:
            return nil
        }
    }

    private func openWork(_ pick: TodayPick) async {
        if let poem = pick.poem { route = .poem(poem, source: pick.id); return }
        guard let id = pick.workID, !openingWork else { return }
        openingWork = true
        defer { openingWork = false }
        if let poem = try? await ctx.store.poem(id: id) { route = .poem(poem, source: pick.id) }
    }

    private func selectDate(_ date: Date) {
        withAnimation(theme.motion.adapted(theme.motion.smooth, reduceMotion: reduceMotion)) { selectedDate = date }
    }

    /// 地图的落点: 合成时记下的经纬度; 没有 (驻点当时还没拉回) 就按驻点 id / 地名现查。
    private func coordinate(of pick: TodayPick) -> CLLocationCoordinate2D? {
        if let lat = pick.latitude, let lon = pick.longitude { return .init(latitude: lat, longitude: lon) }
        if let id = pick.stationID, let station = ctx.store.stations.first(where: { $0.id == id }) {
            return .init(latitude: station.latitude, longitude: station.longitude)
        }
        return TodayPicker.guidePlace(named: pick.placeLabel, ctx: ctx).map { .init(latitude: $0.lat, longitude: $0.lon) }
    }

    // MARK: 推入与 sheet

    @ViewBuilder private func destination(_ route: TodayRoute) -> some View {
        switch route {
        case .poem(let poem, let source):
            // `readingTransition` 已用 AnyView 切断目的页类型 (真机 TypeDecoder 栈溢出)。
            PoemDetailView(ctx: ctx, poem: poem).readingTransition(source, in: readings)
        case .map(let epoch):
            AnyView(LifeMapView(ctx: ctx, focusEpoch: epoch).zxNavigationTitle("行迹", role: .secondary))
        }
    }

    @ViewBuilder private func sheetContent(_ sheet: TodaySheet) -> some View {
        NavigationStack {
            Group {
                switch sheet {
                case .year(let year):
                    AnyView(ChronicleEventsView(ctx: ctx, year: year))
                case .day(let month, let day, let excluding):
                    AnyView(TodayDayArchiveView(ctx: ctx, month: month, day: day, excluding: Set(excluding)))
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { self.sheet = nil } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(theme.color.textPrimary)
    }

    // MARK: 取数

    private func loadDay() async {
        let date = selectedDate
        let key = TodayPickStore.dateKey(date)
        lunar = PoetLunarDay.of(date)
        otherCount = nil
        if let cached = TodayPickStore.cached(for: date, app: app) {
            pick = cached
            phase = .loaded
        } else {
            if pick != nil { pick = nil }
            phase = .loading
            do {
                let chosen = try await TodayPicker.pick(for: date, ctx: ctx)
                guard !Task.isCancelled, key == selectedKey else { return }
                withAnimation(theme.motion.adapted(theme.motion.smooth, reduceMotion: reduceMotion)) {
                    pick = chosen
                    phase = chosen == nil ? .empty : .loaded
                }
                if let chosen { TodayPickStore.save(chosen, for: date, app: app) }
            } catch {
                guard !Task.isCancelled, key == selectedKey else { return }
                phase = .failed
                return
            }
        }
        await loadOtherCount(for: key)
        if weekMarks.isEmpty { await loadWeekMarks() }
        #if DEBUG
        // `-todaySeeDay YES`: 载入后替读者点一下「看这一天」(验跨 Tab 导航)。
        if UserDefaults.standard.bool(forKey: "todaySeeDay"), let pick { seeDayAction(pick)?() }
        #endif
    }

    private func loadOtherCount(for key: String) async {
        guard usesArchive, let pick, let month = pick.month, let day = pick.day, pick.kind != .reading else { return }
        guard let total = try? await ctx.store.eventCount(month: month, day: day),
              !Task.isCancelled, key == selectedKey else { return }
        otherCount = max(total - pick.eventIDs.count, 0)
    }

    /// 本周哪几天有刻 / 有可读的年谱记载。刻在包里; 年谱按农历月各取一次。
    private func loadWeekMarks() async {
        let days = week
        let momentDays = Set((ctx.moments?.chapters ?? []).flatMap(\.moments)
            .filter { $0.date.precision == .day }
            .compactMap { m in m.date.month.flatMap { month in m.date.day.map { "\(month)-\($0)" } } })
        if usesArchive {
            for month in Set(days.map(\.lunarMonth)) where linkedDays[month] == nil {
                if let found = try? await ctx.store.linkedEventDays(month: month) { linkedDays[month] = found }
            }
        }
        weekMarks = Set(days.filter { day in
            momentDays.contains("\(day.lunarMonth)-\(day.lunarDay)")
                || linkedDays[day.lunarMonth]?.contains(day.lunarDay) == true
        }.map(\.key))
    }

    private func loadResume() async {
        guard let id = ctx.userData.reading.first?.poemId else { resumePoem = nil; return }
        if let bundled = ctx.guide?.poem(id) { resumePoem = bundled; return }
        if let fetched = try? await ctx.store.poems(ids: [id]).first, !Task.isCancelled { resumePoem = fetched }
    }

    // MARK: 设计迭代 (DEBUG)

    private static let weekAnchor = "today.week"

    /// `-todayScroll bottom`: 载入后滚到本周 (截图用)。
    private func debugScroll(_ proxy: ScrollViewProxy) async {
        #if DEBUG
        guard UserDefaults.standard.string(forKey: "todayScroll") == "bottom" else { return }
        try? await Task.sleep(for: .seconds(4))
        proxy.scrollTo(Self.weekAnchor, anchor: .bottom)
        #endif
    }

    /// 截图用的启动参数 (与 `-tab` 同法, 只在 DEBUG 生效):
    /// `-todayDate yyyy-MM-dd` 打开那一天 (本周预览态); `-todayFresh YES` 先清掉缓存的一刻 (看选法 / 离线态);
    /// `-todayScroll bottom` 滚到本周; `-todaySeeDay YES` 载入后点「看这一天」。
    private func debugLaunch() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "todayFresh") { TodayPickStore.clear(app: app) }
        if let raw = defaults.string(forKey: "todayDate") {
            let parts = raw.split(separator: "-").compactMap { Int($0) }
            if parts.count == 3, let date = DailyRotation.calendar.date(
                from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) {
                selectedDate = date
            }
        }
        #endif
    }
}

/// 今日页推入的页。经一个 `navigationDestination(item:)` 推, 目的页类型由 AnyView 切断。
enum TodayRoute: Hashable {
    case poem(Poem, source: String)
    /// 本卷行迹 (分期序号; nil = 全部)。
    case map(Int?)
}

enum TodaySheet: Identifiable, Hashable {
    /// 某一年的年谱。
    case year(Int)
    /// 某个农历月日 (各年) 的其他记载。
    case day(month: Int, day: Int, excluding: [UUID])

    var id: String {
        switch self {
        case .year(let year): "year-\(year)"
        case .day(let month, let day, _): "day-\(month)-\(day)"
        }
    }
}

/// 「另有 N 条记载」: 年谱里同一农历月日 (各年) 的事目, 扣掉今日一刻用掉的那几条。
private struct TodayDayArchiveView: View {
    let ctx: CompositionContext
    let month: Int
    let day: Int
    let excluding: Set<UUID>
    @State private var events: [PoetEvent] = []
    @State private var loading = true
    @State private var failed = false
    @Environment(\.zxTheme) private var theme

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if failed {
                LoadFailureView(title: "年谱暂未载入", message: "检查网络后再试一次。") { await load() }
            } else {
                List(events) { event in
                    NavigationLink { EventDetailView(ctx: ctx, event: event) } label: {
                        VStack(alignment: .leading, spacing: theme.space.xs) {
                            Text("\(ctx.era.label(event.year)) · \(String(event.year))")
                                .font(theme.type.subhead.weight(.semibold)).foregroundStyle(theme.color.textPrimary)
                            Text(event.narrative).font(theme.type.body).lineLimit(3)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                    }
                    .listRowBackground(theme.paper()).listRowSeparatorTint(theme.rule)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .background(theme.paper())
        .foregroundStyle(theme.color.textPrimary)
        .zxNavigationTitle("旧日此时",
                           subtitle: "\(TodayText.monthDay(month: month, day: day)) · \(loading ? "正在翻检…" : "\(events.count) 条记载")",
                           role: .secondary)
        .task { await load() }
    }

    private func load() async {
        loading = true; failed = false
        do {
            events = try await ctx.store.onThisDay(month: month, day: day).filter { !excluding.contains($0.id) }
        } catch {
            if !Task.isCancelled { failed = true }
        }
        loading = false
    }
}

/// 副标题的 iOS 26 以下兜底: `zxNavigationTitle` 只在 iOS 26 起把 subtitle 放进导航栏,
/// 更早的系统没有对应位置, 这里补一行顶在内容上 (与玄览 `TodayScreen` 同法)。iOS 26 上什么都不做。
private struct DailySubtitleFallback: ViewModifier {
    let text: String
    @Environment(\.zxTheme) private var theme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) {
                Text(text)
                    .font(theme.type.subhead)
                    .foregroundStyle(theme.color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, theme.space.margin)
                    .padding(.bottom, theme.space.xs)
                    .background(theme.paper())
            }
        }
    }
}

private struct DateSelectionView: View {
    @Binding var date: Date
    @State private var draft: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.zxTheme) private var theme

    init(date: Binding<Date>) {
        _date = date
        _draft = State(initialValue: date.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.space.lg) {
                    Text("选一个日子，看旧日此时的一刻。按北京时间换日。")
                        .font(theme.type.body).foregroundStyle(theme.color.textSecondary)
                    DatePicker("选择日期", selection: $draft, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .environment(\.calendar, DailyRotation.calendar)
                        .environment(\.timeZone, DailyRotation.calendar.timeZone)
                    Button { draft = .now } label: {
                        Label("回到今日", systemImage: "arrow.uturn.backward")
                            .font(theme.type.callout)
                            .frame(minWidth: LifeUI.minTapTarget, minHeight: LifeUI.minTapTarget)
                            .contentShape(Rectangle())
                    }
                        .poetActionStyle()
                        .disabled(DailyRotation.calendar.isDateInToday(draft))
                }
                .padding(theme.space.margin).poetReadableWidth()
            }
            .background(theme.paper())
            .zxNavigationTitle("选择日子", role: .secondary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { date = draft; dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .tint(theme.accent)
        // 这是 sheet 的停靠档 (detent), 不是导航标题模式: 大字号下直接全高, 否则先停在日历刚好放下的高度。
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(640), .large])
        .presentationDragIndicator(.visible)
    }
}
