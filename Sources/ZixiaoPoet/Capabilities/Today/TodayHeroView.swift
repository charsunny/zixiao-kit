import ZixiaoPoetCore
//  TodayHeroView.swift — 今日一刻: 今日页唯一的主角
//
//  画屏 (本刻所在地的山水, 4:3; 有墨迹的刻用真迹, 16:9) 上只放两样: 左上一行小字 (几年前 / 在哪) 与
//  右侧竖排的作品题 —— 整页唯一的 display 字。引句、处境、两个动作在画下的纸上, 随动态字体自由长高。
//  画是装饰 (读屏跳过), 画块整体念一句摘要 (日子、地点、题)。

import SwiftUI
import ZixiaoDesign

struct TodayHeroView: View {
    let ctx: CompositionContext
    let pick: TodayPick
    /// 所看那一天的农历年 (算「N 年前」)。
    let referenceYear: Int
    /// 看的是不是今天 (否则写「这一天」)。
    let isToday: Bool
    /// 同一农历日另有几条年谱记载 (nil = 不知道 / 不显示)。
    let otherCount: Int?
    let namespace: Namespace.ID
    /// 「读这一篇」正在取作品。
    let isOpeningWork: Bool
    let read: () -> Void
    /// 「看这一天」; nil 不显示。
    let seeDay: (() -> Void)?
    let showOthers: () -> Void

    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    private var artwork: Artwork? {
        pick.artworkID.flatMap { id in ctx.artworks.first { $0.id == id } }
    }
    private var artworkImage: UIImage? { artwork.flatMap { ArtworkImages.image($0.cover, resources: ctx.resources) } }

    /// 左上两行。
    private var lines: (String, String?) {
        guard let year = pick.year else { return ("今日选读", pick.chapterTitle) }
        let ago = TodayText.numeral(max(referenceYear - year, 1)) + "年前"
        let era = ctx.era.label(year)
        let place = pick.placeLabel.map { "在\($0)" }
        let second = [era, place].compactMap { $0 }.joined(separator: " · ")
        if pick.isExact {
            return ("\(ago)的\(isToday ? "今天" : "这一天")", second)
        }
        // 就近取: 明说取的是哪一天。
        return ("取最近的\(pick.monthDayLabel ?? "一天")", "\(ago) · \(second)")
    }

