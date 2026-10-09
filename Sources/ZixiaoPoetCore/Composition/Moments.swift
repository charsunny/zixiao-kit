//  Moments.swift — 刻 (moments-<slug>.json): 一生长卷的编辑物
//
//  格式见 zhi/poetkit/moments.schema.json。一生分为若干「卷」(与导读 guide 的分期一一对应),
//  每卷由 8–12 个「刻」串成; 尚未编辑的卷是桩 (moments 为空)。随 App 包发, 经 `PoetResources` 找;
//  包里没有这份文件 = 这位诗人还没有长卷, 能力退回旧的叙事工作区 (见 `CapabilityRegistry`)。
//
//  客户端只读、不排序: 数组顺序即阅读顺序。调试字段 (`_workTitle`) 解码时忽略。

import Foundation

/// 一位诗人的长卷数据。
public struct PoetMoments: Codable, Sendable, Hashable {
    public let schemaVersion: Int
    /// 诗人 slug (与编成的 poet.slug 一致)。
    public let poet: String
    /// 按 epochSequence 升序的卷。
    public let chapters: [Chapter]

    /// 已编好刻的卷数。
    public var writtenChapterCount: Int { chapters.filter { !$0.isStub }.count }
    /// 全书的刻数。
    public var momentCount: Int { chapters.reduce(0) { $0 + $1.moments.count } }

    public func chapter(sequence: Int) -> Chapter? { chapters.first { $0.epochSequence == sequence } }
    public func moment(id: String) -> Moment? {
        for chapter in chapters { if let hit = chapter.moments.first(where: { $0.id == id }) { return hit } }
        return nil
    }

    // MARK: 卷

    /// 一卷。`epochSequence` / 年份 / 旨 与导读的分期对应。
    public struct Chapter: Codable, Sendable, Hashable, Identifiable {
        public var id: Int { epochSequence }
        public let epochSequence: Int
        /// 卷名 (不含「卷N ·」前缀, 前缀由客户端生成)。
        public let title: String
        public let startYear: Int
        public let endYear: Int
        /// 一句旨 (卷封面上那一句)。
        public let thesis: String
        /// 「这一卷」概述; 桩卷可无。
        public let overview: String?
        /// 画屏的地望 seed。
        public let placeSeed: String
        /// 卷封面画屏的季节偏色 (spring / summer / autumn / winter); nil 不偏。
        public let seasonTint: String?
        public let moments: [Moment]

        /// 桩卷: 还没有编好刻。
        public var isStub: Bool { moments.isEmpty }
        /// 「1080 — 1084」/「1079 年」。
        public var yearsLabel: String {
            startYear == endYear ? "\(String(startYear)) 年" : "\(String(startYear)) — \(String(endYear))"
        }
        /// 本卷出场的人 (按首次出现的顺序去重)。
        public var people: [String] {
            var seen = Set<String>()
            return moments.flatMap(\.allPeople).filter { seen.insert($0).inserted }
        }
        public func contains(year: Int) -> Bool { year >= startYear && year <= endYear }

        public init(epochSequence: Int, title: String, startYear: Int, endYear: Int, thesis: String,
                    overview: String? = nil, placeSeed: String, seasonTint: String? = nil, moments: [Moment] = []) {
            self.epochSequence = epochSequence
            self.title = title
            self.startYear = startYear
            self.endYear = endYear
            self.thesis = thesis
            self.overview = overview
            self.placeSeed = placeSeed
            self.seasonTint = seasonTint
            self.moments = moments
        }
    }

    // MARK: 刻

    /// 一刻: 一个日子 + 一个地方 + 一件事 + 一篇作品 (或一件墨迹), 附按语、处境与出处。
    public struct Moment: Codable, Sendable, Hashable, Identifiable {
        /// 主题编排只提供人生背景，不能据此确定关联作品的作年。
        public enum WorkDating: String, Codable, Sendable, Hashable { case dated, contextual }
        /// 稳定 id (收藏与分享以它为键), 如 `<poet>-1082-03-07-<短名>`。
        public let id: String
        public let date: MomentDate
        /// 驻点 (poet_stations.id)。
        public let placeId: UUID?
        /// 给读者看的地点短名。
        public let placeLabel: String
        /// 刻名 (≤8 字)。
        public let title: String
        /// 按语 (≤40 字)。
        public let lede: String
        /// 处境 (80–160 字)。
        public let body: String
        /// 关联事目 (poet_events.id)。
        public let eventIds: [UUID]
        /// 最贴切的一篇作品 (poems.id)。
        public let workId: UUID?
        /// 作品里最能代表此刻的一两句。
        public let workQuote: String?
        /// 墨迹 id (artworks-<slug>.json 的 id)。
        public let artworkId: String?
        /// 出场的人 (可省)。
        public let people: [String]?
        public let sources: [Source]
        public let workDating: WorkDating?

