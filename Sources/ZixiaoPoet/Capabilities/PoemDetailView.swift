import SwiftUI

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
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("poetkit.readingScale") private var readingScale = 1.0
    @AppStorage("poetkit.spaciousReading") private var spaciousReading = true
    @AppStorage("poetkit.readingAppearance") private var readingAppearance: ReadingAppearance = .automatic
    private var theme: Theme { ctx.theme }
    private var usesProseLayout: Bool { poem.form == "wen" || poem.form == "fu" }
    private var genre: String {
        ctx.composition.placement(.corpus)?.genres?.first { $0.id == poem.form }?.label ?? "诗文"
    }
    private var hasAssistance: Bool {
        poem.translation?.isEmpty == false || poem.summary?.isEmpty == false || poem.appreciation?.isEmpty == false
    }
    private var guideChapter: LifeChapter? { ctx.guide?.chapter(containing: poem.id) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 18) {
                    if let journey, let index = journey.index(of: poem) {
                        Text("\(journey.collection.title) · \(index + 1) / \(journey.poems.count)")
                            .font(PoetFont.label).foregroundStyle(theme.accent)
                    }
                    Text(ctx.workTitle(poem)).font(PoetFont.poemTitle).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(ctx.composition.poet.name) · \(genre)")
                        .font(PoetFont.meta).foregroundStyle(theme.secondaryInk)
                }.padding(.top, 28)
                poemText.textSelection(.enabled)
                EditorialRule(theme: theme).padding(.top, 8)
                supplementaryReading
                onwardReading
            }
            .padding(.horizontal, 28).padding(.bottom, 48).poetReadableWidth(640)
        }
        .scrollIndicators(.hidden).foregroundStyle(theme.ink).background(readingAppearance.paper)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
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
                .tint(ctx.userData.isBookmarked(poem) ? theme.seal : theme.accent)
                .disabled(ctx.userData.savingBookmarks.contains(poem.id))
                .accessibilityLabel(ctx.userData.isBookmarked(poem) ? "取消收藏" : "收藏作品")
                .accessibilityValue(ctx.userData.isBookmarked(poem) ? "已收藏" : "未收藏")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("阅读设置", systemImage: "textformat.size") { showingReadingSettings = true }
                    ShareLink(item: "《\(ctx.workTitle(poem))》\n\(ctx.composition.poet.name)\n\n\(poem.content)") {
                        Label("分享作品", systemImage: "square.and.arrow.up")
                    }
                } label: { Label("阅读菜单", systemImage: "ellipsis") }
            }
        }
        .sheet(isPresented: $showingReadingSettings) {
            ReadingSettingsView(sample: poem.lines.first ?? poem.title, usesProseLayout: usesProseLayout,
                                theme: theme, scale: $readingScale, spacious: $spaciousReading,
                                appearance: $readingAppearance)
                .environment(\.colorScheme, systemColorScheme)
        }
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
    private var readingFont: Font {
        Font(PoetFont.serif((usesProseLayout ? 18 : 20) * min(max(readingScale, 1), 1.3)))
    }
    private var poemText: some View {
        VStack(alignment: .leading, spacing: usesProseLayout ? 22 : 14) {
            ForEach(Array(poem.lines.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph).font(readingFont).lineSpacing(spaciousReading ? 10 : 5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var supplementaryReading: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("再读深一层").font(PoetFont.label).foregroundStyle(theme.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            if let chapter = guideChapter {
                NavigationLink { EpochDetailView(ctx: ctx, epoch: chapter.epoch) } label: {
                    Label("\(ctx.narrativeLabel)篇章 · \(chapter.epoch.label)", systemImage: "text.book.closed")
                        .font(PoetFont.entryTitle).frame(minHeight: 48)
                }
                EditorialRule(theme: theme)
            }
            if !occasions.isEmpty {
                DisclosureGroup { occasionNotes.padding(.vertical, 14) } label: {
                    Label("写作线索", systemImage: "calendar").font(PoetFont.entryTitle).frame(minHeight: 48)
                }
                EditorialRule(theme: theme)
            } else if contextFailed {
                Button("写作线索暂未载入，点击重试") { Task { await loadContext() } }
                    .font(PoetFont.meta).frame(minHeight: 44)
            } else if ctx.hasChronicleData {
                Text("年谱尚未关联这篇作品的写作线索。")
                    .font(PoetFont.meta).foregroundStyle(theme.secondaryInk).padding(.vertical, 12)
            }
            if let translation = poem.translation, !translation.isEmpty {
                DisclosureGroup { auxiliaryText(translation.joined(separator: "\n\n")) } label: {
                    Label("白话对照", systemImage: "text.alignleft").font(PoetFont.entryTitle).frame(minHeight: 48)
                }
                EditorialRule(theme: theme)
            }
            if poem.summary?.isEmpty == false || poem.appreciation?.isEmpty == false {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 16) {
                        if let summary = poem.summary, !summary.isEmpty {
                            Text("提要").font(PoetFont.label).foregroundStyle(theme.accent)
                            auxiliaryText(summary)
                        }
                        if let appreciation = poem.appreciation, !appreciation.isEmpty {
                            Text("赏析").font(PoetFont.label).foregroundStyle(theme.accent)
                            auxiliaryText(appreciation)
                        }
                    }.padding(.top, 12)
                } label: {
                    Label("提要与赏析", systemImage: "text.magnifyingglass").font(PoetFont.entryTitle).frame(minHeight: 48)
                }
                EditorialRule(theme: theme)
            }
            if hasAssistance {
                Text("白话、提要与赏析由 AI 辅助生成，供阅读参考。")
                    .font(PoetFont.meta).foregroundStyle(theme.secondaryInk).padding(.top, 10)
            }
        }.tint(theme.accent)
    }
    private func auxiliaryText(_ text: String) -> some View {
        Text(text).textSelection(.enabled).font(PoetFont.body).lineSpacing(8)
            .foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
    }
    private var occasionNotes: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(occasions) { occasion in
                if let event = occasion.poet_events {
                    VStack(alignment: .leading, spacing: 12) {
                        Text([ctx.era.label(event.year), event.poet_stations?.source_name].compactMap { $0 }.joined(separator: " · "))
                            .font(PoetFont.entryTitle)
                        Text(event.narrative).font(PoetFont.body).lineSpacing(7)
                            .foregroundStyle(theme.secondaryInk).lineLimit(5)
                        NavigationLink("回到 \(String(event.year)) 年的年谱", destination: ChronicleEventsView(ctx: ctx, year: event.year))
                            .font(PoetFont.label).frame(minHeight: 44).foregroundStyle(theme.accent)
                        if let epoch = ctx.lifeEpochs.first(where: { $0.contains(event.year) }) {
                            NavigationLink("\(ctx.narrativeLabel)篇章 · \(epoch.label)") { EpochDetailView(ctx: ctx, epoch: epoch) }
                                .font(PoetFont.label).frame(minHeight: 44).foregroundStyle(theme.accent)
                        }
                    }
                }
            }
        }
    }
    @ViewBuilder private var onwardReading: some View {
        if let journey {
            if let next = journey.next(after: poem) {
                NavigationLink { PoemDetailView(ctx: ctx, poem: next, journey: journey) } label: {
                    GlazePanel(theme: theme, glaze: .celadon) {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionLabel(text: "接着读 · \(journey.collection.title)", theme: theme)
                            PoemRow(poem: next, theme: theme, displayTitle: ctx.workTitle(next))
                        }
                    }
                }.buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label("这一组，读到了末篇", systemImage: "checkmark.circle")
                        .font(PoetFont.entryTitle).foregroundStyle(theme.accent)
                    Text("喜欢的句子，可以留在书房里，再读一次。")
                        .font(PoetFont.body).foregroundStyle(theme.secondaryInk)
                }
            }
        } else if let collection = ctx.composition.editorial?.collections.first(where: { $0.works.contains { $0.poemId == poem.id } }) {
            NavigationLink { ReadingCollectionView(ctx: ctx, collection: collection) } label: {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "把这篇放回一组诗文里", theme: theme)
                    ReadingCollectionLabel(collection: collection, theme: theme)
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
