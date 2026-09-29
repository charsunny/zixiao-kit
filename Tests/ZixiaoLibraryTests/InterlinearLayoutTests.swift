import XCTest
@testable import ZixiaoLibrary

/// 竖排白话的两种排法 (双行夹注、白话列) 与段落定位, 都是 `ClassicLayout` 的纯函数。
final class InterlinearLayoutTests: XCTestCase {
    private func texts(_ cells: [ClassicCell]) -> String { cells.map(\.original).joined() }

    /// 末列有空: 夹注从原文之后的空处起 (半格一行), 最后一段两行对半、右行多一字。
    func testNotesContinueInLastColumnAndSplitEvenly() throws {
        let passage = Passage(id: "p", text: "学而时习之", plain: "学了又按时温习")
        let pages = ClassicLayout.paginate(passages: [passage], charsPerColumn: 10, columnsPerPage: 5, plain: .interlinear)
        let columns = pages.flatMap(\.columns)
        XCTAssertEqual(columns.count, 1, "七个小字装得进原文列下半截, 不另起列")
        let notes = try XCTUnwrap(columns[0].notes)
        XCTAssertEqual(notes.startRow, 5 * ClassicLayout.noteRowsPerCell)
        XCTAssertEqual(texts(notes.right), "学了又按")
        XCTAssertEqual(texts(notes.left), "时温习")
        XCTAssertEqual(notes.text, "学了又按时温习", "读序: 先右后左")
        XCTAssertEqual(columns[0].text, "学而时习之", "列的 text 仍只是原文")
    }

    /// 放不下: 本列右行、左行各占满空位, 余下的另起整列。
    func testNotesFillRightLineFirstThenWholeColumns() {
        let passage = Passage(id: "p", text: "道可道", plain: "一二三四五六七八九十甲乙")
        let columns = ClassicLayout.paginate(passages: [passage], charsPerColumn: 2, columnsPerPage: 9, plain: .interlinear)
            .flatMap(\.columns)
        XCTAssertEqual(columns.map(\.text), ["道可", "道", ""])
        XCTAssertNil(columns[0].notes)
        XCTAssertEqual(columns[1].notes?.startRow, 2)
        XCTAssertEqual(columns[1].notes.map { texts($0.right) }, "一二")
        XCTAssertEqual(columns[1].notes.map { texts($0.left) }, "三四")
        XCTAssertEqual(columns[2].notes?.startRow, 0)
        XCTAssertEqual(columns[2].notes.map { texts($0.right) }, "五六七八")
        XCTAssertEqual(columns[2].notes.map { texts($0.left) }, "九十甲乙")
        XCTAssertTrue(columns.allSatisfy { $0.passageId == "p" && $0.role == .text })
    }

    /// 原文列正好满: 夹注另起一列, 从列首起。标点不居行首: 左行首的标点挤进右行末,
    /// 下一列首的标点挤进本列左行末。
    func testNotesKeepPunctuationOffLineHeads() {
        let even = ClassicLayout.paginate(passages: [Passage(id: "a", text: "道可", plain: "一二三四，五六")],
                                          charsPerColumn: 2, columnsPerPage: 9, plain: .interlinear).flatMap(\.columns)
        XCTAssertEqual(even.count, 2)
        XCTAssertEqual(even[1].notes?.startRow, 0)
        XCTAssertEqual(even[1].notes.map { texts($0.right) }, "一二三四，")
        XCTAssertEqual(even[1].notes.map { texts($0.left) }, "五六")
        XCTAssertEqual(even[1].notes?.right.last?.glyph, "︐", "小字的标点同样换直排形")

        let full = ClassicLayout.paginate(passages: [Passage(id: "b", text: "道可", plain: "一二三四五六七八，九")],
                                          charsPerColumn: 2, columnsPerPage: 9, plain: .interlinear).flatMap(\.columns)
        XCTAssertEqual(full.count, 3)
        XCTAssertEqual(full[1].notes.map { texts($0.right) }, "一二三四")
        XCTAssertEqual(full[1].notes.map { texts($0.left) }, "五六七八，")
        XCTAssertEqual(full[2].notes.map { texts($0.right) }, "九")
        XCTAssertEqual(full[2].notes?.left, [])
    }

