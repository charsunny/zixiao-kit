//  ScreenArtView.swift — 画屏上屏: 先铺纸, 图好了淡入; 可选一句竖排诗落在画留出的诗句框里
//
//  - 尺寸 / 外观 / 倍率一变就换键重取 (`.task(id:)`); 换尺寸时先留着旧图 (同配方同外观, 拉伸铺满),
//    稍等 150ms 再取, 免得旋转 / 拖动分栏时一路渲染中间尺寸。
//  - 内存里已有的图在 body 里同步取到, 列表滚回来不闪纸。
//  - 画是装饰 (`accessibilityHidden`); 有诗时整块只念这句诗。
//  - `.redacted(reason: .placeholder)` 下不取图, 只铺纸与一层 fill。

import SwiftUI
import ZixiaoArt
import ZixiaoDesign

public struct ScreenArtView: View {
    private let recipe: PoetScreenArt
    private let aspect: CGFloat?
    private let verse: String?
    private let cache: PoetScreenArtCache

    /// - Parameters:
    ///   - aspect: 宽 / 高; nil 则铺满父视图给的尺寸。
    ///   - verse: 一句诗 / 一个题目, 竖排落在画的诗句框里 (@2 配方由 ZXArt 留框; @1 落在右上)。
    ///     按换行与标点分列, 标点不上画。
    public init(_ recipe: PoetScreenArt, aspect: CGFloat? = nil, verse: String? = nil,
                cache: PoetScreenArtCache = .shared) {
        self.recipe = recipe
        self.aspect = aspect
        self.verse = verse.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        self.cache = cache
    }

    public var body: some View {
        if let aspect {
            surface.aspectRatio(aspect, contentMode: .fit)
        } else {
            surface
        }
    }

    private var surface: some View {
        GeometryReader { proxy in
            ScreenArtSurface(recipe: recipe, verse: verse, size: proxy.size, cache: cache)
        }
    }
}

// MARK: - 画面

private struct ScreenArtSurface: View {
    let recipe: PoetScreenArt
    let verse: String?
    let size: CGSize
    let cache: PoetScreenArtCache

    @Environment(\.zxTheme) private var theme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shown: Shown?

    struct Shown {
        let key: PoetScreenArtCache.Key
        let image: CGImage
    }

    private var key: PoetScreenArtCache.Key? {
        let pixels = PoetScreenArtCache.pixelSize(forPoints: size, scale: displayScale)
        guard pixels.width > 0, recipe.isSupported else { return nil }
        return PoetScreenArtCache.Key(recipe: recipe, pixelSize: pixels, colorScheme: theme.colorScheme)
    }

    /// 当前该上屏的图: 内存里正好有就用; 否则沿用同配方同外观的旧图 (尺寸变化中)。
    private func displayed(for key: PoetScreenArtCache.Key?) -> CGImage? {
        guard let key, !redactionReasons.contains(.placeholder) else { return nil }
        if let hit = cache.cachedImage(key) { return hit }
        guard let shown, shown.key.recipe == key.recipe, shown.key.dark == key.dark else { return nil }
        return shown.image
    }

