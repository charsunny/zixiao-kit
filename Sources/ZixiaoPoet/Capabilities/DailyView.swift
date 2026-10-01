import SwiftUI
import ZixiaoDesign

struct DailyView: View {
    let ctx: CompositionContext
    @State private var todayEvents: [PoetEvent] = []
    @State private var lunar = PoetLunarDay.of()
    @State private var works: [String: Poem] = [:]
    @State private var loadingForms: Set<String> = []
    @State private var failedForms: Set<String> = []
    @State private var historyFailed = false
    @State private var historyLoading = true
    @State private var resumePoem: Poem?
    @State private var pickedDate = Date.now
    @State private var picking = false
    @State private var followingToday = true
    /// 每日选读的封面宽。起点取 kit 封面的「书目页」档, 随动态字体放大 (封面上的字按宽度定)。
    @ScaledMetric(relativeTo: .body) private var coverWidth = BookCoverView.Size.page.width
    @Namespace private var readings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.zxTheme) private var theme
    private var isToday: Bool { DailyRotation.calendar.isDateInToday(pickedDate) }
    private var title: String { ctx.composition.placement(.daily)?.label ?? "今日" }
    /// 干支年与农历 (如「丙午年 · 八月十九」)。iOS 26 起进导航栏副标题槽位, 以下由 `DailySubtitleFallback` 顶在内容上。
    private var subtitle: String { "\(lunar.sexagenary)年 · \(lunar.label)" }
    private var genres: [Genre] {
        let configured = ctx.composition.placement(.corpus)?.genres ?? []
        return ["shi", "ci", "wen", "fu"].compactMap { id in configured.first { $0.id == id && $0.isBrowsable } }
    }
    private var collection: ReadingCollection? {
        guard let choices = ctx.composition.editorial?.collections,
              let index = DailyRotation.index(on: pickedDate, count: choices.count) else { return nil }
        return choices[index]
    }
    private var dailyArt: [Artwork] {
        ["书法", "绘画"].compactMap { kind in
            let choices = ctx.artworks.filter { $0.kind == kind }
            guard let index = DailyRotation.index(on: pickedDate, count: choices.count) else { return nil }
            return choices[index]
        }
    }
    private var dailyChapter: LifeChapter? {
        guard let chapters = ctx.guide?.chapters,
              let index = DailyRotation.index(on: pickedDate, count: chapters.count) else { return nil }
        return chapters[index]
    }

    var body: some View {
        ZXShellScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: theme.space.xl) {
                ForEach(ctx.visibleDailyCards, id: \.self) { card in
                    dailySection(card)
                }
                if !dailyArt.isEmpty {
                    VStack(alignment: .leading, spacing: theme.space.md) {
                        HStack(alignment: .firstTextBaseline) {
                            ZixiaoDesign.SectionLabel("今日看书画")
                            NavigationLink { ArtworkGalleryView(ctx: ctx) } label: {
                                Text("全部").font(theme.type.footnote)
                                    .frame(minWidth: LifeUI.minTapTarget, minHeight: LifeUI.minTapTarget, alignment: .trailing)
                                    .contentShape(Rectangle())
                            }.tint(theme.accent)
                        }
                        ForEach(dailyArt) { artwork in
                            NavigationLink {
                                ArtworkDetailView(ctx: ctx, artwork: artwork)
                                    .readingTransition(artwork.id, in: readings)
                            } label: {
                                DailyArtworkCard(artwork: artwork)
                                    .readingTransitionSource(artwork.id, in: readings)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, theme.space.margin)
                }
                if let collection {
                    VStack(alignment: .leading, spacing: theme.space.md) {
                        ZixiaoDesign.SectionLabel("一起读")
                        NavigationLink { ReadingCollectionView(ctx: ctx, collection: collection) } label: {
                            ZixiaoDesign.GlazePanel(padding: theme.space.lg) {
                                DailyCollectionLabel(collection: collection)
                            }
                        }.buttonStyle(.plain)
                    }.padding(.horizontal, theme.space.margin)
                }
            }.padding(.top, theme.space.sm).padding(.bottom, theme.space.xxl).poetReadableWidth()
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
        .sheet(isPresented: $picking) { DateSelectionView(date: $pickedDate) }
        .refreshable { await loadDay() }
        .onChange(of: pickedDate) { _, date in followingToday = DailyRotation.calendar.isDateInToday(date) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, followingToday, !isToday { pickedDate = .now }
        }
        .task(id: ctx.userData.reading.first?.poemId) {
            guard ctx.visibleDailyCards.contains(.resume),
                  let id = ctx.userData.reading.first?.poemId else { resumePoem = nil; return }
            let bundled = ctx.guide?.poem(id)
            resumePoem = bundled
            if let fetched = try? await ctx.store.poems(ids: [id]).first, !Task.isCancelled {
                resumePoem = fetched
            }
        }
        .task(id: pickedDate) { await loadDay() }
    }

    @ViewBuilder
    private func dailySection(_ card: DailyCard) -> some View {
        switch card {
        case .workOfDay:
            dailyWorks
        case .resume:
            if let poem = resumePoem, !works.values.contains(where: { $0.id == poem.id }) {
                VStack(alignment: .leading, spacing: theme.space.md) {
                    ZixiaoDesign.SectionLabel("接着读")
                    NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                        ZixiaoDesign.GlazePanel(padding: theme.space.lg) {
                            LifeUI.PoemRow(poem: poem, displayTitle: ctx.workTitle(poem))
                        }
                    }.buttonStyle(.plain)
                }.padding(.horizontal, theme.space.margin)
            }
        case .onThisDay:
            historyPreview.padding(.horizontal, theme.space.margin)
        case .epochNote:
            if let chapter = dailyChapter {
                VStack(alignment: .leading, spacing: theme.space.md) {
                    ZixiaoDesign.SectionLabel("今日导读")
                    NavigationLink { EpochDetailView(ctx: ctx, epoch: chapter.epoch) } label: {
                        ZixiaoDesign.GlazePanel {
                            VStack(alignment: .leading, spacing: theme.space.sm) {
                                Text(chapter.epoch.label).font(theme.type.title2)
                                    .foregroundStyle(theme.color.textPrimary)
                                Text(chapter.introduction).font(theme.type.body).lineSpacing(theme.space.xs)
                                    .foregroundStyle(theme.color.textSecondary).lineLimit(3)
                                Label("进入\(ctx.narrativeLabel)篇章", systemImage: "arrow.right")
                                    .font(theme.type.footnote).foregroundStyle(theme.accent)
                            }
                        }
                    }.buttonStyle(.plain)
                }.padding(.horizontal, theme.space.margin)
            }
        case .anecdote:
            EmptyView()
        }
    }

    private var dailyWorks: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            ZixiaoDesign.SectionLabel("每日选读", trailing: genres.map(\.label).joined(separator: " · "))
                .padding(.horizontal, theme.space.margin)
            if typeSize.isAccessibilitySize {
                ForEach(genres) { genre in dailyCard(genre).padding(.horizontal, theme.space.margin) }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: theme.space.lg) {
                        ForEach(genres) { genre in
                            dailyCard(genre).frame(width: coverWidth).id(genre.id)
                        }
                    }.padding(.vertical, theme.space.sm).scrollTargetLayout()
                }
                .contentMargins(.horizontal, theme.space.margin, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
    }

    /// 大字号下封面不跟着字号无限放大 (一张封面撑出屏幕就不是「书」了), 回到「正在阅读」档。
    private var cardCoverWidth: CGFloat {
        typeSize.isAccessibilitySize ? BookCoverView.Size.reading.width : coverWidth
    }

    /// 封面包角按体裁染色 —— 内核不替体裁挑色, 色从身份的角色里取, 浅深各自解析。
    private func genreTint(_ genre: Genre) -> Color {
        switch genre.id {
        case "shi": theme.seal
        case "ci": theme.color.secondary
        case "wen": theme.muted
        default: theme.ink(0.72)
        }
    }

    private func dailyCard(_ genre: Genre) -> some View {
        let width = cardCoverWidth
        return Group {
            if let poem = works[genre.id] {
                NavigationLink {
                    PoemDetailView(ctx: ctx, poem: poem).readingTransition(genre.id, in: readings)
                } label: {
                    VStack(alignment: .leading, spacing: theme.space.md) {
                        BookCoverView(title: ctx.workTitle(poem), author: ctx.composition.poet.name,
                                      size: .width(width), cornerTint: genreTint(genre))
                            .readingTransitionSource(genre.id, in: readings)
                        VStack(alignment: .leading, spacing: theme.space.xs) {
                            Text("每日一\(genre.label)").font(theme.type.subhead.weight(.semibold))
                                .foregroundStyle(theme.color.textPrimary)
                            Text(poem.lines.first ?? poem.title)
                                .font(theme.type.subhead)
                                .foregroundStyle(theme.color.textSecondary)
                                .lineSpacing(theme.space.xxs)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        }
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("每日一\(genre.label)，\(ctx.workTitle(poem))，\(ctx.composition.poet.name)")
                .accessibilityHint("打开全文阅读")
            } else {
                VStack(alignment: .leading, spacing: theme.space.md) {
                    VStack(alignment: .leading, spacing: theme.space.md) {
                        Text(genre.label).font(theme.type.subhead.weight(.semibold))
                        Spacer(minLength: theme.space.md)
                        if loadingForms.contains(genre.id) {
                            ProgressView {
                                Text("正在选读…").font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                            }.tint(theme.muted)
                        } else if failedForms.contains(genre.id) {
                            Text("这一篇暂未载入").font(theme.type.headline)
                            Button { Task { await loadForm(genre.id, on: pickedDate) } } label: {
                                Label("重试", systemImage: "arrow.clockwise")
                                    .font(theme.type.footnote)
                                    .frame(minWidth: LifeUI.minTapTarget, minHeight: LifeUI.minTapTarget)
                                    .contentShape(Rectangle())
                            }
                                .poetActionStyle()
                        } else {
                            Text("作品整理中").font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                        }
                        Spacer(minLength: theme.space.md)
                    }
                    .padding(theme.space.lg).frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: typeSize.isAccessibilitySize ? nil : BookCoverView.Size.width(width).height)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius.xs, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: theme.radius.xs, style: .continuous)
                            .strokeBorder(theme.border, lineWidth: ZXMetric.hairline)
                    }
                    Text("每日一\(genre.label)").font(theme.type.subhead.weight(.semibold))
                }
            }
        }.foregroundStyle(theme.color.textPrimary)
    }

    private var historyPreview: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            ZixiaoDesign.SectionLabel("旧日此时", trailing: lunar.label)
            VStack(alignment: .leading, spacing: theme.space.md) {
                if historyLoading {
                    ProgressView {
                        Text("正在翻阅年谱…").font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                    }.tint(theme.muted)
                } else if historyFailed {
                    Text("年谱暂未载入").font(theme.type.body).foregroundStyle(theme.color.textSecondary)
                    Button { Task { await loadHistory(on: pickedDate) } } label: {
                        Text("重试").font(theme.type.callout)
                            .frame(minWidth: LifeUI.minTapTarget, minHeight: LifeUI.minTapTarget)
                            .contentShape(Rectangle())
                    }.tint(theme.accent)
                } else if let event = todayEvents.first {
                    if todayEvents.contains(where: { $0.month != lunar.month || $0.day != lunar.day }) {
                        Text("当日未见记载，为你选一则相近日子的年谱。")
                            .font(theme.type.caption).foregroundStyle(theme.color.textSecondary)
                    }
                    NavigationLink { EventDetailView(ctx: ctx, event: event) } label: {
                        VStack(alignment: .leading, spacing: theme.space.md) {
                            HStack {
                                Text("\(ctx.era.label(event.year)) · \(String(event.year))")
                                    .font(theme.type.subhead.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right").font(theme.type.caption.weight(.semibold))
                            }.foregroundStyle(theme.accent)
                            Text(event.narrative).font(theme.type.body).lineSpacing(theme.space.xs).lineLimit(3)
                                .foregroundStyle(theme.color.textPrimary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if todayEvents.count > 1 {
                        InkDivider()
                        NavigationLink {
                            DailyArchiveView(ctx: ctx, events: todayEvents, dateLabel: lunar.label)
                        } label: {
                            Text("另有 \(todayEvents.count - 1) 条记载")
                                .frame(minWidth: LifeUI.minTapTarget, minHeight: LifeUI.minTapTarget)
                                .contentShape(Rectangle())
                        }
                        .font(theme.type.subhead).tint(theme.accent)
                    }
                } else {
                    Text("年谱未留下这一天的记载，明日再来翻一页。")
                        .font(theme.type.body).foregroundStyle(theme.color.textSecondary)
                }
            }
            .padding(ZXMetric.panelPadding).frame(maxWidth: .infinity, alignment: .leading)
            .zxSurface(.e1, in: RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
        }
    }

    private func loadForm(_ form: String, on date: Date) async {
        loadingForms.insert(form); failedForms.remove(form)
        let bundled = ctx.guide?.workOfDay(date, form: form)
        if let bundled {
            works[form] = bundled
            loadingForms.remove(form)
        }
        do {
            let poem = try await ctx.store.workOfDay(date, form: form)
            guard !Task.isCancelled, date == pickedDate else { return }
            // Bundled selections keep the reviewed home → guide path stable. Remote data
            // fills forms that have no bundled selection; it never erases local content.
            if bundled == nil, let poem { works[form] = poem }
        } catch {
            guard !Task.isCancelled, date == pickedDate else { return }
            if bundled == nil { failedForms.insert(form) }
        }
        loadingForms.remove(form)
    }
    private func loadHistory(on date: Date) async {
        historyLoading = true; historyFailed = false
        do {
            let events = try await ctx.store.onThisDay(PoetLunarDay.of(date).lunar, fallback: ctx.composition.placement(.daily)?.onThisDay?.fallback ?? .nearestDay)
            guard !Task.isCancelled, date == pickedDate else { return }
            todayEvents = events
        } catch {
            guard !Task.isCancelled, date == pickedDate else { return }
            historyFailed = true
        }
        historyLoading = false
    }
    private func loadDay() async {
        let date = pickedDate
        lunar = PoetLunarDay.of(date); works = [:]; todayEvents = []; failedForms = []
        let cards = ctx.visibleDailyCards
        loadingForms = cards.contains(.workOfDay) ? Set(genres.map(\.id)) : []
        if cards.contains(.workOfDay) {
            await withTaskGroup(of: Void.self) { group in
                for genre in genres { group.addTask { await loadForm(genre.id, on: date) } }
            }
        }
        if cards.contains(.onThisDay) { await loadHistory(on: date) }
        else { historyLoading = false; historyFailed = false }
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

/// 今日页的书画条目。书画页的 `ArtworkPreview` 还收旧主题参数, 这里只取它的缩略图件, 版式用 token。
private struct DailyArtworkCard: View {
    let artwork: Artwork
    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ZixiaoDesign.GlazePanel(padding: theme.space.md) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: theme.space.md) {
                    thumbnail.frame(maxWidth: .infinity).frame(height: theme.space.xxxl * 4)
                    caption
                }
            } else {
                HStack(spacing: theme.space.lg) {
                    thumbnail.frame(width: theme.space.xxxl * 2, height: theme.space.xxxl * 2)
                    caption.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(theme.type.caption.weight(.semibold))
                        .foregroundStyle(theme.color.textTertiary)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: ZXMetric.panelRadius, style: .continuous))
    }

    private var thumbnail: some View {
        ArtworkThumbnail(asset: artwork.cover)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
            .accessibilityHidden(true)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: theme.space.sm) {
            Text(artwork.kind).font(theme.type.caption.weight(.semibold)).foregroundStyle(theme.accent)
            Text(artwork.title).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
            Text(artwork.subtitle).font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        }
    }
}

