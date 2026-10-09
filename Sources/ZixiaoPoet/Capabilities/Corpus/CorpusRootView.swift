import ZixiaoPoetCore
//  CorpusRootView.swift — 诗文 Tab 的根页: 选读 → 按年读 → 全集 → 墨迹
//
//  设计主张 (zhi-design-reboot §3.3): 先选读, 再全集。门面是编辑过的合集 (画屏 + 竖排题的大卡,
//  横滑分页) 与一条年份轴; 全集退成一行入口, 墨迹是真迹大图横滑。
//  - 每节是独立的 View 结构, 推入的页一律经 AnyView 切断类型 (真机主线程栈的类型解析深度)。
//  - 一页只用一处强调色: 年份轴上选中的那一年。节题用墨, 不用朱。
//  - 合集、画屏 seed、分期都来自数据 (随包 collections / moments / guide 与编成), 内核不写死。

import SwiftUI
import ZixiaoArt
import ZixiaoDesign

struct CorpusRootView: View {
    let ctx: CompositionContext
    /// 截图用 (DEBUG): 启动后直接推入的合集。
    @State private var debugOpened: CorpusSelection?
    @Environment(\.zxTheme) private var theme

    /// 根页各节的滚动锚点。
    enum Anchor: String, Hashable { case selections, years, inventory, ink }

    var body: some View {
        ZXShellScrollView {
            ScrollViewReader { proxy in
                LazyVStack(alignment: .leading, spacing: theme.space.xxl) {
                    let selections = ctx.corpusSelections
                    if !selections.isEmpty {
                        CorpusSelectionsSection(ctx: ctx, selections: selections).id(Anchor.selections)
                    }
                    if ctx.hasChronicleData { CorpusYearSection(ctx: ctx).id(Anchor.years) }
                    if !ctx.literaryGenres.isEmpty { CorpusInventorySection(ctx: ctx).id(Anchor.inventory) }
                    if !ctx.artworks.isEmpty { CorpusInkSection(ctx: ctx).id(Anchor.ink) }
                }
                .padding(.vertical, theme.space.xl)
                .poetReadableWidth(1000)
                .task { await debugLaunch(proxy) }
            }
        }
        .background(theme.paper())
        .zxNavigationTitle(ctx.composition.placement(.corpus)?.label ?? "诗文", role: .root)
        .navigationDestination(item: $debugOpened) { selection in
            AnyView(CollectionReadingView(ctx: ctx, selection: selection))
        }
    }

    /// 设计迭代 / 截图用的启动参数 (与 `PoetAppRoot` 的 `-tab` 同法, 只在 DEBUG 生效):
    /// `-corpusScroll years|inventory|ink` 滚到那一节; `-corpusOpen <合集 id>` 推入那一组选读;
    /// `-corpusYear <公元年>` 年份轴初选那一年 (见 `CorpusYearSection`)。
    private func debugLaunch(_ proxy: ScrollViewProxy) async {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "corpusOpen"), debugOpened == nil,
           let hit = ctx.corpusSelections.first(where: { $0.id == id }) {
            debugOpened = hit
        }
        if let raw = defaults.string(forKey: "corpusScroll"), let anchor = Anchor(rawValue: raw) {
            // 年份轴与作品是网络载入的: 等它们排好再滚。
            try? await Task.sleep(for: .seconds(2.5))
            proxy.scrollTo(anchor, anchor: .top)
        }
        #endif
    }
}

// MARK: - 节题

