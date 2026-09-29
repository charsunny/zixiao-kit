import Foundation

/// 离线写队列 (移植自 Flutter `services/outbox.dart`)。
///
/// 与 Flutter 版一致的部分: 扁平记录、按序补传、成功即删、1000 条上限、30 天过期。
/// 比 Flutter 版多做的:
/// - **幂等键去重**: 同一用户同键只留一条, 新载荷覆盖旧的 (偏好反复切换只需补传最后一次);
/// - **指数退避**: 失败的条目按 2s、4s、8s… (封顶 10 分钟) 推迟, 而不是每次 drain 都撞一遍;
/// - **联网即补传**: `startMonitoring()` 订阅 NWPathMonitor, 网络恢复时无视退避立刻重放;
/// - **按用户归属**: 条目记下入队时的用户, 换账号时丢弃上一位的 (Flutter 版在切账号时整箱 clear, 同一意图)。
///
/// 为什么是 actor: 入队 (UI 触发)、补传 (网络回调 / 定时器触发) 会并发发生, actor 串行化对队列与文件的读改写。
/// 注意 actor 可重入: `deliver` 挂起期间可能有新入队或覆盖, 所以投递回来后按 id + revision 复核再删。
public actor ZXOutbox {
    public enum EnqueueResult: Sendable, Hashable {
        /// 新加一条。
        case queued
        /// 同键已有待传条目, 已用新载荷覆盖。
        case replaced
    }

    public nonisolated let fileURL: URL
    public nonisolated let policy: ZXOutboxPolicy

    private let transport: any ZXOutboxTransport
    private let now: @Sendable () -> Date

    private var entries: [ZXOutboxEntry]?
    private var owner: String?
    private var isDraining = false
    private var drainAgain = false
    private var forceAgain = false
    private var retryTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?

    /// 因过期、超额或被服务端永久拒绝而丢掉的条数 (进程内累计), 供诊断上报。
    public private(set) var droppedCount = 0

    /// - Parameters:
    ///   - fileURL: 默认 `Application Support/ZixiaoCore/outbox.json`。
    ///   - transport: 投递出口; 生产用 `ZXSupabaseOutboxTransport()`。
    ///   - now: 时钟, 测试注入以验证退避。
    public init(fileURL: URL? = nil, transport: any ZXOutboxTransport, policy: ZXOutboxPolicy = ZXOutboxPolicy(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL ?? ZXCorePaths.root.appendingPathComponent("outbox.json")
        self.transport = transport
        self.policy = policy
        self.now = now
    }

    // MARK: - 查询

    public var pendingCount: Int { load().count }

    /// 全部待传条目 (含不属于当前用户的), 按入队先后。
    public func pending() -> [ZXOutboxEntry] { load() }

    public var currentOwner: String? { owner }

    // MARK: - 入队

    /// 排一条写入。
    ///
    /// - Parameter idempotencyKey: 同一用户下同键的待传条目会被覆盖而不是追加。插入类写入用客户端生成的行 id,
    ///   upsert 类用「表 + 冲突键值」(如 `"zen_user_preferences:\(uid)"`)。不传则每次都是新条目。
    /// - Throws: 写盘失败时抛出 —— 宁可让调用方知道没排上, 也不静默丢数据。
    @discardableResult
    public func enqueue(table: String, operation: ZXOutboxEntry.Operation = .insert,
                        payload: [String: ZXJSONValue], onConflict: String? = nil,
                        idempotencyKey: String? = nil) throws -> EnqueueResult {
        var list = load()
        let stamp = now()
        let key = idempotencyKey ?? UUID().uuidString
        let result: EnqueueResult
        if let index = list.firstIndex(where: { $0.idempotencyKey == key && $0.owner == owner }) {
            list[index].table = table
            list[index].operation = operation
            list[index].onConflict = onConflict
            list[index].payload = payload
            list[index].updatedAt = stamp
            list[index].revision += 1
            // 新载荷没失败过, 退避清零; 排队位置不变, 保持与其他写入的先后关系。
            list[index].attempts = 0
            list[index].nextAttemptAt = nil
            list[index].lastError = nil
            result = .replaced
        } else {
            // 软上限: 满了先丢最老的。按年龄的清理在 load / drain 时做, 这里只是兜底。
            while list.count >= policy.maxEntries, !list.isEmpty {
                list.removeFirst()
                droppedCount += 1
            }
            list.append(ZXOutboxEntry(idempotencyKey: key, owner: owner, table: table, operation: operation,
                                      onConflict: onConflict, payload: payload, createdAt: stamp))
            result = .queued
        }
        try persist(list)
        kick()
        return result
    }

    /// 清空 (含其他用户的)。
    public func clear() throws {
        retryTask?.cancel()
        try persist([])
    }

    // MARK: - 归属

    /// 当前用户变了 (`ZXAuth` 会自动调用)。
    ///
    /// - 其他用户名下的条目丢弃: 载荷里带着旧用户的 user_id, 以新身份补传要么被 RLS 拒、要么写错人。
    /// - 无主条目 (首启离线时入队) 归新用户。
    /// - 有了用户就试着补传一轮。
    public func setOwner(_ userId: String?) {
        owner = userId
        var list = load()
        let before = list.count
        list.removeAll { $0.owner != nil && $0.owner != userId }
        droppedCount += before - list.count
        if let userId {
            for index in list.indices where list[index].owner == nil {
                list[index].owner = userId
            }
        }
        try? persist(list)
        if userId == nil { retryTask?.cancel() }
        kick()
    }

    // MARK: - 补传

    /// 按序补传当前用户的到期条目。
    ///
    /// - Parameter force: 无视退避 (网络刚恢复时用: 之前的失败多半就是断网造成的)。
    /// 遇到第一条暂时失败就停: 多半是网络又断了, 继续只会白白把后面的条目也推进退避。
    @discardableResult
    public func drain(force: Bool = false) async -> ZXOutboxDrainReport {
        var report = ZXOutboxDrainReport()
        if isDraining {
            drainAgain = true
            forceAgain = forceAgain || force
            report.coalesced = true
            return report
        }
        isDraining = true
        var passForce = force
        repeat {
            drainAgain = false
            await drainPass(force: passForce, report: &report)
            passForce = forceAgain
            forceAgain = false
        } while drainAgain
        isDraining = false
        scheduleRetry()
        return report
    }

    private func drainPass(force: Bool, report: inout ZXOutboxDrainReport) async {
        guard let passOwner = owner else { return }
        prune()
        let start = now()
        let due = load()
            .filter { $0.owner == passOwner && (force || ($0.nextAttemptAt ?? .distantPast) <= start) }
            .map { (id: $0.id, revision: $0.revision) }

        for item in due {
            // 换了用户就停: 剩下的条目已不属于当前 session。
            guard owner == passOwner,
                  let entry = load().first(where: { $0.id == item.id && $0.owner == passOwner }) else { continue }
            let sentRevision = entry.revision
            let outcome = await transport.deliver(entry)

            var list = load()
            guard let index = list.firstIndex(where: { $0.id == item.id }) else { continue }  // 期间被 clear / 换人
            let replacedInFlight = list[index].revision != sentRevision
            switch outcome {
            case .delivered:
                report.delivered += 1
                // 飞行途中被同键覆盖: 服务端拿到的是旧载荷, 新载荷还得再发。
                if !replacedInFlight { list.remove(at: index) }
            case .rejected(let reason):
                report.rejected += 1
                if replacedInFlight {
                    list[index].lastError = reason
                } else {
                    list.remove(at: index)
                    droppedCount += 1
                }
            case .retryLater(let reason):
                report.deferred += 1
                if !replacedInFlight {
                    list[index].attempts += 1
                    list[index].lastError = reason
                    list[index].nextAttemptAt = now().addingTimeInterval(delay(forAttempt: list[index].attempts))
                }
                try? persist(list)
                return
            }
            try? persist(list)
        }
    }

    // MARK: - 联网监测

    /// 订阅网络状态, 每次由断到通 (以及启动时第一次报「通」) 都强制补传一轮。
    /// 重复调用会替换之前的订阅。
    public func startMonitoring(_ connectivity: any ZXConnectivity = ZXPathMonitor()) {
        monitorTask?.cancel()
        let updates = connectivity.updates()
        monitorTask = Task { [weak self] in
            var wasOnline = false
            for await online in updates {
                if Task.isCancelled { break }
                if online && !wasOnline {
                    await self?.drain(force: true)
                }
                wasOnline = online
            }
        }
    }

    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - 内部

    private func delay(forAttempt attempt: Int) -> TimeInterval {
        let base = policy.backoff(attempt: attempt)
        guard policy.jitter > 0 else { return base }
        return base * (1 + Double.random(in: 0..<policy.jitter))
    }

    /// 入队 / 换人后顺手补传一轮 (不等结果)。
    private func kick() {
        guard policy.autoDrain, owner != nil else { return }
        Task { [weak self] in await self?.drain() }
    }

    /// 还有退避中的条目时, 定一个到期就 drain 的定时器。
    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = nil
        guard policy.autoDrain, let owner else { return }
        guard let earliest = load().filter({ $0.owner == owner }).compactMap(\.nextAttemptAt).min() else { return }
        let wait = max(0, earliest.timeIntervalSince(now()))
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await self?.drain()
        }
    }

    /// 丢掉超龄条目。
    private func prune() {
        let list = load()
        let cutoff = now().addingTimeInterval(-policy.maxAge)
        let kept = list.filter { $0.createdAt >= cutoff }
        guard kept.count != list.count else { return }
        droppedCount += list.count - kept.count
        try? persist(kept)
    }

    private func load() -> [ZXOutboxEntry] {
        if let entries { return entries }
        var list: [ZXOutboxEntry] = []
        if let data = try? Data(contentsOf: fileURL) {
            if let file = try? JSONDecoder().decode(OutboxFile.self, from: data) {
                list = file.entries
            } else {
                // 坏文件挪到旁边留证, 不让下一次保存把它覆盖掉 (与 ReadingStateStore 同一做法)。
                let backup = fileURL.appendingPathExtension("corrupt")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.moveItem(at: fileURL, to: backup)
            }
        }
        entries = list
        prune()
        return entries ?? list
    }

    private func persist(_ list: [ZXOutboxEntry]) throws {
        entries = list
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(OutboxFile(entries: list))
        try data.write(to: fileURL, options: .atomic)
    }

    private struct OutboxFile: Codable {
        var schema = 1
        var entries: [ZXOutboxEntry]
    }
}

/// ZixiaoCore 的本地文件根目录: `Application Support/ZixiaoCore/`。
enum ZXCorePaths {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("ZixiaoCore", isDirectory: true)
    }
}
