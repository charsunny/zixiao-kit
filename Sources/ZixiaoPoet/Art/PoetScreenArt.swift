import ZixiaoPoetCore
//  PoetScreenArt.swift — 画屏: 按 seed 出一幅程序化山水 / 花卉, 带季节偏色, 缓存成位图
//
//  卷封面 (全幅)、今日一刻 (半幅)、合集卡 (小幅) 共用一张「配方」(`PoetScreenArt`) 与一个缓存
//  (`PoetScreenArtCache`)。生成与渲染全部交给 ZixiaoArt (`ZXArt.render(procedural:palette:pixelSize:)`,
//  纯 CoreGraphics, 线程安全, 小组件里也能用); 这里只做三件事:
//
//  1. 配方 → `ZXArt.Procedural` + `ZXArt.Palette`。seed 原样交给 ZXArt (它的 `Seed` 就是字符串, 与原作
//     网页 `?seed=` 同序列), 所以同一配方永远同一张画。variant 不给时由 seed 的稳定哈希 (FNV-1a, 不是
//     进程随机化的 `Hasher`) 选, 花卉按季节选花。
//  2. 调色板: 浅色 `ZXArt.Palette.paperInk`, 深色 `.night`; 季节偏色与 `ZXColorTokens` 同法 ——
//     只把纸向 `ZXSeasonTint.bias` 揉 `lightMixAmount` / `darkMixAmount`, 墨不动 (淡墨由纸墨重新派生)。
//  3. 缓存: 内存 (`NSCache`, 按位图字节计成本) → 磁盘 (`Caches/PoetScreenArt/<sha256>.png`) → 渲染。
//     渲染与 PNG 编解码都在 detached task 里, 不占主线程; 同一键的并发请求合并成一次渲染。
//
//  内核纯净: 这里不出现任何诗人 / 地名 —— seed 由编成 / 刻的数据提供 (`forPlace(_:epoch:)`)。

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import ZixiaoArt
import ZixiaoDesign

// MARK: - 配方

/// 一幅画屏的配方。值类型, 可做字典键; 同一配方 + 同一像素尺寸 + 同一外观 → 逐字节同一张图。
public struct PoetScreenArt: Sendable, Hashable {
    /// 山水 @2 (构图给诗留框)。缺省。
    public static let shanshui = "shanshui@2"
    /// 花卉 @2。
    public static let flowers = "nonflowers@2"

    /// 种子 (地望 / 刻 / 作品给的字符串, 如 `"<place>#<epoch>"`)。原样交给 ZXArt。
    public var seed: String
    /// `ZXArt.Procedural.supportedGenerators` 之一。
    public var generator: String
    /// 季节偏色; nil 不偏。
    public var season: ZXSeasonTint?
    /// 山水 "高山" | "江岸" | "远山"; 花 "梅" | "荷" | "菊" | "兰" | "自然"。nil → 见 `resolvedVariant`。
    public var variant: String?
    /// 透传给 ZXArt 的参数 (density 0.5–1.5、quiet_top、verse_side / verse_columns / verse_chars、hue)。
    public var params: ZXArt.Procedural.Params

    public init(seed: String, generator: String = PoetScreenArt.shanshui, season: ZXSeasonTint? = nil,
                variant: String? = nil, params: ZXArt.Procedural.Params = .init()) {
        self.seed = seed
        self.generator = generator
        self.season = season
        self.variant = variant
        self.params = params
    }

    /// 疏密 (契约 0.5–1.5, nil = 1)。`params.density` 的便捷入口。
    public var density: Double? {
        get { params.density }
        set { params.density = newValue }
    }

    /// 地望 seed 表: 编成 / 刻数据给出 `placeSeed` 与分期 (卷) 序号, 这里拼成种子。
    /// 同一地方在不同卷是不同的画 (`epoch` 不同), 同一卷同一地方永远同一幅。
    public static func forPlace(_ placeSeed: String, epoch: Int?, season: ZXSeasonTint? = nil,
                                generator: String = PoetScreenArt.shanshui) -> PoetScreenArt {
        PoetScreenArt(seed: "\(placeSeed)#\(epoch ?? 0)", generator: generator, season: season)
    }

    // MARK: 解析

    /// 缺省只在「高山」「江岸」里挑: @2 横幅 / 方幅下「远山」几乎只剩雾与一叶舟 (D3 预览实测), 做卷封面
    /// 撑不住画面。要远山就在 seed 表里显式写 `variant`。
    private static let defaultShanshuiVariants = ["高山", "江岸"]

    /// 实际用的 variant: 显式给的优先; 山水按 seed 的稳定哈希在高山 / 江岸里挑; 花按季节挑花
    /// (冬梅、春兰、夏与长夏荷、秋菊; 无季节 = 自然)。
    public var resolvedVariant: String {
        if let variant { return variant }
        if generator.hasPrefix("nonflowers") {
            switch season {
            case .winter: return "梅"
            case .spring: return "兰"
            case .summer, .lateSummer: return "荷"
            case .autumn: return "菊"
            case nil: return "自然"
            }
        }
        let list = Self.defaultShanshuiVariants
        return list[Int(Self.stableHash(seed) % UInt64(list.count))]
    }