/// 根页的节题: 墨色小标题 + 一句说明, 右侧可带一个「全部」入口。
struct CorpusSectionHeader<Destination: View>: View {
    let title: String
    var detail: String?
    var linkTitle: String?
    var linkAccessibilityLabel: String?
    @ViewBuilder var destination: () -> Destination
    @Environment(\.zxTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.space.sm) {
            VStack(alignment: .leading, spacing: theme.space.xxs) {
                Text(title).font(theme.type.title3).tracking(theme.type.tracking(for: .title3))
                    .foregroundStyle(theme.color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let detail {
                    Text(detail).font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: theme.space.sm)
            if let linkTitle {
                NavigationLink(destination: destination) {
                    HStack(spacing: theme.space.xs) {
                        Text(linkTitle)
                        Image(systemName: "chevron.right").font(theme.type.caption).accessibilityHidden(true)
                    }
                    .font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                    .frame(minHeight: PoetLayout.minHitTarget).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(linkAccessibilityLabel ?? linkTitle)
            }
        }
        .padding(.horizontal, theme.space.margin)
    }
}

extension CorpusSectionHeader where Destination == EmptyView {
    init(title: String, detail: String? = nil) {
        self.init(title: title, detail: detail, linkTitle: nil, linkAccessibilityLabel: nil) { EmptyView() }
    }
}

// MARK: - 选读

/// 选读: 每个合集一张「画屏 + 竖排题」的大卡, 横滑分页; 辅助字号下改竖排整宽。
struct CorpusSelectionsSection: View {
    let ctx: CompositionContext
    let selections: [CorpusSelection]
    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 卡宽占屏宽的比例与上限 (iPad 上不让一张卡撑成一面墙)。
    private static let widthFraction: CGFloat = 0.72
    private static let maxCardWidth: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.lg) {
            CorpusSectionHeader(title: "选读", detail: "编者选的几组诗文，一组一个题目")
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: theme.space.xl) {
                    ForEach(selections) { selection in link(selection) }
                }.padding(.horizontal, theme.space.margin)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: theme.space.lg) {
                        ForEach(selections) { selection in
                            link(selection)
                                .containerRelativeFrame(.horizontal) { length, _ in
                                    min(length * Self.widthFraction, Self.maxCardWidth)
                                }
                        }
                    }.scrollTargetLayout()
                }
                .contentMargins(.horizontal, theme.space.margin, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    private func link(_ selection: CorpusSelection) -> some View {
        NavigationLink {
            AnyView(CollectionReadingView(ctx: ctx, selection: selection))
        } label: {
            CorpusSelectionCard(selection: selection)
        }
        .buttonStyle(.plain)
    }
}

