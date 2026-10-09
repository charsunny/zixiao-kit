import ZixiaoPoetCore
//  CorpusYearSection.swift — 诗文「按年读」: 一条年份轴, 选年 → 该年作品
//
//  轴: 生年到卒年每年一格 (`CorpusYearAxis`), 有作品的格子一道墨色刻度 (高低随篇数), 分期起始年前
//  一条淡分隔; 选中的那一年是全页唯一的强调色。轴末一个「未编年」伪年。初始落在当前一卷里作品
//  最多的那一年, 横向居中。轴下是该年作品 (至多 `previewLimit` 篇) 与「全部 N 篇」。
//  数据: `PoetStore.workYearCounts` / `workIDs(year:)` (RPC 070, 缺席时客户端退路)。没有任何系年
//  作品的诗人整节收起。

import SwiftUI
import ZixiaoDesign

/// 年份轴上的一格: 某一年, 或末尾的「未编年」。
enum CorpusYearPick: Hashable, Sendable {
    case year(Int)
    case undated
}

/// 逐年篇数与某年作品 id 的会话内缓存 (根页在 LazyVStack 里可能被回收重建, 回来不重取)。
@MainActor
enum CorpusYearCache {
    static var years: [String: PoetWorkYears] = [:]
    static var ids: [String: [UUID]] = [:]
    static func idsKey(_ poet: String, _ year: Int) -> String { "\(poet)#\(year)" }
}

struct CorpusYearSection: View {
    let ctx: CompositionContext
    /// iPad 右栏整页显示时由页自己给标题, 这里不再出节题。
    var showsHeader = true
    @State private var axis: CorpusYearAxis?
    @State private var failed = false
    @State private var selection: CorpusYearPick?
    @Environment(\.zxTheme) private var theme

    private var poetName: String { ctx.composition.poet.name }

    var body: some View {
        if let axis, axis.isEmpty {
            if !showsHeader {
                EmptyState("暂无系年作品", systemImage: "calendar")
                    .frame(maxWidth: .infinity, minHeight: PoetLayout.minHitTarget * 6)
            }
        } else {
            VStack(alignment: .leading, spacing: theme.space.lg) {
                if showsHeader {
                    CorpusSectionHeader(title: "按年读", detail: axis.map(detail) ?? "从生年到卒年，选一年读那一年的作品")
                }
                if let axis {
                    CorpusYearStrip(ctx: ctx, axis: axis, selection: $selection)
                    if let selection {
                        CorpusYearWorks(ctx: ctx, pick: selection, axis: axis)
                            .padding(.horizontal, theme.space.margin)
                    }
                } else if failed {
                    Button("年份轴暂未载入，点击重试") { Task { await load() } }
                        .font(theme.type.subhead)
                        .frame(maxWidth: .infinity, minHeight: PoetLayout.minHitTarget)
                } else {
                    LoadingStateView(label: "正在排年份…")
                }
            }
            .task { if axis == nil { await load() } }
        }
    }

    private func detail(_ axis: CorpusYearAxis) -> String {
        let years = axis.cells.filter(\.hasWorks).count
        return "\(years) 年有系年作品，选一年读那一年写下的诗文"
    }

