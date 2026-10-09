import ZixiaoPoetCore
//  ReaderLifeSections.swift — 读本正文之下: 此时 → 同年作品 → 相关墨迹
//
//  把作品钉回人生: 「此时」卡说它写在哪一年、哪一天、哪里 (刻 > 事目 > 未编年, 判定见 `ReaderTimeline`);
//  有系年时, 同一年的其他作品排成一架书; 有墨迹的, 真迹横着摆一条。
//  每节是独立的 View (不是计算属性): 读本页本来就长, 嵌套的 some View 在真机主线程上解类型元数据会爆栈。
//  色: 只用墨与纸的层级; 页面唯一的强调仍是书签 (印)。

import SwiftUI
import ZixiaoDesign

struct ReaderLifeSections: View {
    let ctx: CompositionContext
    let poem: Poem
    /// nil = 还在判定 (刻是同步的, 事目要查一次)。
    @State private var placement: ReaderPlacement?
    @State private var failed = false
    @State private var sameYear: [Poem] = []
    @State private var yearTotal: Int?
    @State private var sheetYear: ReaderYear?
    @Environment(\.zxTheme) private var theme

    init(ctx: CompositionContext, poem: Poem) {
        self.ctx = ctx
        self.poem = poem
        // 有刻时首帧就画出卡, 不等网络。
        _placement = State(initialValue: ReaderTimeline.moment(for: poem.id, in: ctx.moments).map { .moment($0) })
    }

    /// 没有刻、编成也不带年谱的 App: 不谈系年, 整节不出现 (免得每篇都写「未编年」)。
    private var tracksChronology: Bool {
        ctx.hasChronicleData || ReaderTimeline.moment(for: poem.id, in: ctx.moments) != nil
    }
    private var artworks: [Artwork] { ReaderTimeline.relatedArtworks(for: poem.id, in: ctx.artworks) }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.xxl) {
            if tracksChronology {
                if let placement {
                    ReaderNowCard(ctx: ctx, placement: placement, yearTotal: yearTotal,
                                  openMoment: openMoment, openYear: { sheetYear = ReaderYear(year: $0) })
                } else if failed {
                    Button("此时暂未载入，点击重试") { Task { await load() } }
                        .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                        .frame(minHeight: PoetLayout.minHitTarget)
                }
            }
            if let year = placement?.year, !sameYear.isEmpty {
                ReaderSameYearShelf(ctx: ctx, yearLabel: ctx.era.label(year), poems: sameYear)
            }
            if !artworks.isEmpty {
                ReaderArtworkStrip(ctx: ctx, artworks: artworks)
            }
        }
        .task(id: poem.id) { await load() }
        .sheet(item: $sheetYear) { ReaderYearSheet(ctx: ctx, year: $0.year) }
    }

    /// 「看这一天」: 交给跨 Tab 导航 (D5 的 `LifeNavigationState`), 切到一生长卷并滚到这一刻。
    private func openMoment(_ moment: PoetMoments.Moment) {
        ctx.lifeNavigation.show(moment: moment.id)
    }

    private func load() async {
        guard tracksChronology else { return }
        failed = false
        var links: [WorkEventLink] = []
        if case .moment = placement {
            // 刻已定, 不查事目边。
        } else {
            do { links = try await ctx.store.workEventLinks(of: poem.id) } catch {
                if !Task.isCancelled { failed = placement == nil }
                return
            }
        }
        guard !Task.isCancelled else { return }
        let resolved = ReaderTimeline.placement(of: poem.id, moments: ctx.moments, links: links)
        placement = resolved
        guard let year = resolved.year else { return }
        let poetID: UUID?
        if let id = resolved.poetID { poetID = id } else { poetID = try? await ctx.store.authorID(ofWork: poem.id) }
        guard let poetID, !Task.isCancelled else { return }
        async let works = try? ctx.store.sameYearWorks(poetID: poetID, year: year, excluding: poem.id)
        async let total = eventTotal(for: resolved, poetID: poetID, year: year)
        let (fetchedWorks, fetchedTotal) = await (works, total)
        guard !Task.isCancelled else { return }
        sameYear = fetchedWorks ?? []
        yearTotal = fetchedTotal
    }

    /// 「这一年还有 N 条记载」的 N 只给事目卡用; 刻的卡不数。
    private func eventTotal(for placement: ReaderPlacement, poetID: UUID, year: Int) async -> Int? {
        guard case .events = placement else { return nil }
        return try? await ctx.store.eventCount(poetID: poetID, year: year)
    }
}

/// 年谱 sheet 的一年。
struct ReaderYear: Identifiable, Hashable {
    let year: Int
    var id: Int { year }
}

// MARK: - 此时

/// 「此时」卡。刻: 时地行 + 刻名 + 按语 + 「看这一天」; 事目: 时地行 + 两行事 (至多两条) + 「这一年还有 N 条记载」;
/// 未编年: 一行小字, 不画卡。
struct ReaderNowCard: View {
    let ctx: CompositionContext
    let placement: ReaderPlacement
    let yearTotal: Int?
    let openMoment: (PoetMoments.Moment) -> Void
    let openYear: (Int) -> Void
    @Environment(\.zxTheme) private var theme

