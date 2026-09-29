import XCTest
@testable import ZixiaoCalendar

final class EraNamingTests: XCTestCase {
    func testEraNameSamples() {
        let era = EraNaming(style: .eraName)
        XCTAssertEqual(era.label(1082), "元丰五年")
        XCTAssertEqual(era.label(1078), "元丰元年")
        XCTAssertEqual(era.label(1101), "建中靖国元年")
        XCTAssertEqual(era.label(1102), "崇宁元年")
        XCTAssertEqual(era.label(627), "贞观元年")
        XCTAssertEqual(era.eraName(of: 1082), "元丰")
    }

    func testStyles() {
        XCTAssertEqual(EraNaming(style: .gregorian).label(1082), "1082年")
        XCTAssertEqual(EraNaming(style: .eraNameApprox).label(1082), "约元丰五年")
    }

    /// 表外与超出数字表的年份回落到公元纪年 (与 PoetKit 行为一致)。
    func testFallbacks() {
        let era = EraNaming(style: .eraName)
        XCTAssertEqual(era.label(600), "600年")      // 早于武德
        XCTAssertEqual(era.label(735), "735年")      // 开元二十三年, 超出「二十二」
        XCTAssertNil(era.eraName(of: 600))
    }

    func testStyleDecodesFromIdentityStrings() throws {
        let styles = try JSONDecoder().decode([EraNaming.Style].self, from: Data(#"["era-name","gregorian","era-name-approx"]"#.utf8))
        XCTAssertEqual(styles, [.eraName, .gregorian, .eraNameApprox])
    }
}

final class LeapMonthTests: XCTestCase {
    /// 2025 年闰六月: 2025-07-25 闰六月初一 … 2025-08-22 闰六月廿九, 2025-08-23 七月初一。
    func testLeapSixthMonth2025() {
        let first = ZXCalendar.day(ZXCivilDate(year: 2025, month: 7, day: 25)).lunar
        XCTAssertEqual(first.month, 6)
        XCTAssertEqual(first.day, 1)
        XCTAssertTrue(first.isLeap)
        XCTAssertEqual(first.label, "闰六月初一")

        let last = ZXCalendar.day(ZXCivilDate(year: 2025, month: 8, day: 22)).lunar
        XCTAssertTrue(last.isLeap)
        XCTAssertEqual(last.label, "闰六月廿九")

        let seventh = ZXCalendar.day(ZXCivilDate(year: 2025, month: 8, day: 23)).lunar
        XCTAssertEqual(seventh.month, 7)
        XCTAssertEqual(seventh.day, 1)
        XCTAssertFalse(seventh.isLeap)

        // 正六月不是闰月。
        let regular = ZXCalendar.day(ZXCivilDate(year: 2025, month: 6, day: 25)).lunar
        XCTAssertEqual(regular.month, 6)
        XCTAssertEqual(regular.day, 1)
        XCTAssertFalse(regular.isLeap)
    }

    /// 闰月不过节: 2025 闰六月里整月都不该匹配到按农历六月定的节日 (现表里没有六月节, 用七夕反证 —— 七月初七只出现一次)。
    func testFestivalsIgnoreLeapMonth() {
        let start = ZXCivilDate(year: 2025, month: 7, day: 20)
        let events = ZXCalendar.festivals(within: 60, from: start)
        let qixi = events.filter { $0.festival?.id == "qixi" }
        XCTAssertEqual(qixi.map(\.date.iso), ["2025-08-29"])
    }
}

final class CultureDataTests: XCTestCase {
    func testTablesAreComplete() {
        XCTAssertEqual(ZXCalendar.allHou.count, 72)
        XCTAssertEqual(ZXCalendar.allHou.map(\.index), Array(1...72))
        XCTAssertEqual(ZXCalendar.allHuaxin.count, 24)
        XCTAssertEqual(ZXCalendar.huaxinTerms, ["小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨"])
        XCTAssertEqual(ZXCalendar.hou(1)?.name, "东风解冻")
        XCTAssertNil(ZXCalendar.hou(0))
        XCTAssertNil(ZXCalendar.hou(73))
        // 候的编号与节气编号互相推得出: index = 节气序 × 3 + 候序。
        for h in ZXCalendar.allHou {
            XCTAssertEqual(ZXSolarTerm(name: h.term).map { $0.index * 3 + h.order }, h.index, h.name)
        }
        XCTAssertEqual(ZXCalendar.allFestivals.first { $0.id == "hanshi" }?.offsetDays, -2)
        XCTAssertEqual(ZXCalendar.allFestivals.first { $0.id == "chuxi" }?.lunarDay, -1)
        XCTAssertNotNil(ZXCalendar.termVerse("立春"))
    }

    func testCivilDateArithmetic() {
        let d = ZXCivilDate(year: 2024, month: 2, day: 28)
        XCTAssertEqual(d.adding(days: 1).iso, "2024-02-29")
        XCTAssertEqual(d.adding(days: 2).iso, "2024-03-01")
        XCTAssertEqual(ZXCivilDate(year: 2028, month: 1, day: 1).days(since: ZXCivilDate(year: 2025, month: 1, day: 1)), 1095)
        XCTAssertEqual(ZXCivilDate(year: 1970, month: 1, day: 1).dayNumber, 0)
        XCTAssertEqual(ZXCivilDate(dayNumber: -1).iso, "1969-12-31")
    }
}