    private func load() async {
        failed = false
        do {
            let years: PoetWorkYears
            if let cached = CorpusYearCache.years[poetName] {
                years = cached
            } else {
                years = try await ctx.store.workYearCounts(poet: poetName)
                CorpusYearCache.years[poetName] = years
            }
            guard !Task.isCancelled else { return }
            let built = Self.axis(ctx: ctx, years: years)
            if selection == nil, let year = Self.debugYear ?? built.peakYear(in: focusRange(built)) {
                selection = .year(year)
            }
            axis = built
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }

    /// 截图用 (DEBUG): `-corpusYear <公元年>` 初选那一年。
    private static var debugYear: Int? {
        #if DEBUG
        let year = UserDefaults.standard.integer(forKey: "corpusYear")
        return year > 0 ? year : nil
        #else
        return nil
        #endif
    }

    /// 编成的生卒 + 逐年篇数 + 分期 (有长卷用卷, 否则用导读分期)。未编年: RPC 给的数, 否则按编成的
    /// 体裁篇数减去系年篇数估 (体裁篇数不全时不给数)。
    static func axis(ctx: CompositionContext, years: PoetWorkYears) -> CorpusYearAxis {
        let poet = ctx.composition.poet
        let chapters: [CorpusYearAxis.Chapter]
        if let moments = ctx.moments, !moments.chapters.isEmpty {
            chapters = moments.chapters.map { .init(start: $0.startYear, end: $0.endYear, label: $0.title) }
        } else {
            chapters = ctx.lifeEpochs.map { .init(start: $0.yearStart, end: $0.yearEnd ?? $0.yearStart, label: $0.label) }
        }
        let counts = ctx.literaryGenres.map(\.count)
        let total = counts.contains(nil) ? nil : counts.compactMap { $0 }.reduce(0, +)
        let undated = years.undated ?? total.map { max($0 - years.datedWorks, 0) }
        return CorpusYearAxis(lifespan: poet.birth...max(poet.birth, poet.death), counts: years.counts,
                              chapters: chapters, undated: undated)
    }

    /// 当前一卷: 最近读过、且导读能定卷的作品所在的卷 → 第一卷编好的长卷 → 作品最多的那一卷。
    private func focusRange(_ axis: CorpusYearAxis) -> ClosedRange<Int>? {
        let recent = ctx.userData.reading.sorted { ($0.lastReadAt ?? "") > ($1.lastReadAt ?? "") }
        let read = recent.lazy.compactMap { ctx.guide?.chapter(containing: $0.poemId)?.epoch }.first
            .map { $0.yearStart...max($0.yearStart, $0.yearEnd ?? $0.yearStart) }
        let written = ctx.moments?.chapters.first { !$0.isStub }.map { $0.startYear...max($0.startYear, $0.endYear) }
        return CorpusYearAxis.focusRange(readChapter: read, writtenChapter: written, axis: axis)
    }
}

/// 宽屏右栏的「按年读」整页: 轴与该年作品, 页自己给标题。
struct CorpusYearPage: View {
    let ctx: CompositionContext
    @Environment(\.zxTheme) private var theme

