//  PoetUserData.swift — 收藏 / 阅读进度 / 笔记: 本地缓存 + 离线队列上行 + 换号拉取合并
//
//  与 PoetryHub 的数据隔离: 不复用 public.bookmarks, 用三张 poetkit_* 表 (migration 062),
//  以 `app` 列 (编成的 appSlug) 隔离同一账号在不同诗人应用里的数据。
//
//  上行: 本地每次改动先落缓存 (界面立即可见), 再 `ZXOutbox.enqueue(upsert)`。队列自己管断网、
//        退避、换号丢弃。没有账号时不排 (载荷里得有 owner_key), 有了账号后拉取合并会把本地独有的补推。
//  下行: 账号变了 (bootstrap 出匿名号、Apple 登录 / 手机号找回换到统一账号、退出后新匿名号) 就拉一次
//        该账号在本应用下的全部行, 按 `PoetUserMerge` 并进本地, 再把差异推回去。
//  换号: 前一个是匿名号 (或离线首启没有账号) 而换成了别人 → 那份本机数据并进新账号 (新账号优先), 再拉取合并。
//        两个真实账号之间切换 (前一个不是匿名号) 不并 —— 那是别人的数据。
//  owner_key 一律 'u:<uid>', 匿名用户也是 —— 见 `PoetUserRows`。

import Foundation
import Observation
import ZixiaoCore

@MainActor
@Observable
public final class PoetUserData {
    /// 当前账号在本应用下的本地数据。
    public private(set) var snapshot: PoetUserSnapshot = .empty
    /// 最近一次拉取失败的界面文案; 成功后清空。
    public private(set) var userDataError: String?
    /// 正在提交的收藏 (按钮据此禁用, 防连点)。
    public private(set) var savingBookmarks: Set<UUID> = []
    public private(set) var isPulling = false
    /// 当前账号 (小写 uuid); nil = 没有账号 (离线模式, 或退出后尚未重新匿名登录)。
    public private(set) var userId: String?

    public var bookmarks: [Bookmark] { snapshot.bookmarks }
    public var reading: [ReadingState] { snapshot.reading }
    public var notes: [PoetNote] { snapshot.notes }

    /// 隔离键 (编成的 appSlug)。
    public let app: String

    @ObservationIgnored private let outbox: ZXOutbox?
    @ObservationIgnored private let remote: any PoetUserDataRemote
    @ObservationIgnored private let cache: PoetUserDataCache
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var isAnonymous = false
    @ObservationIgnored private weak var auth: ZXAuth?
    @ObservationIgnored private var pullTask: Task<Void, Never>?
    @ObservationIgnored private var activePullID: UUID?

    public init(app: String, outbox: ZXOutbox?,
                remote: any PoetUserDataRemote = PostgrestPoetUserDataRemote(),
                cache: PoetUserDataCache = PoetUserDataCache(),
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.app = app
        self.outbox = outbox
        self.remote = remote
        self.cache = cache
        self.clock = clock
        self.snapshot = cache.load(app: app, owner: nil)
    }

    // MARK: - 跟着账号走

    /// 立即按当前状态对齐一次, 之后 `auth.state` 每变一次对齐一次。重复调用无副作用。
    public func attach(_ auth: ZXAuth) {
        guard self.auth !== auth else { return }
        self.auth = auth
        observeAuth()
    }

