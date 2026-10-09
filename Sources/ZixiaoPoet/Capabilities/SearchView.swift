import ZixiaoPoetCore
import SwiftUI
import ZixiaoDesign

/// 检索 Tab (编成里的 hero 能力)。零态给出编辑写好的线索; 有词时同时查书画 (本机) 与
/// 作品 (在线与打包代表作) / 已载入的地点与人物 / 年份。
struct SearchZeroStateView: View {
    let ctx: CompositionContext
    @State private var query = ""
    @State private var results = SearchResults.empty
    @State private var searching = false
    @State private var failed = false
    @State private var searchRequestID: UUID?
    @Environment(\.zxTheme) private var theme
    private var artResults: [Artwork] { term.isEmpty ? [] : ctx.artworks.filter { $0.matches(term) } }
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// 行的最小高度 (点按区)。
    private static let rowMinHeight: CGFloat = 48

    var body: some View {
        Group {
            if term.isEmpty { zeroState }
            else if searching && results.isEmpty && artResults.isEmpty { LoadingStateView(label: "正在寻踪…") }
            else if failed && results.isEmpty && artResults.isEmpty { LoadFailureView(title: "检索暂不可用", retry: search) }
            else if results.isEmpty && artResults.isEmpty { noResults }
            else { resultList }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.paper())
        .tint(theme.color.accent)
        .zxNavigationTitle(ctx.composition.placement(.search)?.label ?? "寻踪",
                           subtitle: term.isEmpty ? "作品与\(ctx.narrativeLabel)" : "作品 · 地点 · 人物 · 年份",
                           role: .root)
        .searchable(text: $query, prompt: "搜作品、地点、人物或年份")
        .scrollDismissesKeyboard(.interactively)
        .task(id: "\(term)|\(ctx.store.stations.count)|\(ctx.store.associates.count)") { await search() }
    }

    /// 没搜到: 幽灵行 + 一个能做的动作 (清掉这次的词, 回到线索)。
    private var noResults: some View {
        ScrollView {
            ZXGhostState("没有找到「\(term)」",
                         message: "换一个标题、诗句、地点或人物试试，也可以从线索开始。",
                         actionTitle: "清除搜索", systemImage: "arrow.uturn.backward") {
                query = ""
            }
        }
    }

