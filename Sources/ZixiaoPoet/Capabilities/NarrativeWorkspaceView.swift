import ZixiaoPoetCore
import SwiftUI
import ZixiaoDesign

/// 叙事类 Tab (生平 / 远游 / 时局, 名字取编成) 的工作区: 目录 + 小传、篇章、镜头 (编年 / 行迹 / 交游)、资料。
///
/// 根壳 (`ZXTabShell`) 给每个 Tab 一个 NavigationStack; NavigationSplitView 放进 NavigationStack
/// 里不渲染 (iOS 27 模拟器实测整页空白), 所以这里与作品 Tab (`CorpusView`) 同法, 不用分栏容器:
/// - 窄屏 (iPhone): 目录就是根页, 点一行推入对应页面 (与原分栏在窄屏下先显示侧栏一致)。
///   「下一章」「从…读起」替换已推入的那一页, 不往栈里越叠越深 —— 原来详情列也是整列替换。
/// - 宽屏 (iPad): 左侧目录 + 右侧内容并排; 从内容里再推的页面进壳的栈, 盖住两栏, 返回即回到两栏。
/// 两种宽度共用同一个选中项, 分屏切换宽度时停在同一页。没有设备名或方向分支。
struct NarrativeWorkspaceView: View {
    let ctx: CompositionContext
    let capability: CapabilityID
    /// 宽屏右栏显示的页; 窄屏时记住最近打开的那一页。
    @State private var selection: Destination
    /// 窄屏推入的页 (nil = 停在目录)。
    @State private var pushed: Destination?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.zxTheme) private var theme
    /// 宽屏目录栏的宽度 (固有尺寸, 与原分栏侧栏的理想宽度相同)。
    private static let sidebarWidth: CGFloat = 310

    private enum Destination: Hashable {
        case overview
        case chapter(Epoch)
        case lens(Lens.Kind)
        case network
        case sources
    }

    init(ctx: CompositionContext, capability: CapabilityID) {
        self.ctx = ctx
        self.capability = capability
        let initial = Self.debugInitialSelection()
        _selection = State(initialValue: initial ?? .overview)
        _pushed = State(initialValue: initial)
    }

    /// 设计迭代 / 截图用 (与 `PoetAppRoot` 的 `-tab` 同法): `-lens map|chronicle|network|overview`
    /// 直接落到某个镜头 (窄屏推入, 宽屏放在右栏), 省去在模拟器里手点。只在 DEBUG 生效,
    /// 发布包里恒为 nil (窄屏落在目录, 宽屏右栏是小传)。
    private static func debugInitialSelection() -> Destination? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "lens") {
        case "map": return .lens(.map)
        case "chronicle": return .lens(.chronicle)
        case "network": return .network
        case "overview": return .overview
        default: return nil
        }
        #else
        return nil
        #endif
    }

    private var title: String { ctx.composition.placement(capability)?.label ?? ctx.narrativeLabel }
    private var lenses: [Lens] {
        (ctx.composition.placement(capability)?.lenses ?? []).filter(ctx.itineraryLensIsAvailable)
    }
    private var networkLabel: String? {
        ctx.hasNetworkData ? ctx.composition.lenses(hostedIn: capability).first { $0.id == .network }?.placement.label : nil
    }
    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        if isRegular {
            HStack(spacing: 0) {
                catalogue.frame(width: Self.sidebarWidth)
                InkDivider(.vertical)
                // 标题由右栏的页给: 小传是 Tab 根 (`.root`), 其余是二级 (`.secondary`)。
                destination(selection).id(selection).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(theme.paper())
        } else {
            catalogue
                .zxNavigationTitle(title, role: .root)
                .navigationDestination(item: $pushed) { destination($0) }
        }
    }

    /// 打开某一页: 宽屏换右栏, 窄屏推入 (已推入时就地替换)。
    private func open(_ target: Destination) {
        selection = target
        if !isRegular { pushed = target }
    }

    // MARK: - 目录

    private var catalogue: some View {
        List {
            Section {
                row(.overview) {
                    Label("\(ctx.composition.poet.name)小传", systemImage: "book.closed").font(theme.type.body)
                }
            }
            Section {
                ForEach(ctx.lifeEpochs) { epoch in
                    row(.chapter(epoch)) {
                        VStack(alignment: .leading, spacing: theme.space.xs) {
                            Text(epoch.label).font(theme.type.headline)
                            Text(epoch.period(in: ctx.composition.poet))
                                .font(theme.type.caption.monospacedDigit())
                                .foregroundStyle(theme.color.textSecondary)
                        }.padding(.vertical, theme.space.sm)
                    }
                }
            } header: { ZixiaoDesign.SectionLabel("\(ctx.lifeEpochs.count) 个导读篇章") }
            if !lenses.isEmpty || networkLabel != nil {
                Section {
                    ForEach(lenses) { lens in
                        row(.lens(lens.id)) {
                            Label(lens.label, systemImage: lens.id == .chronicle ? "list.bullet.rectangle" : "map")
                                .font(theme.type.body)
                        }
                    }
                    if let networkLabel {
                        row(.network) {
                            Label(networkLabel, systemImage: "person.2").font(theme.type.body)
                        }
                    }
                } header: { ZixiaoDesign.SectionLabel("深入查阅") }
            }
            if ctx.guide != nil {
                Section {
                    row(.sources) {
                        Label("资料与纪年说明", systemImage: "text.book.closed").font(theme.type.body)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.paper())
        .foregroundStyle(theme.color.textPrimary)
        .tint(theme.color.accent)
        .overlay {
            if ctx.lifeEpochs.isEmpty {
                if ctx.store.loadError != nil { LifeUI.Failure(retry: { await ctx.store.bootstrap() }) }
                else { LifeUI.Empty(title: "导读正在整理", systemImage: "text.book.closed") }
            }
        }
    }

    /// 目录里的一行。宽屏: 点选换右栏, 选中行用强调色的淡底标出 (同作品目录)。
    /// 窄屏: 推入一页, 行尾是系统导航行的箭头。
    private func row<Label: View>(_ target: Destination, @ViewBuilder label: () -> Label) -> some View {
        let selected = isRegular && selection == target
        return Button { open(target) } label: {
            HStack(spacing: theme.space.sm) {
                label()
                    .foregroundStyle(selected ? theme.color.accent : theme.color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !isRegular {
                    Image(systemName: "chevron.right")
                        .font(theme.type.footnote.weight(.semibold))
                        .foregroundStyle(theme.color.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: LifeUI.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? theme.color.fill : nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 各页

    @ViewBuilder private func destination(_ target: Destination) -> some View {
        switch target {
        case .chapter(let epoch):
            EpochDetailView(ctx: ctx, epoch: epoch, selectChapter: { open(.chapter($0)) })
                .id(epoch.id)
        case .lens(.chronicle):
            ChronicleList(ctx: ctx, upTo: ctx.composition.poet.death)
                .zxNavigationTitle("编年", role: .secondary)
        case .lens:
            LifeMapView(ctx: ctx).zxNavigationTitle("行迹", role: .secondary)
        case .network:
            NetworkView(ctx: ctx).zxNavigationTitle(networkLabel ?? "交游", role: .secondary)
        case .sources:
            if let guide = ctx.guide { GuideSourcesView(ctx: ctx, guide: guide) }
        case .overview:
            // 宽屏时小传占着 Tab 根页的位置, 用根标题; 窄屏是推入的二级页。
            introduction.zxNavigationTitle(title, role: isRegular ? .root : .secondary)
        }
    }

    private var introduction: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.xl) {
                LifeUI.Heading(eyebrow: ctx.composition.poet.name, title: "沿\(title)读懂作品",
                               introduction: ctx.guide?.biography)
                if let note = ctx.guide?.chronologyNote {
                    Text(note).font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                        .lineSpacing(theme.space.xs)
                }
                if let first = ctx.lifeEpochs.first {
                    Button { open(.chapter(first)) } label: {
                        Label("从\(first.label)读起", systemImage: "book")
                            .font(theme.type.callout)
                            .frame(minHeight: LifeUI.minTapTarget).contentShape(Rectangle())
                    }.poetActionStyle(prominent: true)
                }
            }.padding(theme.space.margin).poetReadableWidth(LifeUI.textColumnWidth)
        }.background(theme.paper()).foregroundStyle(theme.color.textPrimary)
    }
}
