import SwiftUI
import UIKit

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
    var body: some View {
        GeometryReader { geometry in
            if let image = ArtworkImages.image(asset) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            } else { Color.secondary.opacity(0.1).overlay { Image(systemName: "photo") } }
        }
    }
}

struct ArtworkPreview: View {
    let artwork: Artwork
    let theme: Theme
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if compact && !typeSize.isAccessibilitySize {
                HStack(spacing: 16) {
                    ArtworkThumbnail(asset: artwork.cover).frame(width: 100, height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(artwork.kind).font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                        Text(artwork.title).font(.headline).foregroundStyle(.primary)
                        Text(artwork.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }.padding(14)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ArtworkThumbnail(asset: artwork.cover).frame(height: 210).clipped().accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(artwork.kind).font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(.secondary)
                        }
                        Text(artwork.title).font(.title2.bold()).foregroundStyle(.primary)
                        Text(artwork.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(20)
                }
            }
        }.background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct ArtworkGalleryView: View {
    let ctx: CompositionContext
    var initialKind = "全部"
    var body: some View {
        ArtworkGalleryContent(ctx: ctx, initialKind: initialKind)
            .navigationTitle(initialKind == "全部" ? "书画" : initialKind).navigationBarTitleDisplayMode(.inline)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    private var shown: [Artwork] { ctx.artworks.filter { kind == "全部" || $0.kind == kind } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NativeSectionHeader(title: "从笔墨，走近\(ctx.composition.poet.name)") {
                    Menu {
                        Picker("筛选书画", selection: $kind) {
                            Text("全部").tag("全部"); Text("书法").tag("书法"); Text("绘画").tag("绘画")
                        }
                    } label: { Label(kind, systemImage: "line.3.horizontal.decrease") }
                    .accessibilityLabel("筛选书画，当前\(kind)")
                }
                Text("收录 \(shown.count) 件 · 原图与出处随页可查")
                    .font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 310), spacing: 18)], spacing: 20) {
                    ForEach(shown) { artwork in
                        NavigationLink {
                            ArtworkDetailView(ctx: ctx, artwork: artwork).readingTransition(artwork.id, in: gallery)
                        } label: {
                            ArtworkPreview(artwork: artwork, theme: ctx.theme)
                                .readingTransitionSource(artwork.id, in: gallery)
                        }.buttonStyle(.plain)
                    }
                }
                Text("书画资料按所列馆藏与著录整理。图版中的补书、题跋与正文分别标注。")
                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
            }.padding(20).poetReadableWidth()
        }.background(ctx.theme.paper)
    }
}

