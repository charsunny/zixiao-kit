//  PoetUserMerge.swift — 拉回来的云端行与本地缓存的合并, 纯函数
//
//  规则 (沿玄览 Sync/SyncMerge.swift 的路数, 按三张表的实际列收窄):
//  - 阅读进度: 按 poem_id, `last_read_at` 新者胜 (相同时本地胜: 刚读的那一下不该被拉取覆盖);
//    最多留 50 条。
//  - 笔记: 按 id, `updated_at` 新者胜 (相同时本地胜)。
//  - 收藏: 表上没有 updated_at 也没有墓碑, 是一个集合。云端有的都留 (行内容以云端为准);
//    本地独有的看基准 (`remoteBookmarkKeys`, 上次拉到的云端集合): 在基准里 = 别处删掉了, 丢;
//    不在基准里 = 本机新加还没传, 留并回推。
//  - 回推: 本地独有的、或本地比云端新的那几行 (阅读 / 笔记 / 收藏)。
//  - 换号并入 (`adopt`): 匿名号 (或离线首启) 的本机数据并进新账号, 新账号优先 ——
//    阅读 / 笔记仍按时间戳, 收藏取并集; 新账号的基准不动, 并进来的收藏因此会被回推。

import Foundation

public struct PoetUserMergeResult: Sendable, Hashable {
    public var snapshot: PoetUserSnapshot
    public var bookmarkPushes: [Bookmark]
    public var readingPushes: [ReadingState]
    public var notePushes: [PoetNote]

    public var hasPushes: Bool { !(bookmarkPushes.isEmpty && readingPushes.isEmpty && notePushes.isEmpty) }

    /// 全部回推, 已做成离线队列载荷。
    public func writes(userId: String, app: String) -> [PoetOutboxWrite] {
        bookmarkPushes.map { PoetUserRows.bookmark($0, userId: userId, app: app) }
            + readingPushes.map { PoetUserRows.reading($0, userId: userId, app: app) }
            + notePushes.map { PoetUserRows.note($0, userId: userId, app: app) }
    }
}

public enum PoetUserMerge {
    /// 阅读记录的上限: 书房只展示最近 50 篇。
    public static let readingLimit = 50

    public static func merge(local: PoetUserSnapshot, remote: PoetRemoteRows) -> PoetUserMergeResult {
        let r = reading(local: local.reading, remote: remote.reading)
        let n = notes(local: local.notes, remote: remote.notes)
        let b = bookmarks(local: local.bookmarks, remote: remote.bookmarks, base: local.remoteBookmarkKeys)
        let snapshot = PoetUserSnapshot(bookmarks: b.merged, reading: r.merged, notes: n.merged,
                                        remoteBookmarkKeys: Set(remote.bookmarks.map(\.mergeKey)))
        return PoetUserMergeResult(snapshot: snapshot, bookmarkPushes: b.pushes,
                                   readingPushes: r.pushes, notePushes: n.pushes)
    }

    // MARK: 阅读

    public static func reading(local: [ReadingState], remote: [ReadingState])
    -> (merged: [ReadingState], pushes: [ReadingState]) {
        // 云端在前、本地在后: 时间相同时第二遍的本地胜。
        let merged = normalizedReading(remote + local)
        let remoteByPoem = Dictionary(remote.map { ($0.poemId, $0) }, uniquingKeysWith: newerReading)
        let kept = Set(merged.map(\.poemId))
        let pushes = normalizedReading(local).filter { mine in
            guard kept.contains(mine.poemId) else { return false }
            guard let theirs = remoteByPoem[mine.poemId] else { return true }
            return PoetTimestamp.date(mine.lastReadAt) > PoetTimestamp.date(theirs.lastReadAt)
        }
        return (merged, pushes)
    }

    /// 每篇只留最新的一条, 按时间倒序, 截到上限。相同时间时后出现的胜。
    public static func normalizedReading(_ records: [ReadingState]) -> [ReadingState] {
        var newest: [UUID: ReadingState] = [:]
        for record in records {
            if let existing = newest[record.poemId],
               PoetTimestamp.date(record.lastReadAt) < PoetTimestamp.date(existing.lastReadAt) { continue }
            newest[record.poemId] = record
        }
        return Array(newest.values.sorted {
            let lhs = PoetTimestamp.date($0.lastReadAt), rhs = PoetTimestamp.date($1.lastReadAt)
            return lhs == rhs ? $0.poemId.uuidString < $1.poemId.uuidString : lhs > rhs
        }.prefix(readingLimit))
    }

    private static func newerReading(_ a: ReadingState, _ b: ReadingState) -> ReadingState {
        PoetTimestamp.date(a.lastReadAt) >= PoetTimestamp.date(b.lastReadAt) ? a : b
    }

    // MARK: 笔记

    public static func notes(local: [PoetNote], remote: [PoetNote])
    -> (merged: [PoetNote], pushes: [PoetNote]) {
        var byId = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: newerNote)
        var pushes: [PoetNote] = []
        for mine in local {
            if let theirs = byId[mine.id] {
                guard PoetTimestamp.date(mine.updatedAt) >= PoetTimestamp.date(theirs.updatedAt) else { continue }
                if mine != theirs { pushes.append(mine) }
                byId[mine.id] = mine
            } else {
                byId[mine.id] = mine
                pushes.append(mine)
            }
        }
        let merged = byId.values.sorted {
            let lhs = PoetTimestamp.date($0.updatedAt ?? $0.createdAt)
            let rhs = PoetTimestamp.date($1.updatedAt ?? $1.createdAt)
            return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs > rhs
        }
        return (merged, pushes)
    }

    private static func newerNote(_ a: PoetNote, _ b: PoetNote) -> PoetNote {
        PoetTimestamp.date(a.updatedAt) >= PoetTimestamp.date(b.updatedAt) ? a : b
    }

    // MARK: 收藏

    public static func bookmarks(local: [Bookmark], remote: [Bookmark], base: Set<String>)
    -> (merged: [Bookmark], pushes: [Bookmark]) {
        var seen = Set<String>()
        var merged: [Bookmark] = []
        for row in remote where seen.insert(row.mergeKey).inserted { merged.append(row) }
        var pushes: [Bookmark] = []
        for mine in local where !seen.contains(mine.mergeKey) {
            seen.insert(mine.mergeKey)
            if base.contains(mine.mergeKey) { continue }   // 云端曾有、现在没了: 别处删的
            merged.append(mine)
            pushes.append(mine)
        }
        return (sortedBookmarks(merged), pushes)
    }

    /// 新收藏在前。没有时间的 (旧行) 排最后。
    static func sortedBookmarks(_ list: [Bookmark]) -> [Bookmark] {
        list.enumerated().sorted { a, b in
            let lhs = PoetTimestamp.date(a.element.createdAt), rhs = PoetTimestamp.date(b.element.createdAt)
            return lhs == rhs ? a.offset < b.offset : lhs > rhs
        }.map(\.element)
    }

    // MARK: 换号并入

    /// 把 `source` (被放弃的匿名号 / 离线首启的本机数据) 并进 `target` (新账号)。
    public static func adopt(_ source: PoetUserSnapshot, into target: PoetUserSnapshot) -> PoetUserSnapshot {
        var result = target
        result.reading = normalizedReading(source.reading + target.reading)
        result.notes = notes(local: source.notes, remote: target.notes).merged
        var keys = Set(target.bookmarks.map(\.mergeKey))
        var bookmarks = target.bookmarks
        for b in source.bookmarks where keys.insert(b.mergeKey).inserted { bookmarks.append(b) }
        result.bookmarks = sortedBookmarks(bookmarks)
        return result
    }
}
