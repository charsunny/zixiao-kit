//  Collections.swift — 选读合集 (collections-<slug>.json): 诗文 Tab 门面上的主题合集
//
//  每个合集 = 一句旨 + 一段导读 + 5–8 篇作品 (各带一句按语) + 一幅画屏 (地望 seed + 季节偏色)。
//  随 App 包发, 经 `PoetResources` 找; 包里没有这份文件 = 这位诗人还没编合集, 诗文根页退回
//  编成里的主题共读与导读的「名篇」(见 `CorpusSelection`)。
//
//  客户端只读、不排序: 数组顺序即陈列顺序, `workIds` 顺序即阅读顺序。

import Foundation
import ZixiaoDesign

/// 一位诗人的选读合集。
public struct PoetCollections: Codable, Sendable, Hashable {
    public let schemaVersion: Int
    /// 诗人 slug (与编成的 poet.slug 一致)。
    public let poet: String
    public let collections: [Collection]

    public init(schemaVersion: Int = PoetCollections.supportedSchemaVersion, poet: String, collections: [Collection]) {
        self.schemaVersion = schemaVersion
        self.poet = poet
        self.collections = collections
    }

    public func collection(id: String) -> Collection? { collections.first { $0.id == id } }

    /// 一个合集。
    public struct Collection: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        /// 合集名 (卡片上竖排)。
        public let title: String
        /// 一句旨 (≤30 字, 卡片上题下那一句)。
        public let thesis: String
        /// 导读 (60–120 字, 合集页开头)。
        public let intro: String
        /// 画屏的地望 seed。
        public let placeSeed: String
        /// 画屏的季节偏色 (spring / summer / autumn / winter); nil 不偏。
        public let season: String?
        /// 作品 id (poems.id), 按阅读顺序。
        public let workIds: [UUID]
        /// 逐篇按语 (≤40 字), 键是作品 id 的字符串。可缺。
        public let notes: [String: String]?

        public init(id: String, title: String, thesis: String, intro: String, placeSeed: String,
                    season: String? = nil, workIds: [UUID], notes: [String: String]? = nil) {
            self.id = id
            self.title = title
            self.thesis = thesis
            self.intro = intro
            self.placeSeed = placeSeed
            self.season = season
            self.workIds = workIds
            self.notes = notes
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, thesis, intro, placeSeed, season, workIds, notes
        }

