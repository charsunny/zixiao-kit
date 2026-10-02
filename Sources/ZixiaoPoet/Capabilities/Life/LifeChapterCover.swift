//  LifeChapterCover.swift — 卷封面: 全幅画屏 (伸进导航栏下) + 竖排卷名 + 一枚印 + 卷次 / 年份 / 一句旨
//
//  画屏按本卷地望 seed 生成 (`PoetScreenArt.forPlace`), 同一卷永远同一幅。
//  - 出血: 每张封面顶上多一条与导航栏 (连状态栏) 等高的「只有画」的带。长卷的滚动视图忽略顶端
//    安全区, 第一卷在顶端时这条带就在导航栏底下, 画铺到屏幕最上沿; 卷封面吸附时也贴屏顶,
//    同样画满栏下。字全部落在带以下, 带的上沿再垫一层渐隐的纸, iOS 26 的玻璃栏与「一生」标题
//    压在画上仍清楚。
//  - 视差 (`LifeParallax`): 画比内容慢 (下方多画一截余量, 进场上移时不露底), 卷名反向略快并
//    淡出, 印不动 (与卷次、旨一起随内容走)。第一卷在顶端下拉时画拉长贴住屏顶。
//    减少动态时画与卷名都不动。
//  - 卷名竖排落在画留出的诗句框里 (@2 由 ZXArt 给框); 印只在这里出现, 一卷一枚。

import SwiftUI
import ZixiaoArt
import ZixiaoDesign

struct LifeChapterCover: View {
    let chapter: PoetMoments.Chapter
    /// 在长卷里的位置 (1 起)。
    let position: Int
    /// 顶端出血带 + 正文封面的高与视口。
    let metrics: LifeMetrics
    /// 长卷第一卷: 顶端下拉时画要拉长, 上沿不裁。
    let isFirst: Bool
    @Environment(\.zxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 卷名的展示字号 (随 Dynamic Type, 上限见 `titleSizeCap`)。
    static let titleSize: CGFloat = 36
    /// 卷名再大就挤出画屏: 封面上的卷名放大到 accessibility1 为止 (其余正文不受限)。
    static let titleSizeCap: DynamicTypeSize = .accessibility1
    /// 印面边长 (固有尺寸)。
    static let sealSize: CGFloat = 30
    /// 下沿垫字的纸占封面 (出血带以下) 的比例。
    nonisolated static let scrimFraction: CGFloat = 0.42
    /// 封面自己的坐标空间: 卷名在 `visualEffect` 里由此换算出封面顶在滚动视图里的位置。
    nonisolated static let space = "life.cover"

    private var recipe: PoetScreenArt {
        .forPlace(chapter.placeSeed, epoch: chapter.epochSequence,
                  season: chapter.seasonTint.flatMap(ZXSeasonTint.init(rawValue:)))
    }
    private var ordinal: String { PoetMoments.Chapter.ordinalLabel(position) }
    private var bleed: CGFloat { metrics.coverBleed }
    private var total: CGFloat { metrics.coverBleed + metrics.coverHeight }
    private var overscan: CGFloat { LifeParallax.overscan(viewport: metrics.viewport, cover: total) }

    var body: some View {
        Color.clear
            .frame(height: total)
            .frame(maxWidth: .infinity)
            .background(alignment: .top) { art }
            .overlay(alignment: .top) { topScrim }
            .overlay(alignment: .bottom) { scrim }
            .overlay { GeometryReader { titleBlock(in: $0.size) } }
            .overlay(alignment: .bottomLeading) { caption }
            // 画的视差位移与下沿余量都裁在封面里; 第一卷上沿不裁 (顶端下拉时画往上伸)。
            .clipShape(LifeTopBleedRect(top: isFirst ? metrics.viewport : 0))
            .coordinateSpace(.named(Self.space))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ordinal)，\(chapter.title)，\(chapter.yearsLabel)。\(chapter.thesis)")
            .accessibilityAddTraits(.isHeader)
    }