    private var zeroState: some View {
        List {
            Section {
                ForEach(ctx.composition.editorial?.searchPrompts ?? []) { prompt in
                    Button { query = prompt.query } label: {
                        HStack(spacing: theme.space.md) {
                            Image(systemName: prompt.symbol).font(theme.type.body)
                                .foregroundStyle(theme.color.accent)
                                .frame(width: theme.space.xl + theme.space.xs)
                            VStack(alignment: .leading, spacing: theme.space.xs) {
                                Text(prompt.query).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                                Text(prompt.hint).font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.left").font(theme.type.footnote)
                                .foregroundStyle(theme.color.textTertiary).accessibilityHidden(true)
                        }.padding(.vertical, theme.space.xs)
                    }.accessibilityLabel("搜索\(prompt.query)，\(prompt.hint)")
                }
            } header: { ListSectionTitle("试着搜一搜") }
            .listRowBackground(theme.color.surface)
            if !ctx.artworks.isEmpty {
                Section {
                    ForEach(ctx.artworks.prefix(2)) { artwork in
                        NavigationLink { ArtworkDetailView(ctx: ctx, artwork: artwork) } label: {
                            Label(artwork.title, systemImage: "paintbrush.pointed")
                                .font(theme.type.body).foregroundStyle(theme.color.textPrimary)
                        }
                    }
                } header: { ListSectionTitle("也可以看书画") }
                .listRowBackground(theme.color.surface)
            }
            if ctx.store.loadError != nil && (ctx.hasItineraryData || ctx.hasNetworkData) {
                Section {
                    Button("重新载入地点与人物") { Task { await ctx.store.bootstrap() } }.font(theme.type.body)
                } footer: {
                    Text("地点与人物暂未载入。").font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                }
                .listRowBackground(theme.color.surface)
            }
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden).poetReadableWidth(640)
    }

    private var resultList: some View {
        List {
            if !artResults.isEmpty {
                Section {
                    ForEach(artResults) { artwork in
                        NavigationLink { ArtworkDetailView(ctx: ctx, artwork: artwork) } label: {
                            VStack(alignment: .leading, spacing: theme.space.xs) {
                                Text(artwork.title).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                                Text("\(artwork.kind) · \(artwork.collection)").font(theme.type.subhead)
                                    .foregroundStyle(theme.color.textSecondary)
                            }.padding(.vertical, theme.space.xs)
                        }
                    }
                } header: { ListSectionTitle("书画 · \(artResults.count)") }
                .listRowBackground(theme.color.surface)
            }
            if searching {
                Section { LoadingStateView(label: "正在检索在线诗文…") }
                    .listRowBackground(theme.color.surface)
            }
            if failed {
                Section {
                    Button("在线诗文检索暂不可用，重试") { Task { await search() } }.font(theme.type.body)
                } footer: {
                    Text("已保留本地诗文、书画与已载入的地点、人物线索。")
                        .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                }
                    .listRowBackground(theme.color.surface)
            }

            if let year = results.year {
                Section {
                    NavigationLink { yearDestination(year) } label: {
                        HStack {
                            Text(ctx.era.label(year)).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                            Spacer()
                            Text(String(year)).font(theme.type.footnote.monospacedDigit())
                                .foregroundStyle(theme.color.textSecondary)
                        }.frame(minHeight: PoetLayout.minHitTarget)
                    }
                } header: { ListSectionTitle("年份") }
                .listRowBackground(theme.color.surface)
            }
            if !results.places.isEmpty {
                Section {
                    ForEach(results.places) { station in
                        NavigationLink { StationDetailView(ctx: ctx, station: station) } label: {
                            VStack(alignment: .leading, spacing: theme.space.xs) {
                                Text(station.displayName).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                                Text(ctx.era.label(station.year)).font(theme.type.footnote)
                                    .foregroundStyle(theme.color.textSecondary)
                            }.frame(minHeight: Self.rowMinHeight)
                        }
                    }
                } header: { ListSectionTitle("地点 · \(results.places.count)") }
                .listRowBackground(theme.color.surface)
            }
            if !results.people.isEmpty {
                Section {
                    ForEach(results.people) { person in
                        NavigationLink { AssociateDetailView(ctx: ctx, associate: person) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: theme.space.xs) {
                                    Text(person.name).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                                    if let courtesy = person.courtesyName {
                                        Text("字\(courtesy)").font(theme.type.footnote)
                                            .foregroundStyle(theme.color.textSecondary)
                                    }
                                }
                                Spacer()
                                Text("提及 \(person.weight) 次").font(theme.type.footnote)
                                    .foregroundStyle(theme.color.textSecondary)
                            }.frame(minHeight: Self.rowMinHeight)
                        }
                    }
                } header: { ListSectionTitle("人物 · \(results.people.count)") }
                .listRowBackground(theme.color.surface)
            }
            if !results.poems.isEmpty {
                Section {
                    ForEach(results.poems) { poem in
                        NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                            PoemRow(poem: poem, showsDisclosure: false, displayTitle: ctx.workTitle(poem))
                        }
                    }
                } header: { ListSectionTitle("\(failed ? "离线代表作" : "作品") · \(results.poems.count)") }
                footer: {
                    if !failed && results.poems.count == 40 {
                        Text("显示前 40 篇，输入更完整的标题或诗句可缩小范围。")
                            .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                    }
                }
                .listRowBackground(theme.color.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden).poetReadableWidth().foregroundStyle(theme.color.textPrimary)
    }

    @ViewBuilder private func yearDestination(_ year: Int) -> some View {
        if ctx.hasChronicleData {
            ChronicleEventsView(ctx: ctx, year: year)
        } else if let epoch = ctx.lifeEpochs.first(where: { $0.contains(year) }) {
            EpochDetailView(ctx: ctx, epoch: epoch)
        } else {
            ContentUnavailableView("这一年的资料尚未收录", systemImage: "calendar")
        }
    }

    private func search() async {
        let requestID = UUID()
        searchRequestID = requestID
        let requested = term
        let local = ctx.store.localSearch(requested)
        results = SearchResults(poems: ctx.featuredPoems(matching: requested),
                                places: local.places, people: local.people, year: local.year)
        failed = false
        guard !requested.isEmpty else { searching = false; return }
        searching = true
        defer {
            if searchRequestID == requestID { searching = false }
        }
        do {
            try await Task.sleep(for: .milliseconds(280))
            let fetched = try await ctx.store.search(requested)
            guard !Task.isCancelled, requested == term, searchRequestID == requestID else { return }
            results = SearchResults(poems: Array(ctx.combiningFeatured(fetched.poems, query: requested).prefix(40)),
                                    places: fetched.places, people: fetched.people, year: fetched.year)
        } catch {
            guard !Task.isCancelled, requested == term, searchRequestID == requestID else { return }
            failed = true
        }
    }
}
