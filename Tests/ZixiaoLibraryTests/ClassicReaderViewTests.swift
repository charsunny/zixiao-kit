import SwiftUI
import XCTest
@testable import ZixiaoLibrary

@MainActor
final class ClassicReaderViewTests: XCTestCase {
    private func book(chapters: [String]) -> Book {
        Book(id: "t", title: "测试", category: "经",
             chapters: chapters.enumerated().map { i, id in
                 Chapter(id: id, no: i + 1, title: "第\(i + 1)章",
                         passages: [Passage(id: "\(id)-1", text: "学而时习之")])
             })
    }

    /// 外部绑定给了不在书里的章 id: 退回第一章而不是「没有正文」。
    func testChapterIndexFallsBackToFirstChapter() {
        let b = book(chapters: ["a", "b", "c"])
        XCTAssertEqual(ClassicReaderView.chapterIndex(of: "b", in: b), 1)
        XCTAssertEqual(ClassicReaderView.chapterIndex(of: "zz", in: b), 0)
        XCTAssertNil(ClassicReaderView.chapterIndex(of: "a", in: book(chapters: [])))
    }

    /// 旧调用 (不带新参数) 与新调用 (两个绑定 + 无自带栏) 都能构造。
    func testInitAcceptsLegacyAndBoundForms() {
        let b = book(chapters: ["a", "b"])
        _ = ClassicReaderView(book: b, chapterId: "b", orientation: .horizontal)
        var chapter = "a"
        var orientation = ReaderOrientation.vertical
        _ = ClassicReaderView(
            book: b,
            chapterBinding: Binding(get: { chapter }, set: { chapter = $0 }),
            orientationBinding: Binding(get: { orientation }, set: { orientation = $0 }),
            showsChrome: false
        )
        XCTAssertEqual(chapter, "a")
        XCTAssertEqual(orientation, .vertical)
    }
}
