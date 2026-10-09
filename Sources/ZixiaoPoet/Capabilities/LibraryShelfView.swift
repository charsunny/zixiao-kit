import ZixiaoPoetCore
//  LibraryShelfView.swift — 书房的云端书架
//
//  编成的可选 `library` 块给出一组书 (id / 地址 / sha256 / 分组); 这里按分组一行一行摆上书架,
//  点进去是书目页 (元数据 + 下载 / 阅读), 下载走 ZixiaoLibrary 的 `BookStore` (sha256 校验、原子落盘),
//  读用 `ClassicReaderView`, 阅读位置经 `ReadingStateStore` 只存本机。
//  内核不认识任何一本书、一家来源: 书名、分组、分区标题全来自编成。

import SwiftUI
import ZixiaoDesign
import ZixiaoLibrary
import ZixiaoCore

// MARK: - 模型

/// 书架的状态: 哪些书已在本机、哪些在下载 / 下载失败, 以及阅读位置的落盘。
@MainActor @Observable
final class PoetShelfModel {
    enum Phase: Equatable {
        /// 正在下载; `nil` 为进度未知。
        case downloading(Double?)
        case failed(String)
    }

    private(set) var phases: [String: Phase] = [:]
    /// 已落盘 (本机可读) 的书 id。
    private(set) var offline: Set<String> = []

    @ObservationIgnored let store: BookStore
    @ObservationIgnored let readingStore: ReadingStateStore
    @ObservationIgnored var onReadingChange: (() -> Void)?
    @ObservationIgnored private let center: PoetDownloadProgress
    @ObservationIgnored private var pendingLocation: ReaderLocation?
    @ObservationIgnored private var flushTask: Task<Void, Never>?

    init(store: BookStore? = nil, readingStore: ReadingStateStore = ReadingStateStore(),
         center: PoetDownloadProgress = PoetDownloadProgress()) {
        self.center = center
        // 没有随包书, 也没有云端总目录: 书目由编成给, 每本带自己的地址与校验值。
        self.store = store ?? BookStore(bundled: nil, remoteCatalogURL: nil,
                                        fetcher: PoetBookFetcher(progress: center))
        self.readingStore = readingStore
    }

    func refreshOffline() async {
        offline = Set(await store.downloadedBookIds())
    }

    func phase(_ id: String) -> Phase? { phases[id] }

    /// 取一本书: 本机有 (版本不低于编成给的) 就直接读, 否则下载并校验。失败返回 nil, 原因留在 `phases`。
    func book(for entry: PoetLibrary.Entry) async -> ZixiaoLibrary.Book? {
        if case .downloading = phases[entry.id] { return nil }
        if let local = await store.downloadedVersion(id: entry.id), local >= entry.version,
           let book = try? await store.book(id: entry.id) {
            offline.insert(entry.id)
            return book
        }
        guard let url = entry.downloadURL else {
            phases[entry.id] = .failed(Self.message(for: BookStoreError.noDownloadURL(id: entry.id)))
            return nil
        }
        phases[entry.id] = .downloading(0)
        let token = center.observe(url) { [weak self] fraction in
            Task { @MainActor in self?.setProgress(fraction, for: entry.id) }
        }
        defer { center.remove(token) }
        do {
            let book = try await store.download(from: url, id: entry.id, version: entry.version,
                                                expectedHash: entry.hash)
            phases[entry.id] = nil
            offline.insert(entry.id)
            return book
        } catch {
            phases[entry.id] = .failed(Self.message(for: error))
            return nil
        }
    }

    private func setProgress(_ fraction: Double?, for id: String) {
        guard case .downloading = phases[id] else { return }
        phases[id] = .downloading(fraction)
    }

    func clearFailure(_ id: String) {
        if case .failed = phases[id] { phases[id] = nil }
    }

    // MARK: 阅读位置 (只存本机)

    func progress(for id: String) async -> BookProgress? {
        await readingStore.load().progress(for: id)
    }

    /// 翻页再快也只 500 ms 写一次盘; 离开阅读页时 `flush`。
    func record(_ location: ReaderLocation) {
        pendingLocation = location
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            await self?.flush()
        }
    }

    func flush() async {
        flushTask?.cancel()
        flushTask = nil
        guard let location = pendingLocation else { return }
        pendingLocation = nil
        try? await readingStore.move(bookId: location.bookId, chapterId: location.chapterId,
                                     passageId: location.passageId)
        onReadingChange?()
    }

    func finish(chapterId: String, in book: ZixiaoLibrary.Book) {
        let total = book.chapters.count
        Task { [readingStore] in
            _ = try? await readingStore.finish(bookId: book.id, chapterId: chapterId, totalChapters: total)
            self.onReadingChange?()
        }
    }

    /// 给人看的失败原因: 校验不过与网络不通要分开说, 前者重试通常无济于事之外还要让人知道不是自己的网络问题。
    static func message(for error: Error) -> String {
        switch error {
        case BookStoreError.hashMismatch, BookStoreError.idMismatch, BookStoreError.missingHash:
            return "文件校验未通过，请稍后重试。"
        case BookStoreError.noDownloadURL, BookStoreError.notInCatalog:
            return "这本书暂不可下载。"
        case BookStoreError.http:
            return "书库暂时连不上，请稍后重试。"
        case is URLError:
            return "网络不可用，请检查网络后重试。"
        default:
            return "没能取到这本书，请稍后重试。"
        }
    }
}

