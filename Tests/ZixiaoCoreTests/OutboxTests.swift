import XCTest
@testable import ZixiaoCore

final class OutboxTests: XCTestCase {
    var dir: URL!
    var clock: TestClock!
    var transport: MockTransport!

    override func setUp() {
        dir = makeTempDirectory()
        clock = TestClock()
        transport = MockTransport()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private var fileURL: URL { dir.appendingPathComponent("outbox.json") }

    private func makeOutbox(policy: ZXOutboxPolicy = ZXOutboxPolicy(jitter: 0, autoDrain: false)) -> ZXOutbox {
        let clock = self.clock!
        return ZXOutbox(fileURL: fileURL, transport: transport, policy: policy, now: { clock.now })
    }

    // MARK: - 排队与持久化

    func testEnqueuePersistsAcrossInstances() async throws {
        let outbox = makeOutbox()
        await outbox.setOwner("u1")
        try await outbox.enqueue(table: "zen_reflections", payload: ["id": "r1", "text": "静", "n": 1, "ok": true])
        try await outbox.enqueue(table: "zen_user_preferences", operation: .upsert,
                                 payload: ["user_id": "u1", "lizhu": false], onConflict: "user_id")

        let reopened = makeOutbox()
        let pending = await reopened.pending()
        XCTAssertEqual(pending.map(\.table), ["zen_reflections", "zen_user_preferences"])
        XCTAssertEqual(pending[0].payload["text"], "静")
        XCTAssertEqual(pending[0].payload["n"], .int(1))
        XCTAssertEqual(pending[1].operation, .upsert)
        XCTAssertEqual(pending[1].onConflict, "user_id")
        XCTAssertEqual(pending[0].owner, "u1")
    }

    func testCorruptFileIsSetAsideNotFatal() async throws {
        try Data("not json".utf8).write(to: fileURL)
        let outbox = makeOutbox()
        let count = await outbox.pendingCount
        XCTAssertEqual(count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.appendingPathExtension("corrupt").path))
    }

    // MARK: - 去重

