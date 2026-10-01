import SwiftUI

struct CorpusShelfView: View {
    let ctx: CompositionContext
    @Namespace private var shelf
    @ScaledMetric(relativeTo: .title3) private var coverWidth = 160.0
    @ScaledMetric(relativeTo: .title3) private var coverHeight = 248.0
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 34) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("从名篇读起").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        Text(ctx.composition.editorial?.corpusIntroduction ?? "从代表作与主题开始，慢慢读进这位诗人的作品。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.horizontal, 20)
                    ForEach(ctx.literaryGenres) { genre in literaryShelf(genre) }
                    ForEach(["书法", "绘画"], id: \.self) { kind in
                        let works = ctx.artworks.filter { $0.kind == kind }
                        if !works.isEmpty { artShelf(kind, works: works) }
                    }
                }.padding(.vertical, 22).poetReadableWidth(1000)
            }
            .background(ctx.theme.paper)
            .navigationTitle(ctx.composition.placement(.corpus)?.label ?? "作品").toolbarTitleDisplayMode(.inlineLarge)
    }
    private func literaryShelf(_ genre: Genre) -> some View {
        let features = ctx.guide?.featured.filter { $0.form == genre.id } ?? []
        return VStack(alignment: .leading, spacing: 16) {
            NativeSectionHeader(title: genre.label) {
                NavigationLink { PoemListView(ctx: ctx, genre: genre, usesWorkspaceSearch: true) } label: { HStack(spacing: 5) { Text("全部"); Image(systemName: "chevron.right").font(.caption) }.font(.subheadline) }
                    .accessibilityLabel("全部\(genre.label)，可搜索")
            }.padding(.horizontal, 20)
            if typeSize.isAccessibilitySize {
                VStack(spacing: 22) { ForEach(features) { feature in featureLink(feature, genre: genre, expanded: true) } }.padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 22) {
                        ForEach(features) { feature in featureLink(feature, genre: genre, expanded: false).frame(width: coverWidth) }
                    }.scrollTargetLayout().padding(.vertical, 5)
                }.contentMargins(.horizontal, 20, for: .scrollContent).scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned)
            }
        }
    }
    @ViewBuilder private func featureLink(_ feature: FeaturedWork, genre: Genre, expanded: Bool) -> some View {
        if let poem = ctx.guide?.poem(feature.id) {
            NavigationLink {
                PoemDetailView(ctx: ctx, poem: poem).readingTransition(poem.id, in: shelf)
            } label: {
                VStack(alignment: .leading, spacing: 13) {
                    ReadingCover(title: feature.title, author: ctx.composition.poet.name, genre: genre, height: expanded ? nil : coverHeight)
                        .readingTransitionSource(poem.id, in: shelf)
                    Text(feature.note).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityElement(children: .combine)
        }
    }
    private func artShelf(_ kind: String, works: [Artwork]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            NativeSectionHeader(title: kind) {
                NavigationLink { ArtworkGalleryView(ctx: ctx, initialKind: kind) } label: { HStack(spacing: 5) { Text("全部"); Image(systemName: "chevron.right").font(.caption) }.font(.subheadline) }
                    .accessibilityLabel("全部\(kind)")
            }.padding(.horizontal, 20)
            if works.count == 1 || typeSize.isAccessibilitySize {
                ForEach(works) { work in
                    NavigationLink { ArtworkDetailView(ctx: ctx, artwork: work) } label: {
                        ArtworkPreview(artwork: work, theme: ctx.theme)
                    }.buttonStyle(.plain).padding(.horizontal, 20)
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(works) { work in
                            NavigationLink { ArtworkDetailView(ctx: ctx, artwork: work) } label: {
                                ArtworkPreview(artwork: work, theme: ctx.theme)
                            }.buttonStyle(.plain).frame(width: 280)
                        }
                    }.scrollTargetLayout()
                }.contentMargins(.horizontal, 20, for: .scrollContent).scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned)
            }
        }
    }
}

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
                Section("诗文目录") {
                    ForEach(ctx.literaryGenres) { genre in
                        NavigationLink { PoemListView(ctx: ctx, genre: genre, usesWorkspaceSearch: usesWorkspaceSearch) } label: {
                            LabeledContent(genre.label, value: genre.count.map { "收录 \($0) \(genre.id == "wen" || genre.id == "fu" ? "篇" : "首")" } ?? "浏览")
                                .frame(minHeight: 40)
                        }
                    }
                }
                if !ctx.artworks.isEmpty {
                    Section("书画目录") {
                        ForEach(["书法", "绘画"], id: \.self) { kind in
                            NavigationLink { ArtworkGalleryView(ctx: ctx, initialKind: kind) } label: {
                                LabeledContent(kind, value: "\(ctx.artworks.filter { $0.kind == kind }.count) 件")
                            }
                        }
                    }
                }
                if let collections = ctx.composition.editorial?.collections, !collections.isEmpty {
                    Section("按主题读") {
                        ForEach(collections) { collection in
                            NavigationLink { ReadingCollectionView(ctx: ctx, collection: collection) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(collection.title).font(.headline)
                                    Text(collection.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                }.padding(.vertical, 6)
                            }
                        }
                    }
                }
            } else {
                if searching { ProgressView("正在查找作品…") }
                if failed {
                    Section {
                        Button("重新搜索全部作品") { Task { await search() } }
                    } footer: { Text("网络暂不可用，以下为已收录的离线代表作与书画资料。") }
                }
                if !results.isEmpty {
                    Section(failed ? "离线代表作" : "诗文 · \(results.count) 篇\(results.count == 200 ? "（最多显示 200 篇）" : "")") {
                        ForEach(results) { poem in
                            NavigationLink(value: SearchResult.poem(poem)) {
                                PoemRow(poem: poem, theme: ctx.theme, showsDisclosure: false, displayTitle: ctx.workTitle(poem))
                            }
                        }
                    }
                }
                if !artResults.isEmpty {
                    Section("书画") {
                        ForEach(artResults) { art in
                            NavigationLink(value: SearchResult.artwork(art.id)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(art.title).font(.headline)
                                    Text("\(art.kind) · \(art.collection)").font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 5)
                            }
                        }
                    }
                }
            }
        }.listStyle(.insetGrouped).scrollContentBackground(.hidden).poetReadableWidth(680).background(ctx.theme.paper)
            .navigationTitle("全部作品").toolbarTitleDisplayMode(.inlineLarge)
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
    let theme: Theme
    var showsDisclosure = true
    var displayTitle: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle ?? poem.title).font(PoetFont.entryTitle).foregroundStyle(theme.ink)
                Text(poem.firstLine)
                    .font(PoetFont.callout)
                    .foregroundStyle(theme.secondaryInk)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            }
            Spacer(minLength: 6)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(PoetFont.icon(12)).foregroundStyle(theme.accent)
            }
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

