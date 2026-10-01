//  PoetResources.swift — 诗人专属资源的注入点
//
//  内核不带任何一位诗人的资源。导读 (guide-<slug>.json)、书画清单 (artworks-<slug>.json)
//  与书画图片都随各自 App 的包发, 由这里按编成里的 poet.slug 从**同一个包**里找。
//  找不到时报出的错误带产品名 (取自编成的 app.displayName), 不写死任何名字 ——
//  排查时一眼看出是哪个产品的包漏了哪份资源。

import Foundation

/// 诗人资源缺失或损坏。`product` 来自编成 (`app.displayName`)。
public enum PoetResourceError: LocalizedError, Sendable, Equatable {
    /// 包里没有这份资源。
    case missing(product: String, resource: String)
    /// 有, 但解不开。
    case unreadable(product: String, resource: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case .missing(let product, let resource):
            return "\(product) 的 App 包里缺少资源 \(resource)"
        case .unreadable(let product, let resource, _):
            return "\(product) 的资源 \(resource) 无法解析"
        }
    }
}

/// 从一个包里解析某位诗人的随包资源。
///
/// 为什么不缓存解码结果: `CompositionContext` 启动时各取一次就持有, 这里保持无状态,
/// 测试可以随手拿一个临时目录当「包」。
public struct PoetResources: Sendable {
    /// 资源所在包的路径。存 URL 而不是 `Bundle`, 值本身就是 Sendable; 取资源时再按路径开包
    /// (`Bundle(url:)` 对同一路径返回同一实例)。
    public let bundleURL: URL
    /// 资源文件名里的诗人键 (编成的 poet.slug)。
    public let slug: String
    /// 报错时称呼的产品名 (编成的 app.displayName)。
    public let productName: String

    public init(bundle: Bundle = .main, slug: String, productName: String) {
        self.bundleURL = bundle.bundleURL
        self.slug = slug
        self.productName = productName
    }

    public init(bundle: Bundle = .main, composition: PoetComposition) {
        self.init(bundle: bundle, slug: composition.poet.slug, productName: composition.app.displayName)
    }

    public var guideResourceName: String { "guide-\(slug).json" }
    public var artworksResourceName: String { "artworks-\(slug).json" }

    private var bundle: Bundle? { Bundle(url: bundleURL) }

    /// 包里某个文件的 URL (书画图片等)。没有返回 nil。
    public func url(forAsset name: String) -> URL? {
        if let url = bundle?.url(forResource: name, withExtension: nil) { return url }
        // 扁平目录 (测试、预览拿临时目录当包) 不一定被 Bundle 认作资源根, 直接看一眼文件。
        let direct = bundleURL.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: direct.path) ? direct : nil
    }

    /// 导读。每个产品都该有; 缺失或损坏都抛错。
    func guide() throws -> PoetGuide {
        try decode(guideResourceName, PoetGuide.decode)
    }

    /// 书画清单。只有部分诗人有书画, 缺失不算错 (返回空); 有但解不开才抛错。
    func artworks() throws -> [Artwork] {
        guard url(forAsset: artworksResourceName) != nil else { return [] }
        return try decode(artworksResourceName, Artwork.decodeList)
    }

    private func decode<T>(_ name: String, _ decoder: (Data) throws -> T) throws -> T {
        let raw = try data(named: name)
        do { return try decoder(raw) } catch {
            throw PoetResourceError.unreadable(product: productName, resource: name,
                                               detail: String(describing: error))
        }
    }

    private func data(named name: String) throws -> Data {
        guard let url = url(forAsset: name) else {
            throw PoetResourceError.missing(product: productName, resource: name)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw PoetResourceError.unreadable(product: productName, resource: name,
                                               detail: String(describing: error))
        }
    }
}
