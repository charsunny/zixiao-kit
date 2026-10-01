import Foundation
import XCTest
import ZixiaoCore
@testable import ZixiaoPoet

/// 离线队列载荷的形状: 表名、onConflict (= 062 的唯一键)、owner_key 一律 'u:<小写 uid>'。
final class PoetUserRowsTests: XCTestCase {
    private let uid = "AB12CD34-0000-4000-8000-00000000BEEF"
    private let poem = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    func testBookmarkUpsertsOnTheUniqueKeyWithoutClientId() {
        let bookmark = Bookmark(targetType: "poem", targetId: poem, createdAt: "2026-10-01T08:00:00.000Z")
        let write = PoetUserRows.bookmark(bookmark, userId: uid, app: "testapp")

        XCTAssertEqual(write.table, "poetkit_bookmarks")
        XCTAssertEqual(write.onConflict, "owner_key,app,target_type,target_id")
        XCTAssertEqual(write.payload["owner_key"], .string("u:ab12cd34-0000-4000-8000-00000000beef"))
        XCTAssertEqual(write.payload["app"], .string("testapp"))
        XCTAssertEqual(write.payload["target_type"], .string("poem"))
        XCTAssertEqual(write.payload["target_id"], .string("11111111-1111-4111-8111-111111111111"))
        XCTAssertEqual(write.payload["created_at"], .string("2026-10-01T08:00:00.000Z"))
        XCTAssertNil(write.payload["id"], "主键由服务端生成; 按唯一键 upsert 时不改既有行的 id")
        XCTAssertNil(write.payload["note"])
        XCTAssertEqual(write.idempotencyKey, "poetkit_bookmarks:testapp:poem|11111111-1111-4111-8111-111111111111")
    }

    func testReadingStateUpsertsOnOwnerAppPoem() {
        let state = ReadingState(poemId: poem, progress: 1, finished: true, lastReadAt: "2026-10-01T08:00:00.000Z")
        let write = PoetUserRows.reading(state, userId: uid, app: "testapp")

        XCTAssertEqual(write.table, "poetkit_reading_state")
        XCTAssertEqual(write.onConflict, "owner_key,app,poem_id")
        XCTAssertEqual(write.payload, [
            "owner_key": .string("u:ab12cd34-0000-4000-8000-00000000beef"), "app": .string("testapp"),
            "poem_id": .string("11111111-1111-4111-8111-111111111111"),
            "progress": .double(1), "finished": .bool(true),
            "last_read_at": .string("2026-10-01T08:00:00.000Z"),
        ])
    }

    func testNotesUpsertOnPrimaryKey() {
        let id = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let note = PoetNote(id: id, targetType: "poem", targetId: poem, body: "批注",
                            createdAt: "2026-10-01T08:00:00.000Z", updatedAt: "2026-10-01T09:00:00.000Z")
        let write = PoetUserRows.note(note, userId: uid, app: "testapp")

        XCTAssertEqual(write.table, "poetkit_notes")
        XCTAssertEqual(write.onConflict, "id")
        XCTAssertEqual(write.payload["id"], .string("33333333-3333-4333-8333-333333333333"))
        XCTAssertEqual(write.payload["owner_key"], .string("u:ab12cd34-0000-4000-8000-00000000beef"))
        XCTAssertEqual(write.payload["body"], .string("批注"))
        XCTAssertEqual(write.payload["updated_at"], .string("2026-10-01T09:00:00.000Z"))
    }

    func testOwnerKeyNeverUsesDevicePrefix() {
        XCTAssertEqual(PoetUserRows.ownerKey("ABC"), "u:abc")
        XCTAssertFalse(PoetUserRows.ownerKey("x").hasPrefix("d:"))
    }

    func testEnqueuedWriteKeepsTableConflictAndPayload() async throws {
        let outbox = ZXOutbox(fileURL: FileManager.default.temporaryDirectory
                                .appendingPathComponent("poet-outbox-\(UUID().uuidString).json"),
                              transport: RecordingTransport(), policy: ZXOutboxPolicy(autoDrain: false))
        let state = ReadingState(poemId: poem, progress: 1, finished: true, lastReadAt: "2026-10-01T08:00:00.000Z")
        let write = PoetUserRows.reading(state, userId: uid, app: "testapp")
        try await write.enqueue(into: outbox)
        try await write.enqueue(into: outbox)   // 同键覆盖, 不追加

        let pending = await outbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.table, "poetkit_reading_state")
        XCTAssertEqual(pending.first?.operation, .upsert)
        XCTAssertEqual(pending.first?.onConflict, "owner_key,app,poem_id")
        XCTAssertEqual(pending.first?.payload, write.payload)
    }
}

/// 只记录、不投递的出口。
struct RecordingTransport: ZXOutboxTransport {
    func deliver(_ entry: ZXOutboxEntry) async -> ZXOutboxDelivery { .retryLater("test") }
}
