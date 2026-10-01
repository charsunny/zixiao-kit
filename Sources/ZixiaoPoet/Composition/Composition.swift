//  Composition.swift — L2 编成层的解码
//
//  Navigation and curated introductions are versioned with the app; primary data comes from the store.
//  The composition file ships in the product's own bundle (not in this package): the kernel only
//  knows the slots, each app injects its poet through `PoetComposition.load(from:)`.

import Foundation
import ZixiaoCalendar

public struct PoetComposition: Decodable, Sendable {
    public let schemaVersion: Int
    public let poet: Poet
    public let app: AppMeta
    public let identity: Identity
    public let data: DataManifest?
    public let editorial: Editorial?
    /// 书房的云端书架; 缺省时书房不显示。
    public let library: PoetLibrary?

    /// JSON 里 capabilities 的键是字符串；JSONDecoder 不直接支持
    /// RawRepresentable 枚举做字典键，所以先按 String 解，再收敛成枚举。
    public let capabilities: [CapabilityID: Placement]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, poet, app, identity, data, editorial, library, capabilities
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        poet = try c.decode(Poet.self, forKey: .poet)
        app = try c.decode(AppMeta.self, forKey: .app)
        identity = try c.decode(Identity.self, forKey: .identity)
        data = try c.decodeIfPresent(DataManifest.self, forKey: .data)
        editorial = try c.decodeIfPresent(Editorial.self, forKey: .editorial)
        library = try c.decodeIfPresent(PoetLibrary.self, forKey: .library)
        let raw = try c.decode([String: Placement].self, forKey: .capabilities)
        capabilities = raw.reduce(into: [:]) { acc, kv in
            if let id = CapabilityID(rawValue: kv.key) { acc[id] = kv.value }
        }
    }

    /// 读 App 包里的编成。编成随包发, 冷启动离线可得 —— 导航结构不该等网络。
    ///
    /// - Parameters:
    ///   - bundle: 编成所在的包, 默认主包 (各产品 App 的 Resources/composition.json)。
    ///   - name: 文件名 (不含 .json)。
    public static func load(from bundle: Bundle = .main,
                            name: String = "composition") throws -> PoetComposition {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CompositionError.notFound(name)
        }
        do {
            return try JSONDecoder().decode(PoetComposition.self, from: Data(contentsOf: url))
        } catch {
            throw CompositionError.unreadable(name, String(describing: error))
        }
    }
}

public enum CompositionError: LocalizedError, Sendable {
    case notFound(String)
    case unreadable(String, String)
    public var errorDescription: String? {
        switch self {
        case .notFound(let n): return "App 包里找不到编成文件 \(n).json"
        case .unreadable(let n, _): return "编成文件 \(n).json 无法解析"
        }
    }
}

// MARK: - 诗人与应用

public struct Poet: Decodable, Sendable {
    public let slug: String, name: String, dynasty: Dynasty
    public let style: String?, hao: String?
    public let birth: Int, death: Int
    public let datesNote: String?
}

public struct AppMeta: Decodable, Sendable {
    public let bundleId: String, displayName: String
    public let tagline: String?, thesis: String?
    /// 隐私政策页 (书房 → 关于)。App Store 审核要求 App 内可达; 缺省时关于页不放这一条。
    public let privacyURL: String?
    /// 支持与反馈页 (书房 → 关于)。
    public let supportURL: String?
    /// 「内容来源」署名, 逐条显示在关于页 (底本、开放语料库及其许可)。署名写在各 App 的编成里,
    /// 内核不认识任何一家来源。
    public let credits: [String]?

    /// `privacyURL` 解析成 URL; 写错 (解析不出 http/https) 时为 nil, 界面不放这条链接。
    public var privacyLink: URL? { Self.webURL(privacyURL) }
    /// `supportURL` 解析成 URL。
    public var supportLink: URL? { Self.webURL(supportURL) }

    private static func webURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    /// 用户数据的隔离键。取 bundle id 的末段：
    /// com.example.poetapp → "poetapp"。
    /// 标识应用而不是诗人 —— 一个诗人将来可能有不止一个应用。
    public var appSlug: String {
        bundleId.components(separatedBy: ".").last ?? bundleId
    }
}

public enum Dynasty: String, Decodable, Sendable { case tang, song, wudai, yuan, ming, qing }

// MARK: - 能力与分量

/// L1 已实现的全部能力。新增一项 = 内核扩容，不是给某位诗人开后门。
public enum CapabilityID: String, Decodable, Sendable, CaseIterable, Hashable {
    case daily, corpus, itinerary, network, context, epochs, search, profile

    /// SF Symbol。能力自己带图标，编成不管这一层。
    public var symbol: String {
        switch self {
        case .daily:     return "calendar"
        case .corpus:    return "book"
        case .itinerary: return "point.topleft.down.to.point.bottomright.curvepath"
        case .network:   return "point.3.connected.trianglepath.dotted"
        case .context:   return "chart.line.uptrend.xyaxis"
        case .epochs:    return "timeline.selection"
        case .search:    return "magnifyingglass"
        case .profile:   return "books.vertical"
        }
    }
}

