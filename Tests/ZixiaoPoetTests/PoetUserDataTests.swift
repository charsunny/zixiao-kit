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
}

actor MockRemote: PoetUserDataRemote {
    let rows: PoetRemoteRows
    private(set) var fetchedOwners: [String] = []
    init(rows: PoetRemoteRows) { self.rows = rows }

    func fetch(ownerKey: String, app: String) async throws -> PoetRemoteRows {
        fetchedOwners.append(ownerKey)
        return rows
    }

    func deleteBookmark(ownerKey: String, app: String, targetType: String, targetId: UUID) async throws {}
}

extension Poem {
    static func fixture(_ id: UUID) -> Poem {
        try! JSONDecoder().decode(Poem.self, from: Data(
            #"{"id":"\#(id.uuidString)","title":"占位","form":"shi","content":"占位诗句"}"#.utf8))
    }
}