struct PoemListView: View {
    let ctx: CompositionContext
    let genre: Genre
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
    private static let pageSize = 100
    private var unit: String { genre.id == "wen" || genre.id == "fu" ? "篇" : "首" }
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var shown: [Poem] { term.isEmpty ? poems : searchResults }
    private var subtitle: String {
        if !term.isEmpty {
            if searching { return "正在检索…" }
            if searchFailed { return "检索暂不可用" }
            return "找到 \(searchResults.count) \(unit)" + (searchResults.count == 200 ? " · 最多显示 200 \(unit)" : "")
        }
        return genre.count.map { "共 \($0) \(unit) · 已载入 \(poems.count) \(unit)" } ?? "已载入 \(poems.count) \(unit)"
    }
    var body: some View {
        if usesWorkspaceSearch {
            poemList
        } else {
            poemList.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                                prompt: "搜索标题或诗句")
        }
    }

    private var poemList: some View {
        List {
            ForEach(shown) { poem in
                NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                    PoemRow(poem: poem, theme: ctx.theme, showsDisclosure: false, displayTitle: ctx.workTitle(poem))
                }
                .listRowBackground(ctx.theme.paper).listRowSeparatorTint(ctx.theme.rule)
                .task {
                    guard term.isEmpty, poem.id == poems.last?.id, !pageFailed else { return }
                    await loadNextPage()
                }
            }
            if term.isEmpty && !poems.isEmpty {
                if pageFailed {
                    Button("载入中断，点击重试") { Task { await loadNextPage() } }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .listRowBackground(ctx.theme.paper)
                } else if hasMore {
                    ProgressView("正在载入更多…").frame(maxWidth: .infinity)
                        .listRowBackground(ctx.theme.paper).listRowSeparator(.hidden)
                } else {
                    Text("已读到目录末尾").font(PoetFont.meta).foregroundStyle(ctx.theme.secondaryInk)
                        .frame(maxWidth: .infinity).listRowBackground(ctx.theme.paper).listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).poetReadableWidth()
        .background(ctx.theme.paper).foregroundStyle(ctx.theme.ink)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(genre.label).toolbarTitleDisplayMode(.inlineLarge)
        .poetNavigationSubtitle(subtitle)
        .overlay {
            if term.isEmpty {
                if poems.isEmpty && (!didLoad || loadingPage) { LoadingStateView() }
                else if poems.isEmpty && pageFailed { LoadFailureView(retry: loadNextPage) }
                else if poems.isEmpty { ContentUnavailableView("暂无作品", systemImage: "book") }
            } else {
                if searching { LoadingStateView(label: "正在检索…") }
                else if searchFailed { LoadFailureView(title: "检索暂不可用", retry: search) }
                else if searchResults.isEmpty { ContentUnavailableView.search(text: term) }
            }
        }
        .task { if !didLoad { await loadNextPage() } }
        .task(id: term) { await search() }
    }

    private func search() async {
        let requested = term
        searchResults = []; searchFailed = false
        guard !requested.isEmpty else { searching = false; return }
        searching = true
        do {
            try await Task.sleep(for: .milliseconds(280))
            let fetched = try await ctx.store.searchPoems(form: genre.id, query: requested, limit: 200)
            guard !Task.isCancelled, requested == term else { return }
            searchResults = ctx.combiningFeatured(fetched, query: requested, form: genre.id)
        } catch {
            guard !Task.isCancelled, requested == term else { return }
            searchFailed = true
        }
        searching = false
    }

    private func loadNextPage() async {
        guard !loadingPage, hasMore else { return }
        loadingPage = true; pageFailed = false
        defer { loadingPage = false; didLoad = true }
        do {
            let page = try await ctx.store.poems(form: genre.id, limit: Self.pageSize, offset: poems.count)
            guard !Task.isCancelled else { return }
            let existing = Set(poems.map(\.id))
            poems.append(contentsOf: page.filter { !existing.contains($0.id) })
            hasMore = page.count == Self.pageSize
        } catch {
            if !Task.isCancelled { pageFailed = true }
        }
    }
}
