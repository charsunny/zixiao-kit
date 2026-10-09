@testable import ZixiaoLibraryCore
import XCTest
@testable import ZixiaoLibrary

final class ReadingStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func testMoveAndFinish() {
        var state = ReadingState()
        XCTAssertNil(state.current)
        state.move(bookId: "lunyu", chapterId: "01", passageId: "01.03", at: t0)
        XCTAssertEqual(state.currentBookId, "lunyu")
        XCTAssertEqual(state.current?.chapterId, "01")
        XCTAssertEqual(state.current?.passageId, "01.03")

        XCTAssertFalse(state.finish(bookId: "lunyu", chapterId: "01", totalChapters: 2, at: t0))
        XCTAssertTrue(state.isFinished(bookId: "lunyu", chapterId: "01"))
        XCTAssertTrue(state.finish(bookId: "lunyu", chapterId: "02", totalChapters: 2, at: t0), "最后一章读完报全书读完")
        XCTAssertFalse(state.finish(bookId: "lunyu", chapterId: "02", totalChapters: 2, at: t0), "已经读完的不重复报")

        // 进度保留已读章节。
        state.move(bookId: "lunyu", chapterId: "03", passageId: nil, at: t0)
        XCTAssertEqual(state.progress(for: "lunyu")?.finishedChapters, ["01", "02"])
    }

    func testExcerptsDedupeAndOrder() {
        var state = ReadingState()
        let a = Excerpt(id: "a", bookId: "lunyu", chapterId: "01", passageId: "01.01", text: "学而时习之", createdAt: t0)
        let b = Excerpt(id: "b", bookId: "lunyu", chapterId: "01", passageId: "01.02", text: "其为人也孝弟", createdAt: t0)
        XCTAssertTrue(state.addExcerpt(a))
        XCTAssertTrue(state.addExcerpt(b))
        XCTAssertFalse(state.addExcerpt(Excerpt(id: "c", bookId: "lunyu", chapterId: "01", passageId: "01.01", text: "重复")))
        XCTAssertEqual(state.excerpts.map(\.id), ["b", "a"], "新的在前")
        state.removeExcerpt(id: "b")
        XCTAssertEqual(state.excerpts.map(\.id), ["a"])
    }

    func testStorePersistsAcrossInstances() async throws {
        let dir = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("nested/reading-state.json")

        let store = ReadingStateStore(fileURL: file)
        try await store.move(bookId: "lunyu", chapterId: "17", passageId: "17.02")
        _ = try await store.finish(bookId: "lunyu", chapterId: "17")
        let added = try await store.addExcerpt(
            Excerpt(id: "e1", bookId: "lunyu", bookTitle: "论语", chapterId: "17", chapterTitle: "阳货第十七",
                    passageId: "17.02", text: "性相近也，习相远也。", createdAt: t0))
        XCTAssertTrue(added)

        let reloaded = await ReadingStateStore(fileURL: file).load()
        XCTAssertEqual(reloaded.current?.chapterId, "17")
        XCTAssertEqual(reloaded.current?.passageId, "17.02")
        XCTAssertEqual(reloaded.progress(for: "lunyu")?.finishedChapters, ["17"])
        XCTAssertEqual(reloaded.excerpts.first?.text, "性相近也，习相远也。")
        XCTAssertEqual(reloaded.excerpts.first?.createdAt, t0)
        let first = await store.load()
        XCTAssertEqual(reloaded, first)
    }

    func testCorruptFileFallsBackToEmptyAndKeepsBackup() async throws {
        let dir = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("reading-state.json")
        try Data("{not json".utf8).write(to: file)

        let state = await ReadingStateStore(fileURL: file).load()
        XCTAssertEqual(state, .empty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.appendingPathExtension("corrupt").path))
    }

    func testExcerptFromReaderSelection() throws {
        let book = try JSONDecoder().decode(Book.self, from: Fixtures.data("lunyu.json"))
        let chapter = try XCTUnwrap(book.chapter(id: "17"))
        let selection = ReaderSelection(bookId: book.id, bookTitle: book.title, chapter: chapter, passage: chapter.passages[1])
        let excerpt = selection.makeExcerpt(at: t0)
        XCTAssertEqual(excerpt.bookTitle, "论语")
        XCTAssertEqual(excerpt.chapterTitle, "阳货第十七")
        XCTAssertEqual(excerpt.passageId, chapter.passages[1].id)
        XCTAssertEqual(excerpt.text, chapter.passages[1].text)
    }
}