        public var allPeople: [String] { people ?? [] }

        public init(id: String, date: MomentDate, placeId: UUID? = nil, placeLabel: String, title: String,
                    lede: String, body: String, eventIds: [UUID] = [], workId: UUID? = nil,
                    workQuote: String? = nil, artworkId: String? = nil, people: [String]? = nil,
                    sources: [Source] = [], workDating: WorkDating? = nil) {
            self.id = id
            self.date = date
            self.placeId = placeId
            self.placeLabel = placeLabel
            self.title = title
            self.lede = lede
            self.body = body
            self.eventIds = eventIds
            self.workId = workId
            self.workQuote = workQuote
            self.artworkId = artworkId
            self.people = people
            self.sources = sources
            self.workDating = workDating
        }
    }

    /// 刻的日期。`year` 是年号年对应的公元年数; `month` / `day` 是农历月日 (与事目表同一约定)。
    public struct MomentDate: Codable, Sendable, Hashable {
        public enum Precision: String, Codable, Sendable, Hashable {
            case day, month, year
        }

        public let year: Int
        public let month: Int?
        public let day: Int?
        /// 给读者看的写法 (「元丰五年七月既望」)。纯展示。
        public let lunar: String?
        /// 年号纪年 (「元丰五年」)。
        public let eraLabel: String
        public let precision: Precision

        public init(year: Int, month: Int? = nil, day: Int? = nil, lunar: String? = nil,
                    eraLabel: String, precision: Precision) {
            self.year = year
            self.month = month
            self.day = day
            self.lunar = lunar
            self.eraLabel = eraLabel
            self.precision = precision
        }

        /// 年号之后的那一截 (「三月初七」「七月既望」「春」): 编辑写的 `lunar` 以年号开头时取其余部分
        /// (保留「既望」「寒食」这类写法); 否则按精度由月日拼出。只知年时为 nil。
        public var monthDayLabel: String? {
            if let lunar, lunar.hasPrefix(eraLabel) {
                let rest = lunar.dropFirst(eraLabel.count).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { return rest }
            }
            guard precision != .year, let month, (1...12).contains(month) else { return nil }
            let head = "\(Self.lunarMonthNames[month])月"
            guard precision == .day, let day, (1...30).contains(day) else { return head }
            return head + Self.lunarDay(day)
        }

        /// 日期行: 「元丰五年 · 三月初七」; 只知年时只有年号。
        public var displayLabel: String {
            monthDayLabel.map { "\(eraLabel) · \($0)" } ?? eraLabel
        }

        public static let lunarMonthNames = ["", "正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二"]
        public static func lunarDay(_ d: Int) -> String {
            let u = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
            if d <= 10 { return "初" + u[d] }
            if d < 20 { return "十" + u[d - 10] }
            if d == 20 { return "二十" }
            if d < 30 { return "二十" + u[d - 20] }
            return "三十"
        }
    }

    /// 一条出处: 原文引文及其来历。
    public struct Source: Codable, Sendable, Hashable {
        public let book: String
        public let chapter: String
        public let quote: String
        /// 机器可核对的定位 (殆知阁段落 / Supabase 行)。客户端不读。
        public let ref: String?

        public init(book: String, chapter: String, quote: String, ref: String? = nil) {
            self.book = book
            self.chapter = chapter
            self.quote = quote
            self.ref = ref
        }
    }

    // MARK: 载入

    /// 本内核读得懂的格式版本。
    public static let supportedSchemaVersion = 1

    /// 解码随 App 包发的刻。格式版本更高时报错 (不猜新字段)。
    public static func decode(_ data: Data) throws -> PoetMoments {
        let decoded = try JSONDecoder().decode(PoetMoments.self, from: data)
        guard decoded.schemaVersion <= supportedSchemaVersion else {
            throw DecodingError.dataCorrupted(.init(codingPath: [CodingKeys.schemaVersion],
                                                    debugDescription: "schemaVersion \(decoded.schemaVersion) 高于本内核支持的 \(supportedSchemaVersion)"))
        }
        return decoded
    }

    /// 从包里读 `moments-<poetSlug>.json`。没有这份文件、或解不开, 都返回 nil (长卷收起);
    /// 要区分两者 (诊断) 用 `PoetResources.moments()`。
    public static func load(from bundle: Bundle = .main, poetSlug: String) -> PoetMoments? {
        let resources = PoetResources(bundle: bundle, slug: poetSlug, productName: poetSlug)
        do { return try resources.moments() } catch {
            #if DEBUG
            print("ZixiaoPoet: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
}
