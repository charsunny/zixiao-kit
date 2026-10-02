//  LifeChapterCover.swift — 卷封面: 全幅画屏 + 竖排卷名 + 一枚印 + 卷次 / 年份 / 一句旨
//
//  画屏按本卷地望 seed 生成 (`PoetScreenArt.forPlace`), 同一卷永远同一幅。卷名竖排落在画留出的
//  诗句框里 (@2 由 ZXArt 给框); 印只在这里出现, 一卷一枚。字全部压在纸色上: 画屏本身就是
//  纸 + 墨, 浅深外观各自解析, 下沿再垫一层渐隐的纸, 旨那一行不会落在山石上读不清。

import SwiftUI
import ZixiaoArt
import ZixiaoDesign

struct LifeChapterCover: View {
    let chapter: PoetMoments.Chapter
    /// 在长卷里的位置 (1 起)。
    let position: Int
    let height: CGFloat
    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 卷名的展示字号 (随 Dynamic Type, 上限见 `titleSizeCap`)。
    static let titleSize: CGFloat = 36
    /// 卷名再大就挤出画屏: 封面上的卷名放大到 accessibility1 为止 (其余正文不受限)。
    static let titleSizeCap: DynamicTypeSize = .accessibility1
    /// 印面边长 (固有尺寸)。
    static let sealSize: CGFloat = 30

    private var recipe: PoetScreenArt {
        .forPlace(chapter.placeSeed, epoch: chapter.epochSequence,
                  season: chapter.seasonTint.flatMap(ZXSeasonTint.init(rawValue:)))
    }
    private var ordinal: String { PoetMoments.Chapter.ordinalLabel(position) }

    var body: some View {
        ScreenArtView(recipe, aspect: nil, verse: nil)
            // iOS 27 的 App 环境里 redactionReasons 自带 `.privacy`, 画屏见到任何 redaction 都只铺纸
            // (D2 实测: 卷封面一直空白)。封面不含隐私内容, 这里清掉再交给它。
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) { scrim }
            .overlay { GeometryReader { titleBlock(in: $0.size) } }
            .overlay(alignment: .bottomLeading) { caption }
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ordinal)，\(chapter.title)，\(chapter.yearsLabel)。\(chapter.thesis)")
            .accessibilityAddTraits(.isHeader)
    }

    /// 下沿渐隐的纸: 给卷次、年份与旨垫底。
    private var scrim: some View {
        LinearGradient(colors: [theme.paper(0), theme.paper(0.72), theme.paper(0.94)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: height * 0.42)
            .allowsHitTesting(false)
    }

    /// 竖排卷名 + 印, 落在画的诗句框里; 框是横带或画不出时落在右上。
    private func titleBlock(in size: CGSize) -> some View {
        let layout = recipe.verseLayout(pixelSize: size)
        let vertical = layout?.isVertical ?? false
        let rect = vertical ? layout!.rect(in: size)
            : CGRect(x: size.width * 0.62, y: size.height * 0.08, width: size.width * 0.32, height: size.height * 0.5)
        let leading = layout?.side == .left
        // 框的高度管住竖排: 字号放大到一列装不下时回绕成两列, 不会压到下沿的旨。
        let maxHeight = max(rect.height, size.height * 0.5)
        let width = min(max(rect.width, size.width * 0.3), size.width)
        let x = max(0, min(leading ? rect.minX : rect.maxX - width, size.width - width))
        return VStack(alignment: leading ? .leading : .trailing, spacing: theme.space.md) {
            VerticalText(chapter.title, font: theme.displayFont(Self.titleSize, relativeTo: .largeTitle),
                         color: theme.ink(), charSpacing: theme.space.xs, columnSpacing: theme.space.md)
                .dynamicTypeSize(...Self.titleSizeCap)
            SealView(PoetMoments.Chapter.chineseNumeral(position), style: .baiwen, size: Self.sealSize)
        }
        .frame(maxHeight: maxHeight, alignment: .top)
        .frame(width: width, alignment: leading ? .topLeading : .topTrailing)
        .offset(x: x, y: rect.minY)
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
