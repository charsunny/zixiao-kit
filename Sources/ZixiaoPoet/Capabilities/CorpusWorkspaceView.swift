import SwiftUI
import ZixiaoDesign

/// 作品 Tab 的工作区。
///
/// 根壳 (`ZXTabShell`) 给每个 Tab 一个 NavigationStack; NavigationSplitView 放进 NavigationStack
/// 里不渲染 (iOS 27 模拟器实测整页空白), 所以这里不用分栏容器:
/// - 窄屏 (iPhone): 书架就是根页; 右上角「搜索」推入全部作品目录并直接进入检索。
/// - 宽屏 (iPad): 左侧目录 + 右侧内容并排; 从内容里再推的页面进壳的栈, 盖住两栏, 返回即回到两栏。
struct CorpusView: View {
    let ctx: CompositionContext
    @State private var selection: Destination = .featured
    @State private var showingSearch = false
    @State private var searchPresented = false
    @State private var searchQuery = ""
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.zxTheme) private var theme
    /// 宽屏目录栏的宽度 (固有尺寸, 与原分栏侧栏的理想宽度相同)。
    private static let sidebarWidth: CGFloat = 310

    private enum Destination: Hashable {
        case featured
        case genre(String)
        case poem(Poem)
        case collection(ReadingCollection)
        case art(String)
        case search
    }

    private var title: String { ctx.composition.placement(.corpus)?.label ?? "作品" }

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    catalogue.frame(width: Self.sidebarWidth)
                    InkDivider(.vertical)
                    destination.id(selection).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(theme.paper())
            } else {
                CorpusShelfView(ctx: ctx)
                    .navigationDestination(isPresented: $showingSearch) {
                        CorpusDirectoryView(ctx: ctx, searchPresented: $searchPresented, query: $searchQuery)
                    }
            }
        }
        .toolbar {
            if sizeClass != .regular || selection != .search {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: activateSearch) {
                        Label("搜索作品", systemImage: "magnifyingglass")
                    }
                }
            }
        }
        // ⌘F: 场景级命令 `PoetReadingCommands` (三个 App 都已注册) 经 focusedSceneValue 找到这里。
        .focusedSceneValue(\.corpusSearchAction, activateSearch)
        .tint(theme.color.accent)
    }

    private func activateSearch() {
        searchPresented = false
        if sizeClass == .regular { selection = .search } else { showingSearch = true }
        // 推入 / 切换完成后再展开搜索框, 否则系统会在转场中把它收起。
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            searchPresented = true
        }
    }

    /// 宽屏左栏: 精选 / 搜索 / 各体裁 (全部 + 精选篇目) / 主题共读 / 书画。
    private var catalogue: some View {
        List {
            Section {
                row(.featured) { Label("精选与共读", systemImage: "book") }
                row(.search) { Label("搜索全部作品", systemImage: "magnifyingglass") }
            }
            ForEach(ctx.literaryGenres) { genre in
                Section {
                    row(.genre(genre.id)) {
                        LabeledContent("全部\(genre.label)", value: genre.count.map { String($0) } ?? "浏览")
                    }
                    ForEach(ctx.guide?.featured.filter { $0.form == genre.id } ?? []) { feature in
                        if let poem = ctx.guide?.poem(feature.id) {
                            row(.poem(poem)) {
                                VStack(alignment: .leading, spacing: theme.space.xs) {
                                    Text(feature.title).font(theme.type.headline)
                                    Text(poem.firstLine).font(theme.type.subhead)
                                        .foregroundStyle(theme.color.textSecondary)
                                }.padding(.vertical, theme.space.xs)
                            }
                        }
                    }
                } header: { ListSectionTitle(genre.label) }
            }
            if let collections = ctx.composition.editorial?.collections, !collections.isEmpty {
                Section {
                    ForEach(collections) { collection in
                        row(.collection(collection)) { Text(collection.title) }
                    }
                } header: { ListSectionTitle("按主题读") }
            }
            if !ctx.artworks.isEmpty {
                Section {
                    ForEach(["书法", "绘画"].filter { kind in ctx.artworks.contains { $0.kind == kind } }, id: \.self) { kind in
                        row(.art(kind)) { Text(kind) }
                    }
                } header: { ListSectionTitle("书画") }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.paper())
    }

    /// 目录里的一行: 点选切换右栏, 选中行用强调色的淡底标出。
    private func row<Label: View>(_ target: Destination, @ViewBuilder label: () -> Label) -> some View {
        Button { selection = target } label: {
            label()
                .font(theme.type.body)
                .foregroundStyle(selection == target ? theme.color.accent : theme.color.textPrimary)
                .frame(maxWidth: .infinity, minHeight: PoetLayout.minHitTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selection == target ? theme.color.fill : nil)
        .accessibilityAddTraits(selection == target ? .isSelected : [])
    }

    @ViewBuilder private var destination: some View {
        switch selection {
        case .featured:
            CorpusShelfView(ctx: ctx)
        case .genre(let id):
            if let genre = ctx.literaryGenres.first(where: { $0.id == id }) {
                PoemListView(ctx: ctx, genre: genre)
            }
        case .poem(let poem):
            PoemDetailView(ctx: ctx, poem: poem)
        case .collection(let collection):
            ReadingCollectionView(ctx: ctx, collection: collection)
        case .art(let kind):
            ArtworkGalleryView(ctx: ctx, initialKind: kind)
        case .search:
            CorpusDirectoryView(ctx: ctx, searchPresented: $searchPresented, query: $searchQuery)
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
                .keyboardShortcut("f", modifiers: .command)
                .disabled(search == nil)
        }
    }
}
