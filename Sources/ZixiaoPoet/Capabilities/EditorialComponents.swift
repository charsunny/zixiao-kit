//  EditorialComponents.swift — 编辑版式的小件
//
//  过渡 shim (M1): `EditorialHeading` / `EditorialRule` 保留 PoetKit 的调用形状,
//  分隔线由 `ZixiaoDesign.InkDivider` 画, 字由 ZXTheme 解析。M2 换成 kit 组件后删。
//  `ReadingCollectionLabel` / `ReadingCollectionView` 是能力视图本身, 不是 shim。

import SwiftUI
import ZixiaoDesign

/// Open page typography, reserved panels, and compact indexes establish different reading rhythms.
@available(*, deprecated, message: "M2: use theme.type + ZixiaoDesign.SectionLabel")
struct EditorialHeading: View {
    let eyebrow: String
    let title: String
    var introduction: String? = nil
    let theme: Theme
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow).font(PoetFont.label).foregroundStyle(theme.accent)
            Text(title).font(PoetFont.display).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let introduction {
                Text(introduction).font(PoetFont.body).lineSpacing(7)
                    .foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

@available(*, deprecated, message: "M2: use ZixiaoDesign.InkDivider")
struct EditorialRule: View {
    let theme: Theme
    var body: some View {
        InkDivider()
    }
}

struct ReadingCollectionLabel: View {
    let collection: ReadingCollection
    let theme: Theme
    var featured = false
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: collection.symbol)
                .font(.title2).foregroundStyle(theme.accent)
                .frame(width: 36, height: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(collection.title).font(featured ? PoetFont.cardTitle : PoetFont.entryTitle)
                    .foregroundStyle(theme.ink)
                Text(collection.subtitle).font(PoetFont.callout)
                    .foregroundStyle(theme.secondaryInk).lineSpacing(4)
                Text("共读 \(collection.works.count) 篇")
                    .font(PoetFont.meta).foregroundStyle(theme.accent)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.footnote)
                .foregroundStyle(theme.accent).padding(.top, 10)
        }
        .padding(.vertical, featured ? 8 : 14)
        .contentShape(Rectangle())
    }
}

struct ReadingCollectionView: View {
    let ctx: CompositionContext
    let collection: ReadingCollection
    @State private var poems: [Poem] = []
    @State private var loading = true
    @State private var failed = false
    private var theme: Theme { ctx.theme }
    private var journey: ReadingJourney { ReadingJourney(collection: collection, poems: poems) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                EditorialHeading(eyebrow: "主题共读 · \(collection.works.count) 篇", title: collection.title,
                                 introduction: collection.introduction, theme: theme)
                EditorialRule(theme: theme)
                if loading { LoadingStateView(label: "正在准备这组诗文…") }
                else if failed { LoadFailureView(title: "诗文暂未载入", retry: load) }
                else {
                    ForEach(Array(collection.works.enumerated()), id: \.element.id) { index, selection in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Text(String(format: "%02d", index + 1)).font(PoetFont.label.monospacedDigit())
                                    .foregroundStyle(theme.accent)
                                Text(selection.note).font(PoetFont.body).lineSpacing(6)
                                    .foregroundStyle(theme.secondaryInk)
                            }
                            if let poem = poems.first(where: { $0.id == selection.poemId }) {
                                NavigationLink { PoemDetailView(ctx: ctx, poem: poem, journey: journey) } label: {
                                    PoemRow(poem: poem, theme: theme, displayTitle: ctx.workTitle(poem))
                                        .padding(18).background(theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }.buttonStyle(.plain)
                            } else {
                                Label("这篇正文暂不可用", systemImage: "book.closed")
                                    .font(PoetFont.meta).foregroundStyle(theme.secondaryInk)
                            }
                        }
                    }
                    if poems.count < collection.works.count {
                        Button("重新载入缺少的正文") { Task { await load() } }.frame(minHeight: 44)
                    }
                }
                Text("选篇与导读为编辑整理，原文保留所收录底本。")
                    .font(PoetFont.meta).foregroundStyle(theme.secondaryInk)
            }.padding(.horizontal, Metric.gutter).padding(.vertical, 24).poetReadableWidth(640)
        }
        .background(theme.paper).foregroundStyle(theme.ink)
        .navigationTitle("主题共读").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
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
