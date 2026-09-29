import Foundation

/// 书目: 够画书架, 不用把整本书读进来。随包一份快照, 联网再拿云端的刷新。
public struct BookCatalog: Codable, Sendable, Hashable {
    public var schema: Int
    /// 生成日期 (YYYY-MM-DD)。
    public var generated: String
    public var books: [CatalogEntry]

    public init(schema: Int = 1, generated: String = "", books: [CatalogEntry]) {
        self.schema = schema
        self.generated = generated
        self.books = books
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        generated = try c.decodeIfPresent(String.self, forKey: .generated) ?? ""
        books = try c.decodeIfPresent([CatalogEntry].self, forKey: .books) ?? []
    }

    enum CodingKeys: String, CodingKey { case schema, generated, books }

    public func entry(id: String) -> CatalogEntry? { books.first { $0.id == id } }

    public func books(in category: String) -> [CatalogEntry] { books.filter { $0.category == category } }

    /// 精选 (tags 含 `p0`)。
    public var featured: [CatalogEntry] { books.filter(\.isFeatured) }
}

/// 目录里的一条。
public struct CatalogEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var author: String?
    public var dynasty: String?
    public var category: String
    public var subcategory: String?
    public var tags: [String]
    public var version: Int
    /// `sha256:<hex>`, 对**解压后** book.json 的字节 —— gz 字节随压缩器变, 不拿来校。
    public var hash: String?
    /// `.json.gz` 的大小, 下载前给用户看「约 29 KB」。
    public var bytes: Int?
    /// `book.json.gz` 的地址; 缺省即不可下载。保留字符串, 解析失败时照样能上架, 只是不能下载。
    public var url: String?
    public var hasPlain: Bool
    public var summary: String
    /// 随包的书: 不用下载。不在 JSON 里, 由 `BookStore` 合并目录时标记。
    public var bundled: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, author, dynasty, category, subcategory, tags, version, hash, bytes, url
        case hasPlain = "has_plain"
        case summary, bundled
    }

    public init(
        id: String, title: String, author: String? = nil, dynasty: String? = nil, category: String = "子",
        subcategory: String? = nil, tags: [String] = [], version: Int = 1, hash: String? = nil, bytes: Int? = nil,
        url: String? = nil, hasPlain: Bool = false, summary: String = "", bundled: Bool = false
    ) {
        self.id = id; self.title = title; self.author = author; self.dynasty = dynasty; self.category = category
        self.subcategory = subcategory; self.tags = tags; self.version = version; self.hash = hash
        self.bytes = bytes; self.url = url; self.hasPlain = hasPlain; self.summary = summary; self.bundled = bundled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        dynasty = try c.decodeIfPresent(String.self, forKey: .dynasty)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "子"
        subcategory = try c.decodeIfPresent(String.self, forKey: .subcategory)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        hash = try c.decodeIfPresent(String.self, forKey: .hash)
        bytes = try c.decodeIfPresent(Int.self, forKey: .bytes)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        hasPlain = try c.decodeIfPresent(Bool.self, forKey: .hasPlain) ?? false
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        bundled = try c.decodeIfPresent(Bool.self, forKey: .bundled) ?? false
    }

    public var isFeatured: Bool { tags.contains("p0") }

    /// 封面底下那行小字: 「春秋 · 老子」。
    public var authorLine: String { joinedAuthorLine(dynasty, author) }

    public var downloadURL: URL? { url.flatMap(URL.init(string:)) }

    /// 去掉 `sha256:` 前缀的小写十六进制; 没有 hash 为 nil。
    public var sha256Hex: String? {
        guard let hash, !hash.isEmpty else { return nil }
        let hex = hash.hasPrefix("sha256:") ? String(hash.dropFirst("sha256:".count)) : hash
        return hex.lowercased()
    }
}
