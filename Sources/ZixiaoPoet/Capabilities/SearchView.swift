import SwiftUI

struct SearchZeroStateView: View {
    let ctx: CompositionContext
    @State private var query = ""
    @State private var results = SearchResults.empty
    @State private var searching = false
    @State private var failed = false
    private var theme: Theme { ctx.theme }
    private var artResults: [Artwork] { term.isEmpty ? [] : ctx.artworks.filter { $0.matches(term) } }
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group {
            if term.isEmpty { zeroState }
            else if searching && artResults.isEmpty { LoadingStateView(label: "正在寻踪…") }
            else if failed && artResults.isEmpty { LoadFailureView(title: "检索暂不可用", retry: search) }
            else if results.isEmpty && artResults.isEmpty { ContentUnavailableView.search(text: term) }
            else { resultList }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.paper)
        .navigationTitle(ctx.composition.placement(.search)?.label ?? "寻踪")
        .toolbarTitleDisplayMode(.inlineLarge)
        .poetNavigationSubtitle(term.isEmpty ? "作品与\(ctx.narrativeLabel)" : "作品 · 地点 · 人物 · 年份")
        .searchable(text: $query, prompt: "搜作品、地点、人物或年份")
        .scrollDismissesKeyboard(.interactively)
        .task(id: "\(term)|\(ctx.store.stations.count)|\(ctx.store.associates.count)") { await search() }
    }

    private var zeroState: some View {
        List {
            Section("试着搜一搜") {
                ForEach(ctx.composition.editorial?.searchPrompts ?? []) { prompt in
                    Button { query = prompt.query } label: {
                        HStack(spacing: 14) {
                            Image(systemName: prompt.symbol).foregroundStyle(theme.accent).frame(width: 28)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(prompt.query).font(.headline).foregroundStyle(.primary)
                                Text(prompt.hint).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "arrow.up.left").font(.footnote).foregroundStyle(.tertiary)
                        }.padding(.vertical, 6)
                    }.accessibilityLabel("搜索\(prompt.query)，\(prompt.hint)")
                }
            }
            if !ctx.artworks.isEmpty {
                Section("也可以看书画") {
                    ForEach(ctx.artworks.prefix(2)) { artwork in
                        NavigationLink { ArtworkDetailView(ctx: ctx, artwork: artwork) } label: {
                            Label(artwork.title, systemImage: "paintbrush.pointed")
                        }
                    }
                }
            }
            if ctx.store.loadError != nil {
                Section {
                    Button("重新载入地点与人物") { Task { await ctx.store.bootstrap() } }
                } footer: { Text("地点与人物暂未载入。") }
            }
        }.listStyle(.insetGrouped).scrollContentBackground(.hidden).poetReadableWidth(640)
    }

    private var resultList: some View {
        List {
            if !artResults.isEmpty {
                Section("书画 · \(artResults.count)") {
                    ForEach(artResults) { artwork in
                        NavigationLink { ArtworkDetailView(ctx: ctx, artwork: artwork) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(artwork.title).font(.headline)
                                Text("\(artwork.kind) · \(artwork.collection)").font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }
                    }
                }
            }
            if searching { Section { ProgressView("正在检索在线诗文…") } }
            if failed {
                Section { Button("在线诗文检索暂不可用，重试") { Task { await search() } } }
            }

            if let year = results.year {
                Section("年份") {
                    NavigationLink { ChronicleEventsView(ctx: ctx, year: year) } label: {
                        HStack {
                            Text(ctx.era.label(year)).font(PoetFont.entryTitle)
                            Spacer()
                            Text(String(year)).font(PoetFont.meta.monospacedDigit())
                                .foregroundStyle(theme.secondaryInk)
                        }.frame(minHeight: 44)
                    }
                }.listRowBackground(theme.surface)
            }
            if !results.places.isEmpty {
                Section("地点 · \(results.places.count)") {
                    ForEach(results.places) { station in
                        NavigationLink { StationDetailView(ctx: ctx, station: station) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(station.displayName).font(PoetFont.entryTitle)
                                Text(ctx.era.label(station.year)).font(PoetFont.meta)
                                    .foregroundStyle(theme.secondaryInk)
                            }.frame(minHeight: 48)
                        }
                    }
                }.listRowBackground(theme.surface)
            }
            if !results.people.isEmpty {
                Section("人物 · \(results.people.count)") {
                    ForEach(results.people) { person in
                        NavigationLink { AssociateDetailView(ctx: ctx, associate: person) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(person.name).font(PoetFont.entryTitle)
                                    if let courtesy = person.courtesyName {
                                        Text("字\(courtesy)").font(PoetFont.meta)
                                            .foregroundStyle(theme.secondaryInk)
                                    }
                                }
                                Spacer()
                                Text("提及 \(person.weight) 次").font(PoetFont.meta)
                                    .foregroundStyle(theme.secondaryInk)
                            }.frame(minHeight: 48)
                        }
                    }
                }.listRowBackground(theme.surface)
            }
            if !results.poems.isEmpty {
                Section {
                    ForEach(results.poems) { poem in
                        NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                            PoemRow(poem: poem, theme: theme, showsDisclosure: false, displayTitle: ctx.workTitle(poem))
                        }
                    }
                } header: { Text("作品 · \(results.poems.count)") }
                footer: {
                    if results.poems.count == 40 { Text("显示前 40 篇，输入更完整的标题或诗句可缩小范围。") }
                }
                .listRowBackground(theme.surface)
            }
        }
        .scrollContentBackground(.hidden).poetReadableWidth().foregroundStyle(theme.ink)
    }

    private func search() async {
        let requested = term
        results = .empty; failed = false
        guard !requested.isEmpty else { searching = false; return }
        searching = true
        do {
            try await Task.sleep(for: .milliseconds(280))
            let fetched = try await ctx.store.search(requested)
            guard !Task.isCancelled, requested == term else { return }
            results = fetched
        } catch {
            guard !Task.isCancelled, requested == term else { return }
            failed = true
        }
        searching = false
    }
}
