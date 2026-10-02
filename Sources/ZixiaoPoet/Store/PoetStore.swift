//  PoetStore.swift — 数据层。对应 migration 061 的六张表。
//
//  纪年一律夏历：poet_events.year/month/day 是「元丰五年七月十六日」，
//  不是公历 1082-07-16，别拿去做 Date 运算。

import Foundation
import Supabase
import ZixiaoCalendar
import ZixiaoCore

// MARK: - 行模型

public struct Station: Decodable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let sequence: Int
    public let sourceName: String
    public let latitude: Double
    public let longitude: Double
    public let year: Int
    public let yearLabel: String?
    public let ageLabel: String?
    public let emphasis: String
    public let places: PlaceRef?

    public struct PlaceRef: Decodable, Sendable, Hashable {
        public let name: String            // 古地名：汴京 / 眉州 / 嘉州
        public let modern_name: String?
    }

    public var isEmphasized: Bool { emphasis != "none" }

    /// 有古地名就用古地名 —— 他去的是「汴京」，不是「开封市」。
    /// 488 站里 257 站已解析到 places；其余退回现代名去掉行政后缀。
    /// 剩下那 126 个需要考据宋代政区，不能靠脚本编，所以先照现代名显示。
    public var displayName: String {
        places?.name ?? sourceName.replacingOccurrences(
            of: "[市县区]$", with: "", options: .regularExpression)
    }
    /// 古今不同时，界面上可以小字附注今名。
    public var modernNote: String? {
        guard let p = places, let m = p.modern_name, m != p.name else { return nil }
        return m
    }

    enum CodingKeys: String, CodingKey {
        case id, sequence, latitude, longitude, year, emphasis, places
        case sourceName = "source_name", yearLabel = "year_label", ageLabel = "age_label"
    }
}

public struct PoetEvent: Decodable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let stationId: UUID?
    public let year: Int
    public let month: Int?
    public let day: Int?
    public let isLeapMonth: Bool
    public let datePrecision: String
    public let content: String
    public let workTitles: [String]
    public let fullText: String?
    public let sourceRef: String?

    public var hasDayPrecision: Bool { datePrecision == "day" }
    /// 「闰九月十九日」。月份用中文，与正文的写法一致。
    public var lunarLabel: String? {
        guard let month else { return nil }
        let mn = ["","正","二","三","四","五","六","七","八","九","十","十一","十二"]
        let head = "\(isLeapMonth ? "闰" : "")\(mn[min(month, 12)])月"
        guard let day else { return head }
        return head + Self.cnDay(day)
    }
    static func cnDay(_ d: Int) -> String {
        let u = ["","一","二","三","四","五","六","七","八","九","十"]
        if d <= 10 { return "初" + u[d] }
        if d < 20  { return "十" + u[d - 10] }
        if d == 20 { return "二十" }
        if d < 30  { return "二十" + u[d - 20] }
        return "三十"
    }
    enum CodingKeys: String, CodingKey {
        case id, year, month, day, content
        case stationId = "station_id", isLeapMonth = "is_leap_month"
        case datePrecision = "date_precision", workTitles = "work_titles"
        case fullText = "full_text", sourceRef = "source_ref"
    }
}

/// 叙事骨架的一站。来自既有的 poet_routes（每位诗人 4–12 站），
/// 经纬度经 places 关联取得 —— 全局缩放时画它，而不是 488 个点。
public struct RouteStop: Decodable, Sendable, Identifiable, Hashable {
    public struct Place: Decodable, Sendable, Hashable {
        public let name: String
        public let latitude: Double?
        public let longitude: Double?
    }
    public var id: Int { sequence }
    public let sequence: Int
    public let yearStart: Int?
    public let yearEnd: Int?
    public let event: String?
    public let places: Place?
    enum CodingKeys: String, CodingKey {
        case sequence, event, places
        case yearStart = "year_start", yearEnd = "year_end"
    }
}

