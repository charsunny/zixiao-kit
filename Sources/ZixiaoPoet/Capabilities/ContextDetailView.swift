import SwiftUI

struct EventRow: View {
    let ctx: CompositionContext
    let event: PoetEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { heading; Spacer(); place }
                VStack(alignment: .leading, spacing: 8) { heading; place }
            }
            Text(event.narrative).font(PoetFont.body).lineSpacing(6).lineLimit(4)
            if !event.workTitles.isEmpty {
                Text(event.workTitles.map { "《\($0)》" }.joined(separator: " "))
                    .font(PoetFont.callout).foregroundStyle(ctx.theme.accent).lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
    private var heading: some View {
        Text(event.lunarLabel ?? "是年 · 日期未详")
            .font(PoetFont.label).foregroundStyle(ctx.theme.secondaryInk)
    }
    @ViewBuilder private var place: some View {
        if let station = ctx.store.stations.first(where: { $0.id == event.stationId }) {
            PlaceChip(text: station.displayName, theme: ctx.theme, emphasized: station.isEmphasized)
        }
    }
}

struct EventDetailView: View {
    let ctx: CompositionContext
    let event: PoetEvent
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.blockGap) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ctx.era.label(event.year)).font(PoetFont.display)
                    Text("\(String(event.year)) 年 · \(event.lunarLabel ?? "日期未详")")
                        .font(PoetFont.meta).foregroundStyle(ctx.theme.secondaryInk)
                }
                EditorialRule(theme: ctx.theme)
                Text(event.narrative).font(PoetFont.body).lineSpacing(9).textSelection(.enabled)
                if let station = ctx.store.stations.first(where: { $0.id == event.stationId }) {
                    NavigationLink { StationDetailView(ctx: ctx, station: station) } label: {
                        Label("在\(station.displayName)的驻留事目", systemImage: "mappin.and.ellipse")
                            .frame(minHeight: 44)
                    }.foregroundStyle(ctx.theme.accent)
                }
                if !event.workTitles.isEmpty {
                    GlazePanel(theme: ctx.theme) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(text: "年谱提及的作品", theme: ctx.theme)
                            ForEach(Array(event.workTitles.enumerated()), id: \.offset) { _, title in
                                NavigationLink { WorkLookupView(ctx: ctx, title: title) } label: {
                                    HStack {
                                        Text(title).font(PoetFont.body)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.footnote)
                                    }.frame(minHeight: 44)
                                }
                            }
                        }
                    }
                }
                if let source = event.sourceRef, !source.isEmpty {
                    Text("出处：\(source)").font(PoetFont.meta)
                        .foregroundStyle(ctx.theme.secondaryInk).textSelection(.enabled)
                }
                if let epoch = ctx.lifeEpochs.first(where: { $0.contains(event.year) }) {
                    EditorialRule(theme: ctx.theme)
                    NavigationLink { EpochDetailView(ctx: ctx, epoch: epoch) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "继续读这一段人生", theme: ctx.theme)
                            HStack {
                                Text(epoch.label).font(PoetFont.cardTitle)
                                Spacer(); Image(systemName: "arrow.right")
                            }
                        }.padding(.vertical, 12).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .padding(Metric.gutter).poetReadableWidth(640)
        }
        .background(ctx.theme.paper).foregroundStyle(ctx.theme.ink)
        .navigationTitle("年谱事目").navigationBarTitleDisplayMode(.inline)
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
    private var otherVisits: [Station] {
        ctx.store.stations.filter { $0.displayName == station.displayName && $0.id != station.id }
    }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ctx.era.label(station.year)).font(PoetFont.cardTitle)
                    if let modern = station.modernNote {
                        Text("今 \(modern)").font(PoetFont.body).foregroundStyle(ctx.theme.secondaryInk)
                    }
                    Text("\(String(station.year)) 年 · 第 \(station.sequence + 1) 站")
                        .font(PoetFont.meta).foregroundStyle(ctx.theme.secondaryInk)
                }.padding(.vertical, 8)
            }.listRowBackground(ctx.theme.surface)
            Section("此次驻留") {
                if loading { LoadingStateView() }
                else if failed { LoadFailureView(title: "驻留事目暂未载入", retry: load) }
                else if events.isEmpty {
                    Text("这处驻点尚未关联具体事目，可在当年编年中继续查阅。")
                        .font(PoetFont.body).foregroundStyle(ctx.theme.secondaryInk)
                }
                ForEach(events) { event in
                    NavigationLink { EventDetailView(ctx: ctx, event: event) } label: {
                        EventRow(ctx: ctx, event: event)
                    }
                }
                NavigationLink("查看这一年全部事目") { ChronicleEventsView(ctx: ctx, year: station.year) }
            }.listRowBackground(ctx.theme.surface)
            if !otherVisits.isEmpty {
                Section("在此地的其他驻留") {
                    ForEach(otherVisits) { visit in
                        NavigationLink { StationDetailView(ctx: ctx, station: visit) } label: {
                            HStack {
                                Text(ctx.era.label(visit.year)).font(PoetFont.entryTitle)
                                Spacer()
                                Text("第 \(visit.sequence + 1) 站").font(PoetFont.meta)
                                    .foregroundStyle(ctx.theme.secondaryInk)
                            }
                        }
                    }
                }.listRowBackground(ctx.theme.surface)
            }
        }
        .scrollContentBackground(.hidden).poetReadableWidth().background(ctx.theme.paper).foregroundStyle(ctx.theme.ink)
        .navigationTitle(station.displayName).navigationBarTitleDisplayMode(.inline)
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
    private var theme: Theme { ctx.theme }
    private var group: AssociateGroup? {
        ctx.composition.placement(.network)?.groups?.first { $0.id == associate.groupKey }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                EditorialHeading(eyebrow: group?.label ?? "故人", title: associate.name,
                    introduction: associate.courtesyName.map { "字\($0)" }, theme: theme)
                Text("年谱交游索引 · 提及 \(associate.weight) 次")
                    .font(PoetFont.meta).foregroundStyle(theme.secondaryInk)
                EditorialRule(theme: theme)
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(text: "年谱中的这个名字", theme: theme)
                    if loading { LoadingStateView(label: "正在寻找相关记载…") }
                    else if failed { LoadFailureView(title: "相关记载暂未载入", retry: load) }
                    else if mentions.isEmpty {
                        Text("暂未找到姓名相符的事目，可从下方的往来时段继续查阅。")
                            .font(PoetFont.body).foregroundStyle(theme.secondaryInk)
                    } else {
                        ForEach(mentions.prefix(3)) { event in
                            NavigationLink { EventDetailView(ctx: ctx, event: event) } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("\(ctx.era.label(event.year)) · \(String(event.year))")
                                        .font(PoetFont.label).foregroundStyle(theme.accent)
                                    Text(event.narrative).font(PoetFont.body).lineSpacing(6)
                                        .lineLimit(3).foregroundStyle(theme.ink)
                                    Label("读这则记载", systemImage: "arrow.right")
                                        .font(PoetFont.meta).foregroundStyle(theme.accent)
                                }.padding(.vertical, 8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            EditorialRule(theme: theme)
                        }
                        if mentions.count > 3 {
                            NavigationLink { NameMentionsView(ctx: ctx, name: associate.name, events: mentions) } label: {
                                Label("查看 \(mentions.count) 则姓名提及", systemImage: "text.magnifyingglass")
                                    .font(PoetFont.label).frame(minHeight: 44)
                            }
                        }
                        Text("按姓名检索年谱正文，最多展示 60 则；提及不一定代表当面往来。")
                            .font(PoetFont.meta).foregroundStyle(theme.secondaryInk)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "循年寻人", theme: theme)
                    if let first = associate.firstYear {
                        NavigationLink("初见记载 · \(ctx.era.label(first))") { ChronicleEventsView(ctx: ctx, year: first) }
                            .frame(minHeight: 44)
                    }
                    if let last = associate.lastYear, last != associate.firstYear {
                        NavigationLink("末见记载 · \(ctx.era.label(last))") { ChronicleEventsView(ctx: ctx, year: last) }
                            .frame(minHeight: 44)
                    }
                }
            }.padding(.horizontal, Metric.gutter).padding(.vertical, 24).poetReadableWidth(640)
        }
        .background(theme.paper).foregroundStyle(theme.ink)
        .navigationTitle("故人").navigationBarTitleDisplayMode(.inline)
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
    var body: some View {
        List(events) { event in
            NavigationLink { EventDetailView(ctx: ctx, event: event) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ctx.era.label(event.year)) · \(String(event.year))")
                        .font(PoetFont.label).foregroundStyle(ctx.theme.accent)
                    EventRow(ctx: ctx, event: event)
                }
            }.listRowBackground(ctx.theme.paper).listRowSeparatorTint(ctx.theme.rule)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).poetReadableWidth(640).background(ctx.theme.paper)
        .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
        .poetNavigationSubtitle("按年代排列 · 最多 60 则姓名提及")
    }
}

struct WorkLookupView: View {
    let ctx: CompositionContext
    let title: String
    @State private var poems: [Poem] = []
    @State private var loading = true
    @State private var failed = false
    var body: some View {
        List(poems) { poem in
            NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                PoemRow(poem: poem, theme: ctx.theme, showsDisclosure: false, displayTitle: ctx.workTitle(poem))
            }.listRowBackground(ctx.theme.paper)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).poetReadableWidth()
        .background(ctx.theme.paper)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .overlay {
            if loading { LoadingStateView(label: "正在查找作品…") }
            else if failed { LoadFailureView(retry: load) }
            else if poems.isEmpty {
                ContentUnavailableView("读本暂未收录", systemImage: "book.closed",
                    description: Text("这篇作品见于年谱，目前还没有可读的正文。"))
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