    /// 交给 ZXArt 的配方。
    public var procedural: ZXArt.Procedural {
        ZXArt.Procedural(generator: generator, seed: seed, variant: resolvedVariant, params: params)
    }

    /// ZixiaoArt 能否画 (生成器 / 版本 / variant 都认识)。画不出时视图只留纸。
    public var isSupported: Bool { procedural.isSupported }

    /// 画屏季节偏色比例 (纸向 `ZXSeasonTint.bias` 揉的量), 比界面 token 大。
    public static let lightTintAmount: Double = 0.10
    public static let darkTintAmount: Double = 0.06

    /// 浅色纸墨 / 深色夜色, 纸按季节偏一点 (与 `ZXColorTokens` 同一算法, 比例见上)。
    public func palette(dark: Bool) -> ZXArt.Palette {
        let base: ZXArt.Palette = dark ? .night : .paperInk
        guard let season else { return base }
        let bias = dark ? season.bias.dark : season.bias.light
        // 画屏比界面 token 偏得更明显 (charsunny 2026-10-02: 「加深一点」): 界面是 3.5% / 2%, 画屏 10% / 6%。
        let amount = dark ? Self.darkTintAmount : Self.lightTintAmount
        return ZXArt.Palette(paper: base.paper.mixed(with: bias, amount: amount), ink: base.ink)
    }

    /// @2 的诗句框 (单位坐标); @1 / 画不出时 nil。纯函数, 不生成画。
    public func verseLayout(pixelSize: CGSize) -> ZXArt.VerseLayout? {
        procedural.verseLayout(pixelSize: pixelSize)
    }

    /// FNV-1a 64 (UTF-8)。跨进程、跨设备稳定。
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01b3
        }
        return h
    }
}

// MARK: - 缓存