    var body: some View {
        ScrollView {
            CorpusYearSection(ctx: ctx, showsHeader: false)
                .padding(.vertical, theme.space.xl)
                .poetReadableWidth(1000)
        }
        .background(theme.paper())
        .zxNavigationTitle("按年读", role: .secondary)
    }
}

// MARK: - 轴

struct CorpusYearStrip: View {
    let ctx: CompositionContext
    let axis: CorpusYearAxis
    @Binding var selection: CorpusYearPick?
    @Environment(\.zxTheme) private var theme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 一格的宽 (也是点按区) 与刻度区的高, 随 Dynamic Type 放大。
    @ScaledMetric(relativeTo: .caption) private var cellWidth = 44.0
    @ScaledMetric(relativeTo: .caption) private var tickHeight = 28.0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(axis.cells) { cell in
                        yearButton(cell).id(CorpusYearPick.year(cell.year))
                    }
                    undatedButton.id(CorpusYearPick.undated)
                }
                .overlay(alignment: .bottom) {
                    // 轴线: 一条 hairline, 刻度立在它上面。
                    Rectangle().fill(theme.rule).frame(height: 1 / displayScale)
                        .padding(.bottom, labelBand)
                        .accessibilityHidden(true)
                }
            }
            .contentMargins(.horizontal, theme.space.margin, for: .scrollContent)
            .scrollIndicators(.hidden)
            .onAppear { if let selection { proxy.scrollTo(selection, anchor: .center) } }
            .onChange(of: selection) { _, pick in
                guard let pick else { return }
                withAnimation(theme.motion.adapted(theme.motion.standard, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(pick, anchor: .center)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    /// 年份字那一带的高 (轴线画在它上沿)。
    private var labelBand: CGFloat { tickHeight * 0.75 }

    private func yearButton(_ cell: CorpusYearAxis.Cell) -> some View {
        let selected = selection == .year(cell.year)
        let tint = selected ? theme.color.accent : (cell.hasWorks ? theme.color.textSecondary : theme.color.textTertiary)
        return Button { selection = .year(cell.year) } label: {
            VStack(spacing: theme.space.xxs) {
                tick(cell, selected: selected)
                Text(String(cell.year))
                    .font(theme.type.caption.monospacedDigit().weight(selected ? .semibold : .regular))
                    .foregroundStyle(tint)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(height: labelBand)
            }
            .frame(width: cellWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) {
            if cell.startsChapter {
                Rectangle().fill(theme.rule).frame(width: 1 / displayScale).accessibilityHidden(true)
            }
        }
        .accessibilityLabel(accessibilityLabel(cell))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// 刻度: 有作品的一道墨 (高低按篇数开方, 一篇也看得见); 没有作品只留一个小点。
    private func tick(_ cell: CorpusYearAxis.Cell, selected: Bool) -> some View {
        let fraction = axis.maxCount > 0 ? (Double(cell.count) / Double(axis.maxCount)).squareRoot() : 0
        let height = cell.hasWorks ? max(tickHeight * fraction, theme.space.xs) : 0
        return ZStack(alignment: .bottom) {
            Color.clear
            if cell.hasWorks {
                Capsule()
                    .fill(selected ? theme.color.accent : theme.ink(0.55))
                    .frame(width: selected ? theme.space.xs : theme.space.xxs, height: height)
            }
        }
        .frame(height: tickHeight)
        .accessibilityHidden(true)
    }

    private var undatedButton: some View {
        let selected = selection == .undated
        return Button { selection = .undated } label: {
            VStack(spacing: theme.space.xxs) {
                Color.clear.frame(height: tickHeight)
                Text("未编年")
                    .font(theme.type.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? theme.color.accent : theme.color.textSecondary)
                    .lineLimit(1).fixedSize()
                    .frame(height: labelBand)
            }
            .padding(.horizontal, theme.space.md)
            .frame(minWidth: cellWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, theme.space.sm)
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.rule).frame(width: 1 / displayScale).accessibilityHidden(true)
        }
        .accessibilityLabel(axis.undated.map { "未编年，\($0) 篇" } ?? "未编年")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func accessibilityLabel(_ cell: CorpusYearAxis.Cell) -> String {
        let era = ctx.era.label(cell.year)
        let chapter = cell.chapterLabel.map { "，\($0)" } ?? ""
        let works = cell.hasWorks ? "\(cell.count) 篇" : "无系年作品"
        return "\(String(cell.year)) 年，\(era)\(chapter)，\(works)"
    }
}

// MARK: - 轴下: 该年作品

struct CorpusYearWorks: View {
    let ctx: CompositionContext
    let pick: CorpusYearPick
    let axis: CorpusYearAxis
    @State private var works: [Poem] = []
    @State private var total = 0
    @State private var loading = false
    @State private var failed = false
    @Environment(\.zxTheme) private var theme
    /// 根页上一年至多列几篇, 其余进「全部 N 篇」。
    static let previewLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            switch pick {
            case .year(let year): yearBlock(year)
            case .undated: undatedBlock
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: pick) { await load() }
    }

    @ViewBuilder private func yearBlock(_ year: Int) -> some View {
        let cell = axis.cell(year)
        VStack(alignment: .leading, spacing: theme.space.xxs) {
            Text("\(String(year)) · \(ctx.era.label(year))")
                .font(theme.type.headline.monospacedDigit()).foregroundStyle(theme.color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text([cell?.chapterLabel, cell.map { $0.hasWorks ? "\($0.count) 篇" : "这一年没有系年作品" }]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
        }
        if cell?.hasWorks == true {
            if loading && works.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: PoetLayout.minHitTarget * 2)
            } else if failed && works.isEmpty {
                Button("这一年的作品暂未载入，点击重试") { Task { await load() } }
                    .font(theme.type.subhead).frame(minHeight: PoetLayout.minHitTarget)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(works.enumerated()), id: \.element.id) { index, poem in
                        if index > 0 { InkDivider() }
                        NavigationLink {
                            AnyView(PoemDetailView(ctx: ctx, poem: poem))
                        } label: {
                            CorpusYearWorkRow(ctx: ctx, poem: poem)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if total > works.count {
                    NavigationLink {
                        AnyView(CorpusYearWorksView(ctx: ctx, year: year))
                    } label: {
                        HStack(spacing: theme.space.xs) {
                            Text("全部 \(total) 篇")
                            Image(systemName: "chevron.right").font(theme.type.caption).accessibilityHidden(true)
                        }
                        .font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                        .frame(minHeight: PoetLayout.minHitTarget).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(String(year)) 年全部 \(total) 篇")
                }
            }
        }
    }

    @ViewBuilder private var undatedBlock: some View {
        VStack(alignment: .leading, spacing: theme.space.xs) {
            Text("未编年").font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(axis.undated.map { "还有 \($0) 篇尚未系年。" } ?? "还有一些作品尚未系年。")
                .font(theme.type.body).foregroundStyle(theme.color.textPrimary)
            Text("年谱里查不到它们写于哪一年，这里暂不按年排列；可以在全集里按体裁读到它们。")
                .font(theme.type.callout).foregroundStyle(theme.color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        NavigationLink {
            AnyView(CorpusDirectoryView(ctx: ctx))
        } label: {
            HStack(spacing: theme.space.xs) {
                Text("去全集")
                Image(systemName: "chevron.right").font(theme.type.caption).accessibilityHidden(true)
            }
            .font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
            .frame(minHeight: PoetLayout.minHitTarget).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        guard case .year(let year) = pick, axis.cell(year)?.hasWorks == true else {
            works = []; total = 0; return
        }
        works = []; total = 0
        loading = true; failed = false
        defer { loading = false }
        do {
            let ids = try await CorpusYearWorks.ids(ctx: ctx, year: year)
            guard !Task.isCancelled else { return }
            total = ids.count
            let page = try await ctx.store.poems(ids: Array(ids.prefix(Self.previewLimit)))
            guard !Task.isCancelled else { return }
            works = page
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }

    /// 某年作品 id (会话内记一次)。
    static func ids(ctx: CompositionContext, year: Int) async throws -> [UUID] {
        let name = ctx.composition.poet.name
        let key = CorpusYearCache.idsKey(name, year)
        if let cached = CorpusYearCache.ids[key] { return cached }
        let ids = try await ctx.store.workIDs(year: year, poet: name)
        CorpusYearCache.ids[key] = ids
        return ids
    }
}

/// 按年读的作品行: 题 + 首句 + 体裁。
struct CorpusYearWorkRow: View {
    let ctx: CompositionContext
    let poem: Poem
    var showsDisclosure = true
    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var genreLabel: String {
        let form = ctx.genre(for: poem).label
        guard let fine = poem.genre?.trimmingCharacters(in: .whitespacesAndNewlines), !fine.isEmpty, fine != form
        else { return form }
        return "\(form) · \(fine)"
    }

    var body: some View {
        HStack(spacing: theme.space.md) {
            VStack(alignment: .leading, spacing: theme.space.xs) {
                Text(ctx.workTitle(poem)).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: theme.space.sm) {
                    Text(poem.firstLine).font(theme.type.callout).foregroundStyle(theme.color.textSecondary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    Spacer(minLength: theme.space.xs)
                    Text(genreLabel).font(theme.type.caption).foregroundStyle(theme.color.textTertiary)
                        .lineLimit(1).layoutPriority(1)
                }
            }
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(theme.type.caption.weight(.semibold)).foregroundStyle(theme.color.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, theme.space.md)
        .frame(minHeight: PoetLayout.minHitTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ctx.workTitle(poem))，\(genreLabel)。\(poem.firstLine)")
    }
}

// MARK: - 某一年的全部作品

struct CorpusYearWorksView: View {
    let ctx: CompositionContext
    let year: Int
    @State private var ids: [UUID]?
    @State private var poems: [Poem] = []
    @State private var loadingPage = false
    @State private var failed = false
    @Environment(\.zxTheme) private var theme
    private static let pageSize = 60

    private var hasMore: Bool { (ids?.count ?? 0) > loadedCount }
    @State private var loadedCount = 0

    var body: some View {
        List {
            ForEach(poems) { poem in
                NavigationLink {
                    AnyView(PoemDetailView(ctx: ctx, poem: poem))
                } label: {
                    CorpusYearWorkRow(ctx: ctx, poem: poem, showsDisclosure: false)
                }
                .listRowBackground(theme.paper()).listRowSeparatorTint(theme.rule)
                .task { if poem.id == poems.last?.id, hasMore, !failed { await loadNextPage() } }
            }
            if !poems.isEmpty {
                if failed {
                    Button("载入中断，点击重试") { Task { await loadNextPage() } }
                        .font(theme.type.subhead)
                        .frame(maxWidth: .infinity, minHeight: PoetLayout.minHitTarget)
                        .listRowBackground(theme.paper())
                } else if hasMore {
                    LoadingStateView(label: "正在载入更多…")
                        .listRowBackground(theme.paper()).listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).poetReadableWidth()
        .background(theme.paper()).tint(theme.color.accent)
        .zxNavigationTitle("\(String(year)) 年", subtitle: subtitle, role: .secondary)
        .overlay {
            if poems.isEmpty {
                if failed { LoadFailureView(retry: start) }
                else if ids?.isEmpty == true { EmptyState("这一年没有系年作品", systemImage: "calendar") }
                else { LoadingStateView() }
            }
        }
        .task { if ids == nil { await start() } }
    }

    private var subtitle: String {
        let era = ctx.era.label(year)
        return ids.map { "\(era) · \($0.count) 篇" } ?? era
    }

    private func start() async {
        failed = false
        do {
            let fetched = try await CorpusYearWorks.ids(ctx: ctx, year: year)
            guard !Task.isCancelled else { return }
            ids = fetched
            await loadNextPage()
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }

    private func loadNextPage() async {
        guard let ids, !loadingPage, hasMore else { return }
        loadingPage = true; failed = false
        defer { loadingPage = false }
        let slice = Array(ids[loadedCount..<min(loadedCount + Self.pageSize, ids.count)])
        do {
            let page = try await ctx.store.poems(ids: slice)
            guard !Task.isCancelled else { return }
            let existing = Set(poems.map(\.id))
            poems.append(contentsOf: page.filter { !existing.contains($0.id) })
            loadedCount += slice.count
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}
