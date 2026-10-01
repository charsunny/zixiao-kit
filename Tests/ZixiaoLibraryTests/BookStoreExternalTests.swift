import XCTest
@testable import ZixiaoLibrary

/// T35: 外部目录 (殆知阁全书目索引) 的书经 `download(from:id:version:expectedHash:)` 下载 ——
/// 同样的 sha256 校验与 `<root>/<id>/<version>/` 落盘, `isAvailableOffline` / `downloadedBookIds` 对 dz id 有效。
final class BookStoreExternalTests: XCTestCase {
    private var root: URL!
    private let dzId = "dz-0123456789abcdef"
    private let dzURL = URL(string: "https://example.test/books/v1/dz/dz-0123456789abcdef/1/book.json.gz")!
    private let dzURL2 = URL(string: "https://example.test/books/v1/dz/dz-0123456789abcdef/2/book.json.gz")!

    override func setUpWithError() throws { root = try Fixtures.temporaryDirectory() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// 拿随包样书改个 id 当作一本 dz 书 (book.json 与 schema 1 同形)。返回 (原始 JSON 字节, `sha256:<hex>`)。
    private func dzBook(title: String = "殆知阁样书") throws -> (data: Data, hash: String) {
        let raw = try Gzip.decompress(Fixtures.data("xinjing.json.gz"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        object["id"] = dzId
        object["title"] = title
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return (data, "sha256:" + BookStore.sha256Hex(data))
    }

    func testDownloadFromURLInstallsExternalBookOffline() async throws {
        let (data, hash) = try dzBook()
        let fetcher = StubFetcher([dzURL: data])
        let store = BookStore(bundled: nil, remoteCatalogURL: nil, rootDirectory: root, fetcher: fetcher)

        let book = try await store.download(from: dzURL, id: dzId, version: 1, expectedHash: hash)
        XCTAssertEqual(book.id, dzId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("\(dzId)/1/book.json").path))
        let offline = await store.isAvailableOffline(id: dzId)
        XCTAssertTrue(offline, "不在本库目录里的 dz id 下载后同样离线可读")
        let ids = await store.downloadedBookIds()
        XCTAssertEqual(ids, [dzId])

        // 新开一个 store (冷启动): 不靠内存缓存, 从盘上读回来。
        let cold = BookStore(bundled: nil, remoteCatalogURL: nil, rootDirectory: root, fetcher: StubFetcher())
        let reread = try await cold.book(id: dzId)
        XCTAssertEqual(reread.title, "殆知阁样书")
        let version = await cold.downloadedVersion(id: dzId)
        XCTAssertEqual(version, 1)
    }

    func testDownloadFromURLRejectsHashMismatchAndMissingHash() async throws {
        let (data, _) = try dzBook()
        let store = BookStore(bundled: nil, remoteCatalogURL: nil, rootDirectory: root,
                              fetcher: StubFetcher([dzURL: data]))
        let wrong = "sha256:" + String(repeating: "f", count: 64)
        do {
            _ = try await store.download(from: dzURL, id: dzId, version: 1, expectedHash: wrong)
            XCTFail("hash 不一致必须拒收")
        } catch BookStoreError.hashMismatch(let id, let expected, _) {
            XCTAssertEqual(id, dzId)
            XCTAssertEqual(expected, String(repeating: "f", count: 64))
        }
        do {
            _ = try await store.download(from: dzURL, id: dzId, version: 1, expectedHash: nil)
            XCTFail("没有 hash 不落盘")
        } catch let error as BookStoreError {
            XCTAssertEqual(error, .missingHash(id: dzId))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(dzId).path))
        let offline = await store.isAvailableOffline(id: dzId)
        XCTAssertFalse(offline)
        let ids = await store.downloadedBookIds()
        XCTAssertEqual(ids, [])
    }

    func testDownloadFromURLReplacesOlderVersionAndRejectsUnsafeIdentifier() async throws {
        let v1 = try dzBook(title: "第一版")
        let v2 = try dzBook(title: "第二版")
        let store = BookStore(bundled: nil, remoteCatalogURL: nil, rootDirectory: root,
                              fetcher: StubFetcher([dzURL: v1.data, dzURL2: v2.data]))
        _ = try await store.download(from: dzURL, id: dzId, version: 1, expectedHash: v1.hash)
        let book = try await store.download(from: dzURL2, id: dzId, version: 2, expectedHash: v2.hash)
        XCTAssertEqual(book.title, "第二版")
        let versions = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(dzId).path)
        XCTAssertEqual(versions, ["2"], "每本只留一个版本")
        let version = await store.downloadedVersion(id: dzId)
        XCTAssertEqual(version, 2)

        do {
            _ = try await store.download(from: dzURL, id: "../dz-evil", version: 1, expectedHash: v1.hash)
            XCTFail("id 会拼进路径, 必须挡住 ../")
        } catch let error as BookStoreError {
            XCTAssertEqual(error, .invalidIdentifier("../dz-evil"))
        }
        // 根目录里的 catalog.json 之类的文件不算书。
        try Data("{}".utf8).write(to: root.appendingPathComponent("catalog.json"))
        let ids = await store.downloadedBookIds()
        XCTAssertEqual(ids, [dzId])
    }
}
