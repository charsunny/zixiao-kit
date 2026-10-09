import Foundation
import Observation

/// UI-neutral orchestration for a real product store. Switching accounts invalidates every in-flight apply.
@MainActor @Observable
public final class ZXCloudLibraryDriver {
    public private(set) var status = "尚未同步"
    public private(set) var syncing = false
    public private(set) var conflicts: [ZXCloudLibraryConflict] = []
    public private(set) var owner: String?
    @ObservationIgnored public let client: ZXCloudLibraryClient
    @ObservationIgnored private let scope: String
    @ObservationIgnored private var snapshot: (() async throws -> [ZXCloudLibraryDraft])?
    @ObservationIgnored private var apply: (([ZXCloudLibraryDraft]) async throws -> Void)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var rerun = false

    public init(client: ZXCloudLibraryClient, scope: String) { self.client = client; self.scope = scope }
    public func configure(owner: String?, snapshot: @escaping () async throws -> [ZXCloudLibraryDraft],
                          apply: @escaping ([ZXCloudLibraryDraft]) async throws -> Void) {
        generation += 1
        self.owner = owner?.lowercased(); self.snapshot = snapshot; self.apply = apply
        conflicts = []; status = owner == nil ? "登录后可同步；本机资料由你确认后导入。" : "等待同步"
    }
    public func synchronize() async {
        guard owner != nil else { return }
        if syncing { rerun = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            rerun = false
            let current = generation
            guard let owner, let snapshot, let apply else { return }
            do {
                guard try await client.currentOwner().lowercased() == owner else { throw ZXCloudLibraryError.accountChanged }
                let before = try await snapshot().sorted { $0.key < $1.key }
                guard generation == current else { continue }
                try await client.reconcile(snapshot: before, scope: scope, expectedOwner: owner)
                status = "正在同步…"
                try await client.synchronize(expectedOwner: owner)
                guard generation == current else { continue }
                // Reconcile edits made while HTTP was in flight before applying remote state.
                let latest = try await snapshot().sorted { $0.key < $1.key }
                if latest != before { try await client.reconcile(snapshot: latest, scope: scope, expectedOwner: owner); rerun = true }
                let records = try await client.currentDrafts(expectedOwner: owner)
                guard generation == current else { continue }
                try await apply(records)
                guard generation == current else { continue }
                let applied = try await snapshot()
                try await client.applied(snapshot: applied, scope: scope, expectedOwner: owner)
                conflicts = try await client.conflicts()
                let count = try await client.pendingCount()
                status = !conflicts.isEmpty ? "有 \(conflicts.count) 项冲突，请选择保留的版本。" : count > 0 ? "\(count) 项待上传" : "书房已同步"
            } catch {
                guard generation == current else { continue }
                status = error.localizedDescription
                rerun = false
            }
        } while rerun
    }
    public func resolve(_ conflict: ZXCloudLibraryConflict, keepLocal: Bool) async {
        guard !syncing, let owner, let apply, let snapshot else { return }
        let current = generation
        syncing = true
        defer { syncing = false }
        do {
            guard try await client.currentOwner().lowercased() == owner else { throw ZXCloudLibraryError.accountChanged }
            try await client.resolveConflict(id: conflict.id, keepLocal: keepLocal, expectedOwner: owner)
            let resolved = try await client.currentDrafts(expectedOwner: owner)
            guard generation == current else { return }
            // Apply the chosen server value before capturing another snapshot, or the stale store requeues it.
            try await apply(resolved)
            guard generation == current else { return }
            let projected = try await snapshot()
            try await client.applied(snapshot: projected, scope: scope, expectedOwner: owner)
            syncing = false
            await synchronize()
        } catch { if generation == current { status = error.localizedDescription } }
    }
}
