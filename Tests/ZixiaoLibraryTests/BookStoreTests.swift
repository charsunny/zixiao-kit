import XCTest
@testable import ZixiaoLibrary

/// 网络桩: 按 URL 回固定字节, 记调用次数。
final class StubFetcher: BookFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [URL: Data]
    private var counts: [URL: Int] = [:]

    init(_ responses: [URL: Data] = [:]) { self.responses = responses }

    func data(from url: URL) async throws -> Data {
        let data: Data? = lock.withLock {
            counts[url, default: 0] += 1
            return responses[url]
        }
        // 让出一下, 模拟真实网络的挂起, 并发用例才测得出重复下载。
        try await Task.sleep(nanoseconds: 20_000_000)
        guard let data else { throw URLError(.notConnectedToInternet) }
        return data
    }

    func calls(_ url: URL) -> Int { lock.withLock { counts[url, default: 0] } }
}

final class BookStoreTests: XCTestCase {
    private var root: URL!
    private let catalogURL = URL(string: "https://example.test/books/v1/catalog.json")!
    private let bookURL = URL(string: "https://example.test/books/v1/xinjing/1/book.json.gz")!

    override func setUpWithError() throws { root = try Fixtures.temporaryDirectory() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func xinjingEntry(version: Int = 1, hash: String? = Fixtures.xinjingHash) -> CatalogEntry {
        CatalogEntry(id: "xinjing", title: "般若波罗蜜多心经", category: "子", version: version, hash: hash,
                     bytes: 1442, url: bookURL.absoluteString)
    }

    private func remoteCatalogData(_ entries: [CatalogEntry]) throws -> Data {
        try JSONEncoder().encode(BookCatalog(generated: "2026-09-28", books: entries))
    }

    private func bookFile(_ id: String, _ version: Int) -> URL {
        root.appendingPathComponent("\(id)/\(version)/book.json")
    }

    func testDownloadVerifiesAndWritesToVersionDirectory() async throws {
        let fetcher = StubFetcher([
            catalogURL: try remoteCatalogData([xinjingEntry()]),
            bookURL: try Fixtures.data("xinjing.json.gz"),
        ])
        let store = BookStore(bundled: nil, remoteCatalogURL: catalogURL, rootDirectory: root, fetcher: fetcher)

        let book = try await store.download(id: "xinjing")
        XCTAssertEqual(book.id, "xinjing")
        let written = try Data(contentsOf: bookFile("xinjing", 1))
        XCTAssertEqual("sha256:" + BookStore.sha256Hex(written), Fixtures.xinjingHash, "落盘的是解压后、校验过的原始字节")
        let offline = await store.isAvailableOffline(id: "xinjing")
        XCTAssertTrue(offline)
        let version = await store.downloadedVersion(id: "xinjing")
        XCTAssertEqual(version, 1)
    }

    func testHashMismatchIsRejectedAndNothingIsWritten() async throws {
        let bad = xinjingEntry(hash: "sha256:" + String(repeating: "0", count: 64))
        let store = BookStore(bundled: nil, remoteCatalogURL: nil, rootDirectory: root,
                              fetcher: StubFetcher([bookURL: try Fixtures.data("xinjing.json.gz")]))
        do {
            _ = try await store.download(bad)
            XCTFail("hash 不一致必须抛错")
        } catch BookStoreError.hashMismatch(let id, _, let actual) {
            XCTAssertEqual(id, "xinjing")
            XCTAssertEqual(actual, String(Fixtures.xinjingHash.dropFirst(7)))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("xinjing").path))
        let offline = await store.isAvailableOffline(id: "xinjing")
        XCTAssertFalse(offline)
    }