/// 画屏位图缓存: 内存 → 磁盘 PNG → 后台渲染。`shared` 给 App 用; 测试可指定目录另起一个。
public actor PoetScreenArtCache {
    /// 一张图的出处 (测试与日志用)。
    public enum Source: Sendable, Hashable { case memory, disk, rendered }

    /// 缓存键: 配方 + 像素尺寸 + 外观。
    public struct Key: Sendable, Hashable {
        public let recipe: PoetScreenArt
        public let pixelWidth: Int
        public let pixelHeight: Int
        public let dark: Bool

        public init(recipe: PoetScreenArt, pixelWidth: Int, pixelHeight: Int, dark: Bool) {
            self.recipe = recipe
            self.pixelWidth = max(1, pixelWidth)
            self.pixelHeight = max(1, pixelHeight)
            self.dark = dark
        }

        public init(recipe: PoetScreenArt, pixelSize: CGSize, colorScheme: ColorScheme) {
            self.init(recipe: recipe, pixelWidth: Int(pixelSize.width.rounded()),
                      pixelHeight: Int(pixelSize.height.rounded()), dark: colorScheme == .dark)
        }

        public var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }

        /// 稳定的文字键 (跨启动不变): 版次 + 配方 JSON (键排序) + 季节 + 尺寸 + 外观。
        var identifier: String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let json = (try? encoder.encode(recipe.procedural)).map { String(decoding: $0, as: UTF8.self) }
                ?? "\(recipe.generator)|\(recipe.seed)|\(recipe.resolvedVariant)"
            return "r\(PoetScreenArtCache.revision)|\(json)|\(recipe.season?.rawValue ?? "-")|"
                + "\(pixelWidth)x\(pixelHeight)|\(dark ? "night" : "paper")"
        }

        /// 磁盘文件名: 文字键的 SHA-256。
        var fileName: String {
            SHA256.hash(data: Data(identifier.utf8)).map { String(format: "%02x", $0) }.joined() + ".png"
        }
    }

    /// 取到的图。
    public struct Loaded: @unchecked Sendable {
        // CGImage 不可变, 跨线程只读安全。
        public let image: CGImage
        public let source: Source
    }

    /// 改了调色 / 偏色 / 编码方式就加一, 让旧的磁盘缓存自然失效 (旧文件由 `trimDisk` 按时间清掉)。
    public static let revision = 1
    /// 单边像素上限 (iPad 全屏卷封面 @2x 也够); 超过按比例缩。
    public static let maxPixelSide: CGFloat = 2400
    /// 磁盘缓存上限, 超了按最久未改先删。
    public static let diskByteLimit = 96 << 20

    public static let shared = PoetScreenArtCache()

    /// `Caches/PoetScreenArt/`。
    public static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PoetScreenArt", isDirectory: true)
    }

    public nonisolated let directory: URL?
    private nonisolated let memory: MemoryStore
    private var inFlight: [Key: Task<Loaded?, Never>] = [:]
    private var trimmed = false
    /// 本实例实际渲染了几次 (不含内存 / 磁盘命中)。
    public private(set) var renderCount = 0

    /// - Parameters:
    ///   - directory: 磁盘缓存目录; nil 只用内存。
    ///   - memoryCostLimit: 内存缓存的位图字节上限 (缺省 48 MB ≈ 4 张 2400×1200)。
    public init(directory: URL? = PoetScreenArtCache.defaultDirectory, memoryCostLimit: Int = 48 << 20) {
        self.directory = directory
        self.memory = MemoryStore(costLimit: memoryCostLimit)
    }

    /// 视图上的点尺寸 → 缓存用的像素尺寸: 乘屏幕倍率, 向上取 8 的倍数 (避免布局抖动产生一串近似键),
    /// 单边不超过 `maxPixelSide`。画的构图只看长宽比 (ZXArt 的逻辑画布短边固定), 取整不影响构图。
    public nonisolated static func pixelSize(forPoints size: CGSize, scale: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0, scale > 0 else { return .zero }
        var w = size.width * scale, h = size.height * scale
        let longest = max(w, h)
        if longest > maxPixelSide { w *= maxPixelSide / longest; h *= maxPixelSide / longest }
        func up8(_ v: CGFloat) -> CGFloat { max(8, (v / 8).rounded(.up) * 8) }
        return CGSize(width: up8(w), height: up8(h))
    }

    /// 只查内存, 同步。视图在 body 里用它, 滚回来时不闪纸。
    public nonisolated func cachedImage(_ key: Key) -> CGImage? {
        memory.image(for: key.identifier)
    }

    /// 取图: 内存 → 磁盘 → 渲染 (后台)。画不出的配方返回 nil。
    public func image(for key: Key) async -> CGImage? {
        await load(key)?.image
    }

    /// 同 `image(for:)`, 带出处。
    public func load(_ key: Key) async -> Loaded? {
        let id = key.identifier
        if let hit = memory.image(for: id) { return Loaded(image: hit, source: .memory) }
        guard key.recipe.isSupported else { return nil }
        if let running = inFlight[key] { return await running.value }

        let fileURL = directory?.appendingPathComponent(key.fileName)
        let directory = directory
        let task = Task.detached(priority: .userInitiated) { () -> Loaded? in
            if let fileURL, let image = Self.readPNG(fileURL) { return Loaded(image: image, source: .disk) }
            guard let image = Self.render(key.recipe, pixelSize: key.pixelSize, dark: key.dark) else { return nil }
            if let fileURL, let directory {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                Self.writePNG(image, to: fileURL)
            }
            return Loaded(image: image, source: .rendered)
        }
        inFlight[key] = task
        let loaded = await task.value
        inFlight[key] = nil
        if let loaded {
            memory.insert(loaded.image, for: id)
            if loaded.source == .rendered {
                renderCount += 1
                if !trimmed { trimmed = true; await trimDisk() }
            }
        }
        return loaded
    }

    /// 清内存 (和磁盘)。
    public func removeAll(includingDisk: Bool = false) {
        memory.removeAll()
        guard includingDisk, let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// 磁盘超过 `diskByteLimit` 时按修改时间从旧到新删。
    public func trimDisk(limit: Int = PoetScreenArtCache.diskByteLimit) async {
        guard let directory else { return }
        await Task.detached(priority: .utility) {
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
            else { return }
            var entries = files.compactMap { url -> (URL, Int, Date)? in
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
                return (url, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
            }
            var total = entries.reduce(0) { $0 + $1.1 }
            guard total > limit else { return }
            entries.sort { $0.2 < $1.2 }
            for (url, size, _) in entries where total > limit {
                try? FileManager.default.removeItem(at: url)
                total -= size
            }
        }.value
    }

    // MARK: 纯函数 (任意线程)

    /// 直接渲染, 不经缓存。线程安全 (ZXArt 的矢量栅格化自带锁, 逐字节确定)。
    public nonisolated static func render(_ recipe: PoetScreenArt, pixelSize: CGSize, dark: Bool) -> CGImage? {
        ZXArt.render(procedural: recipe.procedural, palette: recipe.palette(dark: dark), pixelSize: pixelSize)
    }

    nonisolated static func readPNG(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // 立刻解码, 别把解码推迟到主线程上屏时。
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    nonisolated static func writePNG(_ image: CGImage, to url: URL) {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return }
        try? (data as Data).write(to: url, options: .atomic)
    }
}

/// `NSCache` 本身线程安全 (文档保证), 包一层给 actor 的 nonisolated 同步读用。
private final class MemoryStore: @unchecked Sendable {
    private final class Box {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let cache = NSCache<NSString, Box>()

    init(costLimit: Int) {
        cache.totalCostLimit = costLimit
        cache.countLimit = 24
    }

    func image(for id: String) -> CGImage? { cache.object(forKey: id as NSString)?.image }

    func insert(_ image: CGImage, for id: String) {
        cache.setObject(Box(image), forKey: id as NSString, cost: image.bytesPerRow * image.height)
    }

    func removeAll() { cache.removeAllObjects() }
}
