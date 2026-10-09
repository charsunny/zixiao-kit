import Foundation

// 阅读状态: 读到哪、读完了哪些章、摘抄本。
//
// 为什么用 JSON 文件而不是 SwiftData:
// 1. 数据量极小 (几本书的进度 + 几百条摘抄, 通常 < 100 KB), 整份读写比建模型容器还便宜;
// 2. 内核是被多个 App 依赖的 Swift Package, SwiftData 的 ModelContainer 应由 App 持有并决定 schema 迁移,
//    放在包里会让每个 App 都被迫接受同一个容器与迁移节奏;
// 3. `@Model` 类是引用类型且不是 Sendable, 与本包「public API 全部 Sendable + StrictConcurrency」冲突;
// 4. 将来要与 Supabase 同步, 云端存的也是 JSON; 值类型 + Codable 让本地与云端同形, 合并逻辑可以纯函数测试;
// 5. 与 Flutter 版 `LocalUserStateStore` 的字段一一对应, 迁移老用户数据时直接映射。
// 代价是没有查询能力 —— 摘抄本按时间倒序展示, 不需要。

/// 一本书的进度。
public struct BookProgress: Codable, Sendable, Hashable {
    public var bookId: String
    public var chapterId: String
    /// 翻到的那页的第一段; 横排时是视口里第一段。
    public var passageId: String?
    public var finishedChapters: Set<String>
    public var updatedAt: Date

    public init(bookId: String, chapterId: String, passageId: String? = nil,
                finishedChapters: Set<String> = [], updatedAt: Date = Date()) {
        self.bookId = bookId
        self.chapterId = chapterId
        self.passageId = passageId
        self.finishedChapters = finishedChapters
        self.updatedAt = updatedAt
    }
}

/// 一条摘抄: 从哪本书哪一段抄的, 抄的原文。
/// 冗余存书名与章名, 是为了摘抄本不用把整本书读进来就能列出来 (书还可能被删了)。
public struct Excerpt: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var bookId: String
    public var bookTitle: String
    public var chapterId: String
    public var chapterTitle: String
    public var passageId: String
    public var text: String
    /// 眉批 (入口以后做)。
    public var note: String?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, bookId: String, bookTitle: String = "", chapterId: String,
                chapterTitle: String = "", passageId: String, text: String, note: String? = nil,
                createdAt: Date = Date()) {
        self.id = id; self.bookId = bookId; self.bookTitle = bookTitle; self.chapterId = chapterId
        self.chapterTitle = chapterTitle; self.passageId = passageId; self.text = text; self.note = note
        self.createdAt = createdAt
    }

    /// 从阅读器长按的那一段生成。
    public init(book: Book, chapter: Chapter, passage: Passage, createdAt: Date = Date()) {
        self.init(bookId: book.id, bookTitle: book.title, chapterId: chapter.id, chapterTitle: chapter.title,
                  passageId: passage.id, text: passage.text, createdAt: createdAt)
    }
}

/// 全部阅读状态, 纯值类型: 所有变更都是 mutating 函数, 与持久化分开, 方便测试与将来做同步合并。
public struct ReadingState: Codable, Sendable, Hashable {
    /// 文件格式版本, 将来改结构时据此迁移。
    public var schema: Int
    /// 最近在读的那本 (书架「在读」卡)。
    public var currentBookId: String?
    public var progress: [String: BookProgress]
    /// 新的在前。
    public var excerpts: [Excerpt]

    public init(schema: Int = 1, currentBookId: String? = nil, progress: [String: BookProgress] = [:],
                excerpts: [Excerpt] = []) {
        self.schema = schema
        self.currentBookId = currentBookId
        self.progress = progress
        self.excerpts = excerpts
    }

    public static let empty = ReadingState()

    /// 当前在读的位置 (书 / 章 / 段)。
    public var current: BookProgress? { currentBookId.flatMap { progress[$0] } }

    public func progress(for bookId: String) -> BookProgress? { progress[bookId] }

    public func isFinished(bookId: String, chapterId: String) -> Bool {
        progress[bookId]?.finishedChapters.contains(chapterId) ?? false
    }

    /// 翻到某页 / 滚到某段: 记章与段, 并把这本记成「在读」。
    public mutating func move(bookId: String, chapterId: String, passageId: String?, at date: Date = Date()) {
        var p = progress[bookId] ?? BookProgress(bookId: bookId, chapterId: chapterId, updatedAt: date)
        p.chapterId = chapterId
        p.passageId = passageId
        p.updatedAt = date
        progress[bookId] = p
        currentBookId = bookId
    }

    /// 读完一章。返回这本书是否因此全部读完 (`totalChapters` 给出时), App 据此盖印。
    @discardableResult
    public mutating func finish(bookId: String, chapterId: String, totalChapters: Int? = nil,
                                at date: Date = Date()) -> Bool {
        var p = progress[bookId] ?? BookProgress(bookId: bookId, chapterId: chapterId, updatedAt: date)
        let wasComplete = totalChapters.map { p.finishedChapters.count >= $0 } ?? false
        p.finishedChapters.insert(chapterId)
        p.updatedAt = date
        progress[bookId] = p
        guard let totalChapters else { return false }
        return !wasComplete && p.finishedChapters.count >= totalChapters
    }

