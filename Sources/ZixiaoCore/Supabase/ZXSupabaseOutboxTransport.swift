import Foundation
import Supabase

/// 离线队列的 Supabase 出口: 把一条 `ZXOutboxEntry` 写进 PostgREST。
///
/// 错误分类决定条目的命运 (见 `ZXOutboxDelivery`):
/// - `23505` 主键 / 唯一冲突 + insert: 视为**已送达** —— 上次其实写成功了、只是回包丢了, 重放撞上自己。
///   这就是「幂等」在服务端那一半: 插入类写入的载荷应带客户端生成的主键。
/// - 其余 `22xxx` 数据异常、`23xxx` 约束、`42xxx` 权限 / 对象不存在、`PGRST1xx/2xx` 请求不合法: 永久失败, 丢弃。
/// - 网络错误、5xx、JWT 过期 (`PGRST301/303`) 等: 暂时失败, 退避重试。
public struct ZXSupabaseOutboxTransport: ZXOutboxTransport {
    private let clientProvider: @Sendable () throws -> SupabaseClient

    public init() {
        self.init(client: { try ZXSupabase.requireClient() })
    }

    public init(client: @escaping @Sendable () throws -> SupabaseClient) {
        self.clientProvider = client
    }

    public func deliver(_ entry: ZXOutboxEntry) async -> ZXOutboxDelivery {
        guard let client = try? clientProvider() else {
            // 离线模式: 留着, 等 App 配置好后端 (比如下个版本填了密钥) 再发。
            return .retryLater("offline")
        }
        do {
            switch entry.operation {
            case .insert:
                try await client.from(entry.table).insert(entry.payload, returning: .minimal).execute()
            case .upsert:
                try await client.from(entry.table)
                    .upsert(entry.payload, onConflict: entry.onConflict, returning: .minimal).execute()
            }
            return .delivered
        } catch {
            return Self.classify(error, operation: entry.operation)
        }
    }

    static func classify(_ error: any Error, operation: ZXOutboxEntry.Operation) -> ZXOutboxDelivery {
        if let pg = error as? PostgrestError {
            let code = pg.code ?? ""
            if code == "23505" && operation == .insert { return .delivered }
            let permanent = code.hasPrefix("22") || code.hasPrefix("23") || code.hasPrefix("42")
                || code.hasPrefix("PGRST1") || code.hasPrefix("PGRST2")
            return permanent ? .rejected("\(code) \(pg.message)") : .retryLater("\(code) \(pg.message)")
        }
        if let http = error as? HTTPError {
            let status = http.response.statusCode
            // 408 超时、429 限流、5xx 服务端: 可重试; 其余 4xx (除鉴权) 是请求本身的问题。
            let retryable = status == 401 || status == 403 || status == 408 || status == 429 || status >= 500
            return retryable ? .retryLater("HTTP \(status)") : .rejected("HTTP \(status)")
        }
        return .retryLater(String(describing: error))
    }
}
