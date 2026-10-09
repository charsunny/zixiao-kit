import Foundation

// book.json schema 1 的 Swift 镜像, 字段与书库 schema 文档 (content-sources.md §4.1) 逐字段对应。
//
// 为什么全部手写 CodingKeys 而不用 `.convertFromSnakeCase`: 段落 id / 摘抄 / 进度都引用这些字段,
// schema 是跨端契约 (Flutter 客户端、Python 流水线、将来的 Supabase 同步都读同一份),
// 显式映射让「改了 JSON 键名」在编译期与解码测试里暴露, 而不是悄悄变成 nil。
//
// 为什么可选字段那么多: 流水线按书的来源逐步补字段 (诗词集段级才有 title/author, 白话要审过才发),
// 旧版 book.json 也要能读。与 Dart 版 `Book.fromJson` 的缺省值保持一致。

/// 一本书。`chapters` 是正文; 其余是书目元数据。
public struct Book: Codable, Sendable, Hashable, Identifiable {
    /// 恒为 1。留着是为了将来 schema 2 出来时能按版本分流解码。
    public var schema: Int
    public var id: String
    /// 内容版本, 流水线手工递增; 云端目录比它决定要不要重下。
    public var version: Int
    public var title: String
    /// 繁体书名, 封面题签可用。
    public var titleHant: String?
    public var author: String?
    public var dynasty: String?
    /// 经 / 史 / 子 / 集。
    public var category: String
    public var subcategory: String?
    public var tags: [String]
    /// 40–80 字导读。
    public var summary: String
    /// `hans` / `hant`; 决定将来要不要做繁简切换。
    public var script: String?
    public var source: BookSource
    public var plain: PlainInfo
    /// 内容哈希: 对 `chapters` 紧凑 JSON 取 sha256, 与元数据无关, 用来判断正文变没变。
    /// 注意它**不是**云端目录里的那个 hash (那个是整份文件字节的), 两者不能互相校验。
    public var hash: String?
    /// 快照日期 (YYYY-MM-DD), 保留原字符串不转 Date —— 它是日历日, 不是时刻。
    public var updated: String?
    public var chapters: [Chapter]

    enum CodingKeys: String, CodingKey {
        case schema, id, version, title
        case titleHant = "title_hant"
        case author, dynasty, category, subcategory, tags, summary, script, source, plain, hash, updated, chapters
    }

    public init(
        schema: Int = 1, id: String, version: Int = 1, title: String, titleHant: String? = nil,
        author: String? = nil, dynasty: String? = nil, category: String = "子", subcategory: String? = nil,
        tags: [String] = [], summary: String = "", script: String? = nil, source: BookSource = BookSource(),
        plain: PlainInfo = PlainInfo(), hash: String? = nil, updated: String? = nil, chapters: [Chapter]
    ) {
        self.schema = schema; self.id = id; self.version = version; self.title = title
        self.titleHant = titleHant; self.author = author; self.dynasty = dynasty; self.category = category
        self.subcategory = subcategory; self.tags = tags; self.summary = summary; self.script = script
        self.source = source; self.plain = plain; self.hash = hash; self.updated = updated; self.chapters = chapters
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        id = try c.decode(String.self, forKey: .id)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        title = try c.decode(String.self, forKey: .title)
        titleHant = try c.decodeIfPresent(String.self, forKey: .titleHant)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        dynasty = try c.decodeIfPresent(String.self, forKey: .dynasty)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "子"
        subcategory = try c.decodeIfPresent(String.self, forKey: .subcategory)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        script = try c.decodeIfPresent(String.self, forKey: .script)
        source = try c.decodeIfPresent(BookSource.self, forKey: .source) ?? BookSource()
        plain = try c.decodeIfPresent(PlainInfo.self, forKey: .plain) ?? PlainInfo()
        hash = try c.decodeIfPresent(String.self, forKey: .hash)
        updated = try c.decodeIfPresent(String.self, forKey: .updated)
        chapters = try c.decode([Chapter].self, forKey: .chapters)
    }

    public var passageCount: Int { chapters.reduce(0) { $0 + $1.passages.count } }

    public func chapter(id: String) -> Chapter? { chapters.first { $0.id == id } }

    /// 段落 id 形如「02.17」, 前半是章 id —— 先定位章再线性找段, 不用给整本书建索引。
    public func passage(id: String) -> Passage? {
        let chapterId = id.split(separator: ".", maxSplits: 1).first.map(String.init) ?? id
        return chapter(id: chapterId)?.passages.first { $0.id == id }
    }

    /// 「春秋 · 老子」; 两样都没有时为空串。
    public var authorLine: String { joinedAuthorLine(dynasty, author) }
}

/// 底本出处。书级 `source` 是许可证与署名的依据, 界面的「底本 · …」一行读它。
public struct BookSource: Codable, Sendable, Hashable {
    public var name: String
    public var url: String
    public var edition: String?
    /// 抓取快照日期。
    public var retrieved: String?
    public var license: String
    public var attribution: String
    /// 维基文库索引页的修订号, 复现快照用。
    public var revid: Int?
    /// 分页抓取的书 (论语二十篇) 每页一个修订号。
    public var pages: [SourcePage]?
    /// 互校的第二源, 如「daizhige-org:儒藏/四书/论语.md」。
    public var crossChecked: [String]?