struct ArtworkDetailView: View {
    let ctx: CompositionContext
    let artwork: Artwork
    @State private var viewingImage = false
    @State private var relatedPoem: Poem?
    @State private var poemFailed = false
    private var theme: Theme { ctx.theme }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Button { viewingImage = true } label: {
                    VStack(spacing: 0) {
                        ArtworkThumbnail(asset: artwork.cover).frame(height: 270).clipped()
                        HStack {
                            Label("展开图卷", systemImage: "arrow.up.left.and.arrow.down.right")
                            Spacer(); Text("\(artwork.images.count) 张图版")
                        }.font(.subheadline.weight(.medium)).padding(18)
                            .foregroundStyle(theme.accent).background(theme.surface)
                    }.clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }.buttonStyle(.plain).accessibilityLabel("展开\(artwork.title)图卷，可放大查看")
                VStack(alignment: .leading, spacing: 10) {
                    Text(artwork.kind).font(.subheadline.weight(.medium)).foregroundStyle(theme.accent)
                    Text(artwork.title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(artwork.subtitle).font(.title3).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    artFact("作者", artwork.attribution)
                    Divider(); artFact("年代", artwork.dateLabel)
                    Divider(); artFact("形制", artwork.medium)
                    Divider(); artFact("尺寸", artwork.dimensions)
                    Divider(); artFact("收藏", artwork.collection)
                }.padding(20).background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                VStack(alignment: .leading, spacing: 14) {
                    NativeSectionHeader("关于作品")
                    Text(artwork.introduction).font(.body).lineSpacing(7)
                }
                VStack(alignment: .leading, spacing: 14) {
                    NativeSectionHeader("试着这样看")
                    Text(artwork.lookingNotes).font(.body).lineSpacing(7)
                    Text(artwork.images.count > 1 ? "观赏提示为编辑整理。图卷保留馆藏分段拍摄的边缘与色标，可展开查看。" : "观赏提示为编辑整理。展开可查看画心全幅，双指缩放观察笔墨细节。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let relatedPoem {
                    VStack(alignment: .leading, spacing: 12) {
                        NativeSectionHeader("对照读原文")
                        NavigationLink { PoemDetailView(ctx: ctx, poem: relatedPoem) } label: {
                            PoemRow(poem: relatedPoem, theme: theme, displayTitle: ctx.workTitle(relatedPoem)).padding(18)
                                .background(theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                } else if artwork.relatedPoemID != nil {
                    if poemFailed {
                        Button("《\(artwork.relatedPoemTitle ?? "作品")》正文暂未载入，点此重试") { Task { await loadRelated() } }
                            .frame(minHeight: 44)
                    } else { ProgressView("正在准备对照原文…") }
                }
                VStack(alignment: .leading, spacing: 14) {
                    NativeSectionHeader("资料与图像出处")
                    Link(destination: artwork.sourceURL) { Label(artwork.sourceTitle, systemImage: "arrow.up.right.square") }
                        .frame(minHeight: 44)
                    Text(artwork.imageCredit).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack(spacing: 24) {
                        Link("图像来源", destination: artwork.imageSourceURL)
                        Link("图像使用说明", destination: artwork.licenseURL)
                    }.font(.subheadline).frame(minHeight: 44)
                }.padding(20).background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }.padding(20).padding(.bottom, 12).poetReadableWidth(700)
        }.background(theme.paper)
            .navigationTitle("书画").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ShareLink(item: artwork.sourceURL) { Label("分享作品出处", systemImage: "square.and.arrow.up") }
            }
            .fullScreenCover(isPresented: $viewingImage) { ArtworkImageViewer(artwork: artwork) }
            .task { await loadRelated() }
    }
    private func artFact(_ label: String, _ value: String) -> some View {
        LabeledContent { Text(value).multilineTextAlignment(.trailing) } label: {
            Text(label).foregroundStyle(.secondary)
        }.font(.subheadline)
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
    @State private var page = 0
    @State private var zoomCommands: [Int: Int] = [:]
    @State private var zoomAction = 0
    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ForEach(Array(artwork.images.enumerated()), id: \.element.id) { index, panel in
                    ZoomableArtwork(asset: panel.asset, label: panel.caption,
                                    command: zoomCommands[index, default: 0], action: zoomAction)
                        .tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
                .background(.black)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 10) {
                        Text(artwork.images[page].caption).font(.subheadline).multilineTextAlignment(.center)
                        HStack(spacing: 28) {
                            Button { page -= 1 } label: { Image(systemName: "chevron.left") }
                                .disabled(page == 0).accessibilityLabel("上一张图版")
                            Text("\(page + 1) / \(artwork.images.count)").monospacedDigit().accessibilityLabel("第 \(page + 1) 张，共 \(artwork.images.count) 张")
                            Button { page += 1 } label: { Image(systemName: "chevron.right") }
                                .disabled(page == artwork.images.count - 1).accessibilityLabel("下一张图版")
                        }.font(.subheadline).frame(minHeight: 44)
                        Text("双指缩放 · 双击放大 · 左右切换图版").font(.caption).foregroundStyle(.secondary)
                    }.padding(16).frame(maxWidth: .infinity).background(.black)
                }
                .navigationTitle(artwork.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { zoomAction = -1; zoomCommands[page, default: 0] += 1 } label: { Image(systemName: "minus.magnifyingglass") }
                            .accessibilityLabel("缩小图像")
                        Button { zoomAction = 1; zoomCommands[page, default: 0] += 1 } label: { Image(systemName: "plus.magnifyingglass") }
                            .accessibilityLabel("放大图像")
                    }
                }
        }.preferredColorScheme(.dark).tint(.white)
    }
}

private struct ZoomableArtwork: UIViewRepresentable {
    let asset: String
    let label: String
    let command: Int
    let action: Int
    func makeUIView(context: Context) -> ArtworkScrollView {
        let view = ArtworkScrollView()
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
        backgroundColor = .black
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
