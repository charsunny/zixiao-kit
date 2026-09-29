import XCTest
@testable import ZixiaoDesign

/// 屏幕件里抽出来的纯逻辑: 验证码状态机、重发倒计时、混排网格排布。
final class CodeEntryStateTests: XCTestCase {
    func testTypingToCompletionFiresOnce() {
        var s = ZXCodeEntryState(length: 6)
        XCTAssertEqual(s.cursorIndex, 0)
        XCTAssertNil(s.update(text: "1"))
        XCTAssertNil(s.update(text: "12345"))
        XCTAssertEqual(s.cursorIndex, 5)
        XCTAssertEqual(s.update(text: "123456"), .completed("123456"))
        XCTAssertTrue(s.isComplete)
        XCTAssertNil(s.cursorIndex, "输满后没有光标")
        // 多打的一位被截掉, 码不变, 不再回调
        XCTAssertNil(s.update(text: "1234567"))
        XCTAssertEqual(s.code, "123456")
    }

    func testSanitizeKeepsOnlyDecimalDigits() {
        XCTAssertEqual(ZXCodeEntryState.sanitize("12a3 4-5", length: 6), "12345")
        XCTAssertEqual(ZXCodeEntryState.sanitize("１２３４５６", length: 6), "123456", "全角数字落成 ASCII")
        XCTAssertEqual(ZXCodeEntryState.sanitize("验证码 654321, 5 分钟内有效", length: 6), "654321")
        XCTAssertEqual(ZXCodeEntryState.sanitize("五六七", length: 6), "", "汉字数目不是验证码数字")
        XCTAssertEqual(ZXCodeEntryState(length: 4, code: "98765").code, "9876")
        XCTAssertEqual(ZXCodeEntryState(length: 0).length, 1)
    }

    func testPasteWholeCodeCompletes() {
        var s = ZXCodeEntryState()
        XCTAssertEqual(s.update(text: "您的验证码是 246810"), .completed("246810"))
    }

    func testDeleteBackwardReopensCompletion() {
        var s = ZXCodeEntryState(length: 4)
        s.update(text: "1234")
        XCTAssertNil(s.deleteBackward())
        XCTAssertEqual(s.code, "123")
        XCTAssertEqual(s.cursorIndex, 3)
        XCTAssertEqual(s.cell(at: 2), .filled("3"))
        XCTAssertEqual(s.cell(at: 3), .cursor)
        XCTAssertEqual(s.update(text: "1239"), .completed("1239"), "删一位再输满, 再回调一次")
        var empty = ZXCodeEntryState(length: 4)
        XCTAssertNil(empty.deleteBackward())
        XCTAssertEqual(empty.code, "")
    }

    func testVerifyingLocksInput() {
        var s = ZXCodeEntryState(length: 4)
        s.update(text: "1234")
        XCTAssertNil(s.transition(to: .verifying))
        XCTAssertFalse(s.acceptsInput)
        XCTAssertNil(s.update(text: "12"))
        XCTAssertEqual(s.code, "1234", "校验中改码, 回调出去的码就与屏幕不一致了")
        XCTAssertNil(s.transition(to: .verifying), "同阶段不算变化")
    }

    func testFailureClearsAndRemembersRejected() {
        var s = ZXCodeEntryState(length: 4)
        s.update(text: "1234")
        s.transition(to: .verifying)
        XCTAssertEqual(s.transition(to: .failed), .rejected)
        XCTAssertEqual(s.code, "", "失败即清空")
        XCTAssertEqual(s.rejected, "1234")
        XCTAssertTrue(s.acceptsInput)
        XCTAssertEqual(s.cursorIndex, 0)
        XCTAssertNil(s.update(text: "5"))
        XCTAssertNil(s.rejected, "重新动手即清掉错码")
        XCTAssertEqual(s.phase, .editing, "失败后重新输入回到编辑, 下一次失败才看得出变化")
        XCTAssertEqual(s.update(text: "5678"), .completed("5678"))
    }

    func testSuccessLocksInput() {
        var s = ZXCodeEntryState(length: 4)
        s.update(text: "1234")
        s.transition(to: .verifying)
        XCTAssertEqual(s.transition(to: .succeeded), .accepted)
        XCTAssertFalse(s.acceptsInput)
        XCTAssertNil(s.update(text: ""))
        XCTAssertEqual(s.code, "1234")
        XCTAssertEqual((0..<4).map { s.cell(at: $0) }, [.filled("1"), .filled("2"), .filled("3"), .filled("4")])
    }

