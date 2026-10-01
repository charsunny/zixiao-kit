import CryptoKit
import Foundation

/// 取网络字节的最小接口。抽出来是为了测试能注入桩, 也让 App 能换成带鉴权 / 限速的实现。
public protocol BookFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

/// 默认实现: URLSession。
///
/// 注意云端对象带 `Content-Encoding: gzip`, URLSession 会自动解压, 这时拿到的已经是 book.json 字节;
/// 走 CDN 回源或本地服务器时又可能拿到原始 .gz。`BookStore` 按魔数两种都接。
public struct URLSessionBookFetcher: BookFetching {
    public var session: URLSession
    public var timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 60) {
        self.session = session
        self.timeout = timeout
    }

    public func data(from url: URL) async throws -> Data {
        let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: timeout)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BookStoreError.http(status: http.statusCode, url: url)
        }
        return data
    }
}

/// 随包书的位置。内核不知道 App 把书放在 bundle 的哪里 (XcodeGen 的 folder reference 会保留子目录,
/// group 则拍平到根), 所以由 App 注入目录; 目录里是 `catalog.json` 与 `<id>.json`。
public struct BundledBooks: Sendable, Hashable {
    public var directory: URL
    public var catalogFileName: String

    public init(directory: URL, catalogFileName: String = "catalog.json") {
        self.directory = directory
        self.catalogFileName = catalogFileName
    }

    /// 从 bundle 取: `subdirectory` 为 nil 时即 bundle 资源根目录。bundle 没有资源目录时返回 nil。
    public init?(bundle: Bundle, subdirectory: String? = nil, catalogFileName: String = "catalog.json") {
        guard var dir = bundle.resourceURL else { return nil }
        if let subdirectory { dir.appendPathComponent(subdirectory, isDirectory: true) }
        self.init(directory: dir, catalogFileName: catalogFileName)
    }

    func bookURL(_ id: String) -> URL { directory.appendingPathComponent("\(id).json") }
    var catalogURL: URL { directory.appendingPathComponent(catalogFileName) }
}

public enum BookStoreError: Error, Sendable, Equatable {
    /// 本地 (随包 / 已下载) 都没有; 界面据此给「下载」按钮。
    case notAvailable(id: String)
    case notInCatalog(id: String)
    case noDownloadURL(id: String)
    /// 目录没给 hash: 拒绝落盘 —— 没法校验的字节不进书架。
    case missingHash(id: String)
    case hashMismatch(id: String, expected: String, actual: String)
    /// 下下来的书 id 与目录对不上 (CDN 串对象之类)。
    case idMismatch(expected: String, actual: String)
    case invalidIdentifier(String)
    case http(status: Int, url: URL)
}

