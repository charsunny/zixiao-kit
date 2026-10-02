import SwiftUI
import UIKit
import ZixiaoDesign

@MainActor
enum ArtworkImages {
    static let cache = NSCache<NSString, UIImage>()
    /// 书画图片随 App 包发, 由 `CompositionContext` 启动时指过来 (`PoetResources`)。
    static var resources: PoetResources?
    static func image(_ asset: String) -> UIImage? {
        if let image = cache.object(forKey: asset as NSString) { return image }
        guard let url = resources?.url(forAsset: asset),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.countLimit = 8
        cache.totalCostLimit = 64 * 1024 * 1024
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: asset as NSString, cost: cost)
        return image
    }
}

struct ArtworkThumbnail: View {
    let asset: String
    @Environment(\.zxTheme) private var theme
    var body: some View {
        GeometryReader { geometry in
            if let image = ArtworkImages.image(asset) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            } else {
                theme.color.fill.overlay {
                    Image(systemName: "photo").font(theme.type.title3).foregroundStyle(theme.color.textTertiary)
                }
            }
        }
    }
}

struct ArtworkPreview: View {
    let artwork: Artwork
    var compact = false
    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 图版的固有尺寸 (不是间距): 紧凑行的缩略图、卡片的图版高度。
    private static let compactThumb = CGSize(width: 100, height: 104)
    private static let cardImageHeight: CGFloat = 210

    init(artwork: Artwork, compact: Bool = false) {
        self.artwork = artwork
        self.compact = compact
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous)
        Group {
            if compact && !typeSize.isAccessibilitySize {
                HStack(spacing: theme.space.lg) {
                    ArtworkThumbnail(asset: artwork.cover)
                        .frame(width: Self.compactThumb.width, height: Self.compactThumb.height)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: theme.space.sm) {
                        Text(artwork.kind).font(theme.type.caption.weight(.semibold)).foregroundStyle(theme.color.accent)
                        Text(artwork.title).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                        Text(artwork.subtitle).font(theme.type.subhead).foregroundStyle(theme.color.textSecondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(theme.type.caption.weight(.semibold))
                        .foregroundStyle(theme.color.textTertiary).accessibilityHidden(true)
                }.padding(theme.space.md)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ArtworkThumbnail(asset: artwork.cover).frame(height: Self.cardImageHeight).clipped()
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: theme.space.sm) {
                        HStack {
                            Text(artwork.kind).font(theme.type.caption.weight(.semibold)).foregroundStyle(theme.color.accent)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(theme.type.footnote)
                                .foregroundStyle(theme.color.textSecondary).accessibilityHidden(true)
                        }
                        Text(artwork.title).font(theme.type.title2).foregroundStyle(theme.color.textPrimary)
                        Text(artwork.subtitle).font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                    }.padding(theme.space.margin)
                }
            }
        }
        .zxSurface(.e1, in: shape)
        .clipShape(shape)
        .contentShape(shape)
    }
}

struct ArtworkGalleryView: View {
    let ctx: CompositionContext
    var initialKind = "全部"
    var body: some View {
        ArtworkGalleryContent(ctx: ctx, initialKind: initialKind)
            .zxNavigationTitle(initialKind == "全部" ? "书画" : initialKind, role: .secondary)
    }
}

