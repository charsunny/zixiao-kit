//  PoetUserRows.swift — 本地记录 → 离线队列载荷
//
//  表名、冲突键、owner_key 的写法集中在这里, 测试直接核对载荷形状。
//  owner_key 一律 'u:<uid>' (小写 uuid, 与 auth.uid()::text 一致): 匿名用户也是 Supabase 的
//  authenticated 角色, 有自己的 uid —— 不再有 'd:<device>' 行 (migration 065 删了 anon 策略)。

import Foundation
import ZixiaoCore

public enum PoetUserTable {
    public static let bookmarks = "poetkit_bookmarks"
    public static let reading = "poetkit_reading_state"
    public static let notes = "poetkit_notes"

    /// 062 的唯一键 `poetkit_bookmarks_unique`。
    public static let bookmarksConflict = "owner_key,app,target_type,target_id"
    /// 062 的唯一键 `poetkit_reading_state_unique`。
    public static let readingConflict = "owner_key,app,poem_id"
    /// 笔记没有业务唯一键, 按主键 upsert (id 由客户端生成)。
    public static let notesConflict = "id"
}

/// 一条要排进 `ZXOutbox` 的写入。
public struct PoetOutboxWrite: Sendable, Hashable {
    public let table: String
    public let onConflict: String
    public let payload: [String: ZXJSONValue]
    /// 同键的待传写入只留最后一条 (反复切换收藏只补传最终态)。
    public let idempotencyKey: String

    public func enqueue(into outbox: ZXOutbox) async throws {
        try await outbox.enqueue(table: table, operation: .upsert, payload: payload,
                                 onConflict: onConflict, idempotencyKey: idempotencyKey)
    }
}

public enum PoetUserRows {
    public static func ownerKey(_ userId: String) -> String { "u:\(userId.lowercased())" }

    static func uuid(_ id: UUID) -> ZXJSONValue { .string(id.uuidString.lowercased()) }

    /// 收藏。不带 id: 唯一键冲突时更新既有行, 不去改它的主键。
    public static func bookmark(_ b: Bookmark, userId: String, app: String) -> PoetOutboxWrite {
        var payload: [String: ZXJSONValue] = [
            "owner_key": .string(ownerKey(userId)), "app": .string(app),
            "target_type": .string(b.targetType), "target_id": uuid(b.targetId),
        ]
        if let note = b.note { payload["note"] = .string(note) }
        if let created = b.createdAt { payload["created_at"] = .string(created) }
        return PoetOutboxWrite(table: PoetUserTable.bookmarks, onConflict: PoetUserTable.bookmarksConflict,
                               payload: payload,
                               idempotencyKey: "\(PoetUserTable.bookmarks):\(app):\(b.mergeKey)")
    }

    public static func reading(_ r: ReadingState, userId: String, app: String) -> PoetOutboxWrite {
        var payload: [String: ZXJSONValue] = [
            "owner_key": .string(ownerKey(userId)), "app": .string(app),
            "poem_id": uuid(r.poemId), "progress": .double(r.progress), "finished": .bool(r.finished),
        ]
        if let at = r.lastReadAt { payload["last_read_at"] = .string(at) }
        return PoetOutboxWrite(table: PoetUserTable.reading, onConflict: PoetUserTable.readingConflict,
                               payload: payload,
                               idempotencyKey: "\(PoetUserTable.reading):\(app):\(r.poemId.uuidString.lowercased())")
    }

    public static func note(_ n: PoetNote, userId: String, app: String) -> PoetOutboxWrite {
        var payload: [String: ZXJSONValue] = [
            "id": uuid(n.id), "owner_key": .string(ownerKey(userId)), "app": .string(app),
            "target_type": .string(n.targetType), "target_id": uuid(n.targetId), "body": .string(n.body),
        ]
        if let created = n.createdAt { payload["created_at"] = .string(created) }
        if let updated = n.updatedAt { payload["updated_at"] = .string(updated) }
        return PoetOutboxWrite(table: PoetUserTable.notes, onConflict: PoetUserTable.notesConflict,
                               payload: payload,
                               idempotencyKey: "\(PoetUserTable.notes):\(n.id.uuidString.lowercased())")
    }
}
