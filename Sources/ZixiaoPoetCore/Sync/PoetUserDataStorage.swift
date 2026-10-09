//  PoetUserDataStorage.swift — 本地缓存 (按 app + 账号分键) 与云端拉取出口

import Foundation
import Supabase
import ZixiaoCore

// MARK: - 本地缓存

/// 本机的一份用户数据, 落 UserDefaults, 按 `app` (编成的 appSlug) + 账号 (uid) 分键。
/// 没有账号时 (离线模式 / 退出到重新匿名登录之间) 记在 `localOwner` 名下, 有了账号再并过去。
///
/// 为什么不是文件: 量很小 (阅读 50 条 + 收藏 + 笔记), 与 PoetKit 原来的阅读缓存同一存法。
public struct PoetUserDataCache: @unchecked Sendable {
    // UserDefaults 本身线程安全 (文档保证), 只是 SDK 没标 Sendable。
    public static let localOwner = "local"
    static let keyPrefix = "zixiaopoet.user-data.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(app: String, owner: String?) -> PoetUserSnapshot {
        guard let data = defaults.data(forKey: key(app: app, owner: owner)) else { return .empty }
        do {
            var snapshot = try JSONDecoder().decode(PoetUserSnapshot.self, from: data)
            snapshot.reading = PoetUserMerge.normalizedReading(snapshot.reading)
            return snapshot
        } catch {
            #if DEBUG
            print("ZixiaoPoet: failed to decode local user data for \(app): \(error)")
            #endif
            return .empty
        }
    }

    public func save(_ snapshot: PoetUserSnapshot, app: String, owner: String?) {
        var normalized = snapshot
        normalized.reading = PoetUserMerge.normalizedReading(snapshot.reading)
        do {
            defaults.set(try JSONEncoder().encode(normalized), forKey: key(app: app, owner: owner))
        } catch {
            #if DEBUG
            print("ZixiaoPoet: failed to encode local user data for \(app): \(error)")
            #endif
        }
    }

    public func remove(app: String, owner: String?) {
        defaults.removeObject(forKey: key(app: app, owner: owner))
    }

    /// 把 `source` 名下的数据并进 `target` 名下, 删掉 source 那份 —— 免得之后另一个会话看见。
    /// 返回并入后的 target。
    @discardableResult
    public func adopt(app: String, from source: String?, into target: String) -> PoetUserSnapshot {
        let destination = load(app: app, owner: target)
        guard (source ?? Self.localOwner) != target else { return destination }
        let origin = load(app: app, owner: source)
        guard !origin.isEmpty else { return destination }
        let merged = PoetUserMerge.adopt(origin, into: destination)
        save(merged, app: app, owner: target)
        remove(app: app, owner: source)
        return merged
    }

    func key(app: String, owner: String?) -> String {
        "\(Self.keyPrefix).\(app).\((owner ?? Self.localOwner).lowercased())"
    }
}

// MARK: - 云端

/// 拉取与删除的出口。上行写入不走这里, 走 `ZXOutbox`。测试注入 mock。
public protocol PoetUserDataRemote: Sendable {
    func fetch(ownerKey: String, app: String) async throws -> PoetRemoteRows
    /// 取消收藏。离线队列只有 insert / upsert, 删除只能在线做。
    func deleteBookmark(ownerKey: String, app: String, targetType: String, targetId: UUID) async throws
}

/// PostgREST 实现。客户端取 `ZXSupabase` 的那一个 (与账号同一份 session, RLS 按 auth.uid() 放行)。
public struct PostgrestPoetUserDataRemote: PoetUserDataRemote {
    private let clientProvider: @Sendable () throws -> SupabaseClient

    public init(client: @escaping @Sendable () throws -> SupabaseClient = { try ZXSupabase.requireClient() }) {
        self.clientProvider = client
    }

    public func fetch(ownerKey: String, app: String) async throws -> PoetRemoteRows {
        let client = try clientProvider()
        async let b: [Bookmark] = client.from(PoetUserTable.bookmarks)
            .select("id,target_type,target_id,note,created_at")
            .eq("owner_key", value: ownerKey).eq("app", value: app)
            .order("created_at", ascending: false).execute().value
        async let r: [ReadingState] = client.from(PoetUserTable.reading)
            .select("poem_id,progress,finished,last_read_at")
            .eq("owner_key", value: ownerKey).eq("app", value: app)
            .order("last_read_at", ascending: false).limit(PoetUserMerge.readingLimit).execute().value
        async let n: [PoetNote] = client.from(PoetUserTable.notes)
            .select("id,target_type,target_id,body,created_at,updated_at")
            .eq("owner_key", value: ownerKey).eq("app", value: app)
            .order("updated_at", ascending: false).execute().value
        let (bookmarks, reading, notes) = try await (b, r, n)
        return PoetRemoteRows(bookmarks: bookmarks, reading: reading, notes: notes)
    }

    public func deleteBookmark(ownerKey: String, app: String, targetType: String, targetId: UUID) async throws {
        try await clientProvider().from(PoetUserTable.bookmarks).delete()
            .eq("owner_key", value: ownerKey).eq("app", value: app)
            .eq("target_type", value: targetType).eq("target_id", value: targetId.uuidString.lowercased())
            .execute()
    }
}