struct ArtworkGalleryContent: View {
    let ctx: CompositionContext
    @Namespace private var gallery
    @State private var kind: String
    init(ctx: CompositionContext, initialKind: String = "全部") {
        self.ctx = ctx
        _kind = State(initialValue: initialKind)
    }
    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 网格里一张卡的最小宽度 (固有尺寸)。
    private static let minCardWidth: CGFloat = 310
    private var shown: [Artwork] { ctx.artworks.filter { kind == "全部" || $0.kind == kind } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.lg) {
                NativeSectionHeader(title: "从笔墨，走近\(ctx.composition.poet.name)") {
                    Menu {
                        Picker("筛选书画", selection: $kind) {
                            Text("全部").tag("全部"); Text("书法").tag("书法"); Text("绘画").tag("绘画")
                        }
                    } label: { Label(kind, systemImage: "line.3.horizontal.decrease").frame(minHeight: PoetLayout.minHitTarget) }
                    .accessibilityLabel("筛选书画，当前\(kind)")
                }
                Text("收录 \(shown.count) 件 · 原图与出处随页可查")
                    .font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                LazyVGrid(columns: typeSize.isAccessibilitySize
                          ? [GridItem(.flexible())]
                          : [GridItem(.adaptive(minimum: Self.minCardWidth), spacing: theme.space.lg)],
                          spacing: theme.space.margin) {
                    ForEach(shown) { artwork in
                        NavigationLink {
                            ArtworkDetailView(ctx: ctx, artwork: artwork).readingTransition(artwork.id, in: gallery)
                        } label: {
                            ArtworkPreview(artwork: artwork)
                                .readingTransitionSource(artwork.id, in: gallery)
                        }.buttonStyle(.plain)
                    }
                }
                Text("书画资料按所列馆藏与著录整理。图版中的补书、题跋与正文分别标注。")
                    .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary).padding(.top, theme.space.xs)
            }.padding(theme.space.margin).poetReadableWidth()
        }
        .background(theme.paper()).tint(theme.color.accent)
    }
}