    func testSameIdempotencyKeyReplacesPayload() async throws {
        let outbox = makeOutbox()
        await outbox.setOwner("u1")
        let first = try await outbox.enqueue(table: "prefs", operation: .upsert, payload: ["lizhu": true],
                                             idempotencyKey: "prefs:u1")
        let second = try await outbox.enqueue(table: "prefs", operation: .upsert, payload: ["lizhu": false],
                                              idempotencyKey: "prefs:u1")
        XCTAssertEqual(first, .queued)
        XCTAssertEqual(second, .replaced)
        let pending = await outbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].payload["lizhu"], false)
        XCTAssertEqual(pending[0].revision, 1)
    }

    func testKeysWithoutIdempotencyAreDistinct() async throws {
        let outbox = makeOutbox()
        await outbox.setOwner("u1")
        try await outbox.enqueue(table: "t", payload: ["a": 1])
        try await outbox.enqueue(table: "t", payload: ["a": 1])
        let count = await outbox.pendingCount
        XCTAssertEqual(count, 2)
    }

    func testDedupeIsScopedToOwner() async throws {
        let outbox = makeOutbox()
        try await outbox.enqueue(table: "t", payload: ["a": 1], idempotencyKey: "k")   // 无主
        await outbox.setOwner("u1")                                                    // 无主的归 u1
        try await outbox.enqueue(table: "t", payload: ["a": 2], idempotencyKey: "k")   // 同键覆盖
        let pending = await outbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].owner, "u1")
        XCTAssertEqual(pending[0].payload["a"], 2)
    }

    // MARK: - 重放

    func testDrainDeliversInOrderAndEmptiesQueue() async throws {
        let outbox = makeOutbox()
        await outbox.setOwner("u1")
        for i in 1...3 { try await outbox.enqueue(table: "t", payload: ["i": .int(i)]) }
        let report = await outbox.drain()
        XCTAssertEqual(report.delivered, 3)
        XCTAssertEqual(transport.sent.map { $0.payload["i"] }, [1, 2, 3])
        let count = await outbox.pendingCount
        XCTAssertEqual(count, 0)
        // 落盘的也清空了。
        let reopenedCount = await makeOutbox().pendingCount
        XCTAssertEqual(reopenedCount, 0)
    }

    func testDrainWithoutOwnerSendsNothing() async throws {
        let outbox = makeOutbox()
        try await outbox.enqueue(table: "t", payload: [:])
        let report = await outbox.drain()
        XCTAssertEqual(report.delivered, 0)
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testRejectedEntriesAreDropped() async throws {
        transport.script([.rejected("42501 RLS")])
        let outbox = makeOutbox()
        await outbox.setOwner("u1")
        try await outbox.enqueue(table: "t", payload: ["i": 1])
        try await outbox.enqueue(table: "t", payload: ["i": 2])
        let report = await outbox.drain()
        XCTAssertEqual(report.rejected, 1)
        XCTAssertEqual(report.delivered, 1)
        let count = await outbox.pendingCount
        let dropped = await outbox.droppedCount
        XCTAssertEqual(count, 0)
        XCTAssertEqual(dropped, 1)
    }

    func testReplacedWhileInFlightIsResent() async throws {
        let outbox = makeOutbox()
        await outbox.setOwner("u1")
        try await outbox.enqueue(table: "prefs", operation: .upsert, payload: ["v": 1], idempotencyKey: "p")
        // 第一次投递途中, 用户又改了一次偏好。
        transport.onDeliver = { [weak outbox] entry in
            if entry.payload["v"] == 1 {
                _ = try? await outbox?.enqueue(table: "prefs", operation: .upsert, payload: ["v": 2],
                                               idempotencyKey: "p")
            }
        }
        await outbox.drain()
        var pending = await outbox.pending()
        XCTAssertEqual(pending.count, 1, "服务端拿到的是旧载荷, 新载荷必须留着")
        XCTAssertEqual(pending[0].payload["v"], 2)

        transport.onDeliver = nil
        await outbox.drain()
        pending = await outbox.pending()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(transport.sent.map { $0.payload["v"] }, [1, 2])
    }

    // MARK: - 退避

    func testBackoffSchedule() {
        let policy = ZXOutboxPolicy(baseDelay: 2, maxDelay: 600, jitter: 0)
        XCTAssertEqual((0...10).map { policy.backoff(attempt: $0) },
                       [0, 2, 4, 8, 16, 32, 64, 128, 256, 512, 600])
        XCTAssertEqual(policy.backoff(attempt: 10_000), 600)
    }

    func testTransientFailureBacksOffExponentially() async throws {
        transport.script([.retryLater("offline"), .retryLater("offline")], then: .delivered)
        let outbox = makeOutbox()
        await outbox.setOwner("u1")
        try await outbox.enqueue(table: "t", payload: ["i": 1])

        var report = await outbox.drain()
        XCTAssertEqual(report.deferred, 1)
        var pendingNow = await outbox.pending()
        var entry = try XCTUnwrap(pendingNow.first)
        XCTAssertEqual(entry.attempts, 1)
        XCTAssertEqual(entry.nextAttemptAt, clock.now.addingTimeInterval(2))
        XCTAssertEqual(entry.lastError, "offline")

        // 未到期: 不发。
        clock.advance(1)
        report = await outbox.drain()
        XCTAssertEqual(report.delivered + report.deferred, 0)
        XCTAssertEqual(transport.sent.count, 1)

        // 到期: 再失败, 等待翻倍。
        clock.advance(1)
        report = await outbox.drain()
        XCTAssertEqual(report.deferred, 1)
        pendingNow = await outbox.pending()
        entry = try XCTUnwrap(pendingNow.first)
        XCTAssertEqual(transport.sent.count, 2)
        XCTAssertEqual(entry.attempts, 2)
        XCTAssertEqual(entry.nextAttemptAt, clock.now.addingTimeInterval(4))

        // 强制 (联网恢复) 无视退避。
        report = await outbox.drain(force: true)
        XCTAssertEqual(report.delivered, 1)
        let count = await outbox.pendingCount
        XCTAssertEqual(count, 0)
    }

    func testDrainStopsAtFirstTransientFailure() async throws {
        transport.script([.retryLater("timeout")])
        let outbox = makeOutbox()
        await outbox.setOwner("u1")
        for i in 1...3 { try await outbox.enqueue(table: "t", payload: ["i": .int(i)]) }
        let report = await outbox.drain()
        XCTAssertEqual(report.deferred, 1)
        XCTAssertEqual(transport.sent.count, 1, "断网时不该把整队都撞一遍")
        let count = await outbox.pendingCount
        XCTAssertEqual(count, 3)
    }

    func testReenqueueResetsBackoff() async throws {
        transport.script([.retryLater("x")])
        let outbox = makeOutbox()
        await outbox.setOwner("u1")
        try await outbox.enqueue(table: "t", payload: ["v": 1], idempotencyKey: "k")
        await outbox.drain()
        try await outbox.enqueue(table: "t", payload: ["v": 2], idempotencyKey: "k")
        let pendingNow = await outbox.pending()
        let entry = try XCTUnwrap(pendingNow.first)
        XCTAssertEqual(entry.attempts, 0)
        XCTAssertNil(entry.nextAttemptAt)
    }

    // MARK: - 归属

    func testOwnerChangeDropsPreviousUsersEntriesAndAdoptsOrphans() async throws {
        let outbox = makeOutbox()
        try await outbox.enqueue(table: "t", payload: ["who": "nobody"])   // 首启离线, 无主
        await outbox.setOwner("u1")
        try await outbox.enqueue(table: "t", payload: ["who": "u1"])
        var owners = await outbox.pending().map(\.owner)
        XCTAssertEqual(owners, ["u1", "u1"])

        await outbox.setOwner("u2")
        owners = await outbox.pending().map(\.owner)
        XCTAssertEqual(owners, [], "换账号后上一位的写入不能以新身份补传")
    }

    // MARK: - 容量与过期

    func testCapacityDropsOldest() async throws {
        let outbox = makeOutbox(policy: ZXOutboxPolicy(maxEntries: 3, jitter: 0, autoDrain: false))
        await outbox.setOwner("u1")
        for i in 1...5 { try await outbox.enqueue(table: "t", payload: ["i": .int(i)]) }
        let values = await outbox.pending().map { $0.payload["i"] }
        XCTAssertEqual(values, [3, 4, 5])
    }

    func testStaleEntriesArePruned() async throws {
        let outbox = makeOutbox(policy: ZXOutboxPolicy(maxAge: 100, jitter: 0, autoDrain: false))
        await outbox.setOwner("u1")
        try await outbox.enqueue(table: "t", payload: ["i": 1])
        clock.advance(101)
        try await outbox.enqueue(table: "t", payload: ["i": 2])
        let report = await outbox.drain()
        XCTAssertEqual(report.delivered, 1)
        XCTAssertEqual(transport.sent.map { $0.payload["i"] }, [2])
    }

    // MARK: - 联网恢复后重放

    func testConnectivityRecoveryReplaysQueue() async throws {
        transport.script([.retryLater("offline")], then: .delivered)
        let outbox = makeOutbox()
        await outbox.setOwner("u1")
        try await outbox.enqueue(table: "t", payload: ["i": 1])
        await outbox.drain()   // 断网中: 进入退避
        var count = await outbox.pendingCount
        XCTAssertEqual(count, 1)

        let connectivity = MockConnectivity()
        await outbox.startMonitoring(connectivity)
        connectivity.send(false)
        connectivity.send(true)   // 恢复: 应无视退避立即重放
        let drained = await waitUntil { await outbox.pendingCount == 0 }
        XCTAssertTrue(drained)
        count = await outbox.pendingCount
        XCTAssertEqual(count, 0)
        await outbox.stopMonitoring()
    }

    func testAutoDrainOnEnqueue() async throws {
        let outbox = makeOutbox(policy: ZXOutboxPolicy(jitter: 0, autoDrain: true))
        await outbox.setOwner("u1")
        try await outbox.enqueue(table: "t", payload: ["i": 1])
        let drained = await waitUntil { await outbox.pendingCount == 0 }
        XCTAssertTrue(drained)
        XCTAssertEqual(transport.sent.count, 1)
    }

    func testJSONValueRoundTrip() throws {
        let value: ZXJSONValue = ["s": "字", "i": 3, "d": 1.5, "b": true, "n": nil, "a": [1, "x"], "o": ["k": "v"]]
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(ZXJSONValue.self, from: data), value)
    }
}
