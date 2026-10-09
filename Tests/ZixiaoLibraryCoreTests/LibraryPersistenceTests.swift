import CryptoKit
import Foundation
import XCTest
import ZixiaoLibraryCore

/// Exercise the same public data APIs from a client that does not import the iOS reader.
final class LibraryPersistenceTests: XCTestCase {
    func testDownloadedBookAndReadingStateSurviveFreshStores() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let passage = Passage(id: "01.01", text: "测试正文")
        let chapter = Chapter(id: "01", no: 1, title: "第一章", passages: [passage])
        let book = Book(id: "sample", title: "测试读本", chapters: [chapter])
        let bytes = try JSONEncoder().encode(book)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let store = BookStore(bundled: nil, remoteCatalogURL: nil, rootDirectory: root,
                              fetcher: MemoryFetcher(data: bytes))
        let downloaded = try await store.download(from: URL(string: "https://example.invalid/sample.json")!,
                                                   id: book.id, version: book.version, expectedHash: hash)
        XCTAssertEqual(downloaded, book)

        let stateURL = root.appendingPathComponent("reading-state.json")
        let state = ReadingStateStore(fileURL: stateURL)
        try await state.move(bookId: book.id, chapterId: chapter.id, passageId: passage.id)
        try await state.addExcerpt(Excerpt(book: book, chapter: chapter, passage: passage))
        try await state.finish(bookId: book.id, chapterId: chapter.id, totalChapters: 1)

        let reopened = BookStore(bundled: nil, remoteCatalogURL: nil, rootDirectory: root,
                                 fetcher: OfflineFetcher())
        let offlineBook = try await reopened.book(id: book.id)
        let restored = await ReadingStateStore(fileURL: stateURL).load()
        XCTAssertEqual(offlineBook.passage(id: passage.id)?.text, passage.text)
        XCTAssertEqual(restored.current?.passageId, passage.id)
        XCTAssertTrue(restored.isFinished(bookId: book.id, chapterId: chapter.id))
        XCTAssertEqual(restored.excerpts.map(\.text), [passage.text])
    }
}

private struct MemoryFetcher: BookFetching {
    let data: Data
    func data(from url: URL) async throws -> Data { data }
}

private struct OfflineFetcher: BookFetching {
    func data(from url: URL) async throws -> Data { throw URLError(.notConnectedToInternet) }
}
