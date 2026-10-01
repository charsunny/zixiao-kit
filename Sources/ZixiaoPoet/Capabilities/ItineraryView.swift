import SwiftUI

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
    private var years: [Int] { counts.keys.filter { $0 <= upTo }.sorted(by: >) }

    var body: some View {
        List(years, id: \.self) { year in
            NavigationLink { ChronicleEventsView(ctx: ctx, year: year) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(ctx.era.label(year)).font(PoetFont.entryTitle)
                        if let epoch = ctx.lifeEpochs.first(where: { $0.contains(year) }) {
                            Text(epoch.label).font(PoetFont.meta).foregroundStyle(ctx.theme.accent)
                        }
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(String(year)).monospacedDigit()
                        Text("\(counts[year] ?? 0) 条")
                    }.font(PoetFont.meta).foregroundStyle(ctx.theme.secondaryInk)
                }.padding(.vertical, 6)
            }
            .listRowBackground(ctx.theme.paper).listRowSeparatorTint(ctx.theme.rule)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).poetReadableWidth()
        .background(ctx.theme.paper).foregroundStyle(ctx.theme.ink)
        .overlay {
            if loading { LoadingStateView(label: "正在翻检编年…") }
            else if failed { LoadFailureView(title: "编年暂未载入", retry: load) }
            else if counts.isEmpty { ContentUnavailableView("暂无编年记载", systemImage: "calendar") }
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
    var body: some View {
        List(events) { event in
            NavigationLink { EventDetailView(ctx: ctx, event: event) } label: {
                EventRow(ctx: ctx, event: event)
            }
            .listRowBackground(ctx.theme.paper).listRowSeparatorTint(ctx.theme.rule)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).poetReadableWidth()
        .background(ctx.theme.paper).foregroundStyle(ctx.theme.ink)
        .navigationTitle(ctx.era.label(year)).navigationBarTitleDisplayMode(.inline)
        .poetNavigationSubtitle(loading ? "正在翻检…" : "\(year) 年 · \(events.count) 条事目")
        .overlay {
            if loading { LoadingStateView() }
            else if failed { LoadFailureView(title: "事目暂未载入", retry: load) }
            else if events.isEmpty { ContentUnavailableView("这一年暂无记载", systemImage: "text.book.closed") }
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