/// 书库: 随包 → 已下载 → 云端。
///
/// 为什么是 actor: 目录缓存、内存里的书、下载中的任务都是可变共享状态, 且下载与读盘天然异步;
/// actor 让 UI 可以从任意任务并发地要同一本书而不重复下载、不写坏文件。
///
/// 磁盘布局 (根目录默认 `Application Support/ZixiaoLibrary/`):
/// ```
/// <root>/catalog.json              最近一次拿到的云端目录 (离线时还能看到云端书目与 hash)
/// <root>/<id>/<version>/book.json  已校验的书, 每本只留一个版本
/// ```
/// 放 Application Support 而不是 Documents: 这是 App 自管的数据, 不该出现在「文件」App 里;
/// 同时标记不进 iCloud 备份 —— 书都能从云端重下, 按 Apple 的存储指南不该占用户备份空间。
public actor BookStore {
    public nonisolated let bundled: BundledBooks?
    public nonisolated let remoteCatalogURL: URL?
    public nonisolated let rootDirectory: URL
    private let fetcher: any BookFetching

    private var books: [String: Book] = [:]
    private var bundledCatalogCache: BookCatalog?
    private var mergedCatalog: BookCatalog?
    private var inFlight: [String: Task<Book, Error>] = [:]

    /// - Parameters:
    ///   - bundled: 随包书目录; 没有随包书的 App 传 nil。
    ///   - remoteCatalogURL: 云端目录地址 (如 `https://…/books/v1/catalog.json`), 由 App 注入, 内核不写死域名。
    ///   - rootDirectory: 落盘根目录; 测试传临时目录。
    public init(
        bundled: BundledBooks?,
        remoteCatalogURL: URL?,
        rootDirectory: URL? = nil,
        fetcher: any BookFetching = URLSessionBookFetcher()
    ) {
        self.bundled = bundled
        self.remoteCatalogURL = remoteCatalogURL
        self.rootDirectory = rootDirectory ?? BookStore.defaultRootDirectory
        self.fetcher = fetcher
    }

    public static var defaultRootDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("ZixiaoLibrary", isDirectory: true)
    }

    // MARK: 目录

    /// 随包目录, 每条都标 `bundled`。没有随包书时是空目录。
    public func bundledCatalog() throws -> BookCatalog {
        if let bundledCatalogCache { return bundledCatalogCache }
        guard let bundled else { return BookCatalog(books: []) }
        var catalog = try decode(BookCatalog.self, from: Data(contentsOf: bundled.catalogURL))
        for i in catalog.books.indices { catalog.books[i].bundled = true }
        bundledCatalogCache = catalog
        return catalog
    }

    /// 不碰网络的目录: 随包 + 上次缓存的云端目录。书架首屏用它, 不必等网络。
    public func localCatalog() -> BookCatalog {
        let bundledCatalog = (try? bundledCatalog()) ?? BookCatalog(books: [])
        guard let cached = try? decode(BookCatalog.self, from: Data(contentsOf: cachedCatalogURL)) else {
            return bundledCatalog
        }
        return Self.merge(remote: cached, bundled: bundledCatalog)
    }

    /// 云端目录与随包目录合并; 拿不到云端就退回 `localCatalog()`。
    /// 首次调用会联网, 之后返回内存里的, 除非 `refresh`。
    public func catalog(refresh: Bool = false) async -> BookCatalog {
        if let mergedCatalog, !refresh { return mergedCatalog }
        let bundledCatalog = (try? bundledCatalog()) ?? BookCatalog(books: [])
        if let remoteCatalogURL,
           let data = try? await fetcher.data(from: remoteCatalogURL),
           let remote = try? decode(BookCatalog.self, from: data) {
            try? ensureRoot()
            try? data.write(to: cachedCatalogURL, options: .atomic)
            let merged = Self.merge(remote: remote, bundled: bundledCatalog)
            mergedCatalog = merged
            return merged
        }
        // 离线: 不缓存进 mergedCatalog, 下次调用还会再试网络。
        return localCatalog()
    }

    /// 云端为准; 随包书在合并后仍标 bundled; 云端漏了的随包书照样上架。
    static func merge(remote: BookCatalog, bundled: BookCatalog) -> BookCatalog {
        let bundledIds = Set(bundled.books.map(\.id))
        let remoteIds = Set(remote.books.map(\.id))
        var books = remote.books.map { entry -> CatalogEntry in
            var entry = entry
            entry.bundled = bundledIds.contains(entry.id)
            return entry
        }
        books += bundled.books.filter { !remoteIds.contains($0.id) }
        return BookCatalog(schema: remote.schema, generated: remote.generated, books: books)
    }

    // MARK: 读书

    /// 读一本书, 只读本地: 已下载优先 (它可能比随包新), 但随包版本更高时 (App 升级带了新版) 用随包。
    /// 都没有抛 `.notAvailable`, 界面据此给「下载」。
    public func book(id: String) throws -> Book {
        if let cached = books[id] { return cached }
        let bundledVersion = (try? bundledCatalog())?.entry(id: id)?.version
        if let found = downloadedFile(id: id), found.version >= (bundledVersion ?? .min) {
            let file = found.url
            do {
                let book = try decode(Book.self, from: Data(contentsOf: file))
                books[id] = book
                return book
            } catch {
                // 落盘时校验过, 读不出来只能是磁盘损坏或被改: 删掉, 退回随包或重新下载。
                try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            }
        }
        if let bundled, let data = try? Data(contentsOf: bundled.bookURL(id)) {
            let book = try decode(Book.self, from: data)
            books[id] = book
            return book
        }
        throw BookStoreError.notAvailable(id: id)
    }

    public func isAvailableOffline(id: String) -> Bool {
        if books[id] != nil || downloadedFile(id: id) != nil { return true }
        guard let bundled else { return false }
        return FileManager.default.fileExists(atPath: bundled.bookURL(id).path)
    }

    /// 已下载的版本号; 没下过为 nil。
    public func downloadedVersion(id: String) -> Int? { downloadedFile(id: id)?.version }

    /// 本地能读到的最高版本 (随包或已下载)。
    public func localVersion(id: String) -> Int? {
        let bundledVersion = (try? bundledCatalog())?.entry(id: id)?.version
        switch (downloadedVersion(id: id), bundledVersion) {
        case let (d?, b?): return max(d, b)
        case let (d, b): return d ?? b
        }
    }

    /// 目录版本比本地新 (或本地没有) 就该下。
    public func needsDownload(_ entry: CatalogEntry) -> Bool {
        guard let local = localVersion(id: entry.id) else { return true }
        return entry.version > local
    }

    // MARK: 下载

    public func download(id: String) async throws -> Book {
        guard let entry = await catalog().entry(id: id) else { throw BookStoreError.notInCatalog(id: id) }
        return try await download(entry)
    }

    /// 下载 → (必要时) gunzip → sha256 比对目录 hash → 解码 → 原子落盘 → 删旧版本。
    /// 同一本书并发请求只下一次。
    public func download(_ entry: CatalogEntry) async throws -> Book {
        if let running = inFlight[entry.id] { return try await running.value }
        guard let url = entry.downloadURL else { throw BookStoreError.noDownloadURL(id: entry.id) }
        let fetcher = self.fetcher
        let task = Task { () throws -> Book in
            let payload = try await fetcher.data(from: url)
            return try self.install(payload, for: entry)
        }
        inFlight[entry.id] = task
        defer { inFlight[entry.id] = nil }
        return try await task.value
    }

    /// 校验并落盘一份下载到的字节。`payload` 可以是 .gz 原始字节, 也可以是已解压的 JSON。
    ///
    /// 顺序是刻意的: 先校验、再解码、最后写盘 —— 任何一步失败都不留下半截文件;
    /// 新版本写好之后才删旧版本, 中途崩溃也总有一份能读的。
    @discardableResult
    func install(_ payload: Data, for entry: CatalogEntry) throws -> Book {
        try Self.validateIdentifier(entry.id)
        guard let expected = entry.sha256Hex else { throw BookStoreError.missingHash(id: entry.id) }
        let raw = Gzip.isGzip(payload) ? try Gzip.decompress(payload) : payload
        let actual = Self.sha256Hex(raw)
        guard actual == expected else {
            throw BookStoreError.hashMismatch(id: entry.id, expected: expected, actual: actual)
        }
        let book = try decode(Book.self, from: raw)
        guard book.id == entry.id else { throw BookStoreError.idMismatch(expected: entry.id, actual: book.id) }

        try ensureRoot()
        let bookDir = rootDirectory.appendingPathComponent(entry.id, isDirectory: true)
        let versionDir = bookDir.appendingPathComponent(String(entry.version), isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: versionDir, withIntermediateDirectories: true)
        // 写的是校验过的原始字节, 不重新编码 —— 这样磁盘上的文件与目录 hash 始终一致, 可随时复核。
        try raw.write(to: versionDir.appendingPathComponent("book.json"), options: .atomic)
        for other in (try? fm.contentsOfDirectory(at: bookDir, includingPropertiesForKeys: nil)) ?? []
        where other.lastPathComponent != versionDir.lastPathComponent {
            try? fm.removeItem(at: other)
        }
        books[entry.id] = book
        return book
    }

    // MARK: 外部目录的书 (T35)

    /// 下载一本不在本库目录里的书 (如殆知阁全书目索引里的条目): 给出 book.json(.gz) 地址、id、版本与
    /// `sha256:<hex>` (对解压后的 book.json)。走与 `download(_:)` 同一条路 —— 同样的 sha256 校验、
    /// 同样落盘到 `<root>/<id>/<version>/book.json`、同样并发合并; 下完 `book(id:)` /
    /// `isAvailableOffline(id:)` / `downloadedVersion(id:)` 对这个 id 一样有效。
    /// `expectedHash` 为 nil 时与目录条目缺 hash 一样拒收 (`.missingHash`)。
    @discardableResult
    public func download(from url: URL, id: String, version: Int, expectedHash: String?) async throws -> Book {
        try Self.validateIdentifier(id)
        let entry = CatalogEntry(id: id, title: id, version: version, hash: expectedHash, url: url.absoluteString)
        return try await download(entry)
    }

    /// 已下载 (落了盘、文件还在) 的书 id, 按 id 排序。外部目录的书不在 `catalog()` 里, 书架靠它找回来。
    public func downloadedBookIds() -> [String] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return children.map(\.lastPathComponent)
            .filter { (try? Self.validateIdentifier($0)) != nil && downloadedFile(id: $0) != nil }
            .sorted()
    }

    /// 删掉已下载的书 (随包的删不掉, 删完照样能读随包版)。
    public func remove(id: String) throws {
        try Self.validateIdentifier(id)
        books[id] = nil
        let dir = rootDirectory.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }

    // MARK: 私有

    private var cachedCatalogURL: URL { rootDirectory.appendingPathComponent("catalog.json") }

    /// 已下载的最新版本及其文件。
    private func downloadedFile(id: String) -> (version: Int, url: URL)? {
        guard (try? Self.validateIdentifier(id)) != nil else { return nil }
        let dir = rootDirectory.appendingPathComponent(id, isDirectory: true)
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        var best: (version: Int, url: URL)?
        for child in children {
            guard let version = Int(child.lastPathComponent) else { continue }
            let file = child.appendingPathComponent("book.json")
            if version > (best?.version ?? .min), fm.fileExists(atPath: file.path) { best = (version, file) }
        }
        return best
    }

    private func ensureRoot() throws {
        var root = rootDirectory
        guard !FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    /// 书 id 会拼进文件路径, 而目录来自网络: 只允许安全字符, 挡住 `../` 之类。
    static func validateIdentifier(_ id: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !id.isEmpty, id.count <= 128, id.unicodeScalars.allSatisfy(allowed.contains) else {
            throw BookStoreError.invalidIdentifier(id)
        }
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
