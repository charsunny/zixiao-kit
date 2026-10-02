//  PoetRPC.swift — 诗人数据层的显式 RPC
//
//  客户端不拼 SQL。聚合查询一律走服务端定义好的函数 (migration 065), 参数与返回行
//  的形状集中在这里, 测试可以不起网络就核对编码。

import Foundation

public enum PoetRPC {
    /// `poet_event_year_counts(p_poet_id uuid) returns table(year int, n int)`。
    public static let eventYearCounts = "poet_event_year_counts"

    /// 参数。键名与 SQL 形参一致 (`p_poet_id`); uuid 用小写, 与库里的写法一致。
    public struct EventYearCountsParams: Encodable, Sendable, Hashable {
        public let poetId: UUID
        public init(poetId: UUID) { self.poetId = poetId }

        enum CodingKeys: String, CodingKey { case poetId = "p_poet_id" }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(poetId.uuidString.lowercased(), forKey: .poetId)
        }
    }

    /// 返回的一行。
    public struct YearCount: Decodable, Sendable, Hashable {
        public let year: Int
        public let n: Int
        public init(year: Int, n: Int) { self.year = year; self.n = n }
    }

    /// 行 → 年份到条数。同一年出现两次 (不应发生) 时取和, 不崩。
    public static func yearCounts(_ rows: [YearCount]) -> [Int: Int] {
        rows.reduce(into: [:]) { $0[$1.year, default: 0] += $1.n }
    }

    /// `poet_genre_groups(p_poet_id uuid, p_form text) returns table(genre_group text, genre text, n int)`
    /// (migration 069)。genre_group 为空的已在服务端归入「其他」。
    public static let genreGroups = "poet_genre_groups"

    public struct GenreGroupsParams: Encodable, Sendable, Hashable {
        public let poetId: UUID
        public let form: String
        public init(poetId: UUID, form: String) { self.poetId = poetId; self.form = form }

        enum CodingKeys: String, CodingKey { case poetId = "p_poet_id", form = "p_form" }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(poetId.uuidString.lowercased(), forKey: .poetId)
            try c.encode(form, forKey: .form)
        }
    }

    /// 返回的一行; 客户端兜底 (直接 select genre_group,genre) 的每一行也解成它, n 缺省为 1。
    public struct GenreCount: Decodable, Sendable, Hashable {
        public let genreGroup: String?
        public let genre: String?
        public let n: Int
        public init(genreGroup: String?, genre: String?, n: Int = 1) {
            self.genreGroup = genreGroup; self.genre = genre; self.n = n
        }
        enum CodingKeys: String, CodingKey { case genreGroup = "genre_group", genre, n }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            genreGroup = try c.decodeIfPresent(String.self, forKey: .genreGroup)
            genre = try c.decodeIfPresent(String.self, forKey: .genre)
            n = try c.decodeIfPresent(Int.self, forKey: .n) ?? 1
        }
    }
}

/// 一种体裁 (form) 下的大类 → 细体裁目录。由 RPC 行或客户端逐行兜底聚合而来。
public struct PoetGenreIndex: Sendable, Hashable {
    /// 大类为空 (早先入库、未标体裁) 的作品都归在这里, 并且总排在最后。
    public static let otherGroup = "其他"

    public struct Group: Sendable, Hashable, Identifiable {
        public var id: String { label }
        public let label: String
        public let count: Int
        /// 细体裁, 按篇数从多到少。细体裁为空的只计入 `count`, 不单列。
        public let genres: [FineGenre]
        /// 只有一种 (或没有) 细体裁时, 不必再给筛选条。
        public var hasFineGenres: Bool { genres.count > 1 }
        public var isOther: Bool { label == PoetGenreIndex.otherGroup }
    }

    public struct FineGenre: Sendable, Hashable, Identifiable {
        public var id: String { label }
        public let label: String
        public let count: Int
    }

    public let groups: [Group]
    public var total: Int { groups.reduce(0) { $0 + $1.count } }
    /// 通用规则: 不到两个大类就不必分组, 直接给平铺列表。
    public var isGrouped: Bool { groups.count >= 2 }

    public init(groups: [Group]) { self.groups = groups }

    /// 聚合并排序: 大类按篇数从多到少 (同数按名), 「其他」殿后; 细体裁同理。
    /// 空串与空值等同; 同一 (大类, 细体裁) 出现多行时累加。
    public init(rows: [PoetRPC.GenreCount]) {
        func clean(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }
        var totals: [String: Int] = [:]
        var fine: [String: [String: Int]] = [:]
        for row in rows where row.n > 0 {
            let group = clean(row.genreGroup) ?? Self.otherGroup
            totals[group, default: 0] += row.n
            if let genre = clean(row.genre) { fine[group, default: [:]][genre, default: 0] += row.n }
        }
        func byCount(_ a: (key: String, value: Int), _ b: (key: String, value: Int)) -> Bool {
            a.value != b.value ? a.value > b.value : a.key < b.key
        }
        groups = totals.sorted { a, b in
            let ao = a.key == Self.otherGroup, bo = b.key == Self.otherGroup
            return ao != bo ? bo : byCount(a, b)
        }.map { entry in
            Group(label: entry.key, count: entry.value,
                  genres: (fine[entry.key] ?? [:]).sorted(by: byCount).map { FineGenre(label: $0.key, count: $0.value) })
        }
    }

    public func group(_ label: String) -> Group? { groups.first { $0.label == label } }
}