    enum CodingKeys: String, CodingKey {
        case name, url, edition, retrieved, license, attribution, revid, pages
        case crossChecked = "cross_checked"
    }

    public init(
        name: String = "", url: String = "", edition: String? = nil, retrieved: String? = nil,
        license: String = "", attribution: String = "", revid: Int? = nil, pages: [SourcePage]? = nil,
        crossChecked: [String]? = nil
    ) {
        self.name = name; self.url = url; self.edition = edition; self.retrieved = retrieved
        self.license = license; self.attribution = attribution; self.revid = revid; self.pages = pages
        self.crossChecked = crossChecked
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        edition = try c.decodeIfPresent(String.self, forKey: .edition)
        retrieved = try c.decodeIfPresent(String.self, forKey: .retrieved)
        license = try c.decodeIfPresent(String.self, forKey: .license) ?? ""
        attribution = try c.decodeIfPresent(String.self, forKey: .attribution) ?? ""
        revid = try c.decodeIfPresent(Int.self, forKey: .revid)
        pages = try c.decodeIfPresent([SourcePage].self, forKey: .pages)
        crossChecked = try c.decodeStringList(forKey: .crossChecked)
    }
}

public struct SourcePage: Codable, Sendable, Hashable {
    public var title: String
    public var revid: Int?

    public init(title: String, revid: Int? = nil) {
        self.title = title
        self.revid = revid
    }
}

/// 书级白话说明。`kind` 决定界面标不标「意译」、内测渠道外显不显示草稿。
public struct PlainInfo: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case none
        case llmDraft = "llm-draft"
        case reviewed
    }

    /// 原字符串; 用 `kindValue` 取枚举。保留原串是为了遇到未知取值时不整本书解码失败。
    public var kind: String
    /// 界面上的叫法, 如「意译」。
    public var label: String?
    public var model: String?
    public var reviewedBy: String?

    enum CodingKeys: String, CodingKey {
        case kind, label, model
        case reviewedBy = "reviewed_by"
    }

    public init(kind: String = Kind.none.rawValue, label: String? = nil, model: String? = nil, reviewedBy: String? = nil) {
        self.kind = kind; self.label = label; self.model = model; self.reviewedBy = reviewedBy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? Kind.none.rawValue
        label = try c.decodeIfPresent(String.self, forKey: .label)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        reviewedBy = try c.decodeIfPresent(String.self, forKey: .reviewedBy)
    }

    /// 不认识的取值当作 `.none` —— 宁可不显示白话, 也不把没审过的东西当定稿。
    public var kindValue: Kind { Kind(rawValue: kind) ?? .none }
}

/// 一章 (论语的一篇、道德经的一章、禅诗选的一位作者)。
public struct Chapter: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    /// 章序, 从 1 起。汉字页码与「第十七章」由它生成。
    public var no: Int
    public var title: String
    /// JSON 键是 `paragraphs` (schema 1 的叫法); Swift 侧统一叫 Passage, 避免与排版里的「段」混淆。
    public var passages: [Passage]

    enum CodingKeys: String, CodingKey {
        case id, no, title
        case passages = "paragraphs"
    }

    public init(id: String, no: Int, title: String, passages: [Passage]) {
        self.id = id; self.no = no; self.title = title; self.passages = passages
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        no = try c.decodeIfPresent(Int.self, forKey: .no) ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        passages = try c.decode([Passage].self, forKey: .passages)
    }
}

