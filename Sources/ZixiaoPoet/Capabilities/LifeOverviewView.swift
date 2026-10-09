import ZixiaoPoetCore
import SwiftUI
import ZixiaoDesign

struct LifeOverviewView: View {
    let ctx: CompositionContext
    @Environment(\.zxTheme) private var theme
    private var epochs: [Epoch] { ctx.lifeEpochs }
    private var title: String { ctx.composition.placement(.epochs)?.label ?? "\(ctx.narrativeLabel)篇章" }
    var body: some View {
        List {
            if let guide = ctx.guide {
                Section {
                    VStack(alignment: .leading, spacing: theme.space.md) {
                        Text("沿\(ctx.narrativeLabel)读懂作品").font(theme.type.title2)
                            .foregroundStyle(theme.color.textPrimary).accessibilityAddTraits(.isHeader)
                        Text(guide.biography).font(theme.type.body).lineSpacing(theme.space.xs)
                            .foregroundStyle(theme.color.textSecondary)
                        Text(guide.chronologyNote).font(theme.type.footnote).lineSpacing(theme.space.xs)
                            .foregroundStyle(theme.color.textSecondary)
                    }.padding(.vertical, theme.space.sm)
                }.listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: theme.space.sm, leading: 0, bottom: theme.space.md, trailing: 0))
            }
            Section {
                ForEach(Array(epochs.enumerated()), id: \.element.id) { index, epoch in
                    NavigationLink { EpochDetailView(ctx: ctx, epoch: epoch) } label: {
                        HStack(alignment: .top, spacing: theme.space.md) {
                            Text(String(format: "%02d", index + 1)).font(theme.type.subhead.monospacedDigit())
                                .foregroundStyle(theme.accent).padding(.top, theme.space.xxs)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: theme.space.xs) {
                                Text(epoch.label).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                                Text(epoch.period(in: ctx.composition.poet)).font(theme.type.caption.monospacedDigit())
                                    .foregroundStyle(theme.color.textSecondary)
                                if let note = ctx.chapterIntroduction(epoch) {
                                    Text(note).font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }.padding(.vertical, theme.space.sm)
                    }
                }
            } header: { ZixiaoDesign.SectionLabel("\(epochs.count) 个导读篇章") }
                .listRowBackground(theme.surface)
            if let guide = ctx.guide {
                Section {
                    NavigationLink { GuideSourcesView(ctx: ctx, guide: guide) } label: {
                        Label("资料与纪年说明", systemImage: "text.book.closed").font(theme.type.body)
                    }
                } footer: {
                    Text("从导读理解处境，再沿关联作品回到原文；纪年中的存疑处以资料说明为准。")
                        .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                }.listRowBackground(theme.surface)
            }
        }.listStyle(.insetGrouped).scrollContentBackground(.hidden).poetReadableWidth(LifeUI.listColumnWidth)
            .background(theme.paper())
            .zxNavigationTitle(title, role: .root)
            .overlay {
                if epochs.isEmpty {
                    if ctx.store.loadError != nil { LifeUI.Failure(retry: { await ctx.store.bootstrap() }) }
                    else { LifeUI.Empty(title: "导读正在整理", systemImage: "text.book.closed") }
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
    @Environment(\.zxTheme) private var theme
    private var chapter: LifeChapter? { ctx.guide?.chapter(epoch) }
    private var counts: [Int: Int] { liveCounts.isEmpty ? ctx.guide?.archiveCounts ?? [:] : liveCounts }
    private var years: [Int] { counts.keys.filter { epoch.contains($0) }.sorted() }
    private var nextEpoch: Epoch? { ctx.lifeEpochs.first { $0.sequence > epoch.sequence } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.xl) {
                LifeUI.Heading(eyebrow: epoch.period(in: ctx.composition.poet), title: epoch.label,
                               introduction: ctx.chapterIntroduction(epoch))
                if let chapter {
                    ForEach(chapter.paragraphs, id: \.self) { paragraph in
                        Text(paragraph).font(theme.type.body).lineSpacing(theme.space.sm).textSelection(.enabled)
                    }
                    if !chapter.milestones.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ZixiaoDesign.SectionLabel("这一章的转折").padding(.bottom, theme.space.sm)
                            ForEach(chapter.milestones) { milestone in
                                if ctx.hasChronicleData {
                                    NavigationLink { ChronicleEventsView(ctx: ctx, year: milestone.year) } label: {
                                        milestoneLabel(milestone, showsDisclosure: true)
                                    }.buttonStyle(.plain)
                                } else {
                                    milestoneLabel(milestone, showsDisclosure: false)
                                }
                                InkDivider()
                            }
                        }
                    }
                    let works = chapter.workIDs.compactMap { ctx.guide?.poem($0) }
                    if !works.isEmpty {
                        VStack(alignment: .leading, spacing: theme.space.sm) {
                            ZixiaoDesign.SectionLabel("把这一章读进作品")
                            ForEach(works) { poem in
                                NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                                    LifeUI.PoemRow(poem: poem, displayTitle: ctx.workTitle(poem))
                                }.buttonStyle(.plain)
                                InkDivider()
                            }
                        }
                    }
                }
                if ctx.hasChronicleData {
                    VStack(alignment: .leading, spacing: theme.space.lg) {
                        ZixiaoDesign.SectionLabel("逐年查阅", trailing: "有记载的年份")
                        if epoch.sequence == ctx.lifeEpochs.first?.sequence, let guide = ctx.guide {
                            Text(guide.chronologyNote).font(theme.type.footnote)
                                .foregroundStyle(theme.color.textSecondary).lineSpacing(theme.space.xs)
                        }
                        if !years.isEmpty {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.space.md, alignment: .leading),
                                                     count: typeSize.isAccessibilitySize ? 1 : 2),
                                      spacing: theme.space.md) {
                                ForEach(years, id: \.self) { year in
                                    NavigationLink { ChronicleEventsView(ctx: ctx, year: year) } label: {
                                        yearTile(year)
                                    }.buttonStyle(.plain)
                                }
                            }
                        } else {
                            NavigationLink {
                                ChronicleList(ctx: ctx, upTo: epoch.yearEnd ?? ctx.composition.poet.death)
                                    .zxNavigationTitle("编年", role: .secondary)
                            } label: {
                                Text("打开编年目录").font(theme.type.body).foregroundStyle(theme.accent)
                            }
                        }
                    }
                }
                if let next = nextEpoch {
                    InkDivider()
                    if let selectChapter {
                        Button { selectChapter(next) } label: { nextChapterLabel(next) }
                            .buttonStyle(.plain)
                    } else {
                        NavigationLink { EpochDetailView(ctx: ctx, epoch: next) } label: { nextChapterLabel(next) }
                            .buttonStyle(.plain)
                    }
                }
                if let guide = ctx.guide {
                    NavigationLink { GuideSourcesView(ctx: ctx, guide: guide, sourceIDs: chapter?.sourceIDs) } label: {
                        Text("本章资料与纪年说明").font(theme.type.footnote).foregroundStyle(theme.accent)
                    }.frame(minHeight: LifeUI.minTapTarget)
                }
            }.padding(.horizontal, theme.space.margin).padding(.vertical, theme.space.xl)
                .poetReadableWidth(LifeUI.textColumnWidth)
        }.background(theme.paper()).foregroundStyle(theme.color.textPrimary)
            .zxNavigationTitle("\(ctx.narrativeLabel)篇章", role: .secondary)
            .task {
                guard ctx.hasChronicleData else { return }
                if let fetched = try? await ctx.store.eventYearCounts(), !Task.isCancelled { liveCounts = fetched }
            }
    }

    /// 编年镜头里的一年: 年号作题, 公元年与事目数作注。卡面走 `zxSurface`, 不自己配色。
    private func yearTile(_ year: Int) -> some View {
        VStack(alignment: .leading, spacing: theme.space.sm) {
            Text(ctx.era.label(year)).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
            Text("\(String(year)) · \(counts[year] ?? 0) 条事目").font(theme.type.caption.monospacedDigit())
                .foregroundStyle(theme.color.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: theme.space.xxxl + theme.space.md, alignment: .leading)
        .padding(theme.space.lg)
        .zxSurface(.e1, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
    }

    private func nextChapterLabel(_ next: Epoch) -> some View {
        VStack(alignment: .leading, spacing: theme.space.sm) {
            Text("下一章").font(theme.type.caption).foregroundStyle(theme.color.textSecondary)
            HStack {
                Text(next.label).font(theme.type.title3)
                Spacer(); Image(systemName: "arrow.right").foregroundStyle(theme.accent)
            }
        }.frame(minHeight: theme.space.xxxl + theme.space.lg).contentShape(Rectangle())
    }

    private func milestoneLabel(_ milestone: LifeMilestone, showsDisclosure: Bool) -> some View {
        VStack(alignment: .leading, spacing: theme.space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(milestone.title).font(theme.type.headline)
                Spacer()
                Text(String(milestone.year)).font(theme.type.caption.monospacedDigit())
                if showsDisclosure { Image(systemName: "chevron.right").font(theme.type.caption) }
            }.foregroundStyle(theme.accent)
            Text(milestone.detail).font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, theme.space.lg).contentShape(Rectangle())
    }
}

