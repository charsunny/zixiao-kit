//  Collections.swift — 选读合集 (collections-<slug>.json): 诗文 Tab 门面上的主题合集
//
//  每个合集 = 一句旨 + 一段导读 + 5–8 篇作品 (各带一句按语) + 一幅画屏 (地望 seed + 季节偏色)。
//  随 App 包发, 经 `PoetResources` 找; 包里没有这份文件 = 这位诗人还没编合集, 诗文根页退回
//  编成里的主题共读与导读的「名篇」(见 `CorpusSelection`)。
//
//  客户端只读、不排序: 数组顺序即陈列顺序, `workIds` 顺序即阅读顺序。

import Foundation

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
