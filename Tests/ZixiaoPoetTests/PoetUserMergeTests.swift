import Foundation
import XCTest
@testable import ZixiaoPoet

final class PoetUserMergeTests: XCTestCase {
    private func ts(_ second: Int) -> String { String(format: "2026-09-14T09:00:%02dZ", second) }
    private func read(_ id: UUID, _ second: Int, progress: Double = 1) -> ReadingState {
        ReadingState(poemId: id, progress: progress, finished: progress >= 1, lastReadAt: ts(second))
    }
    private func mark(_ id: UUID, _ second: Int) -> Bookmark {
        Bookmark(targetType: "poem", targetId: id, createdAt: ts(second))
    }

    // MARK: 阅读: updated_at (last_read_at) 新者胜, 本地独有回推

    func testNewerReadingWinsAndLocalOnlyRowsArePushed() {
        let shared = UUID(), localOnly = UUID(), remoteOnly = UUID(), remoteNewer = UUID()
        let local = [read(shared, 20), read(localOnly, 5), read(remoteNewer, 1)]
        let remote = [read(shared, 10, progress: 0.5), read(remoteOnly, 3), read(remoteNewer, 30)]

        let result = PoetUserMerge.reading(local: local, remote: remote)

        XCTAssertEqual(Set(result.merged.map(\.poemId)), [shared, localOnly, remoteOnly, remoteNewer])
        XCTAssertEqual(result.merged.first { $0.poemId == shared }?.lastReadAt, ts(20))
        XCTAssertEqual(result.merged.first { $0.poemId == remoteNewer }?.lastReadAt, ts(30))
        XCTAssertEqual(Set(result.pushes.map(\.poemId)), [shared, localOnly],
                       "本地更新的与本地独有的回推; 云端更新的不推")
    }

    /// 迁自 PoetKit ReadingHistoryCacheTests: 拉取途中刚读的那一下不被覆盖。
    func testEquallyOrMoreRecentLocalReadSurvivesAnInFlightPull() {
        let poem = UUID()
        let merged = PoetUserMerge.reading(local: [read(poem, 20)], remote: [read(poem, 10, progress: 0.5)]).merged
        XCTAssertEqual(merged, [read(poem, 20)])
        let tie = PoetUserMerge.reading(local: [read(poem, 10)], remote: [read(poem, 10, progress: 0.5)]).merged
        XCTAssertEqual(tie.first?.progress, 1, "同一时刻本地胜")
    }

    func testReadingKeepsNewestFifty() {
        let records = (0..<55).map { read(UUID(), $0) }
        let merged = PoetUserMerge.normalizedReading(records)
        XCTAssertEqual(merged.count, 50)
        XCTAssertEqual(merged.first?.lastReadAt, ts(54))
        XCTAssertEqual(merged.last?.lastReadAt, ts(5))
    }

    func testPostgresMicrosecondTimestampsCompareCorrectly() {
        let a = PoetTimestamp.date("2026-09-14T09:00:10.123456+00:00")
        let b = PoetTimestamp.date("2026-09-14T09:00:10.200Z")
        XCTAssertNotEqual(a, .distantPast)
        XCTAssertLessThan(a, b)
        XCTAssertEqual(PoetTimestamp.date(nil), .distantPast)
    }

    // MARK: 收藏: 集合 + 基准

    func testBookmarksUnionWithBaseDetectingRemoteDeletes() {
        let kept = UUID(), newLocal = UUID(), deletedElsewhere = UUID(), remoteOnly = UUID()
        let local = [mark(kept, 1), mark(newLocal, 2), mark(deletedElsewhere, 3)]
        let remote = [mark(kept, 1), mark(remoteOnly, 4)]
        let base: Set<String> = [mark(kept, 1).mergeKey, mark(deletedElsewhere, 3).mergeKey]

        let result = PoetUserMerge.bookmarks(local: local, remote: remote, base: base)

        XCTAssertEqual(Set(result.merged.map(\.targetId)), [kept, newLocal, remoteOnly])
        XCTAssertEqual(result.pushes.map(\.targetId), [newLocal], "只回推本机新加的; 别处删掉的不复活")
        XCTAssertEqual(result.merged.first?.targetId, remoteOnly, "新收藏在前")
    }

    func testMergeRecordsTheNewRemoteBaseAndAllPushes() {
        let a = UUID(), b = UUID()
        let local = PoetUserSnapshot(bookmarks: [mark(a, 1)], reading: [read(b, 9)])
        let remote = PoetRemoteRows(bookmarks: [mark(b, 2)], reading: [])

        let result = PoetUserMerge.merge(local: local, remote: remote)

        XCTAssertEqual(result.snapshot.remoteBookmarkKeys, [mark(b, 2).mergeKey])
        XCTAssertEqual(result.bookmarkPushes.map(\.targetId), [a])
        XCTAssertEqual(result.readingPushes.map(\.poemId), [b])
        let writes = result.writes(userId: "U1", app: "testapp")
        XCTAssertEqual(writes.map(\.table), ["poetkit_bookmarks", "poetkit_reading_state"])
        XCTAssertTrue(writes.allSatisfy { $0.payload["owner_key"] == .string("u:u1") })
    }

    // MARK: 笔记

    func testNotesNewerUpdatedAtWins() {
        let id = UUID(), target = UUID()
        func note(_ body: String, _ second: Int) -> PoetNote {
            PoetNote(id: id, targetType: "poem", targetId: target, body: body, createdAt: ts(0), updatedAt: ts(second))
        }
        let remoteNewer = PoetUserMerge.notes(local: [note("旧", 1)], remote: [note("新", 2)])
        XCTAssertEqual(remoteNewer.merged.map(\.body), ["新"])
        XCTAssertTrue(remoteNewer.pushes.isEmpty)

        let localNewer = PoetUserMerge.notes(local: [note("新", 3)], remote: [note("旧", 2)])
        XCTAssertEqual(localNewer.merged.map(\.body), ["新"])
        XCTAssertEqual(localNewer.pushes.map(\.body), ["新"])
    }

    // MARK: 换号并入

    func testAdoptionUnionsIntoTheNewAccountAndKeepsItsBase() {
        let anonOnly = UUID(), both = UUID()
        let anonymous = PoetUserSnapshot(bookmarks: [mark(anonOnly, 1), mark(both, 1)], reading: [read(both, 5)])
        let account = PoetUserSnapshot(bookmarks: [mark(both, 2)], reading: [read(both, 8)],
                                       remoteBookmarkKeys: [mark(both, 2).mergeKey])

        let adopted = PoetUserMerge.adopt(anonymous, into: account)

        XCTAssertEqual(Set(adopted.bookmarks.map(\.targetId)), [anonOnly, both])
        XCTAssertEqual(adopted.bookmarks.first { $0.targetId == both }?.createdAt, ts(2), "新账号优先")
        XCTAssertEqual(adopted.reading.map(\.lastReadAt), [ts(8)])
        XCTAssertEqual(adopted.remoteBookmarkKeys, account.remoteBookmarkKeys)
    }
}
