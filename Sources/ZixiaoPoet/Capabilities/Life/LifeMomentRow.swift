//  LifeMomentRow.swift — 一刻: 年轨上的一个墨点 + 日期与地 + 题 + 按语 + 处境 + 作品 / 墨迹 + 人 + 出处
//
//  年轨: 每行在同一个 x 上画一条全高的发丝线, 行与行之间不留外边距 (间距算在行内的底边),
//  所以一卷的刻连成一条不断的线; 墨点用印色, 年份只在换年时标一次。
//  这里不嵌 NavigationLink: 点作品 / 墨迹 / 年份都交给 `LifeActions`, 由长卷根页统一推入。

import SwiftUI
import ZixiaoDesign

/// 长卷里各行向根页发出的动作。
struct LifeActions {
    let open: (LifeRoute) -> Void
    let openYear: (Int) -> Void
    /// 点作品卡: 作品 id + 转场源 id。
    let openWork: (UUID, String) -> Void
}

/// 长卷的几个固有尺寸 (不是间距 token)。
enum LifeLayout {
    /// 宽屏上长卷的栏宽。
    static let contentWidth: CGFloat = 720
    /// 屏幕前沿给年轨 (拖动跳卷) 留的宽度。
    static let trackInset: CGFloat = 22
    /// 作品卡封面宽。
    static let workCoverWidth: CGFloat = 92
    /// 处境默认显示的行数。
    static let bodyLineLimit = 4
}