    /// 画: 比封面高出下沿余量, 顶对齐; 位移在 `visualEffect` 里按封面顶的 y 算。
    private var art: some View {
        let isFirst = isFirst, overscan = overscan, height = total + overscan, reduce = reduceMotion
        return ScreenArtView(recipe, aspect: nil, verse: nil)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .visualEffect { content, proxy in
                let minY = proxy.frame(in: .scrollView).minY
                let effect = LifeParallax.art(minY: minY, isFirst: isFirst, overscan: overscan,
                                              height: height, reduceMotion: reduce)
                return content
                    .scaleEffect(effect.scale, anchor: .top)
                    .offset(y: effect.offset)
            }
            .accessibilityHidden(true)
    }

    /// 出血带上沿的一层纸: 导航栏的标题与按钮压在画上也读得清。
    private var topScrim: some View {
        LinearGradient(colors: [theme.paper(0.72), theme.paper(0.35), theme.paper(0)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: bleed + theme.space.xl)
            .allowsHitTesting(false)
    }

    /// 下沿渐隐的纸: 给卷次、年份与旨垫底。
    private var scrim: some View {
        LinearGradient(colors: [theme.paper(0), theme.paper(0.72), theme.paper(0.94)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: metrics.coverHeight * Self.scrimFraction)
            .allowsHitTesting(false)
    }

    /// 竖排卷名 + 印, 落在画的诗句框里 (框按画的尺寸算, 画顶即封面顶); 不进出血带。
    /// 框是横带或画不出时落在右上。
    private func titleBlock(in size: CGSize) -> some View {
        let artSize = CGSize(width: size.width, height: total + overscan)
        let layout = recipe.verseLayout(pixelSize: artSize)
        let vertical = layout?.isVertical ?? false
        let body = metrics.coverHeight
        let rect = vertical ? layout!.rect(in: artSize)
            : CGRect(x: size.width * 0.62, y: bleed + body * 0.08, width: size.width * 0.32, height: body * 0.5)
        let leading = layout?.side == .left
        let top = max(rect.minY, bleed + theme.space.lg)
        // 框的高度管住竖排: 字号放大到一列装不下时回绕成两列, 不会压到下沿的旨。
        let maxHeight = max(rect.maxY - top, body * 0.5)
        let width = min(max(rect.width, size.width * 0.3), size.width)
        let x = max(0, min(leading ? rect.minX : rect.maxX - width, size.width - width))
        let reduce = reduceMotion, coverHeight = total
        return VStack(alignment: leading ? .leading : .trailing, spacing: theme.space.md) {
            VerticalText(chapter.title, font: theme.displayFont(Self.titleSize, relativeTo: .largeTitle),
                         color: theme.ink(), charSpacing: theme.space.xs, columnSpacing: theme.space.md)
                .dynamicTypeSize(...Self.titleSizeCap)
                .visualEffect { content, proxy in
                    // 封面顶在滚动视图里的 y = 卷名在滚动视图里的 y − 卷名在封面里的 y。
                    let minY = proxy.frame(in: .scrollView).minY - proxy.frame(in: .named(Self.space)).minY
                    let effect = LifeParallax.title(minY: minY, height: coverHeight, reduceMotion: reduce)
                    return content.offset(y: effect.offset).opacity(effect.opacity)
                }
            SealView(PoetMoments.Chapter.chineseNumeral(position), style: .baiwen, size: Self.sealSize)
        }
        .frame(maxHeight: maxHeight, alignment: .top)
        .frame(width: width, alignment: leading ? .topLeading : .topTrailing)
        .offset(x: x, y: top)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: theme.space.xs) {
            Text("\(ordinal) · \(chapter.yearsLabel)")
                .font(theme.type.footnote.weight(.medium).monospacedDigit())
                .tracking(theme.type.tracking(for: .footnote))
                .foregroundStyle(theme.color.textSecondary)
            Text(chapter.thesis)
                .font(theme.bodyFont(19, relativeTo: .title3))
                .foregroundStyle(theme.color.textPrimary)
                .lineSpacing(theme.space.xs)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, theme.space.margin + LifeLayout.trackInset)
        .padding(.bottom, theme.space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