        /// 作品 id 逐个解: 编辑稿里偶有一条写坏的 id 只丢那一篇, 不让整份合集解不开。
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            thesis = try c.decodeIfPresent(String.self, forKey: .thesis) ?? ""
            intro = try c.decodeIfPresent(String.self, forKey: .intro) ?? ""
            placeSeed = try c.decodeIfPresent(String.self, forKey: .placeSeed) ?? id
            season = try c.decodeIfPresent(String.self, forKey: .season)
            workIds = try c.decode([String].self, forKey: .workIds).compactMap(UUID.init(uuidString:))
            notes = try c.decodeIfPresent([String: String].self, forKey: .notes)
        }

        /// 某篇的按语。键大小写不拘 (编辑脚本有时写大写 uuid)。
        public func note(for workID: UUID) -> String? {
            guard let notes else { return nil }
            let text = notes[workID.uuidString.lowercased()] ?? notes[workID.uuidString]
                ?? notes.first { $0.key.caseInsensitiveCompare(workID.uuidString) == .orderedSame }?.value
            return text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }

        /// 画屏的季节偏色 (认不出的写法当作不偏)。
        public var seasonTint: ZXSeasonTint? { season.flatMap(ZXSeasonTint.init(rawValue:)) }
    }

    // MARK: 载入

    /// 本内核读得懂的格式版本。
    public static let supportedSchemaVersion = 1

    /// 解码随 App 包发的合集。格式版本更高时报错 (不猜新字段)。
    public static func decode(_ data: Data) throws -> PoetCollections {
        let decoded = try JSONDecoder().decode(PoetCollections.self, from: data)
        guard decoded.schemaVersion <= supportedSchemaVersion else {
            throw DecodingError.dataCorrupted(.init(codingPath: [CodingKeys.schemaVersion],
                                                    debugDescription: "schemaVersion \(decoded.schemaVersion) 高于本内核支持的 \(supportedSchemaVersion)"))
        }
        return decoded
    }

    /// 从包里读 `collections-<poetSlug>.json`。没有这份文件、或解不开, 都返回 nil (选读退回编成与导读);
    /// 要区分两者 (诊断) 用 `PoetResources.collections()`。
    public static func load(from bundle: Bundle = .main, poetSlug: String) -> PoetCollections? {
        let resources = PoetResources(bundle: bundle, slug: poetSlug, productName: poetSlug)
        do { return try resources.collections() } catch {
            #if DEBUG
            print("ZixiaoPoet: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
}

// MARK: - 诗文根页上的「一张合集卡」

/// 选读里的一张卡: 来自合集文件; 没有合集文件时退回编成里的主题共读, 再加导读的「名篇」一组。
/// 三种来路在界面上一视同仁 (画屏 + 竖排题 + 旨), 合集页也只认它。
struct CorpusSelection: Identifiable, Hashable, Sendable {
    struct Entry: Hashable, Sendable, Identifiable {
        var id: UUID { workID }
        let workID: UUID
        let note: String?
    }

    let id: String
    let title: String
    let thesis: String
    let intro: String
    /// 画屏配方 (seed 来自数据: 合集的地望, 或编成里的合集 id)。
    let art: PoetScreenArt
    let entries: [Entry]

    var workIDs: [UUID] { entries.map(\.workID) }

    /// 读本「接着读」用的共读 (`ReadingJourney` 只认 `ReadingCollection`)。
    var readingCollection: ReadingCollection {
        ReadingCollection(id: id, title: title, subtitle: thesis, introduction: intro, symbol: "book",
                          works: entries.map { ReadingSelection(poemId: $0.workID, note: $0.note ?? "") })
    }

    init(id: String, title: String, thesis: String, intro: String, art: PoetScreenArt, entries: [Entry]) {
        self.id = id
        self.title = title
        self.thesis = thesis
        self.intro = intro
        self.art = art
        self.entries = entries
    }

    init(_ collection: PoetCollections.Collection) {
        self.init(id: collection.id, title: collection.title, thesis: collection.thesis, intro: collection.intro,
                  art: PoetScreenArt(seed: collection.placeSeed, season: collection.seasonTint),
                  entries: collection.workIds.map { Entry(workID: $0, note: collection.note(for: $0)) })
    }

    /// 编成里的主题共读 (旧格式): 没有地望, 画屏的 seed 用合集 id。
    init(_ collection: ReadingCollection) {
        self.init(id: "editorial.\(collection.id)", title: collection.title, thesis: collection.subtitle,
                  intro: collection.introduction, art: PoetScreenArt(seed: collection.id),
                  entries: collection.works.map { Entry(workID: $0.poemId, note: $0.note) })
    }

    /// 选读的全部卡片。合集文件在就只用它; 不在就是编成的主题共读 + 导读的名篇一组。都没有为空 (整节收起)。
    static func shelf(collections: PoetCollections?, editorial: [ReadingCollection],
                      featured: [FeaturedWork], featuredIntro: String?, seed: String) -> [CorpusSelection] {
        if let collections, !collections.collections.isEmpty {
            return collections.collections.filter { !$0.workIds.isEmpty }.map(CorpusSelection.init)
        }
        var shelf = editorial.filter { !$0.works.isEmpty }.map(CorpusSelection.init)
        if !featured.isEmpty {
            shelf.append(CorpusSelection(
                id: featuredID, title: "名篇", thesis: "从代表作读起",
                intro: featuredIntro ?? "从代表作开始，慢慢读进这位诗人的作品。",
                art: PoetScreenArt(seed: "\(seed)#featured"),
                entries: featured.map { Entry(workID: $0.id, note: $0.note) }))
        }
        return shelf
    }

    static let featuredID = "guide.featured"
}

extension CompositionContext {
    /// 选读合集 (随包 `collections-<slug>.json`)。按包与 slug 记一次, 不在每次重绘时重读文件。
    var collections: PoetCollections? {
        let key = "\(resources.bundleURL.path)|\(resources.slug)"
        if let cached = CollectionsCache.loaded[key] { return cached }
        let loaded: PoetCollections?
        do { loaded = try resources.collections() } catch {
            #if DEBUG
            print("ZixiaoPoet: \(error.localizedDescription)")
            #endif
            loaded = nil
        }
        CollectionsCache.loaded[key] = .some(loaded)
        return loaded
    }

    /// 诗文根页「选读」的卡片 (见 `CorpusSelection.shelf`)。
    var corpusSelections: [CorpusSelection] {
        CorpusSelection.shelf(collections: collections, editorial: composition.editorial?.collections ?? [],
                              featured: guide?.featured ?? [], featuredIntro: composition.editorial?.corpusIntroduction,
                              seed: composition.poet.slug)
    }
}

@MainActor
private enum CollectionsCache {
    static var loaded: [String: PoetCollections?] = [:]
}
