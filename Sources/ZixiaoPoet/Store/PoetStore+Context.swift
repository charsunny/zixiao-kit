//  PoetStore+Context.swift — 读本「此时」的查询: 作品回到它在一生里的那一刻。
//
//  三件事: 作品 → 系年的事目 (比 `occasions(of:)` 多带诗人 id 与驻点 id); 同年的其他作品
//  (poet_event_works 按 poet_events.year 过滤, 一次内连接); 一年的事目数 (只要计数, 不拉正文)。
//  纪年同 PoetStore: year 是年号年对应的公元年数, month / day 是夏历, 不做 Date 运算。

import Foundation
import Supabase

/// 作品与事目的一条边 (poet_event_works → poet_events)。
struct WorkEventLink: Decodable, Sendable, Hashable, Identifiable {
    var id: UUID { event.id }
    let matchScore: Double?
    let event: PoetEvent
    /// 事目所属的诗人 (poets.id = poems.author_id): 查同年作品与年内记载数用。
    let poetId: UUID
    /// 驻点的原始地名 (poet_stations.source_name); 界面优先用预载驻点的古地名 (`Station.displayName`)。
    let stationName: String?

    private enum CodingKeys: String, CodingKey { case matchScore = "match_score", event = "poet_events" }
    private enum EventKeys: String, CodingKey { case poetId = "poet_id", station = "poet_stations" }
    private struct StationRow: Decodable { let source_name: String }

    init(matchScore: Double?, event: PoetEvent, poetId: UUID, stationName: String?) {
        self.matchScore = matchScore
        self.event = event
        self.poetId = poetId
        self.stationName = stationName
    }

    init(from decoder: any Decoder) throws {
        let row = try decoder.container(keyedBy: CodingKeys.self)
        matchScore = try row.decodeIfPresent(Double.self, forKey: .matchScore)
        event = try row.decode(PoetEvent.self, forKey: .event)
        let nested = try row.nestedContainer(keyedBy: EventKeys.self, forKey: .event)
        poetId = try nested.decode(UUID.self, forKey: .poetId)
        stationName = try nested.decodeIfPresent(StationRow.self, forKey: .station)?.source_name
    }
}

/// 同年作品的一行: 作品 id 与它所系事目的月日 (排序用)。
struct YearWorkRow: Decodable, Sendable, Hashable {
    let poemId: UUID
    let month: Int?
    let day: Int?

    private enum CodingKeys: String, CodingKey { case poemId = "poem_id", event = "poet_events" }
    private enum EventKeys: String, CodingKey { case month, day }

    init(poemId: UUID, month: Int?, day: Int?) {
        self.poemId = poemId
        self.month = month
        self.day = day
    }

    init(from decoder: any Decoder) throws {
        let row = try decoder.container(keyedBy: CodingKeys.self)
        poemId = try row.decode(UUID.self, forKey: .poemId)
        let event = try row.nestedContainer(keyedBy: EventKeys.self, forKey: .event)
        month = try event.decodeIfPresent(Int.self, forKey: .month)
        day = try event.decodeIfPresent(Int.self, forKey: .day)
    }
}

extension PoetStore {
    /// 事目列 (不取 full_text: 内嵌的作品全文很长, 「此时」卡只要叙事)。
    private static let linkedEventCols =
        "id,station_id,year,month,day,is_leap_month,date_precision,content,work_titles,source_ref,poet_id,poet_stations(source_name)"

    /// 这篇作品系年到的事目。内连接: 只有篇名、没落到事目上的边不返回。多义未消歧的作品本就没有边 ——
    /// 那是刻意的, 钉错年份比「未编年」更糟。
    func workEventLinks(of poemID: UUID) async throws -> [WorkEventLink] {
        try await client.from("poet_event_works")
            .select("match_score,poet_events!inner(\(Self.linkedEventCols))")
            .eq("poem_id", value: poemID.uuidString).execute().value
    }

    /// 作品的作者 (poems.author_id)。刻上的作品没有事目边时, 查同年作品要靠它定诗人。
    func authorID(ofWork poemID: UUID) async throws -> UUID? {
        struct Row: Decodable { let author_id: UUID? }
        let rows: [Row] = try await client.from("poems").select("author_id")
            .eq("id", value: poemID.uuidString).limit(1).execute().value
        return rows.first?.author_id
    }

    /// 一年的事目条数 (只计数, head 请求不带行)。
    func eventCount(poetID: UUID, year: Int) async throws -> Int {
        let response = try await client.from("poet_events").select("id", head: true, count: .exact)
            .eq("poet_id", value: poetID.uuidString).eq("year", value: year).execute()
        return response.count ?? 0
    }

    /// 同年作品: 系年在这一年的作品, 按事目月日排, 去掉当前这篇, 至多 `limit` 篇。
    /// 一次内连接 (poet_event_works ⋈ poet_events.year); 作品正文再按 id 取一次。
    /// 边上的 poem_id 偶有不在 poems 表里的 (旧 id), 所以候选多取一倍, 取回后再截。
    func sameYearWorks(poetID: UUID, year: Int, excluding poemID: UUID, limit: Int = 8) async throws -> [Poem] {
        guard limit > 0 else { return [] }
        let rows: [YearWorkRow] = try await client.from("poet_event_works")
            .select("poem_id,poet_events!inner(month,day)")
            .eq("poet_events.poet_id", value: poetID.uuidString)
            .eq("poet_events.year", value: year)
            .not("poem_id", operator: .is, value: "null")
            .order("poet_events(month)").order("poet_events(day)").order("poem_id")
            .limit(200).execute().value
        let ids = ReaderTimeline.sameYearIDs(rows, excluding: poemID, limit: limit * 2)
        return Array(try await poems(ids: ids).prefix(limit))
    }
}
