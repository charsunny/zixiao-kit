import SwiftUI

/// A persistent catalogue beside the reading surface in wide windows. In a
/// compact window, the system supplies the back path to the same catalogue.
struct CorpusView: View {
    let ctx: CompositionContext
    @State private var selection: Destination? = .featured
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var preferredColumn: NavigationSplitViewColumn = .detail
    @State private var searchPresented = false
    @State private var searchQuery = ""
    @State private var savedSearchQuery = ""
    @FocusState private var searchFocused: Bool
    @State private var detailPath = NavigationPath()

    private enum Destination: Hashable {
        case featured
        case genre(String)
        case poem(Poem)
        case collection(ReadingCollection)
        case art(String)
        case search
    }

    private var title: String { ctx.composition.placement(.corpus)?.label ?? "作品" }

    private var catalogueSelection: Binding<Destination?> {
        Binding(get: { selection }, set: { next in
            // Snapshot before UIKit dismisses search as the catalogue changes;
            // dismissal may clear the search controller's bound text.
            if selection == .search && next != .search {
                savedSearchQuery = searchQuery
                searchFocused = false
                searchPresented = false
            }
            if selection != .search && next == .search { searchQuery = savedSearchQuery }
            selection = next
        })
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $preferredColumn) {
            List(selection: catalogueSelection) {
                Section {
                    NavigationLink(value: Destination.featured) {
                        Label("精选与共读", systemImage: "book")
                    }
                    NavigationLink(value: Destination.search) {
                        Label("搜索全部作品", systemImage: "magnifyingglass")
                    }
                }
                ForEach(ctx.literaryGenres) { genre in
                    Section(genre.label) {
                        NavigationLink(value: Destination.genre(genre.id)) {
                            LabeledContent("全部\(genre.label)", value: genre.count.map { String($0) } ?? "浏览")
                        }
                        ForEach(ctx.guide?.featured.filter { $0.form == genre.id } ?? []) { feature in
                            if let poem = ctx.guide?.poem(feature.id) {
                                NavigationLink(value: Destination.poem(poem)) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(feature.title).font(.headline)
                                        Text(poem.firstLine).font(.subheadline).foregroundStyle(.secondary)
                                    }.padding(.vertical, 6)
                                }
                            }
                        }
                    }
                }
                if let collections = ctx.composition.editorial?.collections, !collections.isEmpty {
                    Section("按主题读") {
                        ForEach(collections) { collection in
                            NavigationLink(value: Destination.collection(collection)) {
                                Text(collection.title).padding(.vertical, 5)
                            }
                        }
                    }
                }
                if !ctx.artworks.isEmpty {
                    Section("书画") {
                        ForEach(["书法", "绘画"].filter { kind in ctx.artworks.contains { $0.kind == kind } }, id: \.self) { kind in
                            NavigationLink(value: Destination.art(kind)) { Text(kind) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("\(title)目录")
            .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 390)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: activateSearch) {
                        Label("搜索作品", systemImage: "magnifyingglass")
                    }
                }
            }
        } detail: {
            NavigationStack(path: $detailPath) { destination }
                .id(selection)
        }
        // The split view survives detail-stack replacement, so its search
        // controller can retain focus while a result reader returns to search.
        .searchable(text: $searchQuery, isPresented: $searchPresented,
                    placement: .toolbar, prompt: "搜索标题、诗句或书画")
        .modifier(WorkspaceSearchFocus(focus: $searchFocused))
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(\.corpusSearchAction, activateSearch)
        .background {
            NativeSearchCommand(action: activateSearch).frame(width: 0, height: 0)
        }
        .onChange(of: selection) { _, _ in detailPath = NavigationPath() }
        .onChange(of: searchPresented) { _, presented in
            if presented && (selection != .search || !detailPath.isEmpty) { showSearchResults() }
        }
    }

    private func showSearchResults() {
        selection = .search
        preferredColumn = .detail
        detailPath = NavigationPath()
    }

    private func activateSearch() {
        let query = selection == .search ? searchQuery : savedSearchQuery
        searchFocused = false
        searchPresented = false
        showSearchResults()
        // Native search dismissal can clear its visible field while retaining
        // the bound text. Reapply the query and explicitly restore input focus.
        searchQuery = ""
        Task { @MainActor in
            await Task.yield()
            searchQuery = query
            searchPresented = true
            searchFocused = true
        }
    }

    @ViewBuilder private var destination: some View {
        switch selection {
        case .featured, nil:
            CorpusShelfView(ctx: ctx)
        case .genre(let id):
            if let genre = ctx.literaryGenres.first(where: { $0.id == id }) {
                PoemListView(ctx: ctx, genre: genre, usesWorkspaceSearch: true).id(id)
            }
        case .poem(let poem):
            PoemDetailView(ctx: ctx, poem: poem).id(poem.id)
        case .collection(let collection):
            ReadingCollectionView(ctx: ctx, collection: collection).id(collection.id)
        case .art(let kind):
            ArtworkGalleryView(ctx: ctx, initialKind: kind).id(kind)
        case .search:
            CorpusDirectoryView(ctx: ctx, searchPresented: $searchPresented, query: $searchQuery,
                                usesWorkspaceSearch: true)
        }
    }
}

private struct CorpusSearchActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var corpusSearchAction: (() -> Void)? {
        get { self[CorpusSearchActionKey.self] }
        set { self[CorpusSearchActionKey.self] = newValue }
    }
}

/// A scene command stays registered when the focused navigation column changes.
/// The active workspace supplies its own action, preserving per-window state.
public struct PoetReadingCommands: Commands {
    @FocusedValue(\.corpusSearchAction) private var search

    public init() {}

    public var body: some Commands {
        CommandMenu("浏览") {
            Button("搜索作品") { search?() }
                .disabled(search == nil)
        }
    }
}

private struct WorkspaceSearchFocus: ViewModifier {
    let focus: FocusState<Bool>.Binding
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.searchFocused(focus)
        } else {
            content
        }
    }
}
