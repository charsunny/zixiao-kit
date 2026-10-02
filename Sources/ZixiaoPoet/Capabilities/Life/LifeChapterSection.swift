//  LifeChapterSection.swift — 一卷: 封面 → (这一卷) → 刻 → 卷末
//
//  桩卷 (还没编好刻) 不空着: 封面照画, 下面一行「本卷整理中」, 再用导读同一分期的导语与转折
//  (milestones) 垫一份安静的目录。卷末对两种卷一样: 本卷作品书架 (导读的 workIDs) + 此时身边的人。

import SwiftUI
import ZixiaoDesign

/// 长卷的版面量度: 由根页按视口算好往下传。
struct LifeMetrics: Equatable {
    /// 卷封面顶端的出血带 (= 导航栏连状态栏的高): 只有画, 字不进来。
    var coverBleed: CGFloat
    /// 卷封面出血带以下的高 (约屏高的 3/4)。
    var coverHeight: CGFloat
    /// 滚动视图的整高 (忽略顶端安全区后约等于屏高)。
    var viewport: CGFloat
    /// 一刻滚到顶时, 刻的上沿离屏顶多远 (让出导航栏)。
    var readingInset: CGFloat
    /// 正文栏前沿的内边距 (窄屏要让出年轨)。
    var leadingInset: CGFloat
    var trailingInset: CGFloat

    /// 滚到一刻用的锚点: 刻顶的零高锚落在视口 `readingInset` 处。
    var momentAnchor: UnitPoint {
        UnitPoint(x: 0, y: viewport > 0 ? min(readingInset / viewport, 1) : 0)
    }
}

struct LifeChapterSection: View {
    let ctx: CompositionContext
    let chapter: PoetMoments.Chapter
    /// 在长卷里的位置 (1 起)。
    let position: Int
    let metrics: LifeMetrics
    let model: LifeScrollModel
    let actions: LifeActions
    let namespace: Namespace.ID
    /// 长卷的第一卷 (封面在顶端时伸进导航栏下)。
    let isFirst: Bool
    /// 封面在长卷内容坐标里的位置 (吸附用)。
    let onCoverFrame: (CGRect) -> Void
    @Environment(\.zxTheme) private var theme