/// 「一起读」卡的内容。共读页的 `ReadingCollectionLabel` 还收旧主题参数, 这里是 token 版。
private struct DailyCollectionLabel: View {
    let collection: ReadingCollection
    @Environment(\.zxTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: theme.space.lg) {
            Image(systemName: collection.symbol)
                .font(theme.type.title2).foregroundStyle(theme.accent)
                .frame(width: theme.space.xxl + theme.space.xs).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: theme.space.sm) {
                Text(collection.title).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                Text(collection.subtitle).font(theme.type.callout)
                    .foregroundStyle(theme.color.textSecondary).lineSpacing(theme.space.xs)
                Text("共读 \(collection.works.count) 篇")
                    .font(theme.type.footnote).foregroundStyle(theme.accent)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(theme.type.footnote)
                .foregroundStyle(theme.accent).padding(.top, theme.space.sm)
        }
        .contentShape(Rectangle())
    }
}

private struct DailyArchiveView: View {
    let ctx: CompositionContext
    let events: [PoetEvent]
    let dateLabel: String
    @Environment(\.zxTheme) private var theme
    var body: some View {
        List {
            ForEach(events.dropFirst()) { event in
                Section {
                    NavigationLink { EventDetailView(ctx: ctx, event: event) } label: {
                        EventRow(ctx: ctx, event: event)
                    }.listRowBackground(theme.surface)
                } header: {
                    ZixiaoDesign.SectionLabel("\(ctx.era.label(event.year)) · \(String(event.year))")
                }
            }
        }
        .scrollContentBackground(.hidden).poetReadableWidth().background(theme.paper())
        .foregroundStyle(theme.color.textPrimary)
        .zxNavigationTitle("旧日此时", subtitle: "\(dateLabel) · 其他 \(events.count - 1) 条记载", role: .secondary)
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
                    Text("选一个日子，读诗文，也看书画。每日内容按北京时间换新。")
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
