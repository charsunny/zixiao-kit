import Foundation

public struct ZXCloudLibrarySession: Sendable {
    public let userID: String
    public let accessToken: String
    public init(userID: String, accessToken: String) { self.userID = userID; self.accessToken = accessToken }
}

public struct ZXCloudLibraryContentRef: Codable, Hashable, Sendable {
    public var source: String
    public var kind: String
    public var id: String
    public var anchor: ZXJSONValue?
    public init(source: String, kind: String, id: String, anchor: ZXJSONValue? = nil) {
        self.source = source; self.kind = kind; self.id = id; self.anchor = anchor
    }
}

public struct ZXCloudLibraryDraft: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var kind: String
    public var contentRef: ZXCloudLibraryContentRef
    public var payload: [String: ZXJSONValue]
    public var updatedAt: String
    public var deletedAt: String?
    public var id: String { key }
    public var title: String {
        if case .string(let value) = payload["title"] { return value }
        return contentRef.id
    }
    public init(key: String, kind: String, contentRef: ZXCloudLibraryContentRef,
                payload: [String: ZXJSONValue], updatedAt: String = ZXCloudLibraryJSON.timestamp(), deletedAt: String? = nil) {
        self.key = key; self.kind = kind; self.contentRef = contentRef; self.payload = payload
        self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public struct ZXCloudLibraryRecord: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var kind: String
    public var contentRef: ZXCloudLibraryContentRef
    public var payload: [String: ZXJSONValue]
    public var revision: Int
    public var updatedAt: String
    public var deletedAt: String?
    public var serverCursor: String
    public var conflictOf: String?
    public var id: String { key }
    public var draft: ZXCloudLibraryDraft {
        .init(key: key, kind: kind, contentRef: contentRef, payload: payload, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}

public struct ZXCloudLibraryMutation: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var kind: String
    public var contentRef: ZXCloudLibraryContentRef
    public var payload: [String: ZXJSONValue]
    public var revision: Int
    public var updatedAt: String
    public var deletedAt: String?
    public var clientMutationId: String
    public var id: String { clientMutationId }
    public init(draft: ZXCloudLibraryDraft, revision: Int) {
        key = draft.key; kind = draft.kind; contentRef = draft.contentRef; payload = draft.payload
        self.revision = revision; updatedAt = draft.updatedAt; deletedAt = draft.deletedAt
        clientMutationId = UUID().uuidString.lowercased()
    }
    public var draft: ZXCloudLibraryDraft {
        .init(key: key, kind: kind, contentRef: contentRef, payload: payload, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}

public struct ZXCloudLibraryConflict: Codable, Sendable, Identifiable {
    public let local: ZXCloudLibraryMutation
    public let remote: ZXCloudLibraryRecord
    public var id: String { local.id }
}

public enum ZXCloudLibraryError: Error, LocalizedError {
    case signedOut, accountChanged, corruptLocalState, busy, invalidResponse, http(Int, String), missingAsset
    public var errorDescription: String? {
        switch self {
        case .signedOut: "请先登录，再同步书房。"
        case .accountChanged: "账号已切换，本次同步已停止。"
        case .corruptLocalState: "本机同步记录无法读取，原文件已保留。"
        case .busy: "书房正在同步。"
        case .invalidResponse: "暂时无法读取云端书房，待同步资料已保留。"
        case .http(let status, _): status == 401 ? "登录已过期，请重新登录后同步。" : "云端暂不可用（\(status)），待同步资料已保留。"
        case .missingAsset: "这份草稿的照片暂不可用，已保留本机原件。"
        }
    }
}

public enum ZXCloudLibraryJSON {
    public static func timestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.string(from: date)
    }
    public static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }
    public static func encode<T: Encodable>(_ value: T) throws -> ZXJSONValue {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try JSONDecoder().decode(ZXJSONValue.self, from: encoder.encode(value))
    }
    public static func decode<T: Decodable>(_ type: T.Type, from value: ZXJSONValue) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: JSONEncoder().encode(value))
    }
}

/// Only a live reading at an equal/newer actual-read timestamp may be accepted without a dialog.
/// Favorites, notes, tombstones and identity changes always retain explicit conflict resolution.
public enum ZXCloudLibraryReadingResolution {
    public static func accepts(remote: ZXCloudLibraryRecord, insteadOf local: ZXCloudLibraryMutation) -> Bool {
        guard local.kind == "reading", remote.kind == "reading", local.deletedAt == nil, remote.deletedAt == nil,
              remote.key == local.key, remote.contentRef.source == local.contentRef.source,
              remote.contentRef.kind == local.contentRef.kind, remote.contentRef.id == local.contentRef.id,
              let remoteTime = ZXCloudLibraryJSON.date(remote.updatedAt), let localTime = ZXCloudLibraryJSON.date(local.updatedAt) else { return false }
        return remoteTime >= localTime
    }
}