/// 一张合集卡: 3:4 画屏打底, 合集名竖排落在画留的诗句框一侧, 旨垫在下沿渐隐的纸上。
/// 视觉语言与一生长卷的卷封面 (`LifeChapterCover`) 同源, 只是小一号、不带印。
struct CorpusSelectionCard: View {
    let selection: CorpusSelection
    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var displayScale
    /// 竖排合集名的展示字号 (随 Dynamic Type, 放大到 accessibility1 为止 —— 再大就挤出画屏)。
    static let titleSize: CGFloat = 28
    static let titleSizeCap: DynamicTypeSize = .accessibility1
    /// 下沿垫字的纸占卡高的比例。
    private static let scrimFraction: CGFloat = 0.45
    /// 竖排题最低落到卡高的哪里 (旨只占下沿约四分之一; 纸的上半截是淡入, 压一点字无妨)。
    private static let titleFloor: CGFloat = 0.68

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
        VStack(alignment: .leading, spacing: theme.space.md) {
            ScreenArtView(selection.art, aspect: 3 / 4, verse: nil)
                .overlay { GeometryReader { titleBlock(in: $0.size) } }
                .overlay(alignment: .bottom) {
                    if !typeSize.isAccessibilitySize {
                        GeometryReader { proxy in
                            LinearGradient(colors: [theme.paper(0), theme.paper(0.78), theme.paper(0.94)],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: proxy.size.height * Self.scrimFraction)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        .allowsHitTesting(false)
                        .overlay(alignment: .bottomLeading) { caption.padding(theme.space.lg) }
                    }
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(theme.rule, lineWidth: 1 / displayScale))
            if typeSize.isAccessibilitySize { caption }
        }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(selection.title)。\(selection.thesis)。共 \(selection.entries.count) 篇")
        .accessibilityHint("打开这组选读")
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: theme.space.xs) {
            Text(selection.thesis)
                .font(theme.bodyFont(17, relativeTo: .body))
                .foregroundStyle(theme.color.textPrimary)
                .lineSpacing(theme.space.xxs)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(selection.entries.count) 篇")
                .font(theme.type.footnote.monospacedDigit())
                .foregroundStyle(theme.color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 竖排合集名: 顶天, 落在画留出的诗句框那一侧 (框是横带或画不出时落在右侧); 往下至多到 `titleFloor`。
    /// 不跟框的上沿 —— 小卡上框常落在中段, 跟着它往下, 竖排就只剩一两字高、被折成一排。
    private func titleBlock(in size: CGSize) -> some View {
        let leading = selection.art.verseLayout(pixelSize: size)?.side == .left
        let top = theme.space.lg
        let bottomLimit = typeSize.isAccessibilitySize ? size.height : size.height * Self.titleFloor
        return VerticalText(selection.title, font: theme.displayFont(Self.titleSize, relativeTo: .title),
                            color: theme.ink(), charSpacing: theme.space.xs, columnSpacing: theme.space.sm)
            .dynamicTypeSize(...Self.titleSizeCap)
            .frame(maxHeight: max(bottomLimit - top, theme.space.xxl), alignment: .top)
            .padding(.top, top)
            .padding(.horizontal, theme.space.lg)
            .frame(width: size.width, height: size.height, alignment: leading ? .topLeading : .topTrailing)
    }
}

// MARK: - 全集

/// 全集: 一行入口「诗 2,824 · 词 362 · 文 3,713 · 赋 5」, 点进体裁目录 (文再分大类)。
struct CorpusInventorySection: View {
    let ctx: CompositionContext
    @Environment(\.zxTheme) private var theme

    private var parts: [(label: String, count: Int?, unit: String)] {
        ctx.literaryGenres.map { ($0.label, $0.count, $0.unit) }
    }
    private var line: String {
        parts.map { part in part.count.map { "\(part.label) \($0.formatted(.number))" } ?? part.label }
            .joined(separator: " · ")
    }
    private var spoken: String {
        parts.map { part in part.count.map { "\(part.label) \($0) \(part.unit)" } ?? part.label }
            .joined(separator: "，")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            CorpusSectionHeader(title: "全集", detail: "按体裁浏览全部诗文，可检索")
            NavigationLink {
                AnyView(CorpusDirectoryView(ctx: ctx))
            } label: {
                HStack(spacing: theme.space.md) {
                    Text(line)
                        .font(theme.type.body.monospacedDigit())
                        .foregroundStyle(theme.color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: theme.space.sm)
                    Image(systemName: "chevron.right")
                        .font(theme.type.caption.weight(.semibold))
                        .foregroundStyle(theme.color.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, theme.space.lg)
                .frame(minHeight: PoetLayout.minHitTarget + theme.space.md)
                .zxSurface(.e1, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, theme.space.margin)
            .accessibilityLabel("全集，\(spoken)")
        }
    }
}

// MARK: - 墨迹

/// 墨迹: 全部书画的大图卡 (4:3 裁切 + 题 + 类别 · 年代) 横滑, 「全部」进图版目录。
struct CorpusInkSection: View {
    let ctx: CompositionContext
    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    private static let widthFraction: CGFloat = 0.72
    private static let maxCardWidth: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.lg) {
            CorpusSectionHeader(title: "墨迹", detail: "传世书画 \(ctx.artworks.count) 件",
                                linkTitle: "全部", linkAccessibilityLabel: "全部墨迹") {
                AnyView(ArtworkGalleryView(ctx: ctx))
            }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: theme.space.xl) {
                    ForEach(ctx.artworks) { work in link(work) }
                }.padding(.horizontal, theme.space.margin)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: theme.space.lg) {
                        ForEach(ctx.artworks) { work in
                            link(work)
                                .containerRelativeFrame(.horizontal) { length, _ in
                                    min(length * Self.widthFraction, Self.maxCardWidth)
                                }
                        }
                    }.scrollTargetLayout()
                }
                .contentMargins(.horizontal, theme.space.margin, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    private func link(_ work: Artwork) -> some View {
        NavigationLink {
            AnyView(ArtworkDetailView(ctx: ctx, artwork: work))
        } label: {
            CorpusInkCard(artwork: work)
        }
        .buttonStyle(.plain)
    }
}

struct CorpusInkCard: View {
    let artwork: Artwork
    @Environment(\.zxTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.sm) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { ArtworkThumbnail(asset: artwork.cover) }
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
                .accessibilityHidden(true)
            Text(artwork.title).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(artwork.kind) · \(artwork.dateLabel)")
                .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(artwork.title)，\(artwork.kind)，\(artwork.dateLabel)")
    }
}
