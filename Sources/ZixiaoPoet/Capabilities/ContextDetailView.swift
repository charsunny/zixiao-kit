import ZixiaoPoetCore
import SwiftUI
import ZixiaoDesign

struct EventRow: View {
    let ctx: CompositionContext
    let event: PoetEvent
    @Environment(\.zxTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { heading; Spacer(); place }
                VStack(alignment: .leading, spacing: theme.space.sm) { heading; place }
            }
            Text(event.narrative).font(theme.type.body).lineSpacing(theme.space.xs)
                .foregroundStyle(theme.color.textPrimary).lineLimit(4)
            if !event.workTitles.isEmpty {
                Text(event.workTitles.map { "《\($0)》" }.joined(separator: " "))
                    .font(theme.type.callout).foregroundStyle(theme.accent).lineLimit(2)
            }
        }
        .padding(.vertical, theme.space.sm)
        .accessibilityElement(children: .combine)
    }
    private var heading: some View {
        Text(event.lunarLabel ?? "是年 · 日期未详")
            .font(theme.type.footnote.weight(.medium)).foregroundStyle(theme.color.textSecondary)
    }
    @ViewBuilder private var place: some View {
        if let station = ctx.store.stations.first(where: { $0.id == event.stationId }) {
            LifeUI.Tag(text: station.displayName, emphasized: station.isEmphasized)
        }
    }
}

struct EventDetailView: View {
    let ctx: CompositionContext
    let event: PoetEvent
    @Environment(\.zxTheme) private var theme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.xl) {
                VStack(alignment: .leading, spacing: theme.space.sm) {
                    Text(ctx.era.label(event.year)).font(theme.type.display)
                        .tracking(theme.type.tracking(for: .display))
                        .accessibilityAddTraits(.isHeader)
                    Text("\(String(event.year)) 年 · \(event.lunarLabel ?? "日期未详")")
                        .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                }
                InkDivider()
                Text(event.narrative).font(theme.type.body).lineSpacing(theme.space.sm).textSelection(.enabled)
                if let station = ctx.store.stations.first(where: { $0.id == event.stationId }) {
                    NavigationLink { StationDetailView(ctx: ctx, station: station) } label: {
                        Label("在\(station.displayName)的驻留事目", systemImage: "mappin.and.ellipse")
                            .font(theme.type.callout)
                            .frame(minHeight: LifeUI.minTapTarget)
                    }.foregroundStyle(theme.accent)
                }
                if !event.workTitles.isEmpty {
                    ZixiaoDesign.GlazePanel {
                        VStack(alignment: .leading, spacing: theme.space.md) {
                            ZixiaoDesign.SectionLabel("年谱提及的作品")
                            ForEach(Array(event.workTitles.enumerated()), id: \.offset) { _, title in
                                NavigationLink { WorkLookupView(ctx: ctx, title: title) } label: {
                                    HStack {
                                        Text(title).font(theme.type.body)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(theme.type.footnote)
                                    }.frame(minHeight: LifeUI.minTapTarget)
                                }
                            }
                        }
                    }
                }
                if let source = event.sourceRef, !source.isEmpty {
                    Text("出处：\(source)").font(theme.type.footnote)
                        .foregroundStyle(theme.color.textSecondary).textSelection(.enabled)
                }
                if let epoch = ctx.lifeEpochs.first(where: { $0.contains(event.year) }) {
                    InkDivider()
                    NavigationLink { EpochDetailView(ctx: ctx, epoch: epoch) } label: {
                        VStack(alignment: .leading, spacing: theme.space.sm) {
                            ZixiaoDesign.SectionLabel("继续读这一段人生")
                            HStack {
                                Text(epoch.label).font(theme.type.title2)
                                Spacer(); Image(systemName: "arrow.right").foregroundStyle(theme.accent)
                            }
                        }.padding(.vertical, theme.space.md).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .padding(theme.space.margin).poetReadableWidth(LifeUI.textColumnWidth)
        }
        .background(theme.paper()).foregroundStyle(theme.color.textPrimary)
        .zxNavigationTitle("年谱事目", role: .secondary)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: "\(ctx.era.label(event.year))\n\(event.narrative)") {
                    Label("分享事目", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}

struct StationDetailView: View {
    let ctx: CompositionContext
    let station: Station
    @State private var events: [PoetEvent] = []
    @State private var loading = true
    @State private var failed = false
    @Environment(\.zxTheme) private var theme
    private var otherVisits: [Station] {
        ctx.store.stations.filter { $0.displayName == station.displayName && $0.id != station.id }
    }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: theme.space.sm) {
                    Text(ctx.era.label(station.year)).font(theme.type.title2)
                        .accessibilityAddTraits(.isHeader)
                    if let modern = station.modernNote {
                        Text("今 \(modern)").font(theme.type.body).foregroundStyle(theme.color.textSecondary)
                    }
                    Text("\(String(station.year)) 年 · 第 \(station.sequence + 1) 站")
                        .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                }.padding(.vertical, theme.space.sm)
            }.listRowBackground(theme.surface)
            Section {
                if loading { LifeUI.Loading() }
                else if failed { LifeUI.Failure(title: "驻留事目暂未载入", retry: load) }
                else if events.isEmpty {
                    Text("这处驻点尚未关联具体事目，可在当年编年中继续查阅。")
                        .font(theme.type.body).foregroundStyle(theme.color.textSecondary)
                }
                ForEach(events) { event in
                    NavigationLink { EventDetailView(ctx: ctx, event: event) } label: {
                        EventRow(ctx: ctx, event: event)
                    }
                }
                NavigationLink { ChronicleEventsView(ctx: ctx, year: station.year) } label: {
                    Text("查看这一年全部事目").font(theme.type.body).foregroundStyle(theme.accent)
                }
            } header: { ZixiaoDesign.SectionLabel("此次驻留") }
                .listRowBackground(theme.surface)
            if !otherVisits.isEmpty {
                Section {
                    ForEach(otherVisits) { visit in
                        NavigationLink { StationDetailView(ctx: ctx, station: visit) } label: {
                            HStack {
                                Text(ctx.era.label(visit.year)).font(theme.type.headline)
                                Spacer()
                                Text("第 \(visit.sequence + 1) 站").font(theme.type.footnote)
                                    .foregroundStyle(theme.color.textSecondary)
                            }
                        }
                    }
                } header: { ZixiaoDesign.SectionLabel("在此地的其他驻留") }
                    .listRowBackground(theme.surface)
            }
        }
        .scrollContentBackground(.hidden).poetReadableWidth()
        .background(theme.paper()).foregroundStyle(theme.color.textPrimary)
        .zxNavigationTitle(station.displayName, role: .secondary)
        .task(id: station.id) { await load() }.refreshable { await load() }
    }
    private func load() async {
        loading = events.isEmpty; failed = false
        do { events = try await ctx.store.events(at: station) }
        catch { if !Task.isCancelled { failed = true } }
        loading = false
    }
}

