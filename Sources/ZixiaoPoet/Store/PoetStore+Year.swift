//  PoetStore+Year.swift — 诗文「按年读」的查询: 逐年系年篇数, 某一年的作品
//
//  系年靠 poet_event_works (事目 ↔ 作品的边) 连 poet_events.year。两件事都先走 RPC (migration 070):
//  `poet_work_years` 一次给出逐年篇数 (外加「未编年」一行), `poet_works_of_year` 给出某年作品 id
//  (按事目月日排)。RPC 还没部署 (PGRST202) 或调用失败时退回 PostgREST 的嵌入过滤:
//  `poet_event_works?select=poem_id,poet_events!inner(year,…)&poet_events.poet_id=eq.<id>` ——
//  边只有两三千条, 逐页取回在本地数。纪年同 PoetStore: year 是年号年对应的公元年数。

import Foundation
import Supabase

// MARK: - RPC 形状

extension PoetRPC {
    /// `poet_work_years(p_poet_id uuid) returns table(year int, n int)`; year 为 null 的一行是未编年篇数。
    public static let workYears = "poet_work_years"
    /// `poet_works_of_year(p_poet_id uuid, p_year int) returns table(poem_id uuid, month int, day int)`。
    public static let worksOfYear = "poet_works_of_year"

    public struct WorksOfYearParams: Encodable, Sendable, Hashable {
        public let poetId: UUID
        public let year: Int
        public init(poetId: UUID, year: Int) { self.poetId = poetId; self.year = year }

        enum CodingKeys: String, CodingKey { case poetId = "p_poet_id", year = "p_year" }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(poetId.uuidString.lowercased(), forKey: .poetId)
            try c.encode(year, forKey: .year)
        }
    }

    /// `poet_work_years` 的一行。
    public struct WorkYearCount: Decodable, Sendable, Hashable {
        public let year: Int?
        public let n: Int
        public init(year: Int?, n: Int) { self.year = year; self.n = n }
    }

    /// `poet_works_of_year` 的一行。
    public struct YearWork: Decodable, Sendable, Hashable {
        public let poemId: UUID
        public let month: Int?
        public let day: Int?
        public init(poemId: UUID, month: Int?, day: Int?) { self.poemId = poemId; self.month = month; self.day = day }
        enum CodingKeys: String, CodingKey { case poemId = "poem_id", month, day }
    }
}

// MARK: - 结果

/// 逐年系年篇数。
public struct PoetWorkYears: Sendable, Hashable {
    /// 年 → 篇数 (同一篇同一年只算一次)。没有作品的年不在里面。
    public let counts: [Int: Int]
    /// 系过年的作品篇数 (去重; 一篇跨两年只算一篇)。
    public let datedWorks: Int
    /// 未编年篇数; 只有 RPC 给得出 (客户端退路不知道库里总篇数, 由界面按编成的体裁篇数估)。
    public let undated: Int?

    public init(counts: [Int: Int], datedWorks: Int, undated: Int?) {
        self.counts = counts
        self.datedWorks = datedWorks
        self.undated = undated
    }

    public var isEmpty: Bool { counts.values.allSatisfy { $0 <= 0 } }

    /// RPC 行 → 结果。year 为 null 的行是未编年; 同一年两行 (不应发生) 时取和。
    /// RPC 不给去重后的系年总数, 这里用逐年之和 (跨年的篇会多算, 只作展示)。
    public init(rows: [PoetRPC.WorkYearCount]) {
        var counts: [Int: Int] = [:]
        var undated: Int?
        for row in rows {
            if let year = row.year { counts[year, default: 0] += row.n } else { undated = (undated ?? 0) + row.n }
        }
        self.init(counts: counts.filter { $0.value > 0 }, datedWorks: counts.values.reduce(0, +), undated: undated)
    }

    /// 客户端退路: (作品, 年) 的边 → 逐年去重计数。
    public init(edges: [(poemID: UUID, year: Int)]) {
        var byYear: [Int: Set<UUID>] = [:]
        for edge in edges { byYear[edge.year, default: []].insert(edge.poemID) }
        self.init(counts: byYear.mapValues(\.count), datedWorks: Set(edges.map(\.poemID)).count, undated: nil)
    }

    /// 已按月日排好的行 → 作品 id, 去重保序 (一篇挂多条事目时留最早那条的位置)。
    public static func orderedIDs(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}

// MARK: - 查询

/// 边的一行 (客户端退路): 作品 id 与所系事目的年 / 月 / 日。
private struct WorkEdgeRow: Decodable {
    let poemId: UUID
    let year: Int
    let month: Int?
    let day: Int?