    public func hasExcerpt(bookId: String, passageId: String) -> Bool {
        excerpts.contains { $0.bookId == bookId && $0.passageId == passageId }
    }

    /// 同一段只抄一次; 已有返回 false。
    @discardableResult
    public mutating func addExcerpt(_ excerpt: Excerpt) -> Bool {
        guard !hasExcerpt(bookId: excerpt.bookId, passageId: excerpt.passageId) else { return false }
        excerpts.insert(excerpt, at: 0)
        return true
    }

    public mutating func removeExcerpt(id: String) {
        excerpts.removeAll { $0.id == id }
    }
}

/// 同步留口子: 本 sprint 不实现 (账号在 Sprint 2)。
///
/// 预期语义: `pull` 取云端快照, App 用 `ReadingState` 的合并规则 (进度按 `updatedAt` 取新、
/// 已读章节取并集、摘抄按 id 取并集) 合并后 `push`。放成 protocol 是为了内核不依赖 Supabase。
public protocol ReadingStateSyncing: Sendable {
    func pull() async throws -> ReadingState?
    func push(_ state: ReadingState) async throws
}

/// 把 `ReadingState` 存成一个 JSON 文件 (默认 `Application Support/ZixiaoLibrary/reading-state.json`)。
///
/// actor 串行化读改写, 避免两次快速翻页的写盘互相覆盖; 写盘用 `.atomic`, 崩溃不会留下半截文件。
public actor ReadingStateStore {
    public nonisolated let fileURL: URL
    private var cached: ReadingState?

    // 同步 (`ReadingStateSyncing`) 不挂在这里: 合并时机 (启动 / 登录 / 前后台切换) 是 App 的事,
    // 内核只保证本地读写正确。
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? BookStore.defaultRootDirectory.appendingPathComponent("reading-state.json")
    }

    /// 读当前状态。文件不存在是空状态; 文件损坏也回空状态, 但先把坏文件挪到 `.corrupt` 留证,
    /// 免得下一次保存把它覆盖掉、连人工抢救的机会都没有。
    public func load() -> ReadingState {
        if let cached { return cached }
        let state: ReadingState
        if let data = try? Data(contentsOf: fileURL) {
            if let decoded = try? Self.decoder.decode(ReadingState.self, from: data) {
                state = decoded
            } else {
                let backup = fileURL.appendingPathExtension("corrupt")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.moveItem(at: fileURL, to: backup)
                state = .empty
            }
        } else {
            state = .empty
        }
        cached = state
        return state
    }

    /// 改一次并落盘, 返回改后的状态。闭包的返回值一并带回 (如 `addExcerpt` 的是否新增)。
    @discardableResult
    public func update<T: Sendable>(_ change: @Sendable (inout ReadingState) -> T) throws -> (ReadingState, T) {
        var state = load()
        let result = change(&state)
        return (try save(state), result)
    }

    /// 落盘并返回「从盘上读回来会得到的」那份状态: 日期按毫秒存, 内存里若留着微秒,
    /// 重启前后同一份状态会不相等, 同步时按 `updatedAt` 比新旧就会误判。
    @discardableResult
    public func save(_ state: ReadingState) throws -> ReadingState {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
        let stored = try Self.decoder.decode(ReadingState.self, from: data)
        cached = stored
        return stored
    }

    // 便捷方法: 阅读器回调里最常用的三件事。

    public func move(bookId: String, chapterId: String, passageId: String?) throws {
        try update { $0.move(bookId: bookId, chapterId: chapterId, passageId: passageId) }
    }

    @discardableResult
    public func finish(bookId: String, chapterId: String, totalChapters: Int? = nil) throws -> Bool {
        try update { $0.finish(bookId: bookId, chapterId: chapterId, totalChapters: totalChapters) }.1
    }

    @discardableResult
    public func addExcerpt(_ excerpt: Excerpt) throws -> Bool {
        try update { $0.addExcerpt(excerpt) }.1
    }

    public func removeExcerpt(id: String) throws {
        try update { $0.removeExcerpt(id: id) }
    }

    // 日期用带毫秒的 ISO 8601: 人读得懂, 与 Flutter 版 `toIso8601String()` 和 Supabase 的 timestamptz 同形。
    // 读时也接受不带小数秒的写法 (老数据 / 手工编辑)。
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainDateStyle = Date.ISO8601FormatStyle()

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.formatted(dateStyle))
        }
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let string = try c.decode(String.self)
            if let date = try? dateStyle.parse(string) { return date }
            if let date = try? plainDateStyle.parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "不是 ISO 8601 日期: \(string)")
        }
        return d
    }
}
