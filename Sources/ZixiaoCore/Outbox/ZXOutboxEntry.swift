import Foundation

/// 离线队列里的一条写入: 往某张表插入 / upsert 一行。
///
/// 沿用 Flutter `outbox.dart` 的扁平结构 (table + op + payload), 不按表建类型 ——
/// 要排队的写入只有三四条热路径, 泛型化得不偿失。
public struct ZXOutboxEntry: Codable, Sendable, Hashable, Identifiable {
    public enum Operation: String, Codable, Sendable, Hashable {
        case insert
        case upsert
    }

    /// 本条的本地 id (UUID)。
    public let id: String
    /// 幂等键。同一用户下同键的待传写入只保留一条 (新载荷覆盖旧载荷), 见 `ZXOutbox.enqueue`。
    public let idempotencyKey: String
    /// 属于哪个用户。nil = 入队时还没有 session (首启离线), 下一个登录的用户接手。
    public internal(set) var owner: String?
    public internal(set) var table: String
    public internal(set) var operation: Operation
    /// upsert 的冲突列 (PostgREST `on_conflict`)。
    public internal(set) var onConflict: String?
    public internal(set) var payload: [String: ZXJSONValue]
    public let createdAt: Date
    public internal(set) var updatedAt: Date
    /// 已失败 (可重试) 的次数, 决定退避时长。
    public internal(set) var attempts: Int
    /// 退避中: 此刻之前不再自动重试。nil = 随时可发。
    public internal(set) var nextAttemptAt: Date?
    /// 每被同键覆盖一次 +1。补传是异步的, 回来时若版本变了, 说明发出去的是旧载荷, 这条不能删。
    public internal(set) var revision: Int
    public internal(set) var lastError: String?

    init(id: String = UUID().uuidString, idempotencyKey: String, owner: String?, table: String,
         operation: Operation, onConflict: String?, payload: [String: ZXJSONValue], createdAt: Date) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.owner = owner
        self.table = table
        self.operation = operation
        self.onConflict = onConflict
        self.payload = payload
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.attempts = 0
        self.nextAttemptAt = nil
        self.revision = 0
        self.lastError = nil
    }
}

/// 一次投递的结果。transport 自己判断错误的性质, 队列据此决定删、退避还是丢弃。
public enum ZXOutboxDelivery: Sendable, Hashable {
    /// 已落库 (含「主键冲突 = 早先已经落过」这种幂等成功)。
    case delivered
    /// 暂时失败 (断网、超时、5xx、token 过期), 退避后重试。
    case retryLater(String)
    /// 永久失败 (RLS 拒绝、表 / 列不存在、数据不合法), 重试也没用, 丢弃并计数。
    case rejected(String)
}

/// 队列的出口。生产用 `ZXSupabaseOutboxTransport`, 测试注入 mock。
public protocol ZXOutboxTransport: Sendable {
    func deliver(_ entry: ZXOutboxEntry) async -> ZXOutboxDelivery
}

/// 一次 drain 的结果, 给调试与测试看。
public struct ZXOutboxDrainReport: Sendable, Hashable {
    public var delivered = 0
    public var rejected = 0
    /// 本轮遇到暂时失败而退避的条数 (遇到第一条就停, 所以最多 1)。
    public var deferred = 0
    /// 另一轮 drain 正在进行, 本次只登记了「完事后再来一轮」。
    public var coalesced = false

    public init() {}
}

/// 退避与容量策略。
public struct ZXOutboxPolicy: Sendable, Hashable {
    /// 条数上限, 满了丢最老的 (Flutter 版同为 1000)。
    public var maxEntries: Int
    /// 超过这个年龄的条目直接丢 (Flutter 版同为 30 天): 离线几个月的写入多半已被别的路径覆盖。
    public var maxAge: TimeInterval
    /// 第 n 次失败后等 base × 2^(n-1), 封顶 maxDelay。
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval
    /// 在退避时长上加 [0, jitter) 比例的随机量, 服务端恢复时各客户端不至于同一秒涌入。测试设 0。
    public var jitter: Double
    /// 入队、换用户、退避到期时自动 drain。测试关掉以便逐步驱动。
    public var autoDrain: Bool

    public init(maxEntries: Int = 1000, maxAge: TimeInterval = 30 * 86_400, baseDelay: TimeInterval = 2,
                maxDelay: TimeInterval = 600, jitter: Double = 0.1, autoDrain: Bool = true) {
        self.maxEntries = maxEntries
        self.maxAge = maxAge
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitter = jitter
        self.autoDrain = autoDrain
    }

    /// 第 `attempt` 次失败后的等待秒数 (不含抖动)。
    public func backoff(attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        // 2^30 早已超过任何 maxDelay, 截断指数避免溢出。
        let exponent = Double(min(attempt - 1, 30))
        return min(baseDelay * pow(2, exponent), maxDelay)
    }
}