struct LifeMomentRow: View {
    let ctx: CompositionContext
    let moment: PoetMoments.Moment
    /// 换年时才标年份。
    let showsYear: Bool
    let model: LifeScrollModel
    let actions: LifeActions
    let namespace: Namespace.ID
    @State private var expanded = false
    @State private var showsSources = false
    /// 这一刻在屏幕中段 (墨点亮成印色)。
    @State private var lit = false
    @Environment(\.zxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 年份一栏的宽, 随字号放大 (四位数字 + 余量)。
    @ScaledMetric(relativeTo: .footnote) private var yearColumn: CGFloat = 38
    /// 墨点一栏的宽。
    @ScaledMetric(relativeTo: .footnote) private var dotColumn: CGFloat = 14

    /// 墨点亮起的探线: 视口这一比例处 (略偏上, 读的位置)。行与行首尾相接, 同一时刻只亮一点。
    nonisolated static let litProbe: CGFloat = 0.45
    /// 进场: 从下沿露出到露出这一比例, 透明度 0.6 → 1、下移 12pt → 0。
    nonisolated static let entranceThreshold: Double = 0.3
    nonisolated static let entranceOffset: CGFloat = 12
    nonisolated static let entranceOpacity: Double = 0.6

    private var railSpacing: CGFloat { theme.space.xs }
    /// 发丝线的 x: 年份栏 + 间距 + 墨点栏的一半。
    private var lineX: CGFloat { yearColumn + railSpacing + dotColumn / 2 }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: railSpacing) {
            yearLabel.frame(width: yearColumn, alignment: .trailing)
            Image(systemName: "circle.fill")
                .font(theme.uiFont(8, relativeTo: .footnote))
                .foregroundStyle(lit ? theme.seal : theme.muted)
                .scaleEffect(lit && !reduceMotion ? 1.25 : 1)
                .animation(theme.motion.adapted(theme.motion.snappy, reduceMotion: reduceMotion), value: lit)
                .padding(theme.space.xxs)
                .background(theme.paper(), in: Circle())
                .frame(width: dotColumn)
                .accessibilityHidden(true)
            entering(content).padding(.leading, theme.space.sm)
        }
        .padding(.bottom, theme.space.xxl)
        .background(alignment: .topLeading) {
            Rectangle().fill(theme.rule).frame(width: 1).frame(maxHeight: .infinity)
                .offset(x: lineX - 0.5)
                .accessibilityHidden(true)
        }
        // 滚动锚点: 行顶一条零高的空条。零高的视图按 `UnitPoint(y: f)` 滚, 正好落在视口 f 处 ——
        // 长卷用它把刻的上沿放到导航栏之下 (`LifeMetrics.momentAnchor`), 不被栏压住。
        .background(alignment: .top) {
            Color.clear.frame(width: 1, height: 0)
                .id(LifeAnchor.moment(moment.id))
                .accessibilityHidden(true)
        }
        .onGeometryChange(for: Bool.self) { geometry in
            let frame = geometry.frame(in: .scrollView)
            guard let viewport = geometry.bounds(of: .scrollView)?.height else { return false }
            let probe = viewport * Self.litProbe
            return frame.minY <= probe && frame.maxY > probe
        } action: { lit = $0 }
    }

    /// 进场: 从下沿露出时由淡与低处升到位, 跟着滚动走 (interactive); 离开上沿不变。减少动态时不动。
    private func entering(_ view: some View) -> some View {
        let reduce = reduceMotion
        return view.scrollTransition(.interactive.threshold(.visible(Self.entranceThreshold)), axis: .vertical) { content, phase in
            let t = reduce ? 0 : max(phase.value, 0)
            return content
                .opacity(1 - (1 - Self.entranceOpacity) * t)
                .offset(y: Self.entranceOffset * t)
        }
    }

    @ViewBuilder private var yearLabel: some View {
        if showsYear {
            Button { actions.openYear(moment.date.year) } label: {
                Text(String(moment.date.year))
                    .font(theme.type.footnote.monospacedDigit())
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: yearColumn, alignment: .trailing)
                    .contentShape(Rectangle().inset(by: -theme.space.sm))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(String(moment.date.year)) 年")
            .accessibilityHint("查看这一年的年谱")
        } else {
            Text(" ").font(theme.type.footnote).accessibilityHidden(true)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: theme.space.sm) {
            Text("\(moment.date.displayLabel) · \(moment.placeLabel)")
                .font(theme.type.footnote)
                .foregroundStyle(theme.color.textSecondary)
            Text(moment.title)
                .font(theme.type.title2)
                .tracking(theme.type.tracking(for: .title2))
                .foregroundStyle(theme.color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(moment.lede)
                .font(theme.type.body)
                .foregroundStyle(theme.color.textPrimary)
                .lineSpacing(theme.space.xs)
                .fixedSize(horizontal: false, vertical: true)
            LifeClampedText(text: moment.body, lineLimit: LifeLayout.bodyLineLimit, expanded: $expanded)
            if let workId = moment.workId { workCard(workId) }
            if let artworkId = moment.artworkId, let artwork = ctx.artworks.first(where: { $0.id == artworkId }) {
                artworkStrip(artwork).padding(.top, theme.space.sm)
            }
            if !moment.allPeople.isEmpty {
                LifeChipFlow(spacing: theme.space.xs) {
                    ForEach(moment.allPeople, id: \.self) { LifePersonChip(name: $0) }
                }
                .padding(.top, theme.space.xs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("此刻在场：\(moment.allPeople.joined(separator: "、"))")
            }
            if !moment.sources.isEmpty { sources }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 作品卡

    private func workCard(_ workId: UUID) -> some View {
        let poem = model.poem(workId)
        let title = poem.map { ctx.workTitle($0) }
        return Button { actions.openWork(workId, moment.id) } label: {
            HStack(alignment: .top, spacing: theme.space.lg) {
                Group {
                    if let poem {
                        ReadingCover(title: ctx.workTitle(poem), author: ctx.composition.poet.name,
                                     genre: ctx.genre(for: poem), width: LifeLayout.workCoverWidth)
                    } else {
                        RoundedRectangle(cornerRadius: theme.radius.sm, style: .continuous)
                            .fill(theme.color.fill)
                            .frame(width: LifeLayout.workCoverWidth, height: LifeLayout.workCoverWidth * 4 / 3)
                            .overlay {
                                if model.resolving.contains(workId) { ProgressView().tint(theme.muted) }
                            }
                    }
                }
                .readingTransitionSource(moment.id, in: namespace)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: theme.space.sm) {
                    if let quote = moment.workQuote {
                        Text("「\(quote)」")
                            .font(theme.bodyFont(17))
                            .foregroundStyle(theme.color.textPrimary)
                            .lineSpacing(theme.space.sm)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let title {
                        Text("《\(title)》").font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                    }
                    Label("读全文", systemImage: "book")
                        .font(theme.type.footnote)
                        .foregroundStyle(theme.color.textSecondary)
                        .padding(.top, theme.space.xs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(theme.space.md)
            .zxSurface(.e1, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title.map { "《\($0)》" }, moment.workQuote].compactMap { $0 }.joined(separator: "，"))
        .accessibilityHint("打开全文阅读")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: 墨迹

    private func artworkStrip(_ artwork: Artwork) -> some View {
        Button { actions.open(.artwork(artwork.id)) } label: {
            VStack(alignment: .leading, spacing: theme.space.sm) {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay { ArtworkThumbnail(asset: artwork.cover) }
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                    .readingTransitionSource(artwork.id, in: namespace)
                HStack(alignment: .firstTextBaseline) {
                    Text(artwork.title).font(theme.type.subhead).foregroundStyle(theme.color.textPrimary)
                    Spacer(minLength: theme.space.sm)
                    Text(artwork.kind).font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(artwork.kind)，\(artwork.title)")
        .accessibilityHint("查看墨迹")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: 出处

    private var sources: some View {
        DisclosureGroup(isExpanded: $showsSources) {
            VStack(alignment: .leading, spacing: theme.space.sm) {
                ForEach(Array(moment.sources.enumerated()), id: \.offset) { _, source in
                    Text("《\(source.book)》\(source.chapter)：「\(source.quote)」")
                        .font(theme.type.footnote)
                        .foregroundStyle(theme.color.textSecondary)
                        .lineSpacing(theme.space.xxs)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, theme.space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("出处 · \(moment.sources.count)")
                .font(theme.type.footnote)
                .foregroundStyle(theme.color.textSecondary)
        }
        .tint(theme.color.textSecondary)
        .padding(.top, theme.space.xs)
    }
}

// MARK: - 小件

/// 处境: 默认收在几行, 截断了才出「展开」。用一份不限行的隐形副本量出全文高度来判断是否截断。
struct LifeClampedText: View {
    let text: String
    let lineLimit: Int
    @Binding var expanded: Bool
    @State private var clampedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @Environment(\.zxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var truncated: Bool { fullHeight > clampedHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.xs) {
            styled(Text(text))
                .lineLimit(expanded ? nil : lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if !expanded { clampedHeight = $0 } }
                .background(alignment: .topLeading) {
                    styled(Text(text))
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                        .accessibilityHidden(true)
                }
            if truncated || expanded {
                Button {
                    withAnimation(theme.motion.adapted(theme.motion.standard, reduceMotion: reduceMotion)) {
                        expanded.toggle()
                    }
                } label: {
                    Text(expanded ? "收起" : "展开")
                        .font(theme.type.footnote.weight(.medium))
                        .foregroundStyle(theme.color.textSecondary)
                        .frame(minHeight: LifeUI.minTapTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func styled(_ text: Text) -> some View {
        text.font(theme.type.callout)
            .foregroundStyle(theme.color.textSecondary)
            .lineSpacing(theme.space.xs)
    }
}

/// 一个人名小签 (`fill` 胶囊)。
struct LifePersonChip: View {
    let name: String
    @Environment(\.zxTheme) private var theme
    var body: some View {
        Text(name)
            .font(theme.type.footnote)
            .foregroundStyle(theme.color.textSecondary)
            .padding(.horizontal, theme.space.sm + theme.space.xxs)
            .padding(.vertical, theme.space.xs)
            .background(theme.color.fill, in: Capsule())
    }
}

/// 自动换行的一排小签。
struct LifeChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