// MARK: - 下载进度

/// 按 URL 分发下载进度。`BookStore` 的 `BookFetching` 只回整块字节; 进度在 fetcher 的字节循环里产生,
/// 经这里转给正在等那本书的模型。用锁而不是 actor: 回报发生在 URLSession 的字节循环里, 不该每块都跨一次 actor。
final class PoetDownloadProgress: @unchecked Sendable {
    typealias Handler = @Sendable (Double?) -> Void

    struct Token: Hashable, Sendable {
        fileprivate let url: URL
        fileprivate let id: UUID
    }

    private let lock = NSLock()
    private var handlers: [URL: [UUID: Handler]] = [:]

    init() {}

    func observe(_ url: URL, handler: @escaping Handler) -> Token {
        let token = Token(url: url, id: UUID())
        lock.withLock { handlers[url, default: [:]][token.id] = handler }
        return token
    }

    func remove(_ token: Token) {
        lock.withLock {
            handlers[token.url]?[token.id] = nil
            if handlers[token.url]?.isEmpty == true { handlers[token.url] = nil }
        }
    }

    func report(_ url: URL, fraction: Double?) {
        let targets = lock.withLock { handlers[url].map { Array($0.values) } ?? [] }
        for handler in targets { handler(fraction) }
    }
}

/// 带进度的 URLSession fetcher: 逐块读字节, 每 16 KB 报一次。云端对象带 `Content-Encoding: gzip` 时
/// URLSession 解压后的字节数会超过 Content-Length (那是压缩后的长度), 所以进度夹在 0…1, 最后补报一次 1。
struct PoetBookFetcher: BookFetching {
    let progress: PoetDownloadProgress
    var session: URLSession = .shared
    var timeout: TimeInterval = 60

    private static let reportEvery = 16_384

    func data(from url: URL) async throws -> Data {
        let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: timeout)
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BookStoreError.http(status: http.statusCode, url: url)
        }
        let expected = response.expectedContentLength > 0 ? Double(response.expectedContentLength) : nil
        var data = Data()
        if let expected { data.reserveCapacity(Int(expected)) }
        var sinceReport = 0
        progress.report(url, fraction: expected == nil ? nil : 0)
        for try await byte in bytes {
            data.append(byte)
            sinceReport += 1
            if sinceReport >= Self.reportEvery {
                sinceReport = 0
                progress.report(url, fraction: expected.map { min(1, Double(data.count) / $0) })
            }
        }
        progress.report(url, fraction: 1)
        return data
    }
}

// MARK: - 书架 (书房里的一个分区)

struct LibraryShelfSection: View {
    let library: PoetLibrary
    @State private var model: PoetShelfModel
    private let cloud: PoetBooksCloud