    func testResendCountdownRoundsUp() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertEqual(ZXResendCountdown.remaining(until: now.addingTimeInterval(59.2), now: now), 60)
        XCTAssertEqual(ZXResendCountdown.remaining(until: now.addingTimeInterval(0.1), now: now), 1)
        XCTAssertEqual(ZXResendCountdown.remaining(until: now, now: now), 0)
        XCTAssertEqual(ZXResendCountdown.remaining(until: now.addingTimeInterval(-3), now: now), 0)
    }
}

final class BentoLayoutTests: XCTestCase {
    private func slots(_ sizes: [ZXBentoSize], _ columns: Int) -> [[Int]] {
        ZXBentoLayout.place(sizes: sizes, columns: columns).slots.map { [$0.column, $0.row, $0.columnSpan, $0.rowSpan] }
    }

    func testSmallsFillRowByRow() {
        let p = ZXBentoLayout.place(sizes: [.small, .small, .small, .small, .small], columns: 2)
        XCTAssertEqual(p.slots.map { [$0.column, $0.row] }, [[0, 0], [1, 0], [0, 1], [1, 1], [0, 2]])
        XCTAssertEqual(p.rows, 3)
    }

    func testLargeThenSmallsThenWide() {
        XCTAssertEqual(slots([.large, .small, .small, .wide], 2),
                       [[0, 0, 2, 2], [0, 2, 1, 1], [1, 2, 1, 1], [0, 3, 2, 1]])
        XCTAssertEqual(ZXBentoLayout.place(sizes: [.large, .small, .small, .wide], columns: 2).rows, 4)
    }

    func testSmallsBesideLargeInThreeColumns() {
        let p = ZXBentoLayout.place(sizes: [.large, .small, .small, .wide], columns: 3)
        XCTAssertEqual(p.slots.map { [$0.column, $0.row] }, [[0, 0], [2, 0], [2, 1], [0, 2]])
        XCTAssertEqual(p.rows, 3)
    }

    func testTallLeavesRoomBeside() {
        XCTAssertEqual(slots([.tall, .small, .small, .small], 2),
                       [[0, 0, 1, 2], [1, 0, 1, 1], [1, 1, 1, 1], [0, 2, 1, 1]])
    }

    /// 后来的小块回填前面留下的洞。
    func testBackfillsHoles() {
        // 横条 → 小 → 横条 (放不进第二行右格, 去第三行) → 小 (回填第二行右格)
        XCTAssertEqual(slots([.wide, .small, .wide, .small], 2),
                       [[0, 0, 2, 1], [0, 1, 1, 1], [0, 2, 2, 1], [1, 1, 1, 1]])
    }

    func testSpansClampToColumnCount() {
        XCTAssertEqual(slots([.large, .wide], 1), [[0, 0, 1, 2], [0, 2, 1, 1]])
        XCTAssertEqual(ZXBentoLayout.place(sizes: [.small], columns: 0).slots.first?.columnSpan, 1, "列数夹到至少 1")
    }

    func testEmpty() {
        let p = ZXBentoLayout.place(sizes: [], columns: 2)
        XCTAssertTrue(p.slots.isEmpty)
        XCTAssertEqual(p.rows, 0)
    }

    /// 不重叠、不出界: 随便一串大小, 每格最多被占一次。
    func testNoOverlap() {
        let sizes: [ZXBentoSize] = [.large, .tall, .small, .wide, .small, .large, .tall, .wide, .small, .small, .tall]
        for columns in 1...4 {
            let p = ZXBentoLayout.place(sizes: sizes, columns: columns)
            var seen = Set<[Int]>()
            for slot in p.slots {
                XCTAssertLessThanOrEqual(slot.column + slot.columnSpan, columns)
                XCTAssertLessThanOrEqual(slot.row + slot.rowSpan, p.rows)
                for r in slot.row..<(slot.row + slot.rowSpan) {
                    for c in slot.column..<(slot.column + slot.columnSpan) {
                        XCTAssertTrue(seen.insert([c, r]).inserted, "格 (\(c),\(r)) 被占两次, 列数 \(columns)")
                    }
                }
            }
        }
    }
}