public enum Prominence: String, Decodable, Sendable {
    /// iOS 26+ 从胶囊里分离出去的圆钮。系统只由 Tab(role: .search) 承载 ——
    /// 至多一个，且只能是检索类能力。零态可承载该诗人最该被看见的界面。
    case hero
    /// 悬浮胶囊，2–4 个，按 order 排。
    case tab
    /// 寄居在另一能力内部的镜头 / 图层。
    case lens
    /// 这位诗人没有这个能力。允许缺席是本架构的要害 —— 敢删，才不像模板。
    case absent
}

/// 各能力的专属配置字段互不相交，所以摊平成一个结构直接解码，
/// 不做 per-capability 的多态容器 —— 那会让解码代码比它省下的还多。
public struct Placement: Decodable, Sendable {
    public let prominence: Prominence
    public let label: String
    public let order: Int?
    public let host: CapabilityID?

    // daily
    public let cards: [DailyCard]?
    public let onThisDay: OnThisDay?
    // corpus
    public let genres: [Genre]?
    public let reading: Reading?
    // itinerary
    public let fidelity: Fidelity?
    public let basemap: Basemap?
    public let scope: Scope?
    public let continuity: Continuity?
    public let pivot: Int?
    public let layers: [Layer]?
    public let lenses: [Lens]?
    public let emphasisStyle: EmphasisStyle?
    // network
    public let minWeight: Int?
    public let groups: [AssociateGroup]?
    // context
    public let track: String?
    // search
    public let zeroState: ZeroState?
}

public enum DailyCard: String, Decodable, Sendable, Hashable {
    case workOfDay = "work-of-day"
    case onThisDay = "on-this-day"
    case anecdote, resume
    case epochNote = "epoch-note"
}

public struct OnThisDay: Decodable, Sendable {
    public enum Calendar: String, Decodable, Sendable { case lunar, gregorian }
    public enum Fallback: String, Decodable, Sendable {
        case nearestDay = "nearest-day", sameMonth = "same-month", hide
    }
    public let calendar: Calendar
    public let fallback: Fallback
}

public struct Genre: Decodable, Sendable, Identifiable {
    /// pending 的体裁不在界面上露出 —— 宁可少一个入口，
    /// 不要给一个点进去是空的入口。
    public enum Status: String, Decodable, Sendable { case ready, partial, pending }
    public let id: String, label: String
    public let count: Int?
    public let status: Status
    public var isBrowsable: Bool { status != .pending }
}

public struct Reading: Decodable, Sendable {
    public enum Orientation: String, Decodable, Sendable { case vertical, horizontal }
    public enum Variant: String, Decodable, Sendable { case simplified, traditional, both }
    public let defaultOrientation: Orientation
    public let allowToggle: Bool
    public let textVariant: Variant
}

/// 史料置信度，不是工程偏好。approximate 时界面柔化线条、隐去精确年份、
/// 纪年加「约」前缀 —— 把推测画成精确轨迹，是拿工程便利伪造史料。
public enum Fidelity: String, Decodable, Sendable { case precise, approximate }
public enum Basemap: String, Decodable, Sendable { case geographic, illustrated }
public enum Scope: String, Decodable, Sendable { case national, local }
public enum Continuity: String, Decodable, Sendable { case continuous, ruptured }
public enum Layer: String, Decodable, Sendable {
    case spine   // poet_routes：4–12 站叙事骨架，全局缩放用
    case full    // poet_stations：密集驻点，拖拽与详情用
}
public enum EmphasisStyle: String, Decodable, Sendable { case seal, halo, none }
public enum ZeroState: String, Decodable, Sendable { case map, estate, recent, themes }

public struct Lens: Decodable, Sendable, Identifiable, Hashable {
    public enum Kind: String, Decodable, Sendable { case map, chronicle, estate, seasons }
    public let id: Kind
    public let label: String
    public let scope: Scope?
}

public struct AssociateGroup: Decodable, Sendable, Identifiable, Hashable {
    public let id: String, label: String
    public let color: String?
}

public struct DataManifest: Decodable, Sendable {
    public struct Stations: Decodable, Sendable { public let spine, full: Int?; public let placesResolved: Bool? }
    public struct Events: Decodable, Sendable { public let count, dayPrecise: Int? }
    public struct Relations: Decodable, Sendable { public let count, visible, candidate: Int? }
    public let stations: Stations?, events: Events?, relations: Relations?
    public let sources: [String]?
}

// MARK: - 编成查询

public extension PoetComposition {
    /// 胶囊内的 tab，按 order 升序。
    var capsuleTabs: [(id: CapabilityID, placement: Placement)] {
        capabilities.filter { $0.value.prominence == .tab }
            .sorted { ($0.value.order ?? .max) < ($1.value.order ?? .max) }
            .map { (id: $0.key, placement: $0.value) }
    }

    /// 分离圆钮，至多一个。
    var heroTab: (id: CapabilityID, placement: Placement)? {
        capabilities.first { $0.value.prominence == .hero }
            .map { (id: $0.key, placement: $0.value) }
    }

