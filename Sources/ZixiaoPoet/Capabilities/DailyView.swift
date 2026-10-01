import SwiftUI

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
    @ScaledMetric(relativeTo: .body) private var coverWidth = 160.0
    @ScaledMetric(relativeTo: .body) private var coverHeight = 248.0
    @Namespace private var readings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    private var theme: Theme { ctx.theme }
    private var isToday: Bool { DailyRotation.calendar.isDateInToday(pickedDate) }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(ctx.visibleDailyCards, id: \.self) { card in
                    dailySection(card)
                }
                if !dailyArt.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        NativeSectionHeader(title: "今日看书画") {
                            NavigationLink("全部") { ArtworkGalleryView(ctx: ctx) }
                        }
                        ForEach(dailyArt) { artwork in
                            NavigationLink {
                                ArtworkDetailView(ctx: ctx, artwork: artwork)
                                    .readingTransition(artwork.id, in: readings)
                            } label: {
                                ArtworkPreview(artwork: artwork, theme: theme, compact: true)
                                    .readingTransitionSource(artwork.id, in: readings)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 20)
                }
                if let collection {
                    VStack(alignment: .leading, spacing: 12) {
                        NativeSectionHeader("一起读")
                        NavigationLink { ReadingCollectionView(ctx: ctx, collection: collection) } label: {
                            ReadingCollectionLabel(collection: collection, theme: theme)
                                .padding(18).background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }.buttonStyle(.plain)
                    }.padding(.horizontal, 20)
                }
            }.padding(.top, 12).padding(.bottom, 28).poetReadableWidth()
        }
        .background(theme.paper).scrollIndicators(.hidden)
        .navigationTitle(ctx.composition.placement(.daily)?.label ?? "今日")
        .toolbarTitleDisplayMode(.inlineLarge)
        .poetNavigationSubtitle("\(lunar.sexagenary)年 · \(lunar.label)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { picking = true } label: {
                    Image(systemName: isToday ? "calendar" : "calendar.badge.clock")
                }.accessibilityLabel("选择日子")
            }
        }
        .sheet(isPresented: $picking) { DateSelectionView(date: $pickedDate, theme: theme) }
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
                VStack(alignment: .leading, spacing: 12) {
                    NativeSectionHeader("接着读")
                    NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                        PoemRow(poem: poem, theme: theme, displayTitle: ctx.workTitle(poem)).padding(18)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 20)
            }
        case .onThisDay:
            historyPreview.padding(.horizontal, 20)
        case .epochNote:
            if let chapter = dailyChapter {
                VStack(alignment: .leading, spacing: 12) {
                    NativeSectionHeader("今日导读")
                    NavigationLink { EpochDetailView(ctx: ctx, epoch: chapter.epoch) } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(chapter.epoch.label).font(PoetFont.cardTitle).foregroundStyle(theme.ink)
                            Text(chapter.introduction).font(PoetFont.body).lineSpacing(5)
                                .foregroundStyle(theme.secondaryInk).lineLimit(3)
                            Label("进入\(ctx.narrativeLabel)篇章", systemImage: "arrow.right")
                                .font(PoetFont.meta).foregroundStyle(theme.accent)
                        }
                        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 20)
            }
        case .anecdote:
            EmptyView()
        }
    }

    private var dailyWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            NativeSectionHeader(title: "每日选读") {
                Text(genres.map(\.label).joined(separator: " · "))
            }.padding(.horizontal, 20)
            if typeSize.isAccessibilitySize {
                ForEach(genres) { genre in dailyCard(genre).padding(.horizontal, 20) }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(genres) { genre in
                            dailyCard(genre).frame(width: coverWidth).id(genre.id)
                        }
                    }.padding(.vertical, 6).scrollTargetLayout()
                }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
    }

    private func dailyCard(_ genre: Genre) -> some View {
        Group {
            if let poem = works[genre.id] {
                NavigationLink {
                    PoemDetailView(ctx: ctx, poem: poem).readingTransition(genre.id, in: readings)
                } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        ReadingCover(title: ctx.workTitle(poem), author: ctx.composition.poet.name,
                                     genre: genre, height: typeSize.isAccessibilitySize ? nil : coverHeight)
                            .readingTransitionSource(genre.id, in: readings)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("每日一\(genre.label)").font(.subheadline.weight(.semibold))
                            Text(poem.lines.first ?? poem.title)
                                .font(Font(PoetFont.serif(15, .regular, .subheadline)))
                                .foregroundStyle(theme.secondaryInk)
                                .lineSpacing(3)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        }
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("每日一\(genre.label)，\(ctx.workTitle(poem))，\(ctx.composition.poet.name)")
                .accessibilityHint("打开全文阅读")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(genre.label).font(.subheadline.weight(.semibold))
                        Spacer(minLength: 12)
                        if loadingForms.contains(genre.id) { ProgressView("正在选读…") }
                        else if failedForms.contains(genre.id) {
                            Text("这一篇暂未载入").font(.headline)
                            Button { Task { await loadForm(genre.id, on: pickedDate) } } label: {
                                Label("重试", systemImage: "arrow.clockwise")
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                                .poetActionStyle()
                        } else { Text("作品整理中").foregroundStyle(.secondary) }
                        Spacer(minLength: 12)
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: typeSize.isAccessibilitySize ? nil : coverHeight)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 6))
                    Text("每日一\(genre.label)").font(.subheadline.weight(.semibold))
                }
            }
        }.foregroundStyle(theme.ink)
    }

    private var historyPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            NativeSectionHeader(title: "旧日此时") { Text(lunar.label) }
            VStack(alignment: .leading, spacing: 14) {
                if historyLoading { ProgressView("正在翻阅年谱…") }
                else if historyFailed {
                    Text("年谱暂未载入").foregroundStyle(.secondary)
                    Button { Task { await loadHistory(on: pickedDate) } } label: {
                        Text("重试")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                } else if let event = todayEvents.first {
                    if todayEvents.contains(where: { $0.month != lunar.month || $0.day != lunar.day }) {
                        Text("当日未见记载，为你选一则相近日子的年谱。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    NavigationLink { EventDetailView(ctx: ctx, event: event) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("\(ctx.era.label(event.year)) · \(String(event.year))").font(.subheadline.weight(.semibold))
                                Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            }.foregroundStyle(theme.accent)
                            Text(event.narrative).font(.body).lineSpacing(5).lineLimit(3).foregroundStyle(theme.ink)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if todayEvents.count > 1 {
                        Divider()
                        NavigationLink {
                            DailyArchiveView(ctx: ctx, events: todayEvents, dateLabel: lunar.label)
                        } label: {
                            Text("另有 \(todayEvents.count - 1) 条记载")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .font(.subheadline)
                    }
                } else {
                    Text("年谱未留下这一天的记载，明日再来翻一页。").foregroundStyle(.secondary)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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

private struct DailyArchiveView: View {
    let ctx: CompositionContext
    let events: [PoetEvent]
    let dateLabel: String
    var body: some View {
        List {
            ForEach(events.dropFirst()) { event in
                Section("\(ctx.era.label(event.year)) · \(String(event.year))") {
                    NavigationLink { EventDetailView(ctx: ctx, event: event) } label: {
                        EventRow(ctx: ctx, event: event)
                    }.listRowBackground(ctx.theme.surface)
                }
            }
        }
        .scrollContentBackground(.hidden).poetReadableWidth().background(ctx.theme.paper)
        .navigationTitle("旧日此时").navigationBarTitleDisplayMode(.inline)
        .poetNavigationSubtitle("\(dateLabel) · 其他 \(events.count - 1) 条记载")
    }
}

private struct DateSelectionView: View {
    @Binding var date: Date
    let theme: Theme
    @State private var draft: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    init(date: Binding<Date>, theme: Theme) {
        _date = date
        self.theme = theme
        _draft = State(initialValue: date.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("选一个日子，读诗文，也看书画。每日内容按北京时间换新。")
                        .font(PoetFont.body).foregroundStyle(theme.secondaryInk)
                    DatePicker("选择日期", selection: $draft, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .environment(\.calendar, DailyRotation.calendar)
                        .environment(\.timeZone, DailyRotation.calendar.timeZone)
                    Button { draft = .now } label: {
                        Label("回到今日", systemImage: "arrow.uturn.backward")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                        .poetActionStyle()
                        .disabled(DailyRotation.calendar.isDateInToday(draft))
                }
                .padding(Metric.gutter).poetReadableWidth()
            }
            .background(theme.paper)
            .navigationTitle("选择日子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { date = draft; dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .tint(theme.accent)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(640), .large])
        .presentationDragIndicator(.visible)
    }
}
