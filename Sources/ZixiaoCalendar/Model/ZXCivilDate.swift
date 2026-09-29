import Foundation

/// 一个「民用日」: 只有年月日, 不带时刻、不带时区。
///
/// 为什么单独要这个类型而不是直接用 `Date`: 历法里的「今天」是某个时区墙上日历的
/// 日子, 而 `Date` 是时间轴上的一个点。同一个 `Date` 在上海和旧金山是不同的日子;
/// 反过来, 节气 / 候 / 节日的推算只认年月日。先在边界上 (ZXCalendar 的 Date 入口)
/// 按注入的时区把 `Date` 落成 `ZXCivilDate`, 之后的推算就与时区、夏令时彻底无关。
public struct ZXCivilDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// 「2025-01-01」。
    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { iso }

    /// 解析「2025-01-01」; 格式不对返回 nil。
    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// 按 `timeZone` 的墙上日历取 `date` 落在哪一天。
    public init(_ date: Date, timeZone: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// 自 1970-01-01 起的日序 (可为负)。
    ///
    /// 用纯整数的前推格里历算法 (Howard Hinnant 的 days_from_civil), 不经 `Calendar`:
    /// 加减天数、算两日之差都不该碰时区, 否则夏令时那天会少一天或多一天
    /// (Flutter 版在 dailyLineFor 里专门为此改用 UTC 数日子, 这里从根上避免)。
    public var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public init(dayNumber z0: Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        self.init(year: y, month: m, day: d)
    }

    public func adding(days: Int) -> ZXCivilDate {
        ZXCivilDate(dayNumber: dayNumber + days)
    }

    /// `other` 到 `self` 相隔几天 (self 在后为正)。
    public func days(since other: ZXCivilDate) -> Int {
        dayNumber - other.dayNumber
    }

    /// 这一天在 `timeZone` 里 `hour:minute` 那一刻。
    public func date(hour: Int = 0, minute: Int = 0, timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let comps = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return cal.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    public static func < (lhs: ZXCivilDate, rhs: ZXCivilDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
