import SwiftUI

struct LifeOverviewView: View {
    let ctx: CompositionContext
    private var epochs: [Epoch] { ctx.lifeEpochs }
    var body: some View {
        List {
            if let guide = ctx.guide {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("沿\(ctx.narrativeLabel)读懂作品").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        Text(guide.biography).font(.body).lineSpacing(6).foregroundStyle(.secondary)
                        Text(guide.chronologyNote).font(.footnote).lineSpacing(4).foregroundStyle(.secondary)
                    }.padding(.vertical, 10)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 14, trailing: 0))
            }
            Section("\(epochs.count) 个导读篇章") {
                ForEach(Array(epochs.enumerated()), id: \.element.id) { index, epoch in
                    NavigationLink { EpochDetailView(ctx: ctx, epoch: epoch) } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Text(String(format: "%02d", index + 1)).font(.subheadline.monospacedDigit())
                                .foregroundStyle(ctx.theme.accent).frame(width: 26).padding(.top, 3).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(epoch.label).font(.headline)
                                Text(epoch.period(in: ctx.composition.poet)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                if let note = ctx.chapterIntroduction(epoch) {
                                    Text(note).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }.padding(.vertical, 10)
                    }
                }
            }
            if let guide = ctx.guide {
                Section {
                    NavigationLink { GuideSourcesView(ctx: ctx, guide: guide) } label: { Label("资料与纪年说明", systemImage: "text.book.closed") }
                } footer: { Text("从导读理解处境，再沿关联作品回到原文；纪年中的存疑处以资料说明为准。") }
            }
        }.listStyle(.insetGrouped).scrollContentBackground(.hidden).poetReadableWidth(680)
            .background(ctx.theme.paper)
            .overlay {
                if epochs.isEmpty {
                    if ctx.store.loadError != nil { LoadFailureView(retry: { await ctx.store.bootstrap() }) }
                    else { ContentUnavailableView("导读正在整理", systemImage: "text.book.closed") }
                }
            }
    }
}

