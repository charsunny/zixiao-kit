import XCTest
@testable import ZixiaoCalendar

/// 历注逐日对齐 Dart 金标 (Fixtures/almanac-2026.json): 2026 全年每天的宜忌、建除、值神、冲煞、
/// 神方、二十八宿、彭祖百忌, 以及十二时辰的干支 / 值神 / 吉凶 / 宜忌 —— 全部逐字段、按顺序相等。
final class AlmanacFixtureTests: XCTestCase {
    func testEveryDayMatchesDartFixture() throws {
        let fixture = try Fixture.decode(AlmanacFixture.self, "almanac-2026")
        XCTAssertEqual(fixture.timeZone, "Asia/Shanghai")
        XCTAssertEqual(fixture.sampleHour, 12)
        // 2026 非闰年。条数不对说明导出脚本范围变了, 要先看脚本。
        XCTAssertEqual(fixture.days.count, 365)

        var dayMismatches: [String] = []
        var hourMismatches: [String] = []
        for expected in fixture.days {
            let civil = try XCTUnwrap(ZXCivilDate(iso: expected.gregorian))
            let notes = ZXCalendar.almanacNotes(civil)
            XCTAssertEqual(notes.date, civil)
            let actual = Self.row(notes)
            // 日级字段与时辰分开报, 出错时一眼看出是哪一层。
            if Self.dayPart(actual) != Self.dayPart(expected) {
                dayMismatches.append("期望 \(expected)\n    实际 \(actual)")
            }
            for (e, a) in zip(expected.hours, actual.hours) where e != a {
                hourMismatches.append("\(expected.gregorian) 期望 \(e)\n    实际 \(a)")
            }
            XCTAssertEqual(actual.hours.count, expected.hours.count, expected.gregorian)
        }
        XCTAssertTrue(
            dayMismatches.isEmpty,
            "\(dayMismatches.count)/\(fixture.days.count) 天日级历注不一致, 前 10 条:\n"
                + dayMismatches.prefix(10).joined(separator: "\n")
        )
        XCTAssertTrue(
            hourMismatches.isEmpty,
            "\(hourMismatches.count)/\(fixture.days.count * 12) 个时辰不一致, 前 10 条:\n"
                + hourMismatches.prefix(10).joined(separator: "\n")
        )
    }

    /// Date 入口: 当天 00:00 / 12:00 / 23:59 (上海) 查到同一份历注 —— 晚子时不换日。
    func testDateEntryIsStableWithinTheDay() throws {
        let tz = ZXCalendar.defaultTimeZone
        for civil in [ZXCivilDate(year: 2026, month: 1, day: 1), ZXCivilDate(year: 2026, month: 9, day: 29),
                      ZXCivilDate(year: 2026, month: 12, day: 31)] {
            let expected = ZXCalendar.almanacNotes(civil)
            for (h, m) in [(0, 0), (12, 0), (23, 59)] {
                XCTAssertEqual(ZXCalendar.almanacNotes(for: civil.date(hour: h, minute: m, timeZone: tz)), expected,
                               "\(civil) \(h):\(m)")
            }
        }
    }

    /// 时区可注入: 上海 2026-01-01 00:30 在 UTC 仍是 2025-12-31。
    func testTimeZoneInjection() throws {
        let shanghai = ZXCivilDate(year: 2026, month: 1, day: 1).date(hour: 0, minute: 30, timeZone: ZXCalendar.defaultTimeZone)
        XCTAssertEqual(ZXCalendar.almanacNotes(for: shanghai).date.iso, "2026-01-01")
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(ZXCalendar.almanacNotes(for: shanghai, timeZone: utc).date.iso, "2025-12-31")
    }

    /// 十二时辰按子 → 亥排, branchIndex 与 ZXCalendar.allShichen 对得上 (界面按同一下标取当前时辰)。
    func testHoursAreOrderedLikeShichen() {
        let civil = ZXCivilDate(year: 2026, month: 9, day: 29)
        let notes = ZXCalendar.almanacNotes(civil)
        let shichen = ZXCalendar.allShichen(on: civil)
        XCTAssertEqual(notes.hours.map(\.branch), shichen.map(\.branch))
        XCTAssertEqual(notes.hours.map(\.branchIndex), Array(0..<12))
        XCTAssertEqual(notes.hour(branchIndex: 6)?.branch, "午")
        XCTAssertNil(notes.hour(branchIndex: 12))
    }

    /// 与岁时快照共用一把锁: 多线程同时算历注与岁时不能崩、结果要一致。
    func testConcurrentAccessIsSafe() {
        let base = ZXCivilDate(year: 2026, month: 1, day: 1)
        let serial = (0..<64).map { ZXCalendar.almanacNotes(base.adding(days: $0 * 5)) }
        var parallel = [ZXAlmanacNotes?](repeating: nil, count: 64)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 64) { i in
            let notes = ZXCalendar.almanacNotes(base.adding(days: i * 5))
            _ = ZXCalendar.day(base.adding(days: i * 7)) // 交错走另一条快照路径
            lock.lock(); parallel[i] = notes; lock.unlock()
        }
        XCTAssertEqual(parallel.compactMap { $0 }, serial)
    }

    /// 一天建一次 Lunar, 十二时辰查表得出。量一个月 (31 天) 的基线, 供回归对比。
    func testMonthPerformance() {
        let base = ZXCivilDate(year: 2026, month: 1, day: 1)
        measure {
            for i in 0..<31 { _ = ZXCalendar.almanacNotes(base.adding(days: i)) }
        }
    }

    // MARK: - 映射成 fixture 的形状

    private static func row(_ n: ZXAlmanacNotes) -> AlmanacFixture.DayRow {
        AlmanacFixture.DayRow(
            gregorian: n.date.iso,
            yi: n.suitable,
            ji: n.avoid,
            officer: n.dayOfficer,
            tianShen: n.dutyGod,
            huangDao: n.dutyGodPath.label,
            auspicious: n.dutyGodPath.isAuspicious,
            clashZodiac: n.clash.zodiac,
            sha: n.clash.shaDirection,
            deities: .init(xi: n.deities.joy, cai: n.deities.wealth, fu: n.deities.fortune),
            xiu: .init(name: n.mansion.name, zheng: n.mansion.element, animal: n.mansion.animal, luck: n.mansion.luck),
            pengZu: .init(gan: n.pengZu.stem, zhi: n.pengZu.branch),
            hours: n.hours.map {
                .init(branch: $0.branch, ganZhi: $0.ganZhi, tianShen: $0.dutyGod,
                      auspicious: $0.isAuspicious, yi: $0.suitable, ji: $0.avoid)
            }
        )
    }

    /// 去掉时辰的日级部分。
    private static func dayPart(_ r: AlmanacFixture.DayRow) -> AlmanacFixture.DayRow {
        AlmanacFixture.DayRow(
            gregorian: r.gregorian, yi: r.yi, ji: r.ji, officer: r.officer, tianShen: r.tianShen,
            huangDao: r.huangDao, auspicious: r.auspicious, clashZodiac: r.clashZodiac, sha: r.sha,
            deities: r.deities, xiu: r.xiu, pengZu: r.pengZu, hours: []
        )
    }
}