    /// 寄居在 host 内部的镜头。
    func lenses(hostedIn host: CapabilityID) -> [(id: CapabilityID, placement: Placement)] {
        capabilities.filter { $0.value.prominence == .lens && $0.value.host == host }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { (id: $0.key, placement: $0.value) }
    }

    func placement(_ id: CapabilityID) -> Placement? {
        capabilities[id].flatMap { $0.prominence == .absent ? nil : $0 }
    }

    /// 首页只装配编成明确列出的卡片，并保留 JSON 中的次序。
    /// 旧编成没有 cards 时保留最小的「选读 + 续读」行为。
    var configuredDailyCards: [DailyCard] {
        guard let daily = placement(.daily) else { return [] }
        var seen = Set<DailyCard>()
        return (daily.cards ?? [.workOfDay, .resume]).filter { seen.insert($0).inserted }
    }

    /// 日精度为 0 是内容事实，优先级高于一个过时的卡片声明。
    /// manifest 未给出覆盖量时维持旧编成兼容，由请求结果决定空态。
    var enabledDailyCards: [DailyCard] {
        configuredDailyCards.filter { card in
            guard card == .onThisDay else { return true }
            guard placement(.daily)?.onThisDay != nil else { return false }
            return data?.events?.dayPrecise.map { $0 > 0 } ?? true
        }
    }

    var declaresChronicleData: Bool {
        (data?.events?.count ?? 0) > 0
    }

    var declaresNetworkData: Bool {
        (data?.relations?.visible ?? 0) > 0
    }

    var eraName: EraNaming { EraNaming(style: identity.chronology?.style ?? .gregorian) }
}

/// 书房里的云端书架 (编成的可选 `library` 块)。书目由各产品的编成给出 (id / 地址 / 校验值取自书库目录, 由
/// 脚本生成), 内核只负责按分组画书架、按 url + sha256 下载、用阅读器打开。没有这个块, 书房就没有书架。
public struct PoetLibrary: Codable, Sendable, Hashable {
    /// 书架在书房里的位置; 目前只有 `section` (书房里的一个分区)。
    public let prominence: String
    /// 分区标题 (如「东坡著述」)。
    public let label: String
    public let books: [Entry]

    public init(prominence: String = "section", label: String, books: [Entry]) {
        self.prominence = prominence
        self.label = label
        self.books = books
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prominence = try c.decodeIfPresent(String.self, forKey: .prominence) ?? "section"
        label = try c.decode(String.self, forKey: .label)
        books = try c.decode([Entry].self, forKey: .books)
    }

    private enum CodingKeys: String, CodingKey { case prominence, label, books }

    /// 一本书。字段与书库目录一一对应: `hash` 是 `sha256:<hex>` (对解压后的 book.json), `bytes` 是
    /// `.json.gz` 的大小, `version` 决定本机落盘位置。
    public struct Entry: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let title: String
        /// 封面用短题; 目录原题过长时给。
        public let shortTitle: String?
        public let author: String?
        public let dynasty: String?
        public let url: String
        public let hash: String
        public let version: Int
        public let bytes: Int?
        public let group: String

        public init(id: String, title: String, shortTitle: String? = nil, author: String? = nil,
                    dynasty: String? = nil, url: String, hash: String, version: Int = 1, bytes: Int? = nil,
                    group: String) {
            self.id = id; self.title = title; self.shortTitle = shortTitle; self.author = author
            self.dynasty = dynasty; self.url = url; self.hash = hash; self.version = version
            self.bytes = bytes; self.group = group
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            shortTitle = try c.decodeIfPresent(String.self, forKey: .shortTitle)
            author = try c.decodeIfPresent(String.self, forKey: .author)
            dynasty = try c.decodeIfPresent(String.self, forKey: .dynasty)
            url = try c.decode(String.self, forKey: .url)
            hash = try c.decode(String.self, forKey: .hash)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
            bytes = try c.decodeIfPresent(Int.self, forKey: .bytes)
            group = try c.decode(String.self, forKey: .group)
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, shortTitle, author, dynasty, url, hash, version, bytes, group
        }

        /// 封面与列表用的书名。
        public var coverTitle: String { shortTitle ?? title }

        /// 「宋 · 苏轼」; 两样都没有为 nil。
        public var byline: String? {
            let parts = [dynasty, author].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        public var downloadURL: URL? { URL(string: url) }
    }

    /// 一行书架: 分组名 + 该组的书。
    public struct Group: Sendable, Hashable, Identifiable {
        public let name: String
        public let books: [Entry]
        public var id: String { name }
    }

    /// 按分组首次出现的次序分行, 行内保持 `books` 的次序。
    public var groups: [Group] {
        var order: [String] = []
        var buckets: [String: [Entry]] = [:]
        for book in books {
            if buckets[book.group] == nil { order.append(book.group) }
            buckets[book.group, default: []].append(book)
        }
        return order.map { Group(name: $0, books: buckets[$0] ?? []) }
    }
}