struct GuideSourcesView: View {
    let ctx: CompositionContext
    let guide: PoetGuide
    var sourceIDs: [String]? = nil
    @Environment(\.zxTheme) private var theme
    private var sources: [GuideSource] { guide.sources.filter { sourceIDs?.contains($0.id) ?? true } }
    var body: some View {
        List {
            Section {
                Text(guide.chronologyNote).font(theme.type.subhead).lineSpacing(theme.space.xs)
            } header: { ZixiaoDesign.SectionLabel("纪年方式") }
                .listRowBackground(theme.surface)
            Section {
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: theme.space.sm) {
                        if let url = source.url {
                            Link(source.title, destination: url).font(theme.type.headline).foregroundStyle(theme.accent)
                        } else { Text(source.title).font(theme.type.headline) }
                        Text(source.note).font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                    }.padding(.vertical, theme.space.xs)
                }
            } header: { ZixiaoDesign.SectionLabel("资料依据") }
                .listRowBackground(theme.surface)
            if ctx.hasItineraryData {
                Section {
                    Text(ctx.composition.placement(.itinerary)?.fidelity == .approximate
                         ? "Apple 地图提供现代地理底图，古地名与行迹为经资料核对后的约略位置和顺序，不表示精确年代、道路或行政疆界。"
                         : "Apple 地图提供现代地理底图，古地名是本应用叠加的历史注记；连线只表示已整理的主要行程节点，不表示当时道路、完整行程或行政疆界。")
                        .font(theme.type.subhead).lineSpacing(theme.space.xs)
                } header: { ZixiaoDesign.SectionLabel("地图说明") }
                    .listRowBackground(theme.surface)
            }
            Section {
                Text("导览整理于 \(guide.snapshotDate)。导读篇章与所附代表作可离线阅读；更多作品和逐年事目在有资料且网络可用时载入。")
                    .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
            }.listRowBackground(theme.surface)
        }
        .scrollContentBackground(.hidden).background(theme.paper()).foregroundStyle(theme.color.textPrimary)
        .zxNavigationTitle("资料与说明", role: .secondary)
    }
}

extension Epoch {
    func period(in poet: Poet) -> String {
        let start = max(yearStart, poet.birth), end = min(yearEnd ?? poet.death, poet.death)
        return start == end ? "\(String(start)) 年" : "\(String(start)) — \(String(end))"
    }
}