    private var summary: String {
        let (first, second) = lines
        return [first, second, "《\(pick.title)》"].compactMap { $0 }.joined(separator: "，")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.lg) {
            plate
                .readingTransitionSource(pick.id, in: namespace)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: theme.space.md) {
                if let quote = pick.quote {
                    Text(quote)
                        .font(theme.bodyFont(19, relativeTo: .title3, legibilityWeight: legibilityWeight))
                        .foregroundStyle(theme.color.textPrimary)
                        .lineSpacing(theme.space.xs)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !pick.context.isEmpty {
                    Text(pick.context)
                        .font(theme.type.footnote)
                        .foregroundStyle(theme.color.textSecondary)
                        .lineSpacing(theme.space.xxs)
                        .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                }
                if let otherCount, otherCount > 0 {
                    Button(action: showOthers) {
                        HStack(spacing: theme.space.xs) {
                            Text("另有 \(otherCount) 条记载")
                            Image(systemName: "chevron.right").font(theme.type.caption.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                        .font(theme.type.footnote)
                        .foregroundStyle(theme.color.textSecondary)
                        .frame(minHeight: LifeUI.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("查看年谱里这一天的其他事目")
                }
            }
            actions
        }
    }

    // MARK: 画

    private var plate: some View {
        Color.clear
            .aspectRatio(artworkImage == nil ? 4.0 / 3.0 : 16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background { background }
            .overlay(alignment: .topLeading) { caption }
            .overlay(alignment: .topTrailing) { verticalTitle }
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                    .strokeBorder(theme.border, lineWidth: ZXMetric.hairline)
            }
    }

    @ViewBuilder private var background: some View {
        Group {
            if let image = artworkImage {
                Image(uiImage: image).resizable().scaledToFill()
                    // 真迹稍压暗, 让纸色的题与小字浮出来。
                    .brightness(theme.isDark ? -0.18 : -0.06)
            } else {
                ScreenArtView(pick.artRecipe, aspect: nil, verse: nil)
            }
        }
        // 两处纸色晕开: 左上托小字, 右侧托竖排题。只用纸色的透明度, 浅深各自成立。
        .overlay {
            LinearGradient(colors: [theme.paper(0.82), theme.paper(0)],
                           startPoint: .topLeading, endPoint: UnitPoint(x: 0.55, y: 0.35))
        }
        .overlay {
            LinearGradient(colors: [theme.paper(0), theme.paper(0.78)],
                           startPoint: UnitPoint(x: 0.45, y: 0.5), endPoint: .trailing)
        }
        .accessibilityHidden(true)
    }

    private var caption: some View {
        let (first, second) = lines
        return VStack(alignment: .leading, spacing: theme.space.xxs) {
            Text(first)
                .font(theme.uiFont(13, weight: .medium, legibilityWeight: legibilityWeight))
                .foregroundStyle(theme.color.textPrimary)
            if let second, !second.isEmpty {
                Text(second)
                    .font(theme.uiFont(13, legibilityWeight: legibilityWeight))
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(artworkImage == nil ? 0 : theme.space.sm)
        .background {
            // 真迹满纸是字, 渐晕托不住: 小字垫一块纸。
            if artworkImage != nil {
                RoundedRectangle(cornerRadius: theme.radius.sm, style: .continuous).fill(theme.paper(0.9))
            }
        }
        .padding(artworkImage == nil ? theme.space.lg : theme.space.md)
        .frame(maxWidth: 260, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var verticalTitle: some View {
        VerticalText(TodayText.verticalTitle(pick.title),
                     font: theme.displayFont(36, relativeTo: .largeTitle, legibilityWeight: legibilityWeight),
                     color: theme.color.textPrimary, charSpacing: 2, columnSpacing: theme.space.md)
            .padding(artworkImage == nil ? 0 : theme.space.sm)
            .background {
                // 真迹上题写在一张题签上 (纸条压在画上), 像裱好的卷子。
                if artworkImage != nil {
                    RoundedRectangle(cornerRadius: theme.radius.sm, style: .continuous).fill(theme.paper(0.92))
                }
            }
            .padding(.vertical, artworkImage == nil ? theme.space.lg : theme.space.md)
            .padding(.trailing, artworkImage == nil ? theme.space.lg : theme.space.md)
            // 竖排题有界高: 一列排满往左另起一列; 字号封顶, 免得一个题撑破画。
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    // MARK: 动作

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.space.md) { readButton; seeDayButton }
            VStack(alignment: .leading, spacing: theme.space.sm) { readButton; seeDayButton }
        }
    }

    @ViewBuilder private var readButton: some View {
        if pick.workID != nil || pick.poem != nil {
            Button(action: read) {
                HStack(spacing: theme.space.xs) {
                    if isOpeningWork { ProgressView().controlSize(.small) }
                    Text("读这一篇")
                }
                .font(theme.type.callout.weight(.semibold))
                // 墨底上的字用纸色: 浅色是深底浅字, 深色 (墨反白) 是浅底深字, 两边都读得清。
                .foregroundStyle(theme.paper())
                .frame(minHeight: LifeUI.minTapTarget)
                .padding(.horizontal, theme.space.sm)
            }
            .poetActionStyle(prominent: true)
            // 本页的朱色留给本周里的「今天」; 主动作用墨。
            .tint(theme.color.textPrimary)
            .disabled(isOpeningWork)
            .accessibilityHint("打开《\(pick.title)》全文")
        }
    }

    @ViewBuilder private var seeDayButton: some View {
        if let seeDay {
            Button(action: seeDay) {
                Text("看这一天")
                    .font(theme.type.callout)
                    .frame(minHeight: LifeUI.minTapTarget)
                    .padding(.horizontal, theme.space.sm)
            }
            .poetActionStyle()
            .tint(theme.color.textPrimary)
            .accessibilityHint(pick.kind == .moment ? "到一生长卷里的这一刻" : "查看这一年的年谱")
        }
    }
}