public extension PoetEvent {
    /// 年谱条目的可读叙事。原始 content 是「纪年，在某地，任某官。叙事。作品：…（出处）」
    /// 再接内嵌的作品全文 —— 界面上只要中间那段叙事。
    ///
    /// 注意别用正则 `作品：.*$` 去尾：Swift 的 `.` 默认不跨行，
    /// 而内嵌全文是多行的，会漏掉一大片。按分隔符取前缀才对。
    var narrative: String {
        (content.components(separatedBy: "作品：").first ?? content)
            .replacingOccurrences(of: #"^\d{4}年[^，]*，"#, with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public extension Occasion.Event {
    var narrative: String {
        (content.components(separatedBy: "作品：").first ?? content)
            .replacingOccurrences(of: #"^\d{4}年[^，]*，"#, with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct Associate: Decodable, Sendable, Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let courtesyName: String?
    public let groupKey: String?
    public let weight: Int
    public let firstYear: Int?
    public let lastYear: Int?
    enum CodingKeys: String, CodingKey {
        case name, weight
        case courtesyName = "courtesy_name", groupKey = "group_key"
        case firstYear = "first_year", lastYear = "last_year"
    }
}

public struct Epoch: Decodable, Sendable, Identifiable, Hashable {
    public var id: Int { sequence }
    public let sequence: Int
    public let label: String
    public let yearStart: Int
    public let yearEnd: Int?
    public let kind: String?
    public let note: String?
    public func contains(_ year: Int) -> Bool {
        year >= yearStart && year <= (yearEnd ?? Int.max)
    }
    enum CodingKeys: String, CodingKey {
        case sequence, label, kind, note
        case yearStart = "year_start", yearEnd = "year_end"
    }
}

/// 库里的一首作品。translation / appreciation / highlights 是 PoetryHub
/// 的 AI 增强管线已经填好的 —— 分层阅读的料是现成的，不用另建。
public struct Poem: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let title: String
    public let form: String
    public let content: String
    public let paragraphs: [String]?
    public let cipai: String?
    public let summary: String?
    public let appreciation: String?
    public let translation: [String]?
    public let highlights: [String]?
    /// 细体裁 (文): 尺牍 / 书后 / 奏议 …。诗词与早先入库的文为空。
    public let genre: String?
    /// 体裁大类 (文): 书简 / 制诰 / 题跋 …。为空的归入「其他」(`PoetGenreIndex.otherGroup`)。
    public let genreGroup: String?
    /// 出处 (jsonb)。只解码界面要用的书名与章名, 其余键 (互校、flags、notes …) 忽略。
    public let provenance: Provenance?

    public struct Provenance: Codable, Sendable, Hashable {
        public let bookTitle: String?
        public let chapterTitle: String?
        enum CodingKeys: String, CodingKey {
            case bookTitle = "book_title", chapterTitle = "chapter_title"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, form, content, paragraphs, cipai, summary, appreciation, translation, highlights
        case genre, provenance
        case genreGroup = "genre_group"
    }

    public var lines: [String] {
        paragraphs?.isEmpty == false ? paragraphs! : content.components(separatedBy: "\n")
    }
    /// 词的标题只有词牌，靠首句才认得出是哪一首。
    public var firstLine: String {
        (lines.first ?? "").prefix(16).description
    }
    /// 读本标题下的出处小字:「细体裁 · 书名 章名」。三样都没有时为 nil (诗词不显示)。
    public var sourceLine: String? {
        let book = [provenance?.bookTitle, provenance?.chapterTitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        let parts = [genre?.trimmingCharacters(in: .whitespacesAndNewlines), book].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// 一首作品的写作场合。poet_event_works 的边 —— 在读本点一首词
/// 能跳到它写成的那一天，就靠它。
public struct Occasion: Decodable, Sendable, Identifiable, Hashable {
    public struct Event: Decodable, Sendable, Hashable {
        public struct Place: Decodable, Sendable, Hashable { public let source_name: String }
        public let id: UUID
        public let year: Int
        public let month: Int?
        public let day: Int?
        public let is_leap_month: Bool
        public let date_precision: String
        public let content: String
        public let poet_stations: Place?
    }
    public var id: String { poet_events?.id.uuidString ?? title }
    public let title: String
    public let match_score: Double?
    public let poet_events: Event?
}

// MARK: - Store

@MainActor
@Observable
public final class PoetStore {
    let client: SupabaseClient
    private let poetName: String
    private var poetId: UUID?

    public private(set) var stations: [Station] = []
    public private(set) var epochs: [Epoch] = []
    public private(set) var associates: [Associate] = []
    public private(set) var spine: [RouteStop] = []
    public private(set) var loadError: String?
    public private(set) var isLoading = false

    /// 只读查询。用户数据 (收藏 / 阅读 / 笔记) 不在这里, 见 `PoetUserData`。
    public init(client: SupabaseClient, poetName: String) {
        self.client = client
        self.poetName = poetName
    }

    /// 冷启动一次性拉回骨架：驻点 488、分期 8、交游 48。
    /// 事目 6,628 条不预载 —— 按驻点或按日期按需查。
    public func bootstrap() async {
        guard !isLoading, stations.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let id = try await resolvePoetId()
            async let s: [Station] = client.from("poet_stations")
                .select("""
                    id,sequence,source_name,latitude,longitude,year,year_label,age_label,emphasis,\
                    places(name,modern_name)
                    """)
                .eq("poet_id", value: id.uuidString).order("sequence").execute().value
            async let e: [Epoch] = client.from("poet_epochs")
                .select("sequence,label,year_start,year_end,kind,note")
                .eq("poet_id", value: id.uuidString).order("sequence").execute().value
            // 只取 visible —— 共现抽出的 candidate 未经复核，星图不渲染。
            async let a: [Associate] = client.from("poet_associates")
                .select("name,courtesy_name,group_key,weight,first_year,last_year")
                .eq("poet_id", value: id.uuidString).eq("status", value: "visible")
                .order("weight", ascending: false).execute().value
            // 叙事骨架：4–12 站，全局缩放时画它。488 个驻点在一屏上会糊成一团 ——
            // 淡线显示他实际走了多少，清晰的骨架讲故事，两层各司其职。
            async let r: [RouteStop] = client.from("poet_routes")
                .select("sequence,year_start,year_end,event,places(name,latitude,longitude)")
                .eq("poet_id", value: id.uuidString).order("sequence").execute().value
            (stations, epochs, associates, spine) = try await (s, e, a, r)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// 首页「旧日此时」。夏历月日直取 (农历由 ZixiaoCalendar 推算, 见 `PoetLunarDay`);
    /// 年谱覆盖不到的日子按编成的 fallback 处理 —— 就近取，而不是给一张空卡。
    public func onThisDay(_ lunar: ZXLunarDate,
                          fallback: OnThisDay.Fallback = .nearestDay) async throws -> [PoetEvent] {
        let hit = try await onThisDay(month: lunar.month, day: lunar.day)
        if !hit.isEmpty {
            return hit
        }
        switch fallback {
        case .hide: return []
        case .sameMonth:
            return try await eventsIn(month: lunar.month)
        case .nearestDay:
            // 往前后各找 3 天。一年只有 12 天需要走到这里。
            for delta in 1...3 {
                for d in [lunar.day - delta, lunar.day + delta] where (1...30).contains(d) {
                    let hit = try await onThisDay(month: lunar.month, day: d)
                    if !hit.isEmpty {
                        return hit
                    }
                }
            }
            return []
        }
    }

    private func eventsIn(month: Int) async throws -> [PoetEvent] {
        let id = try await resolvePoetId()
        return try await client.from("poet_events").select(Self.eventCols)
            .eq("poet_id", value: id.uuidString).eq("date_precision", value: "day")
            .eq("month", value: month).order("year").limit(6).execute().value
    }

    public func onThisDay(month: Int, day: Int) async throws -> [PoetEvent] {
        let id = try await resolvePoetId()
        return try await client.from("poet_events").select(Self.eventCols)
            .eq("poet_id", value: id.uuidString)
            .eq("date_precision", value: "day")
            .eq("month", value: month).eq("day", value: day)
            .order("year").execute().value
    }

    /// 某一年的全部事目。6,628 条不预载 —— 按年取，一年最多几百条。
    public func events(year: Int) async throws -> [PoetEvent] {
        let id = try await resolvePoetId()
        return try await client.from("poet_events").select(Self.eventCols)
            .eq("poet_id", value: id.uuidString).eq("year", value: year)
            .order("month", ascending: true, nullsFirst: true)
            .order("day", ascending: true, nullsFirst: true)
            .execute().value
    }

    /// 编年镜头的骨架：逐年条数。一次聚合，不用把全部事目拉下来数。
    /// 走显式 RPC (migration 065), 客户端不拼 SQL。
    public func eventYearCounts() async throws -> [Int: Int] {
        let id = try await resolvePoetId()
        let rows: [PoetRPC.YearCount] = try await client
            .rpc(PoetRPC.eventYearCounts, params: PoetRPC.EventYearCountsParams(poetId: id))
            .execute().value
        return PoetRPC.yearCounts(rows)
    }

    public func events(at station: Station) async throws -> [PoetEvent] {
        try await client.from("poet_events").select(Self.eventCols)
            .eq("station_id", value: station.id.uuidString)
            .order("year").order("month").order("day").execute().value
    }

    /// Literal name mentions are reading clues, not evidence of a personal encounter.
    public func events(mentioning name: String) async throws -> [PoetEvent] {
        let id = try await resolvePoetId()
        let literal = name.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        guard !literal.isEmpty else { return [] }
        return try await client.from("poet_events").select(Self.eventCols)
            .eq("poet_id", value: id.uuidString).ilike("content", pattern: "%\(literal)%")
            .order("year").order("month").order("day").order("id").limit(60).execute().value
    }

    /// Fetch only the selected row. The exact count keeps every work eligible, beyond the first page.
    public func workOfDay(_ date: Date, form: String) async throws -> Poem? {
        let id = try await resolvePoetId()
        let response = try await client.from("poems").select("id", head: true, count: .exact)
            .eq("author_id", value: id.uuidString).eq("form", value: form).execute()
        guard let total = response.count else { throw URLError(.badServerResponse) }
        guard let index = DailyRotation.index(on: date, count: total) else { return nil }
        let rows: [Poem] = try await client.from("poems")
            .select(Self.poemCols)
            .eq("author_id", value: id.uuidString).eq("form", value: form)
            .order("id").range(from: index, to: index).execute().value
        return rows.first
    }

    /// 按 id 取作品, 保持传入的顺序 (书房的收藏 / 阅读记录用)。
    public func poems(ids: [UUID]) async throws -> [Poem] {
        guard !ids.isEmpty else { return [] }
        let fetched: [Poem] = try await client.from("poems")
            .select(Self.poemCols)
            .in("id", values: ids.map(\.uuidString)).execute().value
        let index = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        return ids.compactMap { index[$0] }
    }

    /// 按 id 取一篇。库里没有返回 nil。
    public func poem(id: UUID) async throws -> Poem? {
        try await poems(ids: [id]).first
    }

    /// 读本的作品列表。按体裁分页取；range 两端都包含，所以末端要减一。
    public func poems(form: String, limit: Int = 400, offset: Int = 0) async throws -> [Poem] {
        try await poems(form: form, genreGroup: nil, genre: nil, limit: limit, offset: offset)
    }

    /// 按大类 / 细体裁筛的作品列表。genreGroup 为 nil 不筛; 为「其他」时取大类为空或字面「其他」的。
    public func poems(form: String, genreGroup: String?, genre: String? = nil,
                      limit: Int = 400, offset: Int = 0) async throws -> [Poem] {
        guard limit > 0 else { return [] }
        let id = try await resolvePoetId()
        let start = max(0, offset)
        var request = client.from("poems")
            .select(Self.poemCols)
            .eq("author_id", value: id.uuidString).eq("form", value: form)
        if let genreGroup { request = Self.filter(request, genreGroup: genreGroup) }
        if let genre { request = request.eq("genre", value: genre) }
        return try await request
            .order("title").order("id")
            .range(from: start, to: start + limit - 1).execute().value
    }

    /// 「其他」既收大类为空的 (早先入库的文), 也收入库时就标成「其他」的。
    private static func filter(_ request: PostgrestFilterBuilder, genreGroup: String) -> PostgrestFilterBuilder {
        genreGroup == PoetGenreIndex.otherGroup
            ? request.or("genre_group.is.null,genre_group.eq.\(PoetGenreIndex.otherGroup)")
            : request.eq("genre_group", value: genreGroup)
    }

    /// 体裁大类与篇数 (按篇数从多到少, 「其他」殿后)。
    public func genreGroups(form: String) async throws -> [(group: String, count: Int)] {
        try await genreIndex(form: form).groups.map { ($0.label, $0.count) }
    }

    /// 大类 → 细体裁目录。走 RPC `poet_genre_groups` (migration 069); 它还没部署 (PGRST202) 或调用失败时,
    /// 退回客户端: 逐页取这位作者该体裁的 genre_group,genre 两列 (每页 1,000 行, 服务端 max-rows 的默认值;
    /// 最多 5,000 行) 在本地数。
    public func genreIndex(form: String) async throws -> PoetGenreIndex {
        let id = try await resolvePoetId()
        do {
            let rows: [PoetRPC.GenreCount] = try await client
                .rpc(PoetRPC.genreGroups, params: PoetRPC.GenreGroupsParams(poetId: id, form: form))
                .execute().value
            return PoetGenreIndex(rows: rows)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return PoetGenreIndex(rows: try await genreRowsFallback(poetId: id, form: form))
        }
    }

    private func genreRowsFallback(poetId: UUID, form: String) async throws -> [PoetRPC.GenreCount] {
        let page = 1_000, cap = 5_000
        var rows: [PoetRPC.GenreCount] = []
        while rows.count < cap {
            let chunk: [PoetRPC.GenreCount] = try await client.from("poems")
                .select("genre_group,genre")
                .eq("author_id", value: poetId.uuidString).eq("form", value: form)
                .order("id").range(from: rows.count, to: rows.count + page - 1).execute().value
            rows += chunk
            if chunk.count < page { break }
        }
        return rows
    }

    /// 列表内检索必须查完整体裁，不能只筛已经翻到的页。上限 200，避免宽泛词拉回过多正文。
    /// genreGroup 非空时只在该大类里找 (大类列表页的检索)。
    public func searchPoems(form: String? = nil, genreGroup: String? = nil,
                            query raw: String, limit: Int = 200) async throws -> [Poem] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cappedLimit = min(max(0, limit), 200)
        guard !query.isEmpty, cappedLimit > 0 else { return [] }
        let id = try await resolvePoetId()
        let pattern = Self.literalSearchPattern(query)
        var request = client.from("poems")
            .select(Self.poemCols)
            .eq("author_id", value: id.uuidString)
        if let form { request = request.eq("form", value: form) }
        if let genreGroup { request = Self.filter(request, genreGroup: genreGroup) }
        return try await request.or("title.ilike.\(pattern),content.ilike.\(pattern)")
            .order("title").order("id").limit(cappedLimit).execute().value
    }

    private static func literalSearchPattern(_ query: String) -> String {
        // 两层转义各管一件事：先让 ILIKE 按字面匹配，再保护 PostgREST 的引号值语法。
        let literalPattern = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let filterValue = literalPattern
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"%\(filterValue)%\""
    }

    /// 这首作品写于哪一天、在哪里。多义未消歧的会返回空 —— 那是刻意的，
    /// 跳到错的那一天比不跳更糟。
    public func occasions(of poem: Poem) async throws -> [Occasion] {
        try await client.from("poet_event_works")
            .select("""
                title,match_score,\
                poet_events(id,year,month,day,is_leap_month,date_precision,content,\
                poet_stations(source_name))
                """)
            .eq("poem_id", value: poem.id.uuidString).execute().value
    }

    /// 读本 → 编年的反查（按篇名，用于年谱里提到但库中未收的作品）。
    public func occasions(ofWork title: String) async throws -> [PoetEvent] {
        let id = try await resolvePoetId()
        return try await client.from("poet_events").select(Self.eventCols)
            .eq("poet_id", value: id.uuidString)
            .contains("work_titles", value: [title])
            .order("year").execute().value
    }

    /// 寻踪。四个域一次查完：作品走库、地点与人物在内存里筛（骨架已预载）、
    /// 纯数字当年份。刻意不做全文检索 —— 6,628 条事目的正文检索该走
    /// PoetryHub 已有的 bge-m3 向量通道，不是在这里 ilike 硬扫。
    public func search(_ raw: String) async throws -> SearchResults {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 1 else { return .empty }

        let id = try await resolvePoetId()
        let pattern = Self.literalSearchPattern(q)
        let poems: [Poem] = try await client.from("poems")
            .select(Self.poemCols)
            .eq("author_id", value: id.uuidString)
            .or("title.ilike.\(pattern),content.ilike.\(pattern)")
            .order("title").order("id").limit(40).execute().value
        let places = stations.filter { $0.displayName.contains(q) || $0.sourceName.contains(q) }
        var seen = Set<String>()
        let uniquePlaces = places.filter { seen.insert($0.displayName).inserted }
        let people = associates.filter {
            $0.name.contains(q) || ($0.courtesyName?.contains(q) ?? false)
        }
        let year = Int(q).flatMap { y in
            (y >= composition0.birth && y <= composition0.death) ? y : nil
        }
        return SearchResults(poems: poems, places: uniquePlaces, people: people, year: year)
    }

    /// 供 search 判定年份区间。store 不该知道编成，所以只存生卒。
    private var composition0: (birth: Int, death: Int) { lifespan }
    public var lifespan: (birth: Int, death: Int) = (0, 9999)

    /// 作品行的列。provenance 整列取回 (相比正文很小), 客户端只解码书名与章名。
    static let poemCols =
        "id,title,form,content,paragraphs,cipai,summary,appreciation,translation,highlights,genre,genre_group,provenance"

    private static let eventCols =
        "id,station_id,year,month,day,is_leap_month,date_precision,content,work_titles,full_text,source_ref"

    /// 同名同朝代可能有多份 NER 副本，取 poems_count 最大的主行。
    private func resolvePoetId() async throws -> UUID {
        if let poetId { return poetId }
        struct Row: Decodable { let id: UUID; let poems_count: Int? }
        let rows: [Row] = try await client.from("poets")
            .select("id,poems_count").eq("name", value: poetName).execute().value
        guard let best = rows.max(by: { ($0.poems_count ?? 0) < ($1.poems_count ?? 0) }) else {
            throw StoreError.poetNotFound(poetName)
        }
        poetId = best.id
        return best.id
    }
}

public struct SearchResults: Sendable {
    public let poems: [Poem]
    public let places: [Station]
    public let people: [Associate]
    public let year: Int?
    public var isEmpty: Bool { poems.isEmpty && places.isEmpty && people.isEmpty && year == nil }
    public static let empty = SearchResults(poems: [], places: [], people: [], year: nil)
}

public enum StoreError: LocalizedError, Sendable {
    case poetNotFound(String), missingConfig(String)
    public var errorDescription: String? {
        switch self {
        case .poetNotFound(let n):  return "库里找不到诗人「\(n)」"
        case .missingConfig(let k): return "Info.plist 缺少 \(k)"
        }
    }
}

// MARK: - 配置

/// 只读查询用的客户端。App 启动时先 `ZXSupabase.configure(urlString:anonKey:)`
/// (Info.plist 的 SUPABASE_URL / SUPABASE_ANON_KEY), 这里只取已配置的那一个 ——
/// 账号、离线队列与只读查询共用同一个 Supabase 客户端 (同一份 session)。
public enum PoetStoreConfig {
    public static func makeClient() throws -> SupabaseClient {
        #if DEBUG
        // An isolated, deterministic failure path for simulator UI validation.
        if ProcessInfo.processInfo.environment["POETKIT_QA_OFFLINE"] == "1",
           let offlineURL = URL(string: "http://127.0.0.1:1") {
            return SupabaseClient(supabaseURL: offlineURL, supabaseKey: "offline-preview")
        }
        #endif
        guard let client = ZXSupabase.client else { throw StoreError.missingConfig("SUPABASE_URL / SUPABASE_ANON_KEY") }
        return client
    }
}
