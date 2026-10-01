import SwiftUI
import ZixiaoDesign

struct ItineraryView: View {
    let ctx: CompositionContext
    var body: some View {
        NarrativeWorkspaceView(ctx: ctx, capability: .itinerary)
    }
}

struct ChronicleList: View {
    let ctx: CompositionContext
    let upTo: Int
    @State private var counts: [Int: Int] = [:]
    @State private var loading = true
    @State private var failed = false
    @Environment(\.zxTheme) private var theme
    private var years: [Int] { counts.keys.filter { $0 <= upTo }.sorted(by: >) }

    var body: some View {
        List(years, id: \.self) { year in
            NavigationLink { ChronicleEventsView(ctx: ctx, year: year) } label: {
                HStack(alignment: .firstTextBaseline, spacing: theme.space.md) {
                    VStack(alignment: .leading, spacing: theme.space.xs) {
                        Text(ctx.era.label(year)).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                        if let epoch = ctx.lifeEpochs.first(where: { $0.contains(year) }) {
                            LifeUI.Tag(text: epoch.label)
                        }
                    }
                    Spacer(minLength: theme.space.sm)
                    VStack(alignment: .trailing, spacing: theme.space.xs) {
                        Text(String(year)).monospacedDigit()
                        Text("\(counts[year] ?? 0) 条")
                    }.font(theme.type.footnote.monospacedDigit()).foregroundStyle(theme.color.textSecondary)
                }.padding(.vertical, theme.space.xs)
            }
            .listRowBackground(theme.paper()).listRowSeparatorTint(theme.rule)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).poetReadableWidth()
        .background(theme.paper()).foregroundStyle(theme.color.textPrimary)
        .overlay {
            if loading { LifeUI.Loading(label: "正在翻检编年…") }
            else if failed { LifeUI.Failure(title: "编年暂未载入", retry: load) }
            else if counts.isEmpty { LifeUI.Empty(title: "暂无编年记载", systemImage: "calendar") }
        }
        .task { await load() }.refreshable { await load() }
    }
    private func load() async {
        if counts.isEmpty { counts = ctx.guide?.archiveCounts ?? [:] }
        loading = counts.isEmpty; failed = false
        do { counts = try await ctx.store.eventYearCounts() }
        catch { if !Task.isCancelled { failed = counts.isEmpty } }
        loading = false
    }
}

struct ChronicleEventsView: View {
    let ctx: CompositionContext
    let year: Int
    @State private var events: [PoetEvent] = []
    @State private var loading = true
    @State private var failed = false
    @Environment(\.zxTheme) private var theme
    var body: some View {
        List(events) { event in
            NavigationLink { EventDetailView(ctx: ctx, event: event) } label: {
                EventRow(ctx: ctx, event: event)
            }
            .listRowBackground(theme.paper()).listRowSeparatorTint(theme.rule)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).poetReadableWidth()
        .background(theme.paper()).foregroundStyle(theme.color.textPrimary)
        .zxNavigationTitle(ctx.era.label(year),
                           subtitle: loading ? "正在翻检…" : "\(year) 年 · \(events.count) 条事目",
                           role: .secondary)
        .overlay {
            if loading { LifeUI.Loading() }
            else if failed { LifeUI.Failure(title: "事目暂未载入", retry: load) }
            else if events.isEmpty { LifeUI.Empty(title: "这一年暂无记载", systemImage: "text.book.closed") }
        }
        .task { await load() }.refreshable { await load() }
    }
    private func load() async {
        loading = events.isEmpty; failed = false
        do { events = try await ctx.store.events(year: year) }
        catch { if !Task.isCancelled { failed = true } }
        loading = false
    }
}
