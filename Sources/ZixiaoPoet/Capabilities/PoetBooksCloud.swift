import SwiftUI
import ZixiaoCore
import ZixiaoLibrary
import ZixiaoPoetCore

/// A composition and an account have their own reading store. The pre-sync file remains an import source.
@MainActor final class PoetBooksCloud {
    private static var instances: [String: PoetBooksCloud] = [:]
    static func instance(_ ctx: CompositionContext) -> PoetBooksCloud {
        let owner = ctx.isSignedIn ? ctx.auth.userId?.lowercased() : nil
        let key = ctx.composition.app.appSlug + ":" + (owner ?? "guest")
        if let existing = instances[key] { return existing }
        let result = PoetBooksCloud(ctx, owner: owner); instances[key] = result; return result
    }
    let store: ReadingStateStore
    let driver: ZXCloudLibraryDriver
    let library: PoetLibrary?
    let source: String
    private let owner: String?

    private init(_ ctx: CompositionContext, owner: String?) {
        self.owner = owner; library = ctx.composition.library
        source = "zhi:" + ctx.composition.app.appSlug
        if let owner {
            let root = BookStore.defaultRootDirectory.appendingPathComponent("account-reading", isDirectory: true)
            store = ReadingStateStore(fileURL: root.appendingPathComponent(ZXCloudLibraryScope.suffix(owner + source) + ".json"))
        } else { store = ReadingStateStore() }
        driver = ZXCloudLibraryDriver(client: ZXCloudLibraryClient(baseURL: URL(string: "https://www.weshici.com")!, app: "zhi",
            sessionProvider: { try await ZXCloudLibraryScope.session() }), scope: source + ".classic-reading")
        driver.configure(owner: owner, snapshot: { [weak self] in try await self?.snapshot() ?? [] }, apply: { [weak self] records in
            guard let self else { return }
            var state = await self.store.load()
            for item in records where item.contentRef.source == self.source && item.contentRef.kind == "book" {
                if item.kind == "reading" {
                    if item.deletedAt != nil { state.progress[item.contentRef.id] = nil }
                    else if let progress = try? ZXCloudLibraryJSON.decode(BookProgress.self, from: .object(item.payload)) {
                        state.progress[progress.bookId] = progress
                    }
                } else if item.kind == "note", let id = item.payload["id"]?.cloudString {
                    state.excerpts.removeAll { $0.id == id }
                    if item.deletedAt == nil, let excerpt = try? ZXCloudLibraryJSON.decode(Excerpt.self, from: .object(item.payload)) { state.excerpts.append(excerpt) }
                }
            }
            state.currentBookId = state.progress.values.max(by: { $0.updatedAt < $1.updatedAt })?.bookId
            _ = try await self.store.save(state)
        })
    }
    func snapshot() async throws -> [ZXCloudLibraryDraft] {
        let state = await store.load()
        let titles = Dictionary((library?.books ?? []).map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        var result = try state.progress.values.map { progress -> ZXCloudLibraryDraft in
            guard case .object(var payload) = try ZXCloudLibraryJSON.encode(progress) else { throw ZXCloudLibraryError.invalidResponse }
            payload["title"] = .string(titles[progress.bookId] ?? progress.bookId)
            return .init(key: "reading:\(source):book:\(progress.bookId)", kind: "reading",
                contentRef: .init(source: source, kind: "book", id: progress.bookId,
                    anchor: .string(progress.chapterId + ":" + (progress.passageId ?? ""))), payload: payload,
                updatedAt: ZXCloudLibraryJSON.timestamp(progress.updatedAt))
        }
        result += try state.excerpts.map { excerpt in
            guard case .object(let payload) = try ZXCloudLibraryJSON.encode(excerpt) else { throw ZXCloudLibraryError.invalidResponse }
            return .init(key: "note:\(excerpt.id.lowercased())", kind: "note", contentRef: .init(source: source, kind: "book", id: excerpt.bookId,
                anchor: .string(excerpt.chapterId + ":" + excerpt.passageId)), payload: payload, updatedAt: ZXCloudLibraryJSON.timestamp(excerpt.createdAt))
        }
        return result
    }
    struct ImportPreview: Identifiable {
        let id: String
        let title: String
        let chapter: String?
        let excerptCount: Int
    }
    func legacy() async -> [ImportPreview] {
        let state = await ReadingStateStore().load()
        return (library?.books ?? []).compactMap { book in
            let count = state.excerpts.filter { $0.bookId == book.id }.count
            guard state.progress[book.id] != nil || count > 0 else { return nil }
            return ImportPreview(id: book.id, title: book.title, chapter: state.progress[book.id]?.chapterId, excerptCount: count)
        }
    }
    func importLegacy() async throws {
        guard owner != nil else { throw ZXCloudLibraryError.signedOut }
        let old = await ReadingStateStore().load()
        let ids = Set((library?.books ?? []).map(\.id))
        var current = await store.load()
        for progress in old.progress.values where ids.contains(progress.bookId) {
            if current.progress[progress.bookId].map({ $0.updatedAt < progress.updatedAt }) ?? true { current.progress[progress.bookId] = progress }
        }
        for note in old.excerpts where ids.contains(note.bookId) && !current.excerpts.contains(where: { $0.id == note.id }) { current.excerpts.append(note) }
        _ = try await store.save(current)
        await driver.synchronize()
    }
}

struct PoetBooksCloudScreen: View {
    let ctx: CompositionContext
    @State private var preview: [PoetBooksCloud.ImportPreview] = []
    @State private var showingPreview = false
    @State private var error: String?
    private var cloud: PoetBooksCloud { .instance(ctx) }
    var body: some View {
        Form {
            Section {
                Text(cloud.driver.status)
                if let error { Text(error).foregroundStyle(.red) }
                Button("同步书房") { Task { await cloud.driver.synchronize() } }.disabled(!ctx.isSignedIn || cloud.driver.syncing)
                Button("导入本机资料") { Task { preview = await cloud.legacy(); showingPreview = true } }.disabled(!ctx.isSignedIn)
            } footer: { Text("经典阅读进度与摘抄按账号、诗人分别同步。原本保存在设备上的资料会先显示预览，取消不会上传或删除原文件。作品收藏与笔记继续使用原来的同步。") }
            ForEach(cloud.driver.conflicts) { conflict in
                Section(conflict.local.draft.title) {
                    Button("保留本机版本") { Task { await cloud.driver.resolve(conflict, keepLocal: true) } }
                    Button("使用云端版本") { Task { await cloud.driver.resolve(conflict, keepLocal: false) } }
                }
            }
        }.navigationTitle("同步书房").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPreview) {
            NavigationStack {
                List(preview) { item in
                    VStack(alignment: .leading) {
                        Text(item.title)
                        if let chapter = item.chapter { Text(chapter).font(.caption).foregroundStyle(.secondary) }
                        if item.excerptCount > 0 { Text("\(item.excerptCount) 条摘抄").font(.caption).foregroundStyle(.secondary) }
                    }
                }.navigationTitle("导入预览")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showingPreview = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("导入 \(preview.count) 本") {
                        showingPreview = false
                        Task { do { try await cloud.importLegacy() } catch { self.error = error.localizedDescription } }
                    }.disabled(preview.isEmpty) }
                }
            }
        }
    }
}