    var body: some View {
        let key = key
        ZStack(alignment: .topLeading) {
            theme.paper()
            if redactionReasons.contains(.placeholder) {
                theme.color.fill
            } else if let image = displayed(for: key) {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .accessibilityHidden(true)
        .overlay(alignment: .topLeading) {
            if let verse { ScreenArtVerse(verse: verse, recipe: recipe, size: size) }
        }
        .task(id: key) { await load(key) }
    }

    private func load(_ key: PoetScreenArtCache.Key?) async {
        guard let key, !redactionReasons.contains(.placeholder) else { return }
        if let hit = cache.cachedImage(key) {
            shown = Shown(key: key, image: hit)
            return
        }
        if shown != nil {
            // 尺寸 / 外观正在变: 等它停下来再渲染。
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
        }
        guard let loaded = await cache.load(key), !Task.isCancelled else { return }
        let animation = loaded.source == .memory ? nil
            : theme.motion.adapted(theme.motion.standard, reduceMotion: reduceMotion)
        withAnimation(animation) { shown = Shown(key: key, image: loaded.image) }
    }
}

// MARK: - 诗

private struct ScreenArtVerse: View {
    let verse: String
    let recipe: PoetScreenArt
    let size: CGSize

    @Environment(\.zxTheme) private var theme

    /// 断句: 换行与标点处分列, 标点本身不上画 (画上题字不点标点)。
    static func columns(_ text: String) -> [String] {
        let breaks: Set<Character> = ["，", "。", "；", "！", "？", "、", "：", ",", ".", ";", "!", "?", ":", "\n"]
        let drop: Set<Character> = ["「", "」", "『", "』", "《", "》", "“", "”", "‘", "’", "\"", "·"]
        var out: [String] = [], current = ""
        for ch in text {
            if breaks.contains(ch) || ch.isNewline {
                if !current.isEmpty { out.append(current); current = "" }
            } else if !drop.contains(ch), !ch.isWhitespace {
                current.append(ch)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// 诗句框 (点): @2 由 ZXArt 给; @1 / 画不出时落在右上一栏。框只取决于长宽比, 直接用点尺寸算。
    private var layout: ZXArt.VerseLayout {
        recipe.verseLayout(pixelSize: size)
            ?? ZXArt.VerseLayout(side: .right, rect: CGRect(x: 0.62, y: 0.08, width: 0.32, height: 0.62))
    }

    var body: some View {
        let lines = Self.columns(verse)
        let layout = layout
        let rect = layout.rect(in: size)
        let columns = CGFloat(max(lines.count, 1))
        let chars = CGFloat(max(lines.map(\.count).max() ?? 1, 1))
        Group {
            if layout.isVertical {
                // 一格约 1.05 宽 × 1.5 高 (展示字族的行高, 实测), 字距 0.12、列距 0.5 字号; 多留一点余量。
                // fixedSize: 一句一列, 绝不回绕 —— 字号已按框算小, 回绕只会把列挤到画上。
                let fontSize = Self.clampFont(min(rect.height / (chars * 1.66), rect.width / (columns * 1.6)))
                VerticalText(lines.joined(separator: "\n"), font: theme.displayFont(fontSize, relativeTo: nil),
                             color: theme.ink(), charSpacing: fontSize * 0.12, columnSpacing: fontSize * 0.5)
                    .fixedSize()
                    .frame(width: rect.width, height: rect.height,
                           alignment: layout.side == .left ? .topLeading : .topTrailing)
            } else {
                let fontSize = Self.clampFont(min(rect.width / (chars * 1.08), rect.height / (columns * 1.6)))
                Text(lines.joined(separator: "\n"))
                    .font(theme.displayFont(fontSize, relativeTo: nil))
                    .foregroundStyle(theme.ink())
                    .lineSpacing(fontSize * 0.3)
                    .minimumScaleFactor(0.6)
                    .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            }
        }
        .offset(x: rect.minX, y: rect.minY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(verse)
    }

    static func clampFont(_ size: CGFloat) -> CGFloat { min(max(size.rounded(.down), 12), 44) }
}

// MARK: - 预览画廊 (仅 DEBUG)

#if DEBUG
/// 八处地望 × 浅深两色的画屏, 给架构师截图、给 charsunny 挑。地名只出现在这里 (DEBUG)。
public struct ScreenArtGallery: View {
    public static let previewSeeds = ["meishan", "fengxiang", "hangzhou", "mizhou",
                                      "xuzhou", "huangzhou", "huizhou", "danzhou"]

    private let season: ZXSeasonTint?
    private let generator: String
    private let verse: String?
    private let identity = try? ZXIdentity.bundled(.monochromeInk)
    @Environment(\.zxTheme) private var theme

    public init(season: ZXSeasonTint? = nil, generator: String = PoetScreenArt.shanshui, verse: String? = nil) {
        self.season = season
        self.generator = generator
        self.verse = verse
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme.space.lg) {
                ForEach(Self.previewSeeds, id: \.self) { seed in
                    let recipe = PoetScreenArt(seed: seed, generator: generator, season: season)
                    VStack(alignment: .leading, spacing: theme.space.xs) {
                        Text("\(seed) · \(recipe.resolvedVariant)").font(theme.uiFont(12)).foregroundStyle(theme.color.textSecondary)
                        HStack(spacing: theme.space.sm) {
                            tile(recipe, scheme: .light)
                            tile(recipe, scheme: .dark)
                        }
                    }
                }
            }
            .padding(theme.space.lg)
        }
    }

    @ViewBuilder
    private func tile(_ recipe: PoetScreenArt, scheme: ColorScheme) -> some View {
        let art = ScreenArtView(recipe, aspect: 3 / 2, verse: verse)
            .environment(\.colorScheme, scheme)
        if let identity {
            art.environment(\.zxTheme, ZXTheme(identity, colorScheme: scheme, seasonTint: season))
        } else {
            art
        }
    }
}

#Preview("画屏 · 八处") {
    ScreenArtGallery()
}

#Preview("画屏 · 秋 · 带诗") {
    ScreenArtGallery(season: .autumn, verse: "山高月小，水落石出。")
}

#Preview("花卉 · 冬") {
    ScreenArtGallery(season: .winter, generator: PoetScreenArt.flowers)
}
#endif