struct ArtworkDetailView: View {
    let ctx: CompositionContext
    let artwork: Artwork
    @State private var viewingImage = false
    @State private var relatedPoem: Poem?
    @State private var poemFailed = false
    @Environment(\.zxTheme) private var theme
    /// 顶部图版的高度 (固有尺寸)。
    private static let heroImageHeight: CGFloat = 270
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.xl) {
                Button { viewingImage = true } label: {
                    VStack(spacing: 0) {
                        ArtworkThumbnail(asset: artwork.cover).frame(height: Self.heroImageHeight).clipped()
                        HStack {
                            Label("展开图卷", systemImage: "arrow.up.left.and.arrow.down.right")
                            Spacer(); Text("\(artwork.images.count) 张图版")
                        }.font(theme.type.subhead.weight(.medium)).padding(theme.space.lg)
                            .foregroundStyle(theme.color.accent).background(theme.color.surface)
                    }.clipShape(RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
                }.buttonStyle(.plain).accessibilityLabel("展开\(artwork.title)图卷，可放大查看")
                VStack(alignment: .leading, spacing: theme.space.sm) {
                    Text(artwork.kind).font(theme.type.subhead.weight(.medium)).foregroundStyle(theme.color.accent)
                    Text(artwork.title).font(theme.type.title1).tracking(theme.type.tracking(for: .title1))
                        .foregroundStyle(theme.color.textPrimary).accessibilityAddTraits(.isHeader)
                    Text(artwork.subtitle).font(theme.type.title3).foregroundStyle(theme.color.textSecondary)
                }
                VStack(alignment: .leading, spacing: theme.space.md) {
                    artFact("作者", artwork.attribution)
                    InkDivider(); artFact("年代", artwork.dateLabel)
                    InkDivider(); artFact("形制", artwork.medium)
                    InkDivider(); artFact("尺寸", artwork.dimensions)
                    InkDivider(); artFact("收藏", artwork.collection)
                }.padding(theme.space.margin).zxSurface(.e1, in: RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
                VStack(alignment: .leading, spacing: theme.space.md) {
                    NativeSectionHeader("关于作品")
                    Text(artwork.introduction).font(theme.type.body).lineSpacing(theme.space.sm)
                        .foregroundStyle(theme.color.textPrimary)
                }
                VStack(alignment: .leading, spacing: theme.space.md) {
                    NativeSectionHeader("试着这样看")
                    Text(artwork.lookingNotes).font(theme.type.body).lineSpacing(theme.space.sm)
                        .foregroundStyle(theme.color.textPrimary)
                    Text(artwork.images.count > 1 ? "观赏提示为编辑整理。图卷保留馆藏分段拍摄的边缘与色标，可展开查看。" : "观赏提示为编辑整理。展开可查看画心全幅，双指缩放观察笔墨细节。")
                        .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                }
                if let relatedPoem {
                    VStack(alignment: .leading, spacing: theme.space.md) {
                        NativeSectionHeader("对照读原文")
                        NavigationLink { PoemDetailView(ctx: ctx, poem: relatedPoem) } label: {
                            PoemRow(poem: relatedPoem, displayTitle: ctx.workTitle(relatedPoem)).padding(theme.space.lg)
                                .zxSurface(.e1, in: RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                } else if artwork.relatedPoemID != nil {
                    if poemFailed {
                        Button("《\(artwork.relatedPoemTitle ?? "作品")》正文暂未载入，点此重试") { Task { await loadRelated() } }
                            .font(theme.type.subhead).frame(minHeight: PoetLayout.minHitTarget)
                    } else { LoadingStateView(label: "正在准备对照原文…") }
                }
                VStack(alignment: .leading, spacing: theme.space.md) {
                    NativeSectionHeader("资料与图像出处")
                    Link(destination: artwork.sourceURL) { Label(artwork.sourceTitle, systemImage: "arrow.up.right.square") }
                        .font(theme.type.body).frame(minHeight: PoetLayout.minHitTarget)
                    Text(artwork.imageCredit).font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                        .textSelection(.enabled)
                    if let license = artwork.license {
                        Text("授权 · \(license.name)").font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                    }
                    HStack(spacing: theme.space.xl) {
                        Link("图像来源", destination: artwork.imageSourceURL)
                        Link("图像使用说明", destination: artwork.licenseURL)
                    }.font(theme.type.subhead).frame(minHeight: PoetLayout.minHitTarget)
                }.padding(theme.space.margin).zxSurface(.e1, in: RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
            }.padding(theme.space.margin).padding(.bottom, theme.space.md).poetReadableWidth(700)
        }
        .background(theme.paper()).tint(theme.color.accent)
        .zxNavigationTitle("书画", role: .secondary)
        .toolbar {
            ShareLink(item: artwork.sourceURL) { Label("分享作品出处", systemImage: "square.and.arrow.up") }
        }
        .fullScreenCover(isPresented: $viewingImage) {
            // 图版查看器是暗场: 同一身份按深色外观重解析后注入, 不写死黑白。
            ArtworkImageViewer(artwork: artwork).zxTheme(theme.poetResolved(for: .dark))
        }
        .task { await loadRelated() }
    }
    private func artFact(_ label: String, _ value: String) -> some View {
        LabeledContent {
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(theme.color.textPrimary)
        } label: {
            Text(label).foregroundStyle(theme.color.textSecondary)
        }.font(theme.type.subhead)
    }
    private func loadRelated() async {
        guard let id = artwork.relatedPoemID, relatedPoem == nil else { return }
        poemFailed = false
        relatedPoem = ctx.guide?.poem(id)
        do {
            let poem = try await ctx.store.poems(ids: [id]).first
            guard !Task.isCancelled else { return }
            if let poem { relatedPoem = poem }
            poemFailed = relatedPoem == nil
        } catch { if !Task.isCancelled { poemFailed = relatedPoem == nil } }
    }
}

private struct ArtworkImageViewer: View {
    let artwork: Artwork
    @Environment(\.dismiss) private var dismiss
    @Environment(\.zxTheme) private var theme
    @State private var page = 0
    @State private var zoomCommands: [Int: Int] = [:]
    @State private var zoomAction = 0
    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ForEach(Array(artwork.images.enumerated()), id: \.element.id) { index, panel in
                    ZoomableArtwork(asset: panel.asset, label: panel.caption, backdrop: UIColor(theme.color.night),
                                    command: zoomCommands[index, default: 0], action: zoomAction)
                        .tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
                .background(theme.color.night)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: theme.space.sm) {
                        Text(artwork.images[page].caption).font(theme.type.subhead).multilineTextAlignment(.center)
                            .foregroundStyle(theme.color.textPrimary)
                        HStack(spacing: theme.space.xl) {
                            Button { page -= 1 } label: { Image(systemName: "chevron.left").frame(minWidth: PoetLayout.minHitTarget, minHeight: PoetLayout.minHitTarget) }
                                .disabled(page == 0).accessibilityLabel("上一张图版")
                            Text("\(page + 1) / \(artwork.images.count)").monospacedDigit()
                                .foregroundStyle(theme.color.textPrimary)
                                .accessibilityLabel("第 \(page + 1) 张，共 \(artwork.images.count) 张")
                            Button { page += 1 } label: { Image(systemName: "chevron.right").frame(minWidth: PoetLayout.minHitTarget, minHeight: PoetLayout.minHitTarget) }
                                .disabled(page == artwork.images.count - 1).accessibilityLabel("下一张图版")
                        }.font(theme.type.subhead).frame(minHeight: PoetLayout.minHitTarget)
                        Text("双指缩放 · 双击放大 · 左右切换图版").font(theme.type.caption)
                            .foregroundStyle(theme.color.textSecondary)
                    }.padding(theme.space.lg).frame(maxWidth: .infinity).background(theme.color.night)
                }
                .zxNavigationTitle(artwork.title, role: .secondary)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { zoomAction = -1; zoomCommands[page, default: 0] += 1 } label: { Image(systemName: "minus.magnifyingglass") }
                            .accessibilityLabel("缩小图像")
                        Button { zoomAction = 1; zoomCommands[page, default: 0] += 1 } label: { Image(systemName: "plus.magnifyingglass") }
                            .accessibilityLabel("放大图像")
                    }
                }
        }.preferredColorScheme(.dark).tint(theme.ink())
    }
}