    init(library: PoetLibrary, ctx: CompositionContext) {
        self.library = library
        let cloud = PoetBooksCloud.instance(ctx)
        self.cloud = cloud
        let model = PoetShelfModel(readingStore: cloud.store)
        model.onReadingChange = { Task { await cloud.driver.synchronize() } }
        _model = State(initialValue: model)
    }
    @Environment(\.zxTheme) private var theme
    /// 书架上一本书的宽度, 随 Dynamic Type。
    @ScaledMetric(relativeTo: .body) private var coverWidth = BookCoverView.Size.shelf.width

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.lg) {
            ZixiaoDesign.SectionLabel(library.label)
            ForEach(library.groups) { group in
                VStack(alignment: .leading, spacing: theme.space.sm) {
                    Text(group.name)
                        .font(theme.type.subhead)
                        .foregroundStyle(theme.color.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: theme.space.lg) {
                            ForEach(group.books) { entry in
                                NavigationLink {
                                    LibraryBookPage(entry: entry, model: model)
                                } label: {
                                    BookCoverView(title: entry.coverTitle, author: entry.byline,
                                                  size: .width(coverWidth), isRemote: !model.offline.contains(entry.id))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(entry.title)
                                .accessibilityHint(model.offline.contains(entry.id) ? "打开阅读" : "查看并下载")
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
            }
        }
        .task { await model.refreshOffline(); await cloud.driver.synchronize() }
    }
}

// MARK: - 书目页

/// 一本书的二级页: 封面、元数据、下载 / 阅读。下载完自动展卷。
struct LibraryBookPage: View {
    let entry: PoetLibrary.Entry
    let model: PoetShelfModel

    /// 打开阅读器所需的一切; 阅读位置在展卷前读好, 书页不会先按第一章排一遍再跳。
    struct Opened: Hashable {
        let book: ZixiaoLibrary.Book
        let progress: BookProgress?
    }

    @State private var opened: Opened?
    @State private var summary: String?
    @State private var progress: BookProgress?
    @Environment(\.zxTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var coverWidth = BookCoverView.Size.page.width

    private var isOffline: Bool { model.offline.contains(entry.id) }

    var body: some View {
        ScrollView {
            VStack(spacing: theme.space.xl) {
                BookCoverView(title: entry.coverTitle, author: entry.byline, size: .width(coverWidth),
                              isRemote: !isOffline)
                    .accessibilityHidden(true)
                VStack(spacing: theme.space.sm) {
                    Text(entry.title).font(theme.type.title2).foregroundStyle(theme.color.textPrimary)
                        .multilineTextAlignment(.center)
                    if let byline = entry.byline {
                        Text(byline).font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                    }
                    Text(metaLine).font(theme.type.footnote).foregroundStyle(theme.color.textTertiary)
                }
                if let summary, !summary.isEmpty {
                    Text(summary).font(theme.type.body).foregroundStyle(theme.color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                action
            }
            .padding(.horizontal, theme.space.margin).padding(.vertical, theme.space.xl)
            .poetReadableWidth(PoetLayout.readingWidth)
        }
        .background(theme.paper()).foregroundStyle(theme.color.textPrimary).tint(theme.color.accent)
        .zxNavigationTitle(entry.title, role: .secondary)
        .navigationDestination(item: $opened) { item in
            LibraryReaderPage(entry: entry, book: item.book, progress: item.progress, model: model)
        }
        .task { await load() }
        .onDisappear { model.clearFailure(entry.id) }
    }

    private var metaLine: String {
        var parts = [entry.group]
        if let bytes = entry.bytes { parts.append("约 " + Self.sizeText(bytes)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var action: some View {
        switch model.phase(entry.id) {
        case .downloading(let fraction):
            VStack(spacing: theme.space.sm) {
                if let fraction {
                    ProgressView(value: fraction).tint(theme.color.accent)
                    Text("正在下载 \(Int((fraction * 100).rounded()))%")
                        .font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                } else {
                    ProgressView()
                    Text("正在下载").font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("正在下载《\(entry.title)》")
            .accessibilityValue(fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "")
        case .failed(let message):
            EmptyState("没能取到这本书", systemImage: "exclamationmark.arrow.circlepath") {
                VStack(spacing: theme.space.md) {
                    Text(message).font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                        .multilineTextAlignment(.center)
                    Button { Task { await open() } } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                            .foregroundStyle(theme.color.accentOn)
                            .frame(maxWidth: .infinity, minHeight: PoetLayout.minHitTarget)
                    }
                    .poetActionStyle(prominent: true)
                }
            }
        case nil:
            Button { Task { await open() } } label: {
                Label(buttonTitle, systemImage: isOffline ? "book" : "arrow.down.circle")
                    .foregroundStyle(theme.color.accentOn)
                    .frame(maxWidth: .infinity, minHeight: PoetLayout.minHitTarget)
            }
            .poetActionStyle(prominent: true)
        }
    }

    private var buttonTitle: String {
        if isOffline { return progress == nil ? "阅读" : "继续阅读" }
        return "下载并阅读"
    }

    private func load() async {
        await model.refreshOffline()
        progress = await model.progress(for: entry.id)
        if isOffline, let book = try? await model.store.book(id: entry.id) { summary = book.summary }
    }

    private func open() async {
        model.clearFailure(entry.id)
        guard let book = await model.book(for: entry) else { return }
        summary = book.summary
        let latest = await model.progress(for: entry.id)
        progress = latest
        opened = Opened(book: book, progress: latest)
    }

    private static func sizeText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - 阅读页

/// 线装书阅读页: 导航栏 (返回、书名) 加 `ClassicReaderView` 自带的章目与横竖排。位置与读完的章写本机。
struct LibraryReaderPage: View {
    let entry: PoetLibrary.Entry
    let book: ZixiaoLibrary.Book
    let progress: BookProgress?
    let model: PoetShelfModel

    @Environment(\.zxTheme) private var theme

    var body: some View {
        ClassicReaderView(
            book: book,
            chapterId: progress?.chapterId,
            initialPassageId: progress?.passageId,
            finishedChapterIds: progress?.finishedChapters ?? [],
            onLocationChange: { model.record($0) },
            onChapterFinished: { model.finish(chapterId: $0.id, in: book) }
        )
        .background(theme.paper().ignoresSafeArea())
        .zxNavigationTitle(entry.title, role: .secondary)
        .onDisappear { Task { await model.flush() } }
    }
}