    private var guideChapter: LifeChapter? { ctx.guide?.chapters.first { $0.id == chapter.epochSequence } }
    private var shelf: [Poem] { guideChapter.flatMap { ctx.guide?.poems($0.workIDs) } ?? [] }
    private var networkAvailable: Bool { ctx.hasNetworkData }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LifeChapterCover(chapter: chapter, position: position, metrics: metrics, isFirst: isFirst)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(LifeScrollView.contentSpace)) } action: {
                    onCoverFrame($0)
                }
            VStack(alignment: .leading, spacing: 0) {
                if chapter.isStub { stub } else { written }
                coda
            }
            .padding(.leading, metrics.leadingInset)
            .padding(.trailing, metrics.trailingInset)
            .padding(.top, theme.space.xl)
            .padding(.bottom, theme.space.xxxl)
        }
    }

    // MARK: 已编好的卷

    @ViewBuilder private var written: some View {
        if let overview = chapter.overview {
            Text(overview)
                .font(theme.type.body)
                .foregroundStyle(theme.color.textSecondary)
                .lineSpacing(theme.space.sm)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, theme.space.xxl)
        }
        let moments = chapter.moments
        ForEach(Array(moments.enumerated()), id: \.element.id) { index, moment in
            LifeMomentRow(ctx: ctx, moment: moment,
                          showsYear: index == 0 || moments[index - 1].date.year != moment.date.year,
                          model: model, actions: actions, namespace: namespace)
        }
    }

    // MARK: 桩卷

    @ViewBuilder private var stub: some View {
        Text("本卷整理中")
            .font(theme.type.footnote)
            .foregroundStyle(theme.muted)
            .padding(.bottom, theme.space.lg)
        if let introduction = stubIntroduction {
            Text(introduction)
                .font(theme.type.body)
                .foregroundStyle(theme.color.textSecondary)
                .lineSpacing(theme.space.sm)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, theme.space.xl)
        }
        if let milestones = guideChapter?.milestones, !milestones.isEmpty {
            VStack(alignment: .leading, spacing: theme.space.lg) {
                ForEach(milestones) { milestone in
                    HStack(alignment: .firstTextBaseline, spacing: theme.space.md) {
                        yearButton(milestone.year)
                        VStack(alignment: .leading, spacing: theme.space.xs) {
                            Text(milestone.title)
                                .font(theme.type.subhead.weight(.medium))
                                .foregroundStyle(theme.color.textPrimary)
                            Text(milestone.detail)
                                .font(theme.type.footnote)
                                .foregroundStyle(theme.color.textSecondary)
                                .lineSpacing(theme.space.xxs)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.bottom, theme.space.xxl)
        }
    }

    /// 桩卷的导语: 导读的 introduction 常与卷旨同句 (封面上已有), 同句时改用导读的第一段。
    private var stubIntroduction: String? {
        let normalize = { (text: String) in text.filter { !$0.isPunctuation && !$0.isWhitespace } }
        let candidates = [guideChapter?.introduction, guideChapter?.paragraphs.first, chapter.overview]
        return candidates.compactMap { $0 }.first { !$0.isEmpty && normalize($0) != normalize(chapter.thesis) }
    }

    @ViewBuilder private func yearButton(_ year: Int) -> some View {
        let label = Text(String(year)).font(theme.type.footnote.monospacedDigit()).foregroundStyle(theme.muted)
        if ctx.hasChronicleData {
            Button { actions.openYear(year) } label: { label.contentShape(Rectangle().inset(by: -theme.space.sm)) }
                .buttonStyle(.plain)
                .accessibilityLabel("\(String(year)) 年")
                .accessibilityHint("查看这一年的年谱")
        } else {
            label
        }
    }

    // MARK: 卷末

    @ViewBuilder private var coda: some View {
        let people = chapter.people
        if !shelf.isEmpty || !people.isEmpty {
            VStack(alignment: .leading, spacing: theme.space.xl) {
                InkDivider()
                if !shelf.isEmpty {
                    VStack(alignment: .leading, spacing: theme.space.md) {
                        ZixiaoDesign.SectionLabel("此卷作品")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: theme.space.lg) {
                                ForEach(shelf) { poem in shelfItem(poem) }
                            }
                        }
                        .scrollClipDisabled()
                    }
                }
                if !people.isEmpty {
                    VStack(alignment: .leading, spacing: theme.space.md) {
                        ZixiaoDesign.SectionLabel("此时身边的人")
                        LifeChipFlow(spacing: theme.space.xs) {
                            ForEach(people, id: \.self) { name in
                                if networkAvailable {
                                    Button { actions.open(.network) } label: { LifePersonChip(name: name) }
                                        .buttonStyle(.plain)
                                        .accessibilityHint("打开交游")
                                } else {
                                    LifePersonChip(name: name)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func shelfItem(_ poem: Poem) -> some View {
        let source = "shelf-\(chapter.epochSequence)-\(poem.id.uuidString)"
        let title = ctx.workTitle(poem)
        return Button { actions.open(.poem(poem, source: source)) } label: {
            VStack(alignment: .leading, spacing: theme.space.sm) {
                ReadingCover(title: title, author: ctx.composition.poet.name,
                             genre: ctx.genre(for: poem), width: LifeLayout.workCoverWidth)
                    .readingTransitionSource(source, in: namespace)
                Text(title)
                    .font(theme.type.footnote)
                    .foregroundStyle(theme.color.textSecondary)
                    .lineLimit(2)
                    .frame(width: LifeLayout.workCoverWidth, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("《\(title)》")
        .accessibilityHint("打开全文阅读")
        .accessibilityAddTraits(.isButton)
    }
}
