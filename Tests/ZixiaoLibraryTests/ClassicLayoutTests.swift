@testable import ZixiaoLibraryCore
import XCTest
import ZixiaoDesign
@testable import ZixiaoLibrary

final class ClassicLayoutTests: XCTestCase {
    func testPunctuationSqueezesIntoColumnEnd() {
        // 四字一列: 「学而时习」满列后「，」挤在列尾, 不居下一列之首。
        let pages = ClassicLayout.paginate(passages: [Passage(id: "1", text: "学而时习，不亦说乎？")],
                                           charsPerColumn: 4, columnsPerPage: 10)
        let columns = pages[0].columns
        XCTAssertEqual(columns.map(\.text), ["学而时习，", "不亦说乎？"])
        XCTAssertEqual(columns[0].cells.last?.glyph, "︐", "标点换成直排形")
        XCTAssertEqual(columns[0].cells.last?.isPunctuation, true)
    }

    /// 版式的标点判定与直排形完全交给 ZixiaoDesign 的 `ZXVerticalForms`: 每个格子的直排形都与它一致,
    /// 表里每个标点都按「不居列首」处理。
    func testUsesDesignVerticalForms() {
        let text = String(ZXVerticalForms.map.keys.sorted())
        let pages = ClassicLayout.paginate(passages: [Passage(id: "p", text: "子" + text)], charsPerColumn: 1, columnsPerPage: 99)
        let cells = pages.flatMap(\.columns).flatMap(\.cells)
        XCTAssertEqual(cells.count, text.count + 1)
        for cell in cells {
            let ch = Character(cell.original)
            XCTAssertEqual(cell.glyph, String(ZXVerticalForms.vertical(ch)))
            XCTAssertEqual(cell.isPunctuation, ZXVerticalForms.isPunctuation(ch))
        }
        // 一字一列时, 第一个标点不居列首, 挤到「子」所在列的列尾。
        XCTAssertEqual(pages[0].columns.first?.cells.count, 2)
    }

    func testEachPassageAndPoemLineStartsANewColumn() {
        let passages = [
            Passage(id: "a", text: "床前明月光，\n疑是地上霜。"),
            Passage(id: "b", text: "道可道"),
        ]
        let pages = ClassicLayout.paginate(passages: passages, charsPerColumn: 10, columnsPerPage: 2)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].columns.map(\.passageId), ["a", "a"])
        XCTAssertEqual(pages[1].firstPassageId, "b")
        XCTAssertEqual(ClassicLayout.page(containing: "b", in: pages), 1)
        XCTAssertEqual(ClassicLayout.page(containing: "zzz", in: pages), 0)
        XCTAssertEqual(ClassicLayout.page(containing: nil, in: pages), 0)
    }

    func testWhitespaceIsSkippedButIndexKeepsCounting() {
        let pages = ClassicLayout.paginate(passages: [Passage(id: "x", text: "揭谛 揭谛")], charsPerColumn: 10, columnsPerPage: 1)
        let cells = pages[0].columns[0].cells
        XCTAssertEqual(cells.map(\.glyph).joined(), "揭谛揭谛")
        XCTAssertEqual(cells.map(\.index), [0, 1, 3, 4])
    }

    func testPaginatesWholeLunyuChapter() throws {
        let book = try JSONDecoder().decode(Book.self, from: Fixtures.data("lunyu.json"))
        let chapter = try XCTUnwrap(book.chapter(id: "17"))
        let pages = ClassicLayout.paginate(passages: chapter.passages, charsPerColumn: 18, columnsPerPage: 8)
        XCTAssertGreaterThan(pages.count, 1)
        // 所有段落都排进去了, 且顺序不乱。
        let ids = pages.flatMap { $0.columns.map(\.passageId) }
        var seen: [String] = []
        for id in ids where seen.last != id { seen.append(id) }
        XCTAssertEqual(seen, chapter.passages.map(\.id))
        // 除挤进来的标点, 任何一列不超过 18 字。
        for column in pages.flatMap(\.columns) {
            let body = column.cells.filter { !$0.isPunctuation }.count
            XCTAssertLessThanOrEqual(body, 18)
            XCTAssertLessThanOrEqual(column.cells.count, 19)
        }
    }

    func testHanNumerals() {
        XCTAssertEqual(HanNumeral.string(1), "一")
        XCTAssertEqual(HanNumeral.string(10), "十")
        XCTAssertEqual(HanNumeral.string(17), "十七")
        XCTAssertEqual(HanNumeral.string(20), "二十")
        XCTAssertEqual(HanNumeral.string(46), "四十六")
        XCTAssertEqual(HanNumeral.string(100), "一百")
        XCTAssertEqual(HanNumeral.string(105), "一百零五")
        XCTAssertEqual(HanNumeral.string(110), "一百一十")
        XCTAssertEqual(HanNumeral.string(1200), "一千二百")
        XCTAssertEqual(HanNumeral.string(1005), "一千零五")
        XCTAssertEqual(HanNumeral.ordinal(17), "第十七章")
        XCTAssertEqual(HanNumeral.ordinal(3, unit: "卷"), "第三卷")
    }
}
