import XCTest
@testable import ZixiaoCalendar

/// 图鉴详情 (T54): 七十二候 / 花信 / 时辰的详细介绍字段。
/// 字数按 `String.count` (含标点) 计; 数据侧另按去标点口径校过, 两种口径都落在区间内。
final class CultureDetailTests: XCTestCase {
    /// 日课 App, 不是黄历; 也不用语气词。
    private let bannedFragments = ["吉", "凶", "运势", "占卜", "算命", "呢", "哦"]

    private func assertLength(_ s: String?, _ range: ClosedRange<Int>, _ tag: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard let s, !s.isEmpty else {
            return XCTFail("\(tag) 为空", file: file, line: line)
        }
        XCTAssertTrue(range.contains(s.count), "\(tag) 字数 \(s.count) 不在 \(range)", file: file, line: line)
        for w in bannedFragments where s.contains(w) {
            XCTFail("\(tag) 含「\(w)」", file: file, line: line)
        }
    }

    private func assertPoems(_ poems: [ZXPoemQuote?], total: Int, _ tag: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let present = poems.compactMap { $0 }
        XCTAssertGreaterThanOrEqual(Double(present.count) / Double(total), 0.9,
                                    "\(tag) poem 覆盖率 \(present.count)/\(total) 低于 90%", file: file, line: line)
        for p in present {
            XCTAssertFalse(p.text.isEmpty, "\(tag) poem.text 为空", file: file, line: line)
            XCTAssertFalse(p.author.isEmpty, "\(tag)「\(p.text)」缺作者", file: file, line: line)
            XCTAssertFalse(p.title.isEmpty, "\(tag)「\(p.text)」缺篇名", file: file, line: line)
            XCTAssertFalse(p.title.contains("《"), "\(tag) 篇名不带书名号: \(p.title)", file: file, line: line)
            XCTAssertTrue(p.text.hasSuffix("。") || p.text.hasSuffix("？") || p.text.hasSuffix("！"),
                          "\(tag) 诗句应带标点收尾: \(p.text)", file: file, line: line)
        }
    }

    func testHouDetails() {
        let all = ZXCalendar.allHou
        XCTAssertEqual(all.count, 72)
        let books: Set<String> = ["月令七十二候集解", "礼记·月令", "逸周书·时训解"]
        for h in all {
            let tag = "第\(h.index)候「\(h.name)」"
            XCTAssertFalse(h.source?.isEmpty ?? true, "\(tag) source 为空")
            XCTAssertTrue(h.sourceBook.map(books.contains) ?? false, "\(tag) sourceBook = \(h.sourceBook ?? "nil")")
            assertLength(h.explain, 120...200, "\(tag) explain")
            assertLength(h.life, 60...120, "\(tag) life")
        }
        assertPoems(all.map(\.poem), total: 72, "七十二候")
    }

    func testHuaxinDetails() {
        let all = ZXCalendar.allHuaxin
        XCTAssertEqual(all.count, 24)
        for h in all {
            let tag = "花信 \(h.index)「\(h.flower)」"
            assertLength(h.intro, 100...160, "\(tag) intro")
            assertLength(h.life, 60...100, "\(tag) life")
            // source 允许留空 (花信风出处未能逐花考定), 有则不能是空串。
            if let s = h.source { XCTAssertFalse(s.isEmpty, "\(tag) source 是空串, 应省略") }
        }
        assertPoems(all.map(\.poem), total: 24, "花信")
    }

    func testShichenDetails() {
        let all = ZXCalendar.allShichen(on: ZXCivilDate(year: 2026, month: 10, day: 1))
        XCTAssertEqual(all.count, 12)
        for s in all {
            let tag = "\(s.branch)时"
            assertLength(s.explain, 100...160, "\(tag) explain")
            assertLength(s.health, 60...100, "\(tag) health")
        }
        assertPoems(all.map(\.poem), total: 12, "时辰")
        // 查询某一时刻得到的时辰也带详情。
        let noon = ZXCalendar.shichen(at: ZXCivilDate(year: 2026, month: 10, day: 1)
            .date(hour: 12, timeZone: ZXCalendar.defaultTimeZone))
        XCTAssertEqual(noon.branch, "午")
        XCTAssertNotNil(noon.explain)
        XCTAssertEqual(noon.poem?.author, "李绅")
    }

    /// 旧数据 (qizen / Flutter 版同一 schema, 没有新字段) 照样能解, 新字段为 nil。
    func testLegacyItemsDecodeWithoutNewFields() throws {
        let dec = JSONDecoder()
        let hou = try dec.decode(ZXHou.self, from: Data("""
            {"index": 1, "term": "立春", "order": 1, "name": "东风解冻", "text": "春风自东而来。"}
            """.utf8))
        XCTAssertEqual(hou.name, "东风解冻")
        XCTAssertNil(hou.source); XCTAssertNil(hou.sourceBook); XCTAssertNil(hou.explain)
        XCTAssertNil(hou.life); XCTAssertNil(hou.poem)

        let hx = try dec.decode(ZXHuaxin.self, from: Data("""
            {"index": 1, "term": "小寒", "order": 1, "flower": "梅花", "note": "岁末先开。"}
            """.utf8))
        XCTAssertEqual(hx.flower, "梅花")
        XCTAssertNil(hx.intro); XCTAssertNil(hx.source); XCTAssertNil(hx.life); XCTAssertNil(hx.poem)

        let sc = try dec.decode(ZXShichenEntry.self, from: Data("""
            {"branch": "子", "ancient": "夜半", "start": 23, "end": 1, "gloss": "夜色最深。"}
            """.utf8))
        XCTAssertEqual(sc.branch, "子")
        XCTAssertNil(sc.explain); XCTAssertNil(sc.health); XCTAssertNil(sc.poem)
    }

    func testPoemQuoteDecodes() throws {
        let hou = try JSONDecoder().decode(ZXHou.self, from: Data("""
            {"index": 1, "term": "立春", "order": 1, "name": "东风解冻", "text": "t",
             "poem": {"text": "便觉眼前生意满，东风吹水绿参差。", "author": "张栻", "title": "立春偶成"}}
            """.utf8))
        XCTAssertEqual(hou.poem, ZXPoemQuote(text: "便觉眼前生意满，东风吹水绿参差。", author: "张栻", title: "立春偶成"))
    }
}
