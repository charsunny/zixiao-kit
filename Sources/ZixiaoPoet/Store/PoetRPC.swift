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
}
