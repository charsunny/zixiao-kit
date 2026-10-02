//  CollectionReadingView.swift — 一组选读: 画屏题头 → 旨与导读 →「从头读」→ 逐篇 (封面 + 题 + 按语)
//
//  正文先取随包导读里的 (离线也有), 网络只补缺; 推入读本时带上这一组 (`ReadingJourney`),
//  读本末尾能「接着读」下一篇。

import SwiftUI
import ZixiaoDesign

struct CollectionReadingView: View {
    let ctx: CompositionContext
    let selection: CorpusSelection
    @State private var poems: [Poem] = []
    @State private var loading = true
    @State private var failed = false
    @Environment(\.zxTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var thumbWidth = 52.0

    private var journey: ReadingJourney { ReadingJourney(collection: selection.readingCollection, poems: poems) }
    private var indexed: [UUID: Poem] { Dictionary(poems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.xl) {
                ScreenArtView(selection.art, aspect: 2, verse: nil)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
                    .accessibilityHidden(true)
                heading
                if let first = poems.first {
                    NavigationLink {
                        AnyView(PoemDetailView(ctx: ctx, poem: first, journey: journey))
                    } label: {
                        Label("从头读", systemImage: "book")
                            .font(theme.type.headline)
                            .foregroundStyle(theme.color.accentOn)
                            .frame(maxWidth: .infinity, minHeight: PoetLayout.minHitTarget)
                    }
                    .poetActionStyle(prominent: true)
                    .accessibilityHint("打开第一篇：\(ctx.workTitle(first))")
                }
                works
                Text("选篇与按语为编辑整理，原文保留所收录底本。")
                    .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
            }
            .padding(.horizontal, theme.space.margin).padding(.vertical, theme.space.xl)
            .poetReadableWidth(640)
        }
        .background(theme.paper()).foregroundStyle(theme.color.textPrimary).tint(theme.color.accent)
        .zxNavigationTitle(selection.title, role: .secondary)
        .task { await load() }
        .refreshable { await load() }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            Text(selection.title)
                .font(theme.displayFont(30, relativeTo: .title))
                .foregroundStyle(theme.color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(selection.thesis)
                .font(theme.type.headline).foregroundStyle(theme.color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(selection.intro)
                .font(theme.bodyFont(17, relativeTo: .body)).lineSpacing(theme.space.sm)
                .foregroundStyle(theme.color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("共 \(selection.entries.count) 篇")
                .font(theme.type.footnote.monospacedDigit()).foregroundStyle(theme.color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var works: some View {
        if loading && poems.isEmpty {
            LoadingStateView(label: "正在准备这组诗文…")
        } else if failed && poems.isEmpty {
            LoadFailureView(title: "诗文暂未载入", retry: load)
        } else {
            let indexed = indexed
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(selection.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { InkDivider() }
                    if let poem = indexed[entry.workID] {
                        NavigationLink {
                            AnyView(PoemDetailView(ctx: ctx, poem: poem, journey: journey))
                        } label: {
                            CollectionWorkRow(ctx: ctx, poem: poem, note: entry.note, ordinal: index + 1,
                                              thumbWidth: thumbWidth)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Label("这篇正文暂不可用", systemImage: "book.closed")
                            .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                            .frame(minHeight: PoetLayout.minHitTarget)
                    }
                }
            }
            if poems.count < selection.entries.count && !loading {
                Button("重新载入缺少的正文") { Task { await load() } }
                    .font(theme.type.subhead).frame(minHeight: PoetLayout.minHitTarget)
            }
        }
    }

    private func load() async {
        let ids = selection.workIDs
        let bundled = ctx.guide?.poems(ids) ?? []
        if poems.isEmpty { poems = bundled }
        loading = true
        failed = false
        defer { loading = false }
        do {
            let fetched = try await ctx.store.poems(ids: ids)
            guard !Task.isCancelled else { return }
            let remote = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let local = Dictionary(bundled.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            poems = ids.compactMap { local[$0] ?? remote[$0] }
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

/// 合集里的一篇: 小封面 + 序号与题 + 编者按语 (没有按语时给首句)。
struct CollectionWorkRow: View {
    let ctx: CompositionContext
    let poem: Poem
    let note: String?
    let ordinal: Int
    let thumbWidth: CGFloat
    @Environment(\.zxTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: theme.space.lg) {
            ReadingCover(title: ctx.workTitle(poem), author: ctx.composition.poet.name,
                         genre: ctx.genre(for: poem), width: thumbWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: theme.space.xs) {
                Text(String(format: "%02d", ordinal))
                    .font(theme.type.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(theme.color.textSecondary)
                Text(ctx.workTitle(poem)).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(note ?? poem.firstLine)
                    .font(theme.type.callout).foregroundStyle(theme.color.textSecondary)
                    .lineSpacing(theme.space.xxs)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(theme.type.caption.weight(.semibold)).foregroundStyle(theme.color.textTertiary)
                .padding(.top, theme.space.lg)
                .accessibilityHidden(true)
        }
        .padding(.vertical, theme.space.lg)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(ordinal) 篇，\(ctx.workTitle(poem))。\(note ?? poem.firstLine)")
    }
}
