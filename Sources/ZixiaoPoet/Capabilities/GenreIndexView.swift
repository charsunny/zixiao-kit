import ZixiaoPoetCore
import SwiftUI
import ZixiaoDesign

extension Genre {
    /// 文的篇目多、体裁杂 (书简 / 制诰 / 题跋 …), 先给大类目录再进列表。诗 / 词 / 赋 照旧直接是平铺列表。
    /// 目录页里还有一道通用规则: 不到两个大类时退回平铺列表 (`PoetGenreIndex.isGrouped`)。
    var browsesByGenreGroup: Bool { id == "wen" }
    /// 量词: 文赋论篇, 诗词论首。
    var unit: String { id == "wen" || id == "fu" ? "篇" : "首" }
}

/// 一个体裁的「全部」入口: 文走大类目录, 其余体裁直接是分页列表。
struct PoemCatalogView: View {
    let ctx: CompositionContext
    let genre: Genre
    var usesWorkspaceSearch = false

    var body: some View {
        if genre.browsesByGenreGroup {
            GenreIndexView(ctx: ctx, genre: genre, usesWorkspaceSearch: usesWorkspaceSearch)
        } else {
            PoemListView(ctx: ctx, genre: genre, usesWorkspaceSearch: usesWorkspaceSearch)
        }
    }
}

/// 大类目录: 每个大类一行「书简 · 1,434 篇」, 点进去是按该大类筛过的分页列表 (内有细体裁筛选条)。
/// 篇数来自 `PoetStore.genreIndex(form:)` (RPC, 缺席时客户端聚合)。目录取不到或不足两类时退回平铺列表。
struct GenreIndexView: View {
    let ctx: CompositionContext
    let genre: Genre
    var usesWorkspaceSearch = false
    @State private var index: PoetGenreIndex?
    @State private var indexFailed = false
    @State private var query = ""
    @State private var searchResults: [Poem] = []
    @State private var searching = false
    @State private var searchFailed = false
    @Environment(\.zxTheme) private var theme
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        if indexFailed || index?.isGrouped == false {
            // 取不到目录也不挡路: 平铺列表自带载入失败与重试。
            PoemListView(ctx: ctx, genre: genre, usesWorkspaceSearch: usesWorkspaceSearch)
        } else if usesWorkspaceSearch {
            directory
        } else {
            directory.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                                 prompt: "搜索标题或文句")
        }
    }

    private var subtitle: String? {
        guard let index else { return nil }
        return "共 \(index.total) \(genre.unit) · \(index.groups.count) 类"
    }

    private var directory: some View {
        List {
            if term.isEmpty {
                if let index { groupSections(index) }
            } else if !searchResults.isEmpty {
                Section {
                    ForEach(searchResults) { poem in
                        NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                            PoemRow(poem: poem, showsDisclosure: false, displayTitle: ctx.workTitle(poem))
                        }
                    }
                } header: {
                    ListSectionTitle("找到 \(searchResults.count) \(genre.unit)"
                                     + (searchResults.count == 200 ? "（最多显示 200 \(genre.unit)）" : ""))
                }
                .listRowBackground(theme.color.surface)
            }
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden).poetReadableWidth(680)
        .background(theme.paper()).tint(theme.color.accent)
        .scrollDismissesKeyboard(.interactively)
        .zxNavigationTitle(genre.label, subtitle: subtitle, role: .secondary)
        .overlay {
            if term.isEmpty {
                if index == nil { LoadingStateView(label: "正在整理目录…") }
            } else if searching { LoadingStateView(label: "正在检索…") }
            else if searchFailed { LoadFailureView(title: "检索暂不可用", retry: search) }
            else if searchResults.isEmpty { ContentUnavailableView.search(text: term) }
        }
        .task { if index == nil { await loadIndex() } }
        .task(id: term) { await search() }
    }

    @ViewBuilder private func groupSections(_ index: PoetGenreIndex) -> some View {
        let named = index.groups.filter { !$0.isOther }
        let other = index.groups.filter(\.isOther)
        Section {
            ForEach(named) { group in groupLink(group) }
        } header: { ListSectionTitle("按体裁") }
        .listRowBackground(theme.color.surface)
        if !other.isEmpty {
            Section {
                ForEach(other) { group in groupLink(group) }
            } footer: {
                Text("未标注体裁、或难归入上面各类的篇目。")
                    .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
            }
            .listRowBackground(theme.color.surface)
        }
    }

    private func groupLink(_ group: PoetGenreIndex.Group) -> some View {
        NavigationLink {
            PoemListView(ctx: ctx, genre: genre, group: group, usesWorkspaceSearch: usesWorkspaceSearch)
        } label: {
            LabeledContent(group.label, value: "\(group.count) \(genre.unit)")
                .font(theme.type.body)
                .frame(minHeight: PoetLayout.minHitTarget)
        }
    }

    private func loadIndex() async {
        do {
            let fetched = try await ctx.store.genreIndex(form: genre.id)
            guard !Task.isCancelled else { return }
            index = fetched
        } catch {
            if !Task.isCancelled { indexFailed = true }
        }
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
}