    func testMissingHashIsRejected() async throws {
        let store = BookStore(bundled: nil, remoteCatalogURL: nil, rootDirectory: root,
                              fetcher: StubFetcher([bookURL: try Fixtures.data("xinjing.json.gz")]))
        do {
            _ = try await store.download(xinjingEntry(hash: nil))
            XCTFail("没有 hash 不能落盘")
        } catch let error as BookStoreError {
            XCTAssertEqual(error, .missingHash(id: "xinjing"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: bookFile("xinjing", 1).path))
    }

    /// 服务器按 `Content-Encoding: gzip` 回, URLSession 已经解过: 直接是 JSON 也要认。
    func testAcceptsAlreadyDecodedPayload() async throws {
        let raw = try Gzip.decompress(Fixtures.data("xinjing.json.gz"))
        let store = BookStore(bundled: nil, remoteCatalogURL: nil, rootDirectory: root, fetcher: StubFetcher([bookURL: raw]))
        let book = try await store.download(xinjingEntry())
        XCTAssertEqual(book.chapters.count, 1)
    }

    func testVersionUpgradeReplacesOldVersion() async throws {
        let gz = try Fixtures.data("xinjing.json.gz")
        let store = BookStore(bundled: nil, remoteCatalogURL: nil, rootDirectory: root, fetcher: StubFetcher())
        _ = try await store.install(gz, for: xinjingEntry(version: 1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bookFile("xinjing", 1).path))
        let needs = await store.needsDownload(xinjingEntry(version: 2))
        XCTAssertTrue(needs)

        _ = try await store.install(gz, for: xinjingEntry(version: 2))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bookFile("xinjing", 2).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("xinjing/1").path), "旧版本应被覆盖")
        let version = await store.downloadedVersion(id: "xinjing")
        XCTAssertEqual(version, 2)
        let stillNeeds = await store.needsDownload(xinjingEntry(version: 2))
        XCTAssertFalse(stillNeeds)
    }

    func testOfflineReadsDownloadedBookAndCachedCatalog() async throws {
        let online = BookStore(bundled: nil, remoteCatalogURL: catalogURL, rootDirectory: root, fetcher: StubFetcher([
            catalogURL: try remoteCatalogData([xinjingEntry()]),
            bookURL: try Fixtures.data("xinjing.json.gz"),
        ]))
        _ = try await online.download(id: "xinjing")

        // 新进程、断网。
        let offline = BookStore(bundled: nil, remoteCatalogURL: catalogURL, rootDirectory: root, fetcher: StubFetcher())
        let book = try await offline.book(id: "xinjing")
        XCTAssertEqual(book.title, "般若波罗蜜多心经")
        let catalog = await offline.catalog()
        XCTAssertEqual(catalog.entry(id: "xinjing")?.hash, Fixtures.xinjingHash, "离线时用上次缓存的云端目录")
    }

    func testBundledBooksAndCatalogMerge() async throws {
        let bundled = BundledBooks(directory: Fixtures.directory)
        let store = BookStore(bundled: bundled, remoteCatalogURL: catalogURL, rootDirectory: root, fetcher: StubFetcher([
            catalogURL: try Fixtures.data("cloud-catalog.json"),
        ]))
        let bundledCatalog = try await store.bundledCatalog()
        XCTAssertTrue(bundledCatalog.books.allSatisfy(\.bundled))

        let merged = await store.catalog()
        XCTAssertEqual(merged.books.count, 5)
        XCTAssertEqual(merged.entry(id: "lunyu")?.bundled, true)
        XCTAssertNotNil(merged.entry(id: "lunyu")?.url)

        let lunyu = try await store.book(id: "lunyu")
        XCTAssertEqual(lunyu.passageCount, 501)
        do {
            _ = try await store.book(id: "daodejing")
            XCTFail("测试目录里没有道德经正文")
        } catch let error as BookStoreError {
            XCTAssertEqual(error, .notAvailable(id: "daodejing"))
        }
    }

    func testCloudOnlyBooksMergeWithBundledOnes() {
        let bundled = BookCatalog(books: [CatalogEntry(id: "a", title: "甲", bundled: true),
                                          CatalogEntry(id: "b", title: "乙", bundled: true)])
        let remote = BookCatalog(generated: "g", books: [CatalogEntry(id: "a", title: "甲", version: 2),
                                                         CatalogEntry(id: "c", title: "丙")])
        let merged = BookStore.merge(remote: remote, bundled: bundled)
        XCTAssertEqual(merged.books.map(\.id), ["a", "c", "b"], "云端为准, 云端漏了的随包书照样上架")
        XCTAssertEqual(merged.entry(id: "a")?.version, 2)
        XCTAssertEqual(merged.entry(id: "a")?.bundled, true)
        XCTAssertEqual(merged.entry(id: "c")?.bundled, false)
    }

    /// 已下载优先于随包 (版本相同或更新时)。
    func testDownloadedCopyWinsOverBundled() async throws {
        let json = Data(#"{"schema":1,"id":"lunyu","version":2,"title":"论语(新版)","chapters":[{"id":"01","no":1,"title":"学而第一","paragraphs":[{"id":"01.01","text":"子曰。"}]}]}"#.utf8)
        let entry = CatalogEntry(id: "lunyu", title: "论语", version: 2, hash: "sha256:" + BookStore.sha256Hex(json),
                                 url: "https://example.test/lunyu.json.gz")
        let store = BookStore(bundled: BundledBooks(directory: Fixtures.directory), remoteCatalogURL: nil,
                              rootDirectory: root, fetcher: StubFetcher())
        _ = try await store.install(json, for: entry)

        let fresh = BookStore(bundled: BundledBooks(directory: Fixtures.directory), remoteCatalogURL: nil,
                              rootDirectory: root, fetcher: StubFetcher())
        let book = try await fresh.book(id: "lunyu")
        XCTAssertEqual(book.title, "论语(新版)")
        let local = await fresh.localVersion(id: "lunyu")
        XCTAssertEqual(local, 2)

        try await fresh.remove(id: "lunyu")
        let back = try await BookStore(bundled: BundledBooks(directory: Fixtures.directory), remoteCatalogURL: nil,
                                       rootDirectory: root, fetcher: StubFetcher()).book(id: "lunyu")
        XCTAssertEqual(back.title, "论语", "删掉下载版后退回随包版")
    }

    func testRejectsBookWhoseIdDoesNotMatchCatalog() async throws {
        let raw = try Gzip.decompress(Fixtures.data("xinjing.json.gz"))
        let entry = CatalogEntry(id: "lunyu", title: "论语", hash: "sha256:" + BookStore.sha256Hex(raw), url: bookURL.absoluteString)
        let store = BookStore(bundled: nil, remoteCatalogURL: nil, rootDirectory: root, fetcher: StubFetcher())
        do {
            _ = try await store.install(raw, for: entry)
            XCTFail()
        } catch let error as BookStoreError {
            XCTAssertEqual(error, .idMismatch(expected: "lunyu", actual: "xinjing"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("lunyu").path))
    }

    func testRejectsPathTraversalIdentifiers() async throws {
        let store = BookStore(bundled: nil, remoteCatalogURL: nil, rootDirectory: root, fetcher: StubFetcher())
        let entry = CatalogEntry(id: "../evil", title: "x", hash: Fixtures.xinjingHash, url: bookURL.absoluteString)
        do {
            _ = try await store.install(Data(), for: entry)
            XCTFail()
        } catch let error as BookStoreError {
            XCTAssertEqual(error, .invalidIdentifier("../evil"))
        }
    }

    func testConcurrentDownloadsOfSameBookFetchOnce() async throws {
        let fetcher = StubFetcher([bookURL: try Fixtures.data("xinjing.json.gz")])
        let store = BookStore(bundled: nil, remoteCatalogURL: nil, rootDirectory: root, fetcher: fetcher)
        let entry = xinjingEntry()
        async let a = store.download(entry)
        async let b = store.download(entry)
        let (x, y) = try await (a, b)
        XCTAssertEqual(x, y)
        XCTAssertEqual(fetcher.calls(bookURL), 1)
    }
}
