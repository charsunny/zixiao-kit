@testable import ZixiaoPoetCore
import Foundation
import XCTest
import ZixiaoCore
@testable import ZixiaoPoet

/// 迁自 PoetKit ReadingHistoryCacheTests (缓存按 app + 账号隔离、并入后源头清掉),
/// 加上换号后的拉取合并与回推。
@MainActor
final class PoetUserDataTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
        suites = []
        super.tearDown()
    }

    private func makeCache() -> PoetUserDataCache {
        let suite = "ZixiaoPoetTests.UserData.\(UUID().uuidString)"
        suites.append(suite)
        return PoetUserDataCache(defaults: UserDefaults(suiteName: suite)!)
    }

    private func makeOutbox() -> ZXOutbox {
        ZXOutbox(fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("poet-outbox-\(UUID().uuidString).json"),
                 transport: RecordingTransport(), policy: ZXOutboxPolicy(autoDrain: false))
    }

    private func read(_ id: UUID, _ second: Int) -> ReadingState {
        ReadingState(poemId: id, progress: 1, finished: true, lastReadAt: String(format: "2026-09-14T09:00:%02dZ", second))
    }

    func testCacheIsIsolatedByAppAndOwner() {
        let cache = makeCache()
        cache.save(PoetUserSnapshot(reading: (0..<55).map { read(UUID(), $0) }), app: "app-one", owner: "user-a")

        XCTAssertEqual(cache.load(app: "app-one", owner: "user-a").reading.count, 50)
        XCTAssertTrue(cache.load(app: "app-two", owner: "user-a").isEmpty)
        XCTAssertTrue(cache.load(app: "app-one", owner: "user-b").isEmpty)
        XCTAssertTrue(cache.load(app: "app-one", owner: nil).isEmpty)
    }

    func testAdoptingMovesDataAndClearsTheSource() {
        let cache = makeCache()
        let anonymousRecord = read(UUID(), 20), accountRecord = read(UUID(), 30)
        cache.save(PoetUserSnapshot(reading: [anonymousRecord]), app: "app-one", owner: "anon")
        cache.save(PoetUserSnapshot(reading: [accountRecord]), app: "app-one", owner: "user-a")

        cache.adopt(app: "app-one", from: "anon", into: "user-a")

        XCTAssertTrue(cache.load(app: "app-one", owner: "anon").isEmpty)
        XCTAssertEqual(Set(cache.load(app: "app-one", owner: "user-a").reading.map(\.poemId)),
                       [anonymousRecord.poemId, accountRecord.poemId])
        XCTAssertTrue(cache.load(app: "app-one", owner: "user-b").isEmpty)
    }

    /// 匿名号收藏了一首 → Apple 登录换到统一账号 → 本机收藏并进新账号, 拉到云端已有的, 只回推本机独有的。
    func testAccountSwitchAdoptsAnonymousDataPullsAndPushesTheDifference() async throws {
        let cache = makeCache(), outbox = makeOutbox()
        let localPoem = UUID(), cloudPoem = UUID()
        let remote = MockRemote(rows: PoetRemoteRows(bookmarks: [
            Bookmark(targetType: "poem", targetId: cloudPoem, createdAt: "2026-09-01T00:00:00Z"),
        ]))
        let data = PoetUserData(app: "testapp", outbox: outbox, remote: remote, cache: cache)

        data.userDidChange(.anonymous(userId: "anon-1"))
        await data.refresh()
        try await data.toggleBookmark(Poem.fixture(localPoem))
        XCTAssertTrue(data.isBookmarked(Poem.fixture(localPoem)))

        data.userDidChange(.linked(userId: "user-b", providers: [.apple]))
        await data.refresh()

        XCTAssertEqual(data.userId, "user-b")
        XCTAssertEqual(Set(data.bookmarks.map(\.targetId)), [localPoem, cloudPoem])
        XCTAssertTrue(cache.load(app: "testapp", owner: "anon-1").isEmpty, "匿名号的本机数据已并走")
        let fetchedOwners = await remote.fetchedOwners
        XCTAssertEqual(fetchedOwners.last, "u:user-b")

        let pushed = await outbox.pending().filter { $0.payload["owner_key"] == .string("u:user-b") }
        XCTAssertEqual(pushed.map(\.table), ["poetkit_bookmarks"])
        XCTAssertEqual(pushed.first?.payload["target_id"], .string(localPoem.uuidString.lowercased()))
    }

    func testOfflineReadsAreKeptLocallyUntilAnAccountExists() async {
        let cache = makeCache(), outbox = makeOutbox()
        let data = PoetUserData(app: "testapp", outbox: outbox, remote: MockRemote(rows: PoetRemoteRows()), cache: cache)
        let poem = UUID()

        await data.markRead(Poem.fixture(poem))
        let queuedWhileSignedOut = await outbox.pendingCount
        XCTAssertEqual(queuedWhileSignedOut, 0, "没有账号时不排上行 (载荷里得有 owner_key)")

        data.userDidChange(.anonymous(userId: "anon-2"))
        await data.refresh()
        XCTAssertEqual(data.reading.map(\.poemId), [poem])
        let pushed = await outbox.pending()
        XCTAssertEqual(pushed.map(\.table), ["poetkit_reading_state"])
        XCTAssertEqual(pushed.first?.payload["owner_key"], .string("u:anon-2"))
    }

    func testClearLocalAfterAccountDeletion() async throws {
        let cache = makeCache()
        let data = PoetUserData(app: "testapp", outbox: makeOutbox(), remote: MockRemote(rows: PoetRemoteRows()),
                                cache: cache)
        data.userDidChange(.linked(userId: "user-c", providers: [.phone]))
        await data.refresh()
        await data.markRead(Poem.fixture(UUID()))
        XCTAssertFalse(data.reading.isEmpty)

        data.clearLocal(for: "user-c")

        XCTAssertTrue(data.reading.isEmpty)
        XCTAssertTrue(cache.load(app: "testapp", owner: "user-c").isEmpty)
    }

    func testOlderPullCannotOverwriteANewerCompletedRefresh() async {
        let remote = SuspendedUserDataRemote(), cache = makeCache()
        let data = PoetUserData(app: "testapp", outbox: nil, remote: remote, cache: cache)
        data.userDidChange(.linked(userId: "user-a", providers: [.apple]))
        await data.refresh()
        await remote.suspendFetches()

        let older = Task { await data.refresh() }
        await remote.waitForRequests(1)
        let newer = Task { await data.refresh() }
        await remote.waitForRequests(2)
        let currentRecord = read(UUID(), 30), staleRecord = read(UUID(), 10)
        await remote.complete(1, with: PoetRemoteRows(reading: [currentRecord]))
        await newer.value
        await remote.complete(0, with: PoetRemoteRows(reading: [staleRecord]))
        await older.value

        XCTAssertEqual(data.reading.map(\.poemId), [currentRecord.poemId])
        XCTAssertEqual(cache.load(app: "testapp", owner: "user-a").reading.map(\.poemId), [currentRecord.poemId])
        XCTAssertFalse(data.isPulling)
    }

    func testOlderPullCannotDismissTheCurrentLoadingIndicator() async {
        let remote = SuspendedUserDataRemote()
        let data = PoetUserData(app: "testapp", outbox: nil, remote: remote, cache: makeCache())
        data.userDidChange(.linked(userId: "user-a", providers: [.apple]))
        await data.refresh()
        await remote.suspendFetches()

        let older = Task { await data.refresh() }
        await remote.waitForRequests(1)
        let newer = Task { await data.refresh() }
        await remote.waitForRequests(2)
        await remote.complete(0, with: PoetRemoteRows())
        await older.value
        XCTAssertTrue(data.isPulling, "仍有当前请求在等待时，旧请求不能撤掉加载状态")
        await remote.complete(1, with: PoetRemoteRows())
        await newer.value
        XCTAssertFalse(data.isPulling)
    }

    func testClearedAccountDataCannotBeRestoredByAnInflightPull() async {
        let remote = SuspendedUserDataRemote(), cache = makeCache()
        let data = PoetUserData(app: "testapp", outbox: nil, remote: remote, cache: cache)
        data.userDidChange(.linked(userId: "user-a", providers: [.apple]))
        await data.refresh()
        await remote.suspendFetches()
        let refresh = Task { await data.refresh() }
        await remote.waitForRequests(1)

        data.clearLocal(for: "user-a")
        XCTAssertFalse(data.isPulling)
        await remote.complete(0, with: PoetRemoteRows(reading: [read(UUID(), 30)]))
        await refresh.value

        XCTAssertTrue(data.reading.isEmpty)
        XCTAssertTrue(cache.load(app: "testapp", owner: "user-a").isEmpty)
    }

    func testFailedQueuedUploadPreventsDeleteAndRestoresBookmark() async throws {
        let remote = MockRemote(rows: PoetRemoteRows()), outbox = makeOutbox()
        let data = PoetUserData(app: "testapp", outbox: outbox, remote: remote, cache: makeCache())
        data.userDidChange(.linked(userId: "user-a", providers: [.apple]))
        await data.refresh()
        await outbox.setOwner("user-a")
        let poem = Poem.fixture(UUID())
        try await data.toggleBookmark(poem)

        do {
            try await data.toggleBookmark(poem)
            XCTFail("补传还未成功时不能删完又让待传收藏重新出现")
        } catch {
            XCTAssertTrue(data.isBookmarked(poem))
        }
        let deletes = await remote.deletedBookmarks
        XCTAssertTrue(deletes.isEmpty)
        let queued = await outbox.pendingCount
        XCTAssertEqual(queued, 1, "补传意图保留，不能为了删除失败而丢掉收藏")
    }

    func testInflightPullCannotRestoreAnUnbookmarkedPoem() async throws {
        let remote = SuspendedUserDataRemote()
        let data = PoetUserData(app: "testapp", outbox: nil, remote: remote, cache: makeCache())
        data.userDidChange(.linked(userId: "user-a", providers: [.apple]))
        await data.refresh()
        let poem = Poem.fixture(UUID())
        try await data.toggleBookmark(poem)
        let oldRows = PoetRemoteRows(bookmarks: data.bookmarks)
        await remote.suspendFetches()
        let refresh = Task { await data.refresh() }
        await remote.waitForRequests(1)

        try await data.toggleBookmark(poem)
        await remote.complete(0, with: oldRows)
        await refresh.value

        XCTAssertFalse(data.isBookmarked(poem))
    }
}