    private enum CodingKeys: String, CodingKey { case poemId = "poem_id", event = "poet_events" }
    private enum EventKeys: String, CodingKey { case year, month, day }

    init(from decoder: any Decoder) throws {
        let row = try decoder.container(keyedBy: CodingKeys.self)
        poemId = try row.decode(UUID.self, forKey: .poemId)
        let event = try row.nestedContainer(keyedBy: EventKeys.self, forKey: .event)
        year = try event.decode(Int.self, forKey: .year)
        month = try event.decodeIfPresent(Int.self, forKey: .month)
        day = try event.decodeIfPresent(Int.self, forKey: .day)
    }
}

/// 诗人名 → poets.id (同名取 poems_count 最大的主行, 与 `PoetStore` 的解析同法)。按名记一次。
@MainActor
private enum PoetIDCache {
    static var ids: [String: UUID] = [:]
}

extension PoetStore {
    /// 一页边的行数 (服务端 max-rows 的默认值) 与退路最多取的行数。
    private static let edgePage = 1_000
    private static let edgeCap = 10_000

    /// 诗人 id。`PoetStore` 的解析是私有的, 这里按同一规则再解一次并记住。
    func poetID(named name: String) async throws -> UUID {
        if let cached = PoetIDCache.ids[name] { return cached }
        struct Row: Decodable { let id: UUID; let poems_count: Int? }
        let rows: [Row] = try await client.from("poets")
            .select("id,poems_count").eq("name", value: name).execute().value
        guard let best = rows.max(by: { ($0.poems_count ?? 0) < ($1.poems_count ?? 0) }) else {
            throw StoreError.poetNotFound(name)
        }
        PoetIDCache.ids[name] = best.id
        return best.id
    }

    /// 逐年系年篇数。RPC `poet_work_years` 缺席或失败时退回逐页取边、本地计数。
    public func workYearCounts(poet name: String) async throws -> PoetWorkYears {
        let id = try await poetID(named: name)
        do {
            let rows: [PoetRPC.WorkYearCount] = try await client
                .rpc(PoetRPC.workYears, params: PoetRPC.EventYearCountsParams(poetId: id))
                .execute().value
            return PoetWorkYears(rows: rows)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return PoetWorkYears(edges: try await workEdges(poetID: id).map { ($0.poemId, $0.year) })
        }
    }

    /// 某一年系年作品的 id (按事目月日排, 去重)。RPC `poet_works_of_year` 缺席或失败时退回嵌入过滤。
    public func workIDs(year: Int, poet name: String) async throws -> [UUID] {
        let id = try await poetID(named: name)
        do {
            let rows: [PoetRPC.YearWork] = try await client
                .rpc(PoetRPC.worksOfYear, params: PoetRPC.WorksOfYearParams(poetId: id, year: year))
                .execute().value
            return PoetWorkYears.orderedIDs(rows.map(\.poemId))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let rows: [WorkEdgeRow] = try await client.from("poet_event_works")
                .select("poem_id,poet_events!inner(year,month,day)")
                .eq("poet_events.poet_id", value: id.uuidString)
                .eq("poet_events.year", value: year)
                .not("poem_id", operator: .is, value: "null")
                .order("poet_events(month)").order("poet_events(day)").order("poem_id")
                .limit(Self.edgePage).execute().value
            return PoetWorkYears.orderedIDs(rows.map(\.poemId))
        }
    }

    /// 某一年的作品 (正文), 按事目月日排, 分页: 先取全年 id, 再按页取正文。
    /// 读不到的 id (未入库 / RLS 不放) 在取正文时自然落掉。
    public func poems(year: Int, poet name: String, limit: Int = 100, offset: Int = 0) async throws -> [Poem] {
        guard limit > 0 else { return [] }
        let ids = try await workIDs(year: year, poet: name)
        let start = min(max(0, offset), ids.count)
        return try await poems(ids: Array(ids[start..<min(start + limit, ids.count)]))
    }

    /// 退路: 这位诗人全部的 (作品, 事目年月日) 边, 逐页取。
    private func workEdges(poetID: UUID) async throws -> [WorkEdgeRow] {
        var rows: [WorkEdgeRow] = []
        while rows.count < Self.edgeCap {
            let chunk: [WorkEdgeRow] = try await client.from("poet_event_works")
                .select("poem_id,poet_events!inner(year,month,day)")
                .eq("poet_events.poet_id", value: poetID.uuidString)
                .not("poem_id", operator: .is, value: "null")
                .order("poem_id").order("event_id")
                .range(from: rows.count, to: rows.count + Self.edgePage - 1).execute().value
            rows += chunk
            if chunk.count < Self.edgePage { break }
        }
        return rows
    }
}
