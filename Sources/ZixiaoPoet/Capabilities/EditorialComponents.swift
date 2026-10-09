import ZixiaoPoetCore
//  EditorialComponents.swift — 主题共读: 入口行与共读页
//
//  能力视图本身。
//  字、色、间距全部来自 `@Environment(\.zxTheme)`。

import SwiftUI
import ZixiaoDesign

/// 一组共读的入口行: 图标 + 题目 + 副题 + 篇数。
struct ReadingCollectionLabel: View {
    let collection: ReadingCollection
    var featured = false
    @Environment(\.zxTheme) private var theme

    init(collection: ReadingCollection, featured: Bool = false) {
        self.collection = collection
        self.featured = featured
    }

    var body: some View {
        HStack(alignment: .top, spacing: theme.space.lg) {
            Image(systemName: collection.symbol)
                .font(theme.type.title2).foregroundStyle(theme.color.accent)
                .frame(width: theme.space.xxl + theme.space.xs, height: theme.space.xxl + theme.space.sm)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: theme.space.sm) {
                Text(collection.title).font(featured ? theme.type.title2 : theme.type.headline)
                    .foregroundStyle(theme.color.textPrimary)
                Text(collection.subtitle).font(theme.type.callout)
                    .foregroundStyle(theme.color.textSecondary).lineSpacing(theme.space.xs)
                Text("共读 \(collection.works.count) 篇")
                    .font(theme.type.footnote).foregroundStyle(theme.color.accent)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(theme.type.footnote)
                .foregroundStyle(theme.color.accent).padding(.top, theme.space.sm)
        }
        .padding(.vertical, featured ? theme.space.sm : theme.space.md)
        .contentShape(Rectangle())
    }
}

/// 主题共读页: 导读 → 逐篇按语 + 作品行。正文优先取随包导读, 网络只补缺。
struct ReadingCollectionView: View {
    let ctx: CompositionContext
    let collection: ReadingCollection
    @State private var poems: [Poem] = []
    @State private var loading = true
    @State private var failed = false
    @Environment(\.zxTheme) private var theme
    private var journey: ReadingJourney { ReadingJourney(collection: collection, poems: poems) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.xl) {
                heading
                InkDivider()
                if loading { LoadingStateView(label: "正在准备这组诗文…") }
                else if failed { LoadFailureView(title: "诗文暂未载入", retry: load) }
                else {
                    ForEach(Array(collection.works.enumerated()), id: \.element.id) { index, selection in
                        VStack(alignment: .leading, spacing: theme.space.md) {
                            HStack(alignment: .firstTextBaseline, spacing: theme.space.md) {
                                Text(String(format: "%02d", index + 1))
                                    .font(theme.type.footnote.monospacedDigit().weight(.medium))
                                    .foregroundStyle(theme.color.accent)
                                Text(selection.note).font(theme.type.body).lineSpacing(theme.space.xs + theme.space.xxs)
                                    .foregroundStyle(theme.color.textSecondary)
                            }
                            if let poem = poems.first(where: { $0.id == selection.poemId }) {
                                NavigationLink { PoemDetailView(ctx: ctx, poem: poem, journey: journey) } label: {
                                    PoemRow(poem: poem, displayTitle: ctx.workTitle(poem))
                                        .padding(theme.space.lg)
                                        .zxSurface(.e1, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
                                }.buttonStyle(.plain)
                            } else {
                                Label("这篇正文暂不可用", systemImage: "book.closed")
                                    .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                            }
                        }
                    }
                    if poems.count < collection.works.count {
                        Button("重新载入缺少的正文") { Task { await load() } }
                            .font(theme.type.subhead).frame(minHeight: PoetLayout.minHitTarget)
                    }
                }
                Text("选篇与导读为编辑整理，原文保留所收录底本。")
                    .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
            }
            .padding(.horizontal, theme.space.margin).padding(.vertical, theme.space.xl)
            .poetReadableWidth(640)
        }
        .background(theme.paper()).foregroundStyle(theme.color.textPrimary).tint(theme.color.accent)
        .zxNavigationTitle("主题共读", role: .secondary)
        .task { await load() }.refreshable { await load() }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            ZixiaoDesign.SectionLabel("主题共读 · \(collection.works.count) 篇")
            Text(collection.title).font(theme.type.title1).tracking(theme.type.tracking(for: .title1))
                .foregroundStyle(theme.color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(collection.introduction).font(theme.type.body).lineSpacing(theme.space.sm)
                .foregroundStyle(theme.color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        let ids = collection.works.map(\.poemId)
        let bundled = ctx.guide?.poems(ids) ?? []
        if poems.isEmpty { poems = bundled }
        loading = poems.isEmpty
        failed = false
        do {
            let fetched = try await ctx.store.poems(ids: ids)
            guard !Task.isCancelled else { return }
            let remote = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            let local = Dictionary(uniqueKeysWithValues: bundled.map { ($0.id, $0) })
            poems = ids.compactMap { local[$0] ?? remote[$0] }
        } catch {
            if !Task.isCancelled { failed = poems.isEmpty }
        }
        loading = false
    }
}
