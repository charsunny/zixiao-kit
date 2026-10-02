import SwiftUI
import ZixiaoDesign

/// 诗文 Tab 的工作区。
///
/// 根壳 (`ZXTabShell`) 给每个 Tab 一个 NavigationStack; NavigationSplitView 放进 NavigationStack
/// 里不渲染 (iOS 27 模拟器实测整页空白), 所以这里不用分栏容器:
/// - 窄屏 (iPhone): 根页 (`CorpusRootView`: 选读 → 按年读 → 全集 → 墨迹); 右上角「搜索」推入全部作品目录并直接进入检索。
/// - 宽屏 (iPad): 左侧目录 (同样四节) + 右侧内容并排; 从内容里再推的页面进壳的栈, 盖住两栏, 返回即回到两栏。
struct CorpusView: View {
    let ctx: CompositionContext
    @State private var selection: Destination = .overview
    @State private var showingSearch = false
    @State private var searchPresented = false
    @State private var searchQuery = ""
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.zxTheme) private var theme
    /// 宽屏目录栏的宽度 (固有尺寸, 与原分栏侧栏的理想宽度相同)。
    private static let sidebarWidth: CGFloat = 310

    private enum Destination: Hashable {
        case overview
        case selection(String)
        case years
        case genre(String)
        case art(String)
        case search
    }

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
                CorpusRootView(ctx: ctx)
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

    /// 宽屏左栏: 总览 / 搜索, 然后与根页同序的四节 —— 选读 (各合集) / 按年读 / 全集 (各体裁) / 墨迹 (书法 · 绘画)。
    private var catalogue: some View {
        List {
            Section {
                row(.overview) { Label("诗文总览", systemImage: "book") }
                row(.search) { Label("搜索全部作品", systemImage: "magnifyingglass") }
            }
            let selections = ctx.corpusSelections
            if !selections.isEmpty {
                Section {
                    ForEach(selections) { item in
                        row(.selection(item.id)) {
                            VStack(alignment: .leading, spacing: theme.space.xxs) {
                                Text(item.title).font(theme.type.body)
                                Text(item.thesis).font(theme.type.footnote)
                                    .foregroundStyle(theme.color.textSecondary).lineLimit(2)
                            }.padding(.vertical, theme.space.xs)
                        }
                    }
                } header: { ListSectionTitle("选读") }
            }
            Section {
                row(.years) { Label("年份轴", systemImage: "calendar") }
            } header: { ListSectionTitle("按年读") }
            if !ctx.literaryGenres.isEmpty {
                Section {
                    ForEach(ctx.literaryGenres) { genre in
                        row(.genre(genre.id)) {
                            LabeledContent(genre.label, value: genre.count.map { $0.formatted(.number) } ?? "浏览")
                        }
                    }
                } header: { ListSectionTitle("全集") }
            }
            if !ctx.artworks.isEmpty {
                Section {
                    ForEach(["书法", "绘画"].filter { kind in ctx.artworks.contains { $0.kind == kind } }, id: \.self) { kind in
                        row(.art(kind)) {
                            LabeledContent(kind, value: "\(ctx.artworks.filter { $0.kind == kind }.count) 件")
                        }
                    }
                } header: { ListSectionTitle("墨迹") }
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
        case .overview:
            AnyView(CorpusRootView(ctx: ctx))
        case .selection(let id):
            if let item = ctx.corpusSelections.first(where: { $0.id == id }) {
                AnyView(CollectionReadingView(ctx: ctx, selection: item))
            }
        case .years:
            AnyView(CorpusYearPage(ctx: ctx))
        case .genre(let id):
            if let genre = ctx.literaryGenres.first(where: { $0.id == id }) {
                AnyView(PoemCatalogView(ctx: ctx, genre: genre))
            }
        case .art(let kind):
            AnyView(ArtworkGalleryView(ctx: ctx, initialKind: kind))
        case .search:
            AnyView(CorpusDirectoryView(ctx: ctx, searchPresented: $searchPresented, query: $searchQuery))
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
