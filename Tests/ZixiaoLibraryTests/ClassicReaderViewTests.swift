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

@MainActor
final class ClassicReaderLocateTests: XCTestCase {
    private let book = Book(id: "t", title: "测试", category: "经", chapters: [
        Chapter(id: "a", no: 1, title: "一", passages: [Passage(id: "a1", text: "学"), Passage(id: "same", text: "而")]),
        Chapter(id: "b", no: 2, title: "二", passages: [Passage(id: "b1", text: "时"), Passage(id: "same", text: "习")]),
    ])

    /// 段落定位: 先看当前章 (两章都有同 id 的段时不乱跳), 再按书序; 书里没有为 nil。
    func testChapterContainingPassage() {
        XCTAssertEqual(ClassicReaderView.chapterIndex(containing: "b1", in: book, preferring: "a"), 1)
        XCTAssertEqual(ClassicReaderView.chapterIndex(containing: "a1", in: book, preferring: nil), 0)
        XCTAssertEqual(ClassicReaderView.chapterIndex(containing: "same", in: book, preferring: "b"), 1)
        XCTAssertEqual(ClassicReaderView.chapterIndex(containing: "same", in: book, preferring: "zz"), 0)
        XCTAssertNil(ClassicReaderView.chapterIndex(containing: "nope", in: book, preferring: "a"))
    }

    /// 轻点页边: 章内翻页, 章尾 / 章首跨章; 单页章两头都跨章。
    func testPageTurn() {
        XCTAssertEqual(ClassicReaderView.pageTurn(from: 0, pageCount: 3, towardNext: true), .page(1))
        XCTAssertEqual(ClassicReaderView.pageTurn(from: 2, pageCount: 3, towardNext: true), .nextChapter)
        XCTAssertEqual(ClassicReaderView.pageTurn(from: 2, pageCount: 3, towardNext: false), .page(1))
        XCTAssertEqual(ClassicReaderView.pageTurn(from: 0, pageCount: 3, towardNext: false), .previousChapter)
        XCTAssertEqual(ClassicReaderView.pageTurn(from: 0, pageCount: 1, towardNext: true), .nextChapter)
        XCTAssertEqual(ClassicReaderView.pageTurn(from: 0, pageCount: 1, towardNext: false), .previousChapter)
    }

    /// 白话三态: 轮换顺序、竖排排法、原始值 (App 存偏好用)。
    func testPlainModes() {
        XCTAssertEqual(ReaderPlainMode.allCases.map(\.rawValue), ["interlinear", "parallel", "hidden"])
        XCTAssertEqual(ReaderPlainMode.allCases.map(\.title), ["夹注", "对照", "不显示白话"])
        XCTAssertEqual(ReaderPlainMode.interlinear.next, .parallel)
        XCTAssertEqual(ReaderPlainMode.parallel.next, .hidden)
        XCTAssertEqual(ReaderPlainMode.hidden.next, .interlinear)
        XCTAssertEqual(ReaderPlainMode.allCases.map(\.classicLayout), [.interlinear, .columns, .none])
    }

    /// 新参数 (白话排法 + 段落绑定) 能与旧参数一起构造。
    func testInitAcceptsPlainModeAndPassageBinding() {
        var passage: String? = "b1"
        _ = ClassicReaderView(book: book, showsChrome: false, plainMode: .hidden,
                              passageBinding: Binding(get: { passage }, set: { passage = $0 }))
        XCTAssertEqual(passage, "b1", "构造本身不消费定位, 显示时才处理")
    }
}