/// Deliberately completes canceled requests too, like a response already in flight.
/// Explicit continuations let the tests control response order without sleeps.
private actor SuspendedUserDataRemote: PoetUserDataRemote {
    private var suspended = false
    private var requests: [CheckedContinuation<PoetRemoteRows, Never>] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func suspendFetches() { suspended = true }

    func fetch(ownerKey: String, app: String) async throws -> PoetRemoteRows {
        guard suspended else { return PoetRemoteRows() }
        return await withCheckedContinuation { continuation in
            requests.append(continuation)
            let ready = waiters.filter { $0.0 <= requests.count }
            waiters.removeAll { $0.0 <= requests.count }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func waitForRequests(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func complete(_ index: Int, with rows: PoetRemoteRows) { requests[index].resume(returning: rows) }
    func deleteBookmark(ownerKey: String, app: String, targetType: String, targetId: UUID) async throws {}
}

actor MockRemote: PoetUserDataRemote {
    let rows: PoetRemoteRows
    private(set) var fetchedOwners: [String] = []
    private(set) var deletedBookmarks: [UUID] = []
    init(rows: PoetRemoteRows) { self.rows = rows }

    func fetch(ownerKey: String, app: String) async throws -> PoetRemoteRows {
        fetchedOwners.append(ownerKey)
        return rows
    }

    func deleteBookmark(ownerKey: String, app: String, targetType: String, targetId: UUID) async throws {
        deletedBookmarks.append(targetId)
    }
}

extension Poem {
    static func fixture(_ id: UUID) -> Poem {
        try! JSONDecoder().decode(Poem.self, from: Data(
            #"{"id":"\#(id.uuidString)","title":"占位","form":"shi","content":"占位诗句"}"#.utf8))
    }
}