struct EpochDetailView: View {
    let ctx: CompositionContext
    let epoch: Epoch
    var selectChapter: ((Epoch) -> Void)? = nil
    @State private var liveCounts: [Int: Int] = [:]
    @Environment(\.dynamicTypeSize) private var typeSize
    private var theme: Theme { ctx.theme }
    private var chapter: LifeChapter? { ctx.guide?.chapter(epoch) }
    private var counts: [Int: Int] { liveCounts.isEmpty ? ctx.guide?.archiveCounts ?? [:] : liveCounts }
    private var years: [Int] { counts.keys.filter { epoch.contains($0) }.sorted() }
    private var nextEpoch: Epoch? { ctx.lifeEpochs.first { $0.sequence > epoch.sequence } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                EditorialHeading(eyebrow: epoch.period(in: ctx.composition.poet), title: epoch.label,
                                 introduction: ctx.chapterIntroduction(epoch), theme: theme)
                if let chapter {
                    ForEach(chapter.paragraphs, id: \.self) { paragraph in
                        Text(paragraph).font(.body).lineSpacing(8).textSelection(.enabled)
                    }
                    if !chapter.milestones.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionLabel(text: "这一章的转折", theme: theme).padding(.bottom, 10)
                            ForEach(chapter.milestones) { milestone in
                                if ctx.hasChronicleData {
                                    NavigationLink { ChronicleEventsView(ctx: ctx, year: milestone.year) } label: {
                                        milestoneLabel(milestone, showsDisclosure: true)
                                    }.buttonStyle(.plain)
                                } else {
                                    milestoneLabel(milestone, showsDisclosure: false)
                                }
                                Divider()
                            }
                        }
                    }
                    let works = chapter.workIDs.compactMap { ctx.guide?.poem($0) }
                    if !works.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "把这一章读进作品", theme: theme)
                            ForEach(works) { poem in
                                NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                                    PoemRow(poem: poem, theme: theme, displayTitle: ctx.workTitle(poem))
                                }.buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                }
                if ctx.hasChronicleData {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionLabel(text: "逐年查阅", theme: theme, trailing: "有记载的年份")
                        if epoch.sequence == ctx.lifeEpochs.first?.sequence, let guide = ctx.guide {
                            Text(guide.chronologyNote).font(.footnote).foregroundStyle(.secondary).lineSpacing(4)
                        }
                        if !years.isEmpty {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                                ForEach(years, id: \.self) { year in
                                    NavigationLink { ChronicleEventsView(ctx: ctx, year: year) } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(ctx.era.label(year)).font(.headline)
                                            Text("\(String(year)) · \(counts[year] ?? 0) 条事目").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                                            .padding(16).background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }.buttonStyle(.plain)
                                }
                            }
                        } else {
                            NavigationLink("打开编年目录") { ChronicleList(ctx: ctx, upTo: epoch.yearEnd ?? ctx.composition.poet.death).navigationTitle("编年").toolbarTitleDisplayMode(.inlineLarge) }
                        }
                    }
                }
                if let next = nextEpoch {
                    Divider()
                    if let selectChapter {
                        Button { selectChapter(next) } label: { nextChapterLabel(next) }
                            .buttonStyle(.plain)
                    } else {
                        NavigationLink { EpochDetailView(ctx: ctx, epoch: next) } label: { nextChapterLabel(next) }
                            .buttonStyle(.plain)
                    }
                }
                if let guide = ctx.guide {
                    NavigationLink("本章资料与纪年说明") { GuideSourcesView(ctx: ctx, guide: guide, sourceIDs: chapter?.sourceIDs) }
                        .font(.footnote).frame(minHeight: 44)
                }
            }.padding(.horizontal, Metric.gutter).padding(.vertical, 24).poetReadableWidth(640)
        }.background(theme.paper).foregroundStyle(theme.ink)
            .navigationTitle("\(ctx.narrativeLabel)篇章").toolbarTitleDisplayMode(.inlineLarge)
            .task {
                guard ctx.hasChronicleData else { return }
                if let fetched = try? await ctx.store.eventYearCounts(), !Task.isCancelled { liveCounts = fetched }
            }
    }

    private func nextChapterLabel(_ next: Epoch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("下一章").font(.caption).foregroundStyle(.secondary)
            HStack { Text(next.label).font(.title3.bold()); Spacer(); Image(systemName: "arrow.right") }
        }.frame(minHeight: 64).contentShape(Rectangle())
    }

    private func milestoneLabel(_ milestone: LifeMilestone, showsDisclosure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(milestone.title).font(.headline)
                Spacer()
                Text(String(milestone.year)).font(.caption.monospacedDigit())
                if showsDisclosure { Image(systemName: "chevron.right").font(.caption) }
            }.foregroundStyle(theme.accent)
            Text(milestone.detail).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 16).contentShape(Rectangle())
    }
}

struct GuideSourcesView: View {
    let ctx: CompositionContext
    let guide: PoetGuide
    var sourceIDs: [String]? = nil
    private var sources: [GuideSource] { guide.sources.filter { sourceIDs?.contains($0.id) ?? true } }
    var body: some View {
        List {
            Section("纪年方式") { Text(guide.chronologyNote).font(.subheadline).lineSpacing(5) }
            Section("资料依据") {
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: 8) {
                        if let url = source.url { Link(source.title, destination: url).font(.headline) }
                        else { Text(source.title).font(.headline) }
                        Text(source.note).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
            if ctx.hasItineraryData {
                Section("地图说明") {
                    Text(ctx.composition.placement(.itinerary)?.fidelity == .approximate
                         ? "Apple 地图提供现代地理底图，古地名与行迹为经资料核对后的约略位置和顺序，不表示精确年代、道路或行政疆界。"
                         : "Apple 地图提供现代地理底图，古地名是本应用叠加的历史注记；连线只表示已整理的主要行程节点，不表示当时道路、完整行程或行政疆界。")
                        .font(.subheadline).lineSpacing(5)
                }
            }
            Section { Text("导览整理于 \(guide.snapshotDate)。导读篇章与所附代表作可离线阅读；更多作品和逐年事目在有资料且网络可用时载入。")
                    .font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("资料与说明").toolbarTitleDisplayMode(.inlineLarge)
    }
}

extension Epoch {
    func period(in poet: Poet) -> String {
        let start = max(yearStart, poet.birth), end = min(yearEnd ?? poet.death, poet.death)
        return start == end ? "\(String(start)) 年" : "\(String(start)) — \(String(end))"
    }
}