struct AssociateDetailView: View {
    let ctx: CompositionContext
    let associate: Associate
    @State private var mentions: [PoetEvent] = []
    @State private var loading = true
    @State private var failed = false
    @Environment(\.zxTheme) private var theme
    private var group: AssociateGroup? {
        ctx.composition.placement(.network)?.groups?.first { $0.id == associate.groupKey }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.xl) {
                LifeUI.Heading(eyebrow: group?.label ?? "故人", title: associate.name,
                               introduction: associate.courtesyName.map { "字\($0)" })
                Text("年谱交游索引 · 提及 \(associate.weight) 次")
                    .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                InkDivider()
                VStack(alignment: .leading, spacing: theme.space.lg) {
                    ZixiaoDesign.SectionLabel("年谱中的这个名字")
                    if loading { LifeUI.Loading(label: "正在寻找相关记载…") }
                    else if failed { LifeUI.Failure(title: "相关记载暂未载入", retry: load) }
                    else if mentions.isEmpty {
                        Text("暂未找到姓名相符的事目，可从下方的往来时段继续查阅。")
                            .font(theme.type.body).foregroundStyle(theme.color.textSecondary)
                    } else {
                        ForEach(mentions.prefix(3)) { event in
                            NavigationLink { EventDetailView(ctx: ctx, event: event) } label: {
                                VStack(alignment: .leading, spacing: theme.space.sm) {
                                    Text("\(ctx.era.label(event.year)) · \(String(event.year))")
                                        .font(theme.type.footnote.weight(.medium)).foregroundStyle(theme.accent)
                                    Text(event.narrative).font(theme.type.body).lineSpacing(theme.space.xs)
                                        .lineLimit(3).foregroundStyle(theme.color.textPrimary)
                                    Label("读这则记载", systemImage: "arrow.right")
                                        .font(theme.type.footnote).foregroundStyle(theme.accent)
                                }.padding(.vertical, theme.space.sm).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            InkDivider()
                        }
                        if mentions.count > 3 {
                            NavigationLink { NameMentionsView(ctx: ctx, name: associate.name, events: mentions) } label: {
                                Label("查看 \(mentions.count) 则姓名提及", systemImage: "text.magnifyingglass")
                                    .font(theme.type.footnote.weight(.medium)).frame(minHeight: LifeUI.minTapTarget)
                            }
                        }
                        Text("按姓名检索年谱正文，最多展示 60 则；提及不一定代表当面往来。")
                            .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: theme.space.md) {
                    ZixiaoDesign.SectionLabel("循年寻人")
                    if let first = associate.firstYear {
                        NavigationLink { ChronicleEventsView(ctx: ctx, year: first) } label: {
                            Text("初见记载 · \(ctx.era.label(first))").font(theme.type.body)
                        }.frame(minHeight: LifeUI.minTapTarget)
                    }
                    if let last = associate.lastYear, last != associate.firstYear {
                        NavigationLink { ChronicleEventsView(ctx: ctx, year: last) } label: {
                            Text("末见记载 · \(ctx.era.label(last))").font(theme.type.body)
                        }.frame(minHeight: LifeUI.minTapTarget)
                    }
                }
            }.padding(.horizontal, theme.space.margin).padding(.vertical, theme.space.xl)
                .poetReadableWidth(LifeUI.textColumnWidth)
        }
        .background(theme.paper()).foregroundStyle(theme.color.textPrimary)
        .zxNavigationTitle("故人", role: .secondary)
        .task(id: associate.id) { await load() }
    }
    private func load() async {
        loading = mentions.isEmpty; failed = false
        do {
            let fetched = try await ctx.store.events(mentioning: associate.name)
            guard !Task.isCancelled else { return }
            mentions = fetched
        } catch { if !Task.isCancelled { failed = true } }
        loading = false
    }
}