private struct ZoomableArtwork: UIViewRepresentable {
    let asset: String
    let label: String
    /// 暗场底色 (由主题解析好传进来, UIKit 这层不认识主题)。
    let backdrop: UIColor
    let command: Int
    let action: Int
    func makeUIView(context: Context) -> ArtworkScrollView {
        let view = ArtworkScrollView()
        view.backgroundColor = backdrop
        view.setImage(ArtworkImages.image(asset), label: label)
        return view
    }
    func updateUIView(_ view: ArtworkScrollView, context: Context) {
        if command > 0 && view.lastCommand != command {
            view.lastCommand = command
            view.setZoomScale(min(view.maximumZoomScale, max(view.minimumZoomScale, view.zoomScale * (action > 0 ? 1.7 : 1 / 1.7))), animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }
}

private final class ArtworkScrollView: UIScrollView, UIScrollViewDelegate {
    let art = UIImageView()
    var lastCommand = 0
    private var lastSize = CGSize.zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        showsVerticalScrollIndicator = false; showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        bouncesZoom = true
        addSubview(art)
        let tap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        tap.numberOfTapsRequired = 2; addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setImage(_ image: UIImage?, label: String) {
        art.image = image; art.frame = CGRect(origin: .zero, size: image?.size ?? .zero)
        art.isAccessibilityElement = true; art.accessibilityLabel = label
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, let image = art.image else { return }
        if bounds.size != lastSize {
            lastSize = bounds.size
            let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
            minimumZoomScale = fit; maximumZoomScale = fit * 8
            zoomScale = fit
        }
        centerImage()
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { art }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
    private func centerImage() {
        contentInset = UIEdgeInsets(top: max(0, (bounds.height - art.frame.height) / 2),
                                    left: max(0, (bounds.width - art.frame.width) / 2),
                                    bottom: 0, right: 0)
    }
    @objc private func doubleTap(_ recognizer: UITapGestureRecognizer) {
        let animate = !UIAccessibility.isReduceMotionEnabled
        if zoomScale > minimumZoomScale * 1.1 { setZoomScale(minimumZoomScale, animated: animate) }
        else {
            let scale = minimumZoomScale * 3
            let point = recognizer.location(in: art)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: animate)
        }
    }
}
