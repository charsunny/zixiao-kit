import SwiftUI
import SwiftPieces
import ZixiaoDesign

/// Full inventory and search live one level below the curated shelves.
struct CorpusDirectoryView: View {
    let ctx: CompositionContext
    private let externalSearchPresented: Binding<Bool>?
    @State private var localSearchPresented = false
    private let externalQuery: Binding<String>?
    private let usesWorkspaceSearch: Bool
    @State private var localQuery = ""
    @State private var results: [Poem] = []
    @State private var searching = false
    @State private var failed = false
    @Environment(\.zxTheme) private var theme
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var artResults: [Artwork] { ctx.artworks.filter { $0.matches(term) } }
    private enum SearchResult: Hashable {
        case poem(Poem)
        case artwork(String)
    }

    init(ctx: CompositionContext, searchPresented: Binding<Bool>? = nil, query: Binding<String>? = nil,
         usesWorkspaceSearch: Bool = false) {
        self.ctx = ctx
        self.externalSearchPresented = searchPresented
        self.externalQuery = query
        self.usesWorkspaceSearch = usesWorkspaceSearch
    }

    private var searchPresentation: Binding<Bool> { externalSearchPresented ?? $localSearchPresented }
    private var queryBinding: Binding<String> { externalQuery ?? $localQuery }
    private var query: String { queryBinding.wrappedValue }
    var body: some View {
        if usesWorkspaceSearch {
            directory
        } else {
            directory.searchable(text: queryBinding, isPresented: searchPresentation,
                                 placement: .navigationBarDrawer(displayMode: .always),
                                 prompt: "搜索标题、诗句或书画")
        }
    }

