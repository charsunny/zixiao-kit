import XCTest
@testable import ZixiaoCalendar

/// 十二时辰 × 起止前后一分钟 = 48 个边界时刻, 对齐 Dart 金标。
final class ShichenTests: XCTestCase {
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func testShichenBoundariesMatchDartFixture() throws {
        let fixture = try Fixture.decode(ShichenFixture.self, "shichen")
        XCTAssertEqual(fixture.probes.count, 48)
        for p in fixture.probes {
            let date = try XCTUnwrap(iso.date(from: p.iso), p.iso)
            let s = ZXCalendar.shichen(at: date)
            let tag = "\(p.of)时 \(p.probe) \(p.time)"
            XCTAssertEqual(s.branch, p.branch, tag)
            XCTAssertEqual(s.ancientName, p.ancientName, tag)
            XCTAssertEqual(s.geng.map { ShichenFixture.Probe.Geng(index: $0.index, name: $0.name) }, p.geng, tag)
            // 起止必须包住查询时刻, 且恰好两小时 (上海无夏令时)。
            XCTAssertLessThanOrEqual(s.start, date, tag)
            XCTAssertGreaterThan(s.end, date, tag)
            XCTAssertEqual(s.end.timeIntervalSince(s.start), 7200, tag)
        }
    }

    func testZiShichenSpansMidnight() throws {
        let tz = ZXCalendar.defaultTimeZone
        let day = ZXCivilDate(year: 2026, month: 9, day: 28)
        // 23:30 的子时: 起于当日 23:00, 止于次日 01:00。
        let late = ZXCalendar.shichen(at: day.date(hour: 23, minute: 30, timeZone: tz))
        XCTAssertEqual(late.branch, "子")
        XCTAssertEqual(late.start, day.date(hour: 23, timeZone: tz))
        XCTAssertEqual(late.end, day.adding(days: 1).date(hour: 1, timeZone: tz))
        XCTAssertEqual(late.rangeLabel, "23:00–01:00")
        // 00:30 的子时: 起于前一日 23:00。
        let early = ZXCalendar.shichen(at: day.date(hour: 0, minute: 30, timeZone: tz))
        XCTAssertEqual(early.start, day.adding(days: -1).date(hour: 23, timeZone: tz))
        XCTAssertEqual(early.end, day.date(hour: 1, timeZone: tz))
        XCTAssertEqual(early.geng?.name, "三更")
    }

    func testAllShichenOfADay() {
        let tz = ZXCalendar.defaultTimeZone
        let day = ZXCivilDate(year: 2026, month: 9, day: 28)
        let all = ZXCalendar.allShichen(on: day, timeZone: tz)
        XCTAssertEqual(all.map(\.branch), ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"])
        XCTAssertEqual(all.first?.start, day.adding(days: -1).date(hour: 23, timeZone: tz))
        XCTAssertEqual(all.last?.end, day.date(hour: 23, timeZone: tz))
        // 相邻首尾相接, 一天正好铺满。
        for (a, b) in zip(all, all.dropFirst()) { XCTAssertEqual(a.end, b.start) }
        XCTAssertEqual(all.compactMap(\.geng).map(\.name), ["三更", "四更", "五更", "一更", "二更"])
    }
}
