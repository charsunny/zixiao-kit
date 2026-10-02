import SwiftUI
import ZixiaoDesign

struct PoemDetailView: View {
    let ctx: CompositionContext
    let poem: Poem
    var journey: ReadingJourney? = nil
    @State private var occasions: [Occasion] = []
    @State private var loaded = false
    @State private var bookmarkFailed = false
    @State private var contextFailed = false
    @State private var bookmarkFeedback = 0
    @State private var showingReadingSettings = false
    /// 竖排区可用的高度 (页面可视区), 决定一列排几个字。
    @State private var viewportHeight: CGFloat = 0
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// App 的主题; 读本按纸色档位在它上面派生 (`theme`)。
    @Environment(\.zxTheme) private var appTheme
    @AppStorage("poetkit.readingScale") private var readingScale = 1.0
    @AppStorage("poetkit.spaciousReading") private var spaciousReading = true
    @AppStorage("poetkit.readingAppearance") private var readingAppearance: ReadingAppearance = .automatic
    @AppStorage("poetkit.readingOrientation") private var readingOrientation: ReadingOrientation = .horizontal
    /// 读本用的主题: 夜读时是同一身份的深色解析, 其余即 App 主题。整页 (含子视图) 经 `.zxTheme` 注入它。
    private var theme: ZXTheme { readingAppearance.theme(from: appTheme) }
    private var usesProseLayout: Bool { poem.form == "wen" || poem.form == "fu" }
    private var genre: String {
        ctx.composition.placement(.corpus)?.genres?.first { $0.id == poem.form }?.label ?? "诗文"
    }
    private var hasAssistance: Bool {
        poem.translation?.isEmpty == false || poem.summary?.isEmpty == false || poem.appreciation?.isEmpty == false
    }
    private var guideChapter: LifeChapter? { ctx.guide?.chapter(containing: poem.id) }
    /// 读本栏宽 (比通用栏宽窄: 一行诗不宜太长)。
    private static let columnWidth: CGFloat = 640
    /// 「再读深一层」里各条目的行高 (点按区)。
    private static let entryHeight: CGFloat = 48

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.xxl) {
                VStack(alignment: .leading, spacing: theme.space.lg) {
                    if let journey, let index = journey.index(of: poem) {
                        Text("\(journey.collection.title) · \(index + 1) / \(journey.poems.count)")
                            .font(theme.type.footnote.weight(.medium)).foregroundStyle(theme.color.accent)
                    }
                    Text(ctx.workTitle(poem)).font(theme.type.display(30, relativeTo: .largeTitle))
                        .tracking(theme.type.tracking(for: .display))
                        .foregroundStyle(theme.color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: theme.space.xxs) {
                        Text("\(ctx.composition.poet.name) · \(genre)")
                        // 文的出处:「细体裁 · 书名 章名」。诗词没有这些字段, 不显示。
                        if let source = poem.sourceLine {
                            Text(source).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                }.padding(.top, theme.space.xl + theme.space.xs)
                if readingOrientation == .vertical {
                    verticalText
                } else {
                    poemText.textSelection(.enabled)
                }
                InkDivider().padding(.top, theme.space.sm)
                // 下半页: 此时 → 同年作品 → 相关墨迹 → 再读深一层 → 接着读 / 合集。
                ReaderLifeSections(ctx: ctx, poem: poem)
                supplementaryReading
                onwardReading
            }
            .padding(.horizontal, theme.space.xl + theme.space.xs).padding(.bottom, theme.space.xxxl)
            .poetReadableWidth(Self.columnWidth)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .scrollIndicators(.hidden).foregroundStyle(theme.color.textPrimary)
        .background { ReadingPaper(appearance: readingAppearance).ignoresSafeArea() }
        .zxNavigationTitle("", role: .secondary)
        .toolbar(.hidden, for: .tabBar)
        .toolbarColorScheme(readingAppearance.colorScheme(following: systemColorScheme), for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        do { try await ctx.userData.toggleBookmark(poem); bookmarkFeedback += 1 }
                        catch { bookmarkFailed = true }
                    }
                } label: {
                    Image(systemName: ctx.userData.isBookmarked(poem) ? "bookmark.fill" : "bookmark")
                        .symbolEffect(.bounce, options: .speed(1.5), value: reduceMotion ? 0 : bookmarkFeedback)
                }
                .tint(ctx.userData.isBookmarked(poem) ? theme.color.seal : theme.color.accent)
                .disabled(ctx.userData.savingBookmarks.contains(poem.id))
                .accessibilityLabel(ctx.userData.isBookmarked(poem) ? "取消收藏" : "收藏作品")
                .accessibilityValue(ctx.userData.isBookmarked(poem) ? "已收藏" : "未收藏")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("阅读设置", systemImage: "textformat.size") { showingReadingSettings = true }
                    Button(readingOrientation == .vertical ? "改为横排" : "改为竖排",
                           systemImage: readingOrientation == .vertical ? "text.alignleft" : "character.textbox") {
                        readingOrientation = readingOrientation == .vertical ? .horizontal : .vertical
                    }
                    ShareLink(item: "《\(ctx.workTitle(poem))》\n\(ctx.composition.poet.name)\n\n\(poem.content)") {
                        Label("分享作品", systemImage: "square.and.arrow.up")
                    }
                } label: { Label("阅读菜单", systemImage: "ellipsis") }
            }
        }
        .sheet(isPresented: $showingReadingSettings) {
            ReadingSettingsView(sample: poem.lines.first ?? poem.title, usesProseLayout: usesProseLayout,
                                scale: $readingScale, spacious: $spaciousReading,
                                appearance: $readingAppearance, orientation: $readingOrientation)
                .environment(\.colorScheme, systemColorScheme)
                .zxTheme(appTheme)
        }
        .tint(theme.color.accent)
        .zxTheme(theme)
        .environment(\.colorScheme, readingAppearance.colorScheme(following: systemColorScheme))
        .sensoryFeedback(.selection, trigger: bookmarkFeedback)
        .alert("收藏未能同步", isPresented: $bookmarkFailed) {
            Button("知道了", role: .cancel) { }
        } message: { Text("已恢复之前的收藏状态，请检查网络后重试。") }
        .task {
            guard !loaded else { return }
            loaded = true
            async let context: Void = loadContext()
            await ctx.userData.markRead(poem)
            await context
        }
    }

    // MARK: 正文

    private var horizontalSize: CGFloat {
        ReadingMetrics.size(base: ReadingMetrics.horizontalBase(prose: usesProseLayout), scale: readingScale)
    }
    private var poemText: some View {
        VStack(alignment: .leading, spacing: usesProseLayout ? theme.space.margin : theme.space.md) {
            ForEach(Array(poem.lines.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph).font(theme.bodyFont(horizontalSize, relativeTo: .body))
                    .lineSpacing(spaciousReading ? theme.space.sm + theme.space.xxs : theme.space.xs)
                    .foregroundStyle(theme.ink())
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 竖排: 字从上到下、列从右到左。诗词一句一列 (按句读切开, 不在列内回绕); 文赋一段起一列,
    /// 列高按页面可视区截断后在列内回绕。宽于屏幕时横向滑动, 起点在最右。
    private var verticalText: some View {
        let size = ReadingMetrics.size(base: ReadingMetrics.verticalBase, scale: readingScale)
        let glyphGap = size * ReadingMetrics.glyphGapRatio
        let text = usesProseLayout ? poem.lines.joined(separator: "\n") : ReadingMetrics.verseColumns(poem.lines)
        return ScrollView(.horizontal, showsIndicators: false) {
            VerticalText(text, font: theme.bodyFont(size, relativeTo: nil), color: theme.ink(),
                         charSpacing: glyphGap, columnSpacing: size * ReadingMetrics.columnGapRatio)
                .frame(height: usesProseLayout ? proseColumnHeight(size: size, gap: glyphGap) : nil, alignment: .top)
                .padding(.vertical, theme.space.sm)
        }
        .defaultScrollAnchor(.trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel(poem.content)
    }

    /// 文赋竖排的列高: 页面可视区的六成 (留出标题与工具栏), 至少 8 字。
    private func proseColumnHeight(size: CGFloat, gap: CGFloat) -> CGFloat {
        let cell = size * ReadingMetrics.cellHeightRatio + gap
        let fit = max(8, Int((viewportHeight * 0.6) / cell))
        return CGFloat(fit) * cell
    }

    // MARK: 再读深一层

    private var supplementaryReading: some View {
        VStack(alignment: .leading, spacing: theme.space.sm) {
            Text("再读深一层").font(theme.type.footnote.weight(.medium)).foregroundStyle(theme.color.textSecondary)
                .accessibilityAddTraits(.isHeader)
            if let chapter = guideChapter {
                NavigationLink { EpochDetailView(ctx: ctx, epoch: chapter.epoch) } label: {
                    Label("\(ctx.narrativeLabel)篇章 · \(chapter.epoch.label)", systemImage: "text.book.closed")
                        .font(theme.type.headline).frame(minHeight: Self.entryHeight)
                }
                InkDivider()
            }
            if !occasions.isEmpty {
                DisclosureGroup { occasionNotes.padding(.vertical, theme.space.md) } label: {
                    Label("写作线索", systemImage: "calendar").font(theme.type.headline).frame(minHeight: Self.entryHeight)
                }
                InkDivider()
            } else if contextFailed {
                Button("写作线索暂未载入，点击重试") { Task { await loadContext() } }
                    .font(theme.type.footnote).frame(minHeight: PoetLayout.minHitTarget)
            } else if ctx.hasChronicleData {
                Text("年谱尚未关联这篇作品的写作线索。")
                    .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary).padding(.vertical, theme.space.md)
            }
            if let translation = poem.translation, !translation.isEmpty {
                DisclosureGroup { auxiliaryText(translation.joined(separator: "\n\n")) } label: {
                    Label("白话对照", systemImage: "text.alignleft").font(theme.type.headline).frame(minHeight: Self.entryHeight)
                }
                InkDivider()
            }
            if poem.summary?.isEmpty == false || poem.appreciation?.isEmpty == false {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: theme.space.lg) {
                        if let summary = poem.summary, !summary.isEmpty {
                            Text("提要").font(theme.type.footnote.weight(.medium)).foregroundStyle(theme.color.accent)
                            auxiliaryText(summary)
                        }
                        if let appreciation = poem.appreciation, !appreciation.isEmpty {
                            Text("赏析").font(theme.type.footnote.weight(.medium)).foregroundStyle(theme.color.accent)
                            auxiliaryText(appreciation)
                        }
                    }.padding(.top, theme.space.md)
                } label: {
                    Label("提要与赏析", systemImage: "text.magnifyingglass").font(theme.type.headline).frame(minHeight: Self.entryHeight)
                }
                InkDivider()
            }
            if hasAssistance {
                Text("白话、提要与赏析由 AI 辅助生成，供阅读参考。")
                    .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary).padding(.top, theme.space.sm)
            }
        }.tint(theme.color.accent)
    }
    private func auxiliaryText(_ text: String) -> some View {
        Text(text).textSelection(.enabled).font(theme.type.body).lineSpacing(theme.space.sm)
            .foregroundStyle(theme.color.textSecondary).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, theme.space.sm)
    }
    private var occasionNotes: some View {
        VStack(alignment: .leading, spacing: theme.space.xl) {
            ForEach(occasions) { occasion in
                if let event = occasion.poet_events {
                    VStack(alignment: .leading, spacing: theme.space.md) {
                        Text([ctx.era.label(event.year), event.poet_stations?.source_name].compactMap { $0 }.joined(separator: " · "))
                            .font(theme.type.headline)
                        Text(event.narrative).font(theme.type.body).lineSpacing(theme.space.sm)
                            .foregroundStyle(theme.color.textSecondary).lineLimit(5)
                        NavigationLink("回到 \(String(event.year)) 年的年谱", destination: ChronicleEventsView(ctx: ctx, year: event.year))
                            .font(theme.type.footnote.weight(.medium)).frame(minHeight: PoetLayout.minHitTarget)
                            .foregroundStyle(theme.color.accent)
                        if let epoch = ctx.lifeEpochs.first(where: { $0.contains(event.year) }) {
                            NavigationLink("\(ctx.narrativeLabel)篇章 · \(epoch.label)") { EpochDetailView(ctx: ctx, epoch: epoch) }
                                .font(theme.type.footnote.weight(.medium)).frame(minHeight: PoetLayout.minHitTarget)
                                .foregroundStyle(theme.color.accent)
                        }
                    }
                }
            }
        }
    }

    // MARK: 接着读

    @ViewBuilder private var onwardReading: some View {
        if let journey {
            if let next = journey.next(after: poem) {
                NavigationLink { PoemDetailView(ctx: ctx, poem: next, journey: journey) } label: {
                    ZixiaoDesign.GlazePanel(glaze: .wash) {
                        VStack(alignment: .leading, spacing: theme.space.md) {
                            ZixiaoDesign.SectionLabel("接着读 · \(journey.collection.title)")
                            PoemRow(poem: next, displayTitle: ctx.workTitle(next))
                        }
                    }
                }.buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: theme.space.md) {
                    Label("这一组，读到了末篇", systemImage: "checkmark.circle")
                        .font(theme.type.headline).foregroundStyle(theme.color.accent)
                    Text("喜欢的句子，可以留在书房里，再读一次。")
                        .font(theme.type.body).foregroundStyle(theme.color.textSecondary)
                }
            }
        } else if let collection = ctx.composition.editorial?.collections.first(where: { $0.works.contains { $0.poemId == poem.id } }) {
            NavigationLink { ReadingCollectionView(ctx: ctx, collection: collection) } label: {
                VStack(alignment: .leading, spacing: theme.space.md) {
                    ZixiaoDesign.SectionLabel("把这篇放回一组诗文里")
                    ReadingCollectionLabel(collection: collection)
                }
            }.buttonStyle(.plain)
        }
    }
    private func loadContext() async {
        contextFailed = false
        guard ctx.hasChronicleData else { return }
        do {
            let fetched = try await ctx.store.occasions(of: poem)
            guard !Task.isCancelled else { return }
            occasions = fetched.filter { $0.poet_events != nil }
        } catch { if !Task.isCancelled { contextFailed = true } }
    }
}
