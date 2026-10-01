//  PoetUserModels.swift — 收藏 / 阅读进度 / 笔记的行模型
//
//  对应 migration 062 的三张表 (poetkit_bookmarks / poetkit_reading_state / poetkit_notes)。
//  同一组模型既解 PostgREST 的行, 也落本地缓存, 所以编码键就是列名。

import Foundation

public struct Bookmark: Codable, Sendable, Identifiable, Hashable {
    /// 本地 id。云端行的 id 由服务端生成, 拉取后以云端为准; 上行载荷不带 id (按唯一键 upsert)。
    public let id: UUID
    public let targetType: String
    public let targetId: UUID
    public let note: String?
    /// ISO 8601。旧行可能缺。
    public let createdAt: String?

    public init(id: UUID = UUID(), targetType: String, targetId: UUID, note: String? = nil,
                createdAt: String? = nil) {
        self.id = id
        self.targetType = targetType
        self.targetId = targetId
        self.note = note
        self.createdAt = createdAt
    }

    /// 合并用的身份: 同一应用里 (类型, 目标) 唯一 —— 与 062 的唯一键 (除去 owner_key / app) 一致。
    public var mergeKey: String { "\(targetType)|\(targetId.uuidString.lowercased())" }

    enum CodingKeys: String, CodingKey {
        case id, note
        case targetType = "target_type", targetId = "target_id", createdAt = "created_at"
    }
}

public struct ReadingState: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID { poemId }
    public let poemId: UUID
    public let progress: Double
    public let finished: Bool
    /// ISO 8601。合并时「新者胜」比的就是它。
    public let lastReadAt: String?

    public init(poemId: UUID, progress: Double, finished: Bool, lastReadAt: String?) {
        self.poemId = poemId
        self.progress = progress
        self.finished = finished
        self.lastReadAt = lastReadAt
    }

    enum CodingKeys: String, CodingKey {
        case progress, finished
        case poemId = "poem_id", lastReadAt = "last_read_at"
    }
}

public struct PoetNote: Codable, Sendable, Identifiable, Hashable {
    /// 客户端生成, 即云端主键 (笔记表没有业务唯一键, 按 id upsert)。
    public let id: UUID
    public let targetType: String
    public let targetId: UUID
    public let body: String
    public let createdAt: String?
    public let updatedAt: String?

    public init(id: UUID = UUID(), targetType: String, targetId: UUID, body: String,
                createdAt: String?, updatedAt: String?) {
        self.id = id
        self.targetType = targetType
        self.targetId = targetId
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, body
        case targetType = "target_type", targetId = "target_id"
        case createdAt = "created_at", updatedAt = "updated_at"
    }
}

/// 一个账号在一个应用下的本地用户数据。
public struct PoetUserSnapshot: Codable, Sendable, Hashable {
    public var bookmarks: [Bookmark]
    public var reading: [ReadingState]
    public var notes: [PoetNote]
    /// 上次拉取时云端有的收藏 (`Bookmark.mergeKey`)。三方合并的基准:
    /// 本地有、云端没有的收藏, 若在基准里, 说明是别处删掉的 (删除不经离线队列, 没有墓碑), 不再回推;
    /// 不在基准里, 才是本机新加、还没传上去的。
    public var remoteBookmarkKeys: Set<String>

    public init(bookmarks: [Bookmark] = [], reading: [ReadingState] = [], notes: [PoetNote] = [],
                remoteBookmarkKeys: Set<String> = []) {
        self.bookmarks = bookmarks
        self.reading = reading
        self.notes = notes
        self.remoteBookmarkKeys = remoteBookmarkKeys
    }

    public static let empty = PoetUserSnapshot()

    public var isEmpty: Bool { bookmarks.isEmpty && reading.isEmpty && notes.isEmpty }
}

/// 拉回来的云端行。
public struct PoetRemoteRows: Sendable, Hashable {
    public var bookmarks: [Bookmark]
    public var reading: [ReadingState]
    public var notes: [PoetNote]

    public init(bookmarks: [Bookmark] = [], reading: [ReadingState] = [], notes: [PoetNote] = []) {
        self.bookmarks = bookmarks
        self.reading = reading
        self.notes = notes
    }
}

/// 时间戳: 写出带毫秒的 UTC ISO 8601; 读入兼容 PostgREST 的微秒与 `+00:00` 写法。
public enum PoetTimestamp {
    public static func string(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// 解析失败 (含 nil) 返回 `.distantPast`: 没有时间的一方在「新者胜」里永远输。
    public static func date(_ value: String?) -> Date {
        guard let value, !value.isEmpty else { return .distantPast }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: trimmedFraction(value)) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: value) ?? .distantPast
    }

    /// Postgres 给 6 位小数秒, ISO8601DateFormatter 只稳妥地认 3 位: 截到毫秒。
    static func trimmedFraction(_ value: String) -> String {
        guard let dot = value.firstIndex(of: ".") else { return value }
        let afterDot = value.index(after: dot)
        let digitsEnd = value[afterDot...].firstIndex { !$0.isNumber } ?? value.endIndex
        let digits = value[afterDot..<digitsEnd]
        guard digits.count > 3 else { return value }
        return String(value[..<afterDot]) + digits.prefix(3) + value[digitsEnd...]
    }
}