    var body: some View {
        switch placement {
        case .moment(let moment):
            card {
                Text(ReaderTimeline.momentLine(moment))
                    .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                VStack(alignment: .leading, spacing: theme.space.xs) {
                    Text(moment.title).font(theme.type.title3).foregroundStyle(theme.color.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(moment.lede).font(theme.type.body).foregroundStyle(theme.color.textSecondary)
                        .lineSpacing(theme.space.xs).fixedSize(horizontal: false, vertical: true)
                }
                action(moment.workDating == .contextual ? "回到人生长卷" : "看这一天") { openMoment(moment) }
            }
        case .events(let links):
            card {
                ForEach(links.prefix(ReaderTimeline.shownEventLimit)) { link in
                    VStack(alignment: .leading, spacing: theme.space.xs) {
                        Text(ReaderTimeline.eventLine(link.event, eraLabel: ctx.era.label(link.event.year),
                                                      place: ReaderTimeline.placeName(stationID: link.event.stationId,
                                                                                      stations: ctx.store.stations,
                                                                                      fallback: link.stationName)))
                            .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                        Text(ReaderTimeline.excerpt(link.event))
                            .font(theme.type.body).foregroundStyle(theme.color.textPrimary)
                            .lineSpacing(theme.space.xs).lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let year = links.first?.event.year {
                    action(yearAction(shown: min(links.count, ReaderTimeline.shownEventLimit))) { openYear(year) }
                }
            }
        case .undated:
            Text("未编年")
                .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                .accessibilityLabel("此时：未编年")
        }
    }

    private func yearAction(shown: Int) -> String {
        guard let yearTotal else { return "看这一年的年谱" }
        let rest = ReaderTimeline.remainingCount(yearTotal: yearTotal, shown: shown)
        return rest > 0 ? "这一年还有 \(rest) 条记载" : "看这一年的年谱"
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZixiaoDesign.GlazePanel(glaze: .surface) {
            VStack(alignment: .leading, spacing: theme.space.md) {
                ZixiaoDesign.SectionLabel(isContextual ? "人生背景" : "此时")
                content()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var isContextual: Bool {
        if case .moment(let moment) = placement { return moment.workDating == .contextual }
        return false
    }

    /// 卡内的下钻: 墨色小字 + 箭头, 不用强调色 (页面的强调留给书签)。
    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: theme.space.xs) {
                Text(title)
                Image(systemName: "chevron.right").font(theme.type.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(theme.type.footnote.weight(.medium)).foregroundStyle(theme.color.textPrimary)
            .frame(minHeight: PoetLayout.minHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 同年作品

/// 同一年的其他作品, 一架线装书 (素面书衣, 不着包角色), 横滑。点开推入它的读本。
struct ReaderSameYearShelf: View {
    let ctx: CompositionContext
    let yearLabel: String
    let poems: [Poem]
    @Environment(\.zxTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var coverWidth = BookCoverView.Size.shelf.width
    /// 题签竖排两列放得下的字数; 更长的篇名在封面上截短, 读屏仍念全名。
    private static let coverTitleLimit = 12

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            ReaderSectionTitle("同年作品", detail: yearLabel)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: theme.space.lg) {
                    ForEach(poems) { poem in
                        let title = ctx.workTitle(poem)
                        NavigationLink {
                            AnyView(PoemDetailView(ctx: ctx, poem: poem))
                        } label: {
                            BookCoverView(title: Self.coverTitle(title), author: genre(of: poem),
                                          size: .width(coverWidth))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(title)，\(genre(of: poem))")
                    }
                }
                .padding(.vertical, theme.space.xs)
            }
            .scrollClipDisabled()
        }
    }

    private func genre(of poem: Poem) -> String {
        ctx.composition.placement(.corpus)?.genres?.first { $0.id == poem.form }?.label ?? "诗文"
    }

    static func coverTitle(_ title: String) -> String {
        let compact = title.replacingOccurrences(of: " ", with: "")
        return compact.count > coverTitleLimit ? String(compact.prefix(coverTitleLimit - 1)) + "…" : compact
    }
}

// MARK: - 相关墨迹

/// 与这篇相关的真迹: 16:9 图版 + 题名。一件时占满栏宽, 多件时横滑。点开推入墨迹页。
struct ReaderArtworkStrip: View {
    let ctx: CompositionContext
    let artworks: [Artwork]
    @Environment(\.zxTheme) private var theme
    /// 多件横滑时一张的宽度 (固有尺寸)。
    @ScaledMetric(relativeTo: .body) private var tileWidth: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            ReaderSectionTitle("相关墨迹", detail: nil)
            if artworks.count == 1, let artwork = artworks.first {
                tile(artwork)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: theme.space.lg) {
                        ForEach(artworks) { tile($0).frame(width: tileWidth) }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private func tile(_ artwork: Artwork) -> some View {
        NavigationLink {
            AnyView(ArtworkDetailView(ctx: ctx, artwork: artwork))
        } label: {
            VStack(alignment: .leading, spacing: theme.space.sm) {
                Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                    .overlay { ArtworkThumbnail(asset: artwork.cover) }
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: theme.space.xxs) {
                    Text(artwork.title).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                    Text([artwork.kind, artwork.dateLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary).lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开墨迹")
    }
}

// MARK: - 共用

/// 下半页的小节题: 与「再读深一层」同一级 (footnote 中重、次级墨色)。
struct ReaderSectionTitle: View {
    let title: String
    let detail: String?
    @Environment(\.zxTheme) private var theme

    init(_ title: String, detail: String?) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        Text([title, detail].compactMap { $0 }.joined(separator: " · "))
            .font(theme.type.footnote.weight(.medium)).foregroundStyle(theme.color.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 当年的年谱, 半屏 sheet (与长卷里点年份打开的是同一页 `ChronicleEventsView`)。
struct ReaderYearSheet: View {
    let ctx: CompositionContext
    let year: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.zxTheme) private var theme

    var body: some View {
        NavigationStack {
            ChronicleEventsView(ctx: ctx, year: year)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(theme.color.textPrimary)
    }
}