    private func observeAuth() {
        guard let auth else { return }
        let state = withObservationTracking {
            auth.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeAuth() }
        }
        userDidChange(state)
    }

    /// 账号状态变了。换了人就并入 (若该并)、换上新账号的缓存、拉一次。
    public func userDidChange(_ state: ZXAuthState) {
        let newId = state.userId
        let previous = userId
        guard newId != previous || state.isAnonymous != isAnonymous else { return }
        invalidatePull()
        if newId != previous {
            if let newId, previous == nil || isAnonymous {
                // 离线首启 / 退出后的空档 (previous == nil) 或匿名号 → 新账号: 本机数据跟过去。
                cache.adopt(app: app, from: previous, into: newId)
            }
            userId = newId
            snapshot = cache.load(app: app, owner: newId)
            userDataError = nil
        }
        isAnonymous = state.isAnonymous
        guard newId != nil else { return }
        pullTask = Task { [weak self] in await self?.pull() }
    }

    // MARK: - 拉取

    /// 拉当前账号的全部行并合并 (下拉刷新、「重新同步」按钮也走这里)。
    public func refresh() async {
        pullTask?.cancel()
        await pull()
    }

    private func pull() async {
        guard let uid = userId, !Task.isCancelled, savingBookmarks.isEmpty else { return }
        let requestID = UUID()
        activePullID = requestID
        isPulling = true
        defer {
            if activePullID == requestID {
                isPulling = false
                activePullID = nil
            }
        }
        do {
            let rows = try await remote.fetch(ownerKey: PoetUserRows.ownerKey(uid), app: app)
            // 拉取途中换了人: 结果属于上一位, 丢掉。
            guard userId == uid, activePullID == requestID, !Task.isCancelled else { return }
            // 合并前重读缓存: 拉取期间可能又读了一篇 / 收藏了一首。
            let local = cache.load(app: app, owner: uid)
            let result = PoetUserMerge.merge(local: local, remote: rows)
            cache.save(result.snapshot, app: app, owner: uid)
            snapshot = result.snapshot
            userDataError = nil
            await enqueue(result.writes(userId: uid, app: app))
        } catch {
            guard userId == uid, activePullID == requestID, !Task.isCancelled else { return }
            #if DEBUG
            print("PoetUserData.pull failed:", error)
            #endif
            userDataError = "收藏与阅读记录暂时无法同步，请稍后重试。"
        }
    }

    // MARK: - 收藏

    public func isBookmarked(_ poem: Poem) -> Bool {
        snapshot.bookmarks.contains { $0.targetType == "poem" && $0.targetId == poem.id }
    }

    /// 乐观更新; 失败回滚, 收藏不会悄悄消失。
    /// 加收藏只需排进离线队列 (断网也成功); 取消收藏要在线删 (队列没有删除), 失败抛错。
    public func toggleBookmark(_ poem: Poem) async throws {
        guard savingBookmarks.insert(poem.id).inserted else { return }
        // 收藏变更期间不要把变更之前抓到的云端快照合回来。
        invalidatePull()
        defer { savingBookmarks.remove(poem.id) }
        let owner = userId
        if let existing = snapshot.bookmarks.first(where: { $0.targetType == "poem" && $0.targetId == poem.id }) {
            update(owner) { $0.bookmarks.removeAll { $0.mergeKey == existing.mergeKey } }
            guard let uid = owner else { return }
            do {
                // 先把队列里可能还没送出的那条 upsert 送完, 否则删完它又被补传回来。
                if let outbox {
                    _ = await outbox.drain(force: true)
                    let write = PoetUserRows.bookmark(existing, userId: uid, app: app)
                    let pending = await outbox.pending()
                    guard !pending.contains(where: {
                        $0.idempotencyKey == write.idempotencyKey &&
                        $0.payload["owner_key"] == write.payload["owner_key"]
                    }) else { throw BookmarkUpdateError.pendingUpload }
                }
                guard userId == uid else { throw CancellationError() }
                try await remote.deleteBookmark(ownerKey: PoetUserRows.ownerKey(uid), app: app,
                                                targetType: existing.targetType, targetId: existing.targetId)
                update(uid) { $0.remoteBookmarkKeys.remove(existing.mergeKey) }
            } catch {
                update(uid) { snap in
                    if !snap.bookmarks.contains(where: { $0.mergeKey == existing.mergeKey }) {
                        snap.bookmarks = PoetUserMerge.sortedBookmarks(snap.bookmarks + [existing])
                    }
                }
                throw error
            }
        } else {
            let bookmark = Bookmark(targetType: "poem", targetId: poem.id,
                                    createdAt: PoetTimestamp.string(clock()))
            update(owner) { $0.bookmarks.insert(bookmark, at: 0) }
            guard let uid = owner, let outbox else { return }
            do {
                try await PoetUserRows.bookmark(bookmark, userId: uid, app: app).enqueue(into: outbox)
            } catch {
                update(uid) { $0.bookmarks.removeAll { $0.mergeKey == bookmark.mergeKey } }
                throw error
            }
        }
    }

    // MARK: - 阅读

    /// 读过就记一笔。一首诗一屏读完, 所以直接记完成 —— 不做假的滚动百分比。
    public func markRead(_ poem: Poem) async {
        let entry = ReadingState(poemId: poem.id, progress: 1, finished: true,
                                 lastReadAt: PoetTimestamp.string(clock()))
        let owner = userId
        update(owner) { $0.reading = PoetUserMerge.normalizedReading($0.reading + [entry]) }
        guard let uid = owner else { return }
        await enqueue([PoetUserRows.reading(entry, userId: uid, app: app)])
    }

    // MARK: - 笔记

    /// 写 (或改) 一条笔记。`id` 传已有笔记的 id 即为修改。
    @discardableResult
    public func saveNote(id: UUID? = nil, targetType: String, targetId: UUID, body: String) async throws -> PoetNote {
        let now = PoetTimestamp.string(clock())
        let created = id.flatMap { id in snapshot.notes.first { $0.id == id }?.createdAt } ?? now
        let note = PoetNote(id: id ?? UUID(), targetType: targetType, targetId: targetId, body: body,
                            createdAt: created, updatedAt: now)
        let owner = userId
        update(owner) { snap in
            snap.notes.removeAll { $0.id == note.id }
            snap.notes.insert(note, at: 0)
        }
        if let uid = owner, let outbox {
            try await PoetUserRows.note(note, userId: uid, app: app).enqueue(into: outbox)
        }
        return note
    }

    // MARK: - 注销

    /// 删号之后: 清掉该账号在本应用下的本地数据 (阅读偏好等设备设置不动)。
    public func clearLocal(for userId: String?) {
        cache.remove(app: app, owner: userId)
        if self.userId == userId {
            invalidatePull()
            snapshot = .empty
        }
    }

    // MARK: - 内部

    private func invalidatePull() {
        pullTask?.cancel()
        activePullID = nil
        isPulling = false
    }

    /// 改某个账号的缓存; 若它仍是当前账号, 同步到界面。
    private func update(_ owner: String?, _ change: (inout PoetUserSnapshot) -> Void) {
        var snap = cache.load(app: app, owner: owner)
        change(&snap)
        cache.save(snap, app: app, owner: owner)
        if owner == userId { snapshot = cache.load(app: app, owner: owner) }
    }

    private func enqueue(_ writes: [PoetOutboxWrite]) async {
        guard let outbox, !writes.isEmpty else { return }
        for write in writes {
            // 写盘失败只影响这一条的补传; 本地缓存已经有了, 下次拉取合并会再推。
            try? await write.enqueue(into: outbox)
        }
    }
}

private enum BookmarkUpdateError: Error {
    case pendingUpload
}