/// 一段。id 稳定 —— 今日一句、摘抄、阅读进度都靠它定位, 所以流水线改分段时必须升 version。
public struct Passage: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    /// 只放原文。诗以 `\n` 分句, 竖排时每句起一列。
    public var text: String
    /// 白话槽位: 没审过的段落不发, 缺则界面不显示。
    public var plain: String?
    public var notes: [PassageNote]
    public var tags: [String]?
    /// 诗词集每首一段, 段级带题、作者、朝代。
    public var title: String?
    public var author: String?
    public var dynasty: String?
    /// 段级出处 (诗词集逐首注明公版来源)。
    public var source: PassageSource?
    /// 诗词集: 这一首是否已对过底本扫描页。
    public var verified: Bool?
    /// 禅诗选: 关联到「禅偈」内容的 id, 供今日页交叉引用。
    public var zenVerses: [String]?

    enum CodingKeys: String, CodingKey {
        case id, text, plain, notes, tags, title, author, dynasty, source, verified
        case zenVerses = "zen_verses"
    }

    public init(
        id: String, text: String, plain: String? = nil, notes: [PassageNote] = [], tags: [String]? = nil,
        title: String? = nil, author: String? = nil, dynasty: String? = nil, source: PassageSource? = nil,
        verified: Bool? = nil, zenVerses: [String]? = nil
    ) {
        self.id = id; self.text = text; self.plain = plain; self.notes = notes; self.tags = tags
        self.title = title; self.author = author; self.dynasty = dynasty; self.source = source
        self.verified = verified; self.zenVerses = zenVerses
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        plain = try c.decodeIfPresent(String.self, forKey: .plain)
        notes = try c.decodeIfPresent([PassageNote].self, forKey: .notes) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        dynasty = try c.decodeIfPresent(String.self, forKey: .dynasty)
        source = try c.decodeIfPresent(PassageSource.self, forKey: .source)
        verified = try c.decodeIfPresent(Bool.self, forKey: .verified)
        zenVerses = try c.decodeIfPresent([String].self, forKey: .zenVerses)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(plain, forKey: .plain)
        // notes 为空不写, 与流水线产物保持同形, 便于字节级比对。
        if !notes.isEmpty { try c.encode(notes, forKey: .notes) }
        try c.encodeIfPresent(tags, forKey: .tags)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(author, forKey: .author)
        try c.encodeIfPresent(dynasty, forKey: .dynasty)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encodeIfPresent(verified, forKey: .verified)
        try c.encodeIfPresent(zenVerses, forKey: .zenVerses)
    }

    /// 空串与缺失同等对待: 流水线偶尔会留空槽。
    public var hasPlain: Bool { !(plain ?? "").isEmpty }

    /// 诗按 `\n` 分句; 散文就是一句。
    public var lines: [String] { text.components(separatedBy: "\n") }
}

/// 一条注: 锚在段里某个词上, 注明出处 (朱熹集注、王弼……)。将来做夹注就读它。
public struct PassageNote: Codable, Sendable, Hashable {
    public var anchor: String
    public var text: String
    public var src: String?

    public init(anchor: String, text: String, src: String? = nil) {
        self.anchor = anchor; self.text = text; self.src = src
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        anchor = try c.decodeIfPresent(String.self, forKey: .anchor) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        src = try c.decodeIfPresent(String.self, forKey: .src)
    }

    enum CodingKeys: String, CodingKey { case anchor, text, src }
}

/// 段级出处。诗词集每首来源各异, 字段是书级 `BookSource` 的超集且全部可选 ——
/// 实测禅诗选里同一个键 (`cross_checked`) 有时是字符串有时是数组, 所以这里宽松解码。
public struct PassageSource: Codable, Sendable, Hashable {
    public var name: String?
    public var url: String?
    /// 维基文库页题。
    public var page: String?
    public var revid: Int?
    public var retrieved: String?
    public var license: String?
    public var edition: String?
    public var section: String?
    /// 扫描页 (`Page:` 命名空间), 用于人工核对。
    public var scanPages: String?
    public var scanURL: String?
    public var scanRevids: [Int]?
    public var crossChecked: [String]?

    enum CodingKeys: String, CodingKey {
        case name, url, page, revid, retrieved, license, edition, section
        case scanPages = "scan_pages"
        case scanURL = "scan_url"
        case scanRevids = "scan_revids"
        case crossChecked = "cross_checked"
    }

    public init(
        name: String? = nil, url: String? = nil, page: String? = nil, revid: Int? = nil, retrieved: String? = nil,
        license: String? = nil, edition: String? = nil, section: String? = nil, scanPages: String? = nil,
        scanURL: String? = nil, scanRevids: [Int]? = nil, crossChecked: [String]? = nil
    ) {
        self.name = name; self.url = url; self.page = page; self.revid = revid; self.retrieved = retrieved
        self.license = license; self.edition = edition; self.section = section; self.scanPages = scanPages
        self.scanURL = scanURL; self.scanRevids = scanRevids; self.crossChecked = crossChecked
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        page = try? c.decodeIfPresent(String.self, forKey: .page)
        revid = try? c.decodeIfPresent(Int.self, forKey: .revid)
        retrieved = try? c.decodeIfPresent(String.self, forKey: .retrieved)
        license = try? c.decodeIfPresent(String.self, forKey: .license)
        edition = try? c.decodeIfPresent(String.self, forKey: .edition)
        section = try? c.decodeIfPresent(String.self, forKey: .section)
        scanPages = try? c.decodeIfPresent(String.self, forKey: .scanPages)
        scanURL = try? c.decodeIfPresent(String.self, forKey: .scanURL)
        scanRevids = try? c.decodeIfPresent([Int].self, forKey: .scanRevids)
        crossChecked = try c.decodeStringList(forKey: .crossChecked)
    }
}

extension KeyedDecodingContainer {
    /// 「一个字符串或字符串数组」统一成数组; 其他形状当作缺失, 不让一个旁注字段拖垮整本书。
    func decodeStringList(forKey key: Key) throws -> [String]? {
        if let list = try? decodeIfPresent([String].self, forKey: key) { return list }
        if let single = try? decodeIfPresent(String.self, forKey: key) { return [single] }
        return nil
    }
}

package func joinedAuthorLine(_ parts: String?...) -> String {
    parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
}