private struct NameMentionsView: View {
    let ctx: CompositionContext
    let name: String
    let events: [PoetEvent]
    @Environment(\.zxTheme) private var theme
    var body: some View {
        List(events) { event in
            NavigationLink { EventDetailView(ctx: ctx, event: event) } label: {
                VStack(alignment: .leading, spacing: theme.space.xs) {
                    Text("\(ctx.era.label(event.year)) · \(String(event.year))")
                        .font(theme.type.footnote.weight(.medium)).foregroundStyle(theme.accent)
                    EventRow(ctx: ctx, event: event)
                }
            }.listRowBackground(theme.paper()).listRowSeparatorTint(theme.rule)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).poetReadableWidth(LifeUI.textColumnWidth)
        .background(theme.paper())
        .zxNavigationTitle(name, subtitle: "按年代排列 · 最多 60 则姓名提及", role: .secondary)
    }
}

struct WorkLookupView: View {
    let ctx: CompositionContext
    let title: String
    @State private var poems: [Poem] = []
    @State private var loading = true
    @State private var failed = false
    @Environment(\.zxTheme) private var theme
    var body: some View {
        List(poems) { poem in
            NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                LifeUI.PoemRow(poem: poem, displayTitle: ctx.workTitle(poem), showsDisclosure: false)
            }.listRowBackground(theme.paper()).listRowSeparatorTint(theme.rule)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).poetReadableWidth()
        .background(theme.paper())
        .zxNavigationTitle(title, role: .secondary)
        .overlay {
            if loading { LifeUI.Loading(label: "正在查找作品…") }
            else if failed { LifeUI.Failure(retry: load) }
            else if poems.isEmpty {
                LifeUI.Empty(title: "读本暂未收录", message: "这篇作品见于年谱，目前还没有可读的正文。",
                             systemImage: "book.closed")
            }
        }
        .task { await load() }
    }
    private func load() async {
        loading = true; failed = false
        do { poems = try await ctx.store.search(title).poems }
        catch { if !Task.isCancelled { failed = true } }
        loading = false
    }
}

// MARK: - 今日 / 生平 共用小件
//
// 只给今日、生平这一组视图用 (DailyView / LifeOverview / Narrative / Itinerary / LifeMap / Network /
// ContextDetail)。放进一个命名空间, 免得和作品、书房那边同时在改的视图撞名。
// 全部只读 `@Environment(\.zxTheme)`: 颜色、字、间距都是 token, 不收主题参数。