    /// 白话列 (竖排「对照」): 另起列, 单行小字, 一列装两倍的字; 标点同样不居列首。
    func testPlainColumnsStartNewColumnsWithDoubleCapacity() {
        let passage = Passage(id: "p", text: "学而", plain: "一二三四五六七八九")
        let columns = ClassicLayout.paginate(passages: [passage], charsPerColumn: 4, columnsPerPage: 9, plain: .columns)
            .flatMap(\.columns)
        XCTAssertEqual(columns.map(\.text), ["学而", "一二三四五六七八", "九"])
        XCTAssertEqual(columns.map(\.role), [.text, .plain, .plain])
        XCTAssertTrue(columns.allSatisfy { $0.notes == nil })
    }

    /// 不排白话 (默认) 与旧版式逐列相同; 没有白话的段落在三种排法下都一样。
    func testNoPlainIsUnchangedAndPassagesWithoutPlainAreUnaffected() throws {
        let book = try JSONDecoder().decode(Book.self, from: Fixtures.data("lunyu.json"))
        let chapter = try XCTUnwrap(book.chapter(id: "17"))
        let legacy = ClassicLayout.paginate(passages: chapter.passages, charsPerColumn: 18, columnsPerPage: 8)
        for plain in [ClassicPlainLayout.none, .interlinear, .columns] {
            XCTAssertEqual(ClassicLayout.paginate(passages: chapter.passages, charsPerColumn: 18, columnsPerPage: 8,
                                                  plain: plain), legacy)
        }
        let withPlain = [Passage(id: "x", text: "学而时习之", plain: "学了又按时温习")]
        XCTAssertEqual(ClassicLayout.paginate(passages: withPlain, charsPerColumn: 10, columnsPerPage: 5, plain: .none),
                       ClassicLayout.paginate(passages: [Passage(id: "x", text: "学而时习之")], charsPerColumn: 10,
                                              columnsPerPage: 5))
    }

    /// 段落定位: 夹注把后面的段落推到下一页, 定位跟着走; 高亮取本页属于该段的所有列 (含只有夹注的列)。
    func testLocatingPassagesAcrossNotePages() {
        let passages = [
            Passage(id: "a", text: "道可道非常道", plain: "一二三四五六七八九十甲乙丙丁戊己"),
            Passage(id: "b", text: "名可名"),
        ]
        let plainPages = ClassicLayout.paginate(passages: passages, charsPerColumn: 3, columnsPerPage: 3)
        XCTAssertEqual(ClassicLayout.page(containing: "b", in: plainPages), 0)
        let pages = ClassicLayout.paginate(passages: passages, charsPerColumn: 3, columnsPerPage: 3, plain: .interlinear)
        // a: 两列原文 (满) + 16 个小字 → 每列 6 行两行共 12 字, 两列夹注; b 被挤到第二页。
        XCTAssertEqual(pages.map { $0.columns.map(\.passageId) }, [["a", "a", "a"], ["a", "b"]])
        XCTAssertEqual(ClassicLayout.page(containing: "b", in: pages), 1)
        XCTAssertEqual(ClassicLayout.page(containing: "a", in: pages), 0)
        XCTAssertEqual(pages[0].columnIndices(of: "a"), [0, 1, 2])
        XCTAssertEqual(pages[1].columnIndices(of: "a"), [0])
        XCTAssertEqual(pages[1].columnIndices(of: "b"), [1])
        XCTAssertEqual(pages[1].columnIndices(of: "zz"), [])
    }

    /// 切分的不变量: 读序拼回原白话 (去空白), 每行不超过空位 + 1 (挤进来的标点)。
    func testRunsPreserveTextAndCapacity() {
        let plain = "孔子说：学了又按时温习，不也很愉快吗？有朋友从远方来，不也很快乐吗？别人不了解我，我却不恼怒，不也是君子吗？"
        for perColumn in 1...12 {
            for used in 0..<perColumn {
                let cells = ClassicLayout.cells(of: plain, passageId: "p")
                let runs = ClassicLayout.interlinearRuns(cells, rowsPerColumn: perColumn * 2, firstStartRow: used * 2)
                XCTAssertEqual(runs.map(\.text).joined(), plain, "perColumn \(perColumn) used \(used)")
                for run in runs {
                    let capacity = perColumn * 2 - run.startRow
                    XCTAssertLessThanOrEqual(run.right.count, capacity + 1)
                    XCTAssertLessThanOrEqual(run.left.count, capacity + 1)
                    // 右行先读, 不短于左行; 左行至多多出一个挤进来的标点。
                    XCTAssertGreaterThanOrEqual(run.right.count + 1, run.left.count)
                    if run.left.count > run.right.count { XCTAssertEqual(run.left.last?.isPunctuation, true) }
                }
                XCTAssertEqual(runs.dropFirst().map(\.startRow), Array(repeating: 0, count: max(runs.count - 1, 0)))
            }
        }
    }
}