    private var directory: some View {
        List {
            if term.isEmpty {
                Section {
                    ForEach(ctx.literaryGenres) { genre in
                        NavigationLink { PoemCatalogView(ctx: ctx, genre: genre, usesWorkspaceSearch: usesWorkspaceSearch) } label: {
                            LabeledContent(genre.label, value: genre.count.map { "收录 \($0) \(genre.unit)" } ?? "浏览")
                                .font(theme.type.body)
                                .frame(minHeight: PoetLayout.minHitTarget)
                        }
                    }
                } header: { ListSectionTitle("诗文目录") }
                .listRowBackground(theme.color.surface)
                if !ctx.artworks.isEmpty {
                    Section {
                        ForEach(["书法", "绘画"], id: \.self) { kind in
                            NavigationLink { ArtworkGalleryView(ctx: ctx, initialKind: kind) } label: {
                                LabeledContent(kind, value: "\(ctx.artworks.filter { $0.kind == kind }.count) 件")
                                    .font(theme.type.body)
                            }
                        }
                    } header: { ListSectionTitle("书画目录") }
                    .listRowBackground(theme.color.surface)
                }
                if let collections = ctx.composition.editorial?.collections, !collections.isEmpty {
                    Section {
                        ForEach(collections) { collection in
                            NavigationLink { ReadingCollectionView(ctx: ctx, collection: collection) } label: {
                                VStack(alignment: .leading, spacing: theme.space.xs) {
                                    Text(collection.title).font(theme.type.headline)
                                        .foregroundStyle(theme.color.textPrimary)
                                    Text(collection.subtitle).font(theme.type.subhead)
                                        .foregroundStyle(theme.color.textSecondary)
                                }.padding(.vertical, theme.space.xs)
                            }
                        }
                    } header: { ListSectionTitle("按主题读") }
                    .listRowBackground(theme.color.surface)
                }
            } else {
                if searching {
                    ProgressView {
                        Text("正在查找作品…").font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                    }.listRowBackground(theme.color.surface)
                }
                if failed {
                    Section {
                        Button("重新搜索全部作品") { Task { await search() } }.font(theme.type.body)
                    } footer: {
                        Text("网络暂不可用，以下为已收录的离线代表作与书画资料。")
                            .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                    }
                    .listRowBackground(theme.color.surface)
                }
                if !results.isEmpty {
                    Section {
                        ForEach(results) { poem in
                            NavigationLink(value: SearchResult.poem(poem)) {
                                PoemRow(poem: poem, showsDisclosure: false, displayTitle: ctx.workTitle(poem))
                            }
                        }
                    } header: {
                        ListSectionTitle(failed ? "离线代表作" : "诗文 · \(results.count) 篇\(results.count == 200 ? "（最多显示 200 篇）" : "")")
                    }
                    .listRowBackground(theme.color.surface)
                }
                if !artResults.isEmpty {
                    Section {
                        ForEach(artResults) { art in
                            NavigationLink(value: SearchResult.artwork(art.id)) {
                                VStack(alignment: .leading, spacing: theme.space.xs) {
                                    Text(art.title).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                                    Text("\(art.kind) · \(art.collection)").font(theme.type.caption)
                                        .foregroundStyle(theme.color.textSecondary)
                                }.padding(.vertical, theme.space.xs)
                            }
                        }
                    } header: { ListSectionTitle("书画") }
                    .listRowBackground(theme.color.surface)
                }
            }
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden).poetReadableWidth(680)
        .background(theme.paper()).tint(theme.color.accent)
        .zxNavigationTitle("全部作品", role: .secondary)
        .navigationDestination(for: SearchResult.self) { result in
            switch result {
            case .poem(let poem):
                PoemDetailView(ctx: ctx, poem: poem)
                    .onAppear { searchPresentation.wrappedValue = false }
            case .artwork(let id):
                if let art = ctx.artworks.first(where: { $0.id == id }) {
                    ArtworkDetailView(ctx: ctx, artwork: art)
                        .onAppear { searchPresentation.wrappedValue = false }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay { if !term.isEmpty && !searching && !failed && results.isEmpty && artResults.isEmpty { ContentUnavailableView.search(text: term) } }
        .task(id: term) { await search() }
    }
    private func search() async {
        let requested = term
        results = []; failed = false
        guard !requested.isEmpty else { searching = false; return }
        searching = true
        do {
            try await Task.sleep(for: .milliseconds(280))
            let fetched = try await ctx.store.searchPoems(query: requested)
            guard !Task.isCancelled, requested == term else { return }
            results = ctx.combiningFeatured(fetched, query: requested)
        } catch {
            guard !Task.isCancelled, requested == term else { return }
            failed = true
            results = ctx.featuredPoems(matching: requested)
        }
        searching = false
    }
}

/// 作品行。词的标题只有词牌，一位词人常有几十首同调之作 ——
/// 列表里必须带首句，否则根本认不出是哪一首。
struct PoemRow: View {
    let poem: Poem
    var showsDisclosure = true
    var displayTitle: String? = nil
    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 作品行的最小高度: 两行字 + 上下留白, 也是点按区。
    private static let minRowHeight: CGFloat = 52

    init(poem: Poem, showsDisclosure: Bool = true, displayTitle: String? = nil) {
        self.poem = poem
        self.showsDisclosure = showsDisclosure
        self.displayTitle = displayTitle
    }

    var body: some View {
        HStack(spacing: theme.space.md) {
            VStack(alignment: .leading, spacing: theme.space.xs) {
                Text(displayTitle ?? poem.title).font(theme.type.headline)
                    .foregroundStyle(theme.color.textPrimary)
                Text(poem.firstLine)
                    .font(theme.type.callout)
                    .foregroundStyle(theme.color.textSecondary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            }
            Spacer(minLength: theme.space.sm)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(theme.type.caption.weight(.semibold)).foregroundStyle(theme.color.accent)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Self.minRowHeight)
        .contentShape(Rectangle())
    }
}

struct PoemListView: View {
    let ctx: CompositionContext
    let genre: Genre
    /// 非空时是大类目录点进来的: 只列这一大类, 有多种细体裁时顶上给一条筛选条。
    var group: PoetGenreIndex.Group? = nil
    var usesWorkspaceSearch = false
    @State private var poems: [Poem] = []
    @State private var searchResults: [Poem] = []
    @State private var query = ""
    @State private var didLoad = false
    @State private var hasMore = true
    @State private var loadingPage = false
    @State private var searching = false
    @State private var pageFailed = false
    @State private var searchFailed = false
    /// 细体裁筛选条的选中项 (单选, 「全部」= 不筛)。
    @State private var fineSelection: Set<String> = [Self.allFine]
    /// 已经载入的筛选键; 换筛选项时清空重载, 返回本页时不重载。
    @State private var loadedKey: String?
    /// 每次清空重载加一: 旧筛选项还在路上的那一页回来时据此丢弃。
    @State private var generation = 0
    @Environment(\.zxTheme) private var theme
    private static let pageSize = 100
    private static let allFine = "全部"
    private var unit: String { genre.unit }
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var shown: [Poem] { term.isEmpty ? poems : searchResults }
    private var fineGenre: String? { fineSelection.first.flatMap { $0 == Self.allFine ? nil : $0 } }
    private var filterKey: String { fineGenre ?? "" }
    private var total: Int? {
        guard let group else { return genre.count }
        return fineGenre.flatMap { name in group.genres.first { $0.label == name }?.count } ?? group.count
    }
    private var subtitle: String {
        if !term.isEmpty {
            if searching { return "正在检索…" }
            if searchFailed { return "检索暂不可用" }
            return "找到 \(searchResults.count) \(unit)" + (searchResults.count == 200 ? " · 最多显示 200 \(unit)" : "")
        }
        return total.map { "共 \($0) \(unit) · 已载入 \(poems.count) \(unit)" } ?? "已载入 \(poems.count) \(unit)"
    }
    var body: some View {
        if usesWorkspaceSearch {
            poemList
        } else {
            poemList.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                                prompt: group.map { "在\($0.label)中搜索" } ?? "搜索标题或诗句")
        }
    }

    private var poemList: some View {
        List {
            ForEach(shown) { poem in
                NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                    PoemRow(poem: poem, showsDisclosure: false, displayTitle: ctx.workTitle(poem))
                }
                .listRowBackground(theme.paper()).listRowSeparatorTint(theme.rule)
                .task {
                    guard term.isEmpty, poem.id == poems.last?.id, !pageFailed else { return }
                    await loadNextPage()
                }
            }
            if term.isEmpty && !poems.isEmpty {
                if pageFailed {
                    Button("载入中断，点击重试") { Task { await loadNextPage() } }
                        .font(theme.type.subhead)
                        .frame(maxWidth: .infinity, minHeight: PoetLayout.minHitTarget)
                        .listRowBackground(theme.paper())
                } else if hasMore {
                    LoadingStateView(label: "正在载入更多…")
                        .listRowBackground(theme.paper()).listRowSeparator(.hidden)
                } else {
                    Text("已读到目录末尾").font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                        .frame(maxWidth: .infinity).listRowBackground(theme.paper()).listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).poetReadableWidth()
        .background(theme.paper()).foregroundStyle(theme.color.textPrimary).tint(theme.color.accent)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let group, group.hasFineGenres, term.isEmpty { fineGenreRail(group) }
        }
        .zxNavigationTitle(group?.label ?? genre.label, subtitle: subtitle, role: .secondary)
        .overlay {
            if term.isEmpty {
                if poems.isEmpty && (!didLoad || loadingPage) { LoadingStateView() }
                else if poems.isEmpty && pageFailed { LoadFailureView(retry: loadNextPage) }
                else if poems.isEmpty { EmptyState("暂无作品", systemImage: "book") }
            } else {
                if searching { LoadingStateView(label: "正在检索…") }
                else if searchFailed { LoadFailureView(title: "检索暂不可用", retry: search) }
                else if searchResults.isEmpty { ContentUnavailableView.search(text: term) }
            }
        }
        .task(id: filterKey) {
            guard loadedKey != filterKey else { return }
            if loadedKey != nil { resetPages() }
            loadedKey = filterKey
            await loadNextPage()
        }
        .task(id: term) { await search() }
    }

    /// 细体裁筛选条 (单选)。颜色取主题 token, 篇数附在每项后面。
    private func fineGenreRail(_ group: PoetGenreIndex.Group) -> some View {
        var counts = Dictionary(uniqueKeysWithValues: group.genres.map { ($0.label, $0.count) })
        counts[Self.allFine] = group.count
        return FilterRail(options: [Self.allFine] + group.genres.map(\.label), selection: $fineSelection,
                          counts: counts,
                          style: .init(chip: theme.color.fill, label: theme.color.textPrimary,
                                       secondaryLabel: theme.color.textSecondary, indicator: theme.color.accent,
                                       onIndicator: theme.color.accentOn, chipHeight: 34))
            .padding(.vertical, theme.space.xs)
            .background(theme.paper())
    }

    private func resetPages() {
        generation += 1
        poems = []; hasMore = true; pageFailed = false; loadingPage = false; didLoad = false
    }

    private func search() async {
        let requested = term
        searchResults = []; searchFailed = false
        guard !requested.isEmpty else { searching = false; return }
        searching = true
        do {
            try await Task.sleep(for: .milliseconds(280))
            let fetched = try await ctx.store.searchPoems(form: genre.id, genreGroup: group?.label,
                                                          query: requested, limit: 200)
            guard !Task.isCancelled, requested == term else { return }
            // 编者的代表作不带体裁字段, 只在整体裁的列表里并入。
            searchResults = group == nil ? ctx.combiningFeatured(fetched, query: requested, form: genre.id) : fetched
        } catch {
            guard !Task.isCancelled, requested == term else { return }
            searchFailed = true
        }
        searching = false
    }

    private func loadNextPage() async {
        guard !loadingPage, hasMore else { return }
        let requestGeneration = generation
        loadingPage = true; pageFailed = false
        defer { if requestGeneration == generation { loadingPage = false; didLoad = true } }
        do {
            let page = try await ctx.store.poems(form: genre.id, genreGroup: group?.label, genre: fineGenre,
                                                 limit: Self.pageSize, offset: poems.count)
            guard !Task.isCancelled, requestGeneration == generation else { return }
            let existing = Set(poems.map(\.id))
            poems.append(contentsOf: page.filter { !existing.contains($0.id) })
            hasMore = page.count == Self.pageSize
        } catch {
            if !Task.isCancelled, requestGeneration == generation { pageFailed = true }
        }
    }
}