enum LifeUI {
    /// HIG 的最小点按区。ZX token 里没有这一格 (kit gap, 见 M2a 报告), 用到的地方统一引用它。
    static let minTapTarget: CGFloat = 44
    /// 导读、事目这类长文的栏宽。ZX token 不管页面级栏宽 (`ZXMetric` 只放组件尺度), 沿用原值。
    static let textColumnWidth: CGFloat = 640
    /// 目录类列表的栏宽 (导读目录、行迹详情)。
    static let listColumnWidth: CGFloat = 680

    /// 页首: 小字题眉 + 展示字标题 + 导语。原 `EditorialHeading` 的 token 版。
    struct Heading: View {
        let eyebrow: String
        let title: String
        var introduction: String? = nil
        @Environment(\.zxTheme) private var theme
        var body: some View {
            VStack(alignment: .leading, spacing: theme.space.md) {
                Text(eyebrow).font(theme.type.footnote.weight(.medium))
                    .tracking(theme.type.tracking(for: .footnote))
                    .foregroundStyle(theme.accent)
                Text(title).font(theme.type.display).tracking(theme.type.tracking(for: .display))
                    .foregroundStyle(theme.color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let introduction {
                    Text(introduction).font(theme.type.body).lineSpacing(theme.space.sm)
                        .foregroundStyle(theme.color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 地名 / 分期的小签。`secondary` 是契约里给标签用的色; 贬所之类的强调地落在印色上。
    /// (纸墨朱印里 accent 与 seal 同为朱, 原先「强调走印、其余走 accent」两种看不出差别。)
    struct Tag: View {
        let text: String
        var emphasized = false
        @Environment(\.zxTheme) private var theme
        var body: some View {
            let tint = emphasized ? theme.seal : theme.color.secondary
            Text(text)
                .font(theme.type.footnote.weight(.medium))
                .foregroundStyle(tint)
                .padding(.horizontal, theme.space.sm)
                .padding(.vertical, theme.space.xxs)
                .background(tint.opacity(0.12), in: Capsule())
        }
    }

    /// 作品条目: 题 + 首句。作品页的 `PoemRow` 还收旧主题参数, 这里用 token 版, 两边互不牵扯。
    struct PoemRow: View {
        let poem: Poem
        var displayTitle: String? = nil
        var showsDisclosure = true
        @Environment(\.zxTheme) private var theme
        @Environment(\.dynamicTypeSize) private var typeSize
        var body: some View {
            HStack(spacing: theme.space.sm) {
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
                        .font(theme.type.caption.weight(.semibold)).foregroundStyle(theme.accent)
                }
            }
            .frame(minHeight: minTapTarget)
            .contentShape(Rectangle())
        }
    }

    /// 载入中。
    struct Loading: View {
        var label = "正在载入…"
        @Environment(\.zxTheme) private var theme
        var body: some View {
            ProgressView {
                Text(label).font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
            }
            .tint(theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.space.xxxl)
            .accessibilityLabel(label)
        }
    }

    /// 没有内容 (不是出错)。kit `EmptyState` 的标题 + 一行补充。
    struct Empty: View {
        let title: String
        var message: String? = nil
        var systemImage: String? = nil
        @Environment(\.zxTheme) private var theme
        var body: some View {
            EmptyState(title, systemImage: systemImage) {
                if let message {
                    Text(message).font(theme.type.footnote).foregroundStyle(theme.color.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    /// 载入失败 + 重试。kit `EmptyState`, 报错类按它的建议给一个图标 (示警靠形状不靠颜色)。
    struct Failure: View {
        var title = "暂时无法载入"
        var message = "请检查网络连接后重试。"
        var retry: () async -> Void
        @State private var retrying = false
        @Environment(\.zxTheme) private var theme
        var body: some View {
            EmptyState(title, systemImage: "wifi.exclamationmark") {
                VStack(spacing: theme.space.md) {
                    Text(message).font(theme.type.footnote).foregroundStyle(theme.color.textTertiary)
                        .multilineTextAlignment(.center)
                    Button(retrying ? "正在重试…" : "重试") {
                        Task { retrying = true; await retry(); retrying = false }
                    }
                    .font(theme.type.callout)
                    .frame(minHeight: minTapTarget)
                    .poetActionStyle()
                    .disabled(retrying)
                }
            }
        }
    }
}
