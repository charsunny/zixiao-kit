import XCTest
@testable import ZixiaoCalendar

/// 逐日对齐 Dart 金标: 2025-01-01 ~ 2027-12-31 每一天的全部字段。
final class CalendarFixtureTests: XCTestCase {
    func testEveryDayMatchesDartFixture() throws {
        let fixture = try Fixture.decode(CalendarFixture.self, "calendar-2025-2027")
        XCTAssertEqual(fixture.timeZone, "Asia/Shanghai")
        XCTAssertEqual(fixture.sampleHour, 12)
        // 三年无闰年, 365 × 3。条数不对说明导出脚本范围变了, 要先看脚本。
        XCTAssertEqual(fixture.days.count, 1095)

        var mismatches: [String] = []
        for expected in fixture.days {
            let civil = try XCTUnwrap(ZXCivilDate(iso: expected.gregorian))
            let actual = Self.row(ZXCalendar.day(civil))
            if actual != expected {
                mismatches.append("期望 \(expected)\n    实际 \(actual)")
            }
        }
        XCTAssertTrue(
            mismatches.isEmpty,
            "\(mismatches.count)/\(fixture.days.count) 天不一致, 前 10 条:\n" + mismatches.prefix(10).joined(separator: "\n")
        )
    }

    /// 走 Date 入口 (Asia/Shanghai 正午与当天 00:00 / 23:59) 应与民用日入口同一结果:
    /// 同一天无论几点查, 岁时信息都不该变。抽每月 1 日与 15 日。
    func testDateEntryIsStableWithinTheDay() throws {
        let fixture = try Fixture.decode(CalendarFixture.self, "calendar-2025-2027")
        let tz = ZXCalendar.defaultTimeZone
        for expected in fixture.days where expected.gregorian.hasSuffix("-01") || expected.gregorian.hasSuffix("-15") {
            let civil = try XCTUnwrap(ZXCivilDate(iso: expected.gregorian))
            for (h, m) in [(0, 0), (12, 0), (23, 59)] {
                let date = civil.date(hour: h, minute: m, timeZone: tz)
                XCTAssertEqual(Self.row(ZXCalendar.day(for: date)), expected, "\(expected.gregorian) \(h):\(m)")
            }
        }
    }

    /// 时区可注入: 上海 2025-01-01 00:30 在 UTC 仍是 2024-12-31。
    func testTimeZoneInjection() throws {
        let shanghai = ZXCivilDate(year: 2025, month: 1, day: 1).date(hour: 0, minute: 30, timeZone: ZXCalendar.defaultTimeZone)
        XCTAssertEqual(ZXCalendar.day(for: shanghai).gregorian.iso, "2025-01-01")
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(ZXCalendar.day(for: shanghai, timeZone: utc).gregorian.iso, "2024-12-31")
    }

    /// lunar-swift 内部有静态缓存, 内核靠锁保证并发安全; 多线程同时算不能崩、结果要一致。
    func testConcurrentAccessIsSafe() {
        let base = ZXCivilDate(year: 2026, month: 1, day: 1)
        let serial = (0..<64).map { ZXCalendar.day(base.adding(days: $0 * 11)) }
        var parallel = [ZXDay?](repeating: nil, count: 64)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 64) { i in
            let d = ZXCalendar.day(base.adding(days: i * 11))
            lock.lock(); parallel[i] = d; lock.unlock()
        }
        XCTAssertEqual(parallel.compactMap { $0 }, serial)
    }

    static func row(_ d: ZXDay) -> CalendarFixture.DayRow {
        CalendarFixture.DayRow(
            gregorian: d.gregorian.iso,
            lunar: .init(year: d.lunar.year, month: d.lunar.month, day: d.lunar.day, isLeap: d.lunar.isLeap, label: d.lunar.label),
            ganzhi: .init(year: d.ganzhi.year, month: d.ganzhi.month, day: d.ganzhi.day),
            term: .init(name: d.term.name, index: d.term.index),
            isTermDay: d.isTermDay,
            nextTerm: d.nextTerm.name,
            daysToNextTerm: d.daysToNextTerm,
            hou: .init(index: d.hou.index, term: d.hou.term, order: d.hou.order, name: d.hou.name),
            huaxin: d.huaxin.map { .init(index: $0.index, term: $0.term, order: $0.order, flower: $0.flower) },
            festivalsWithin7Days: d.festivalIDsWithin7Days
        )
    }
}
