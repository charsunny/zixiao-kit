import Foundation

/// A Shanghai calendar day selects one position in the entire genre, including long poetry catalogs.
enum DailyRotation {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
    static func dayNumber(_ date: Date) -> Int {
        return calendar.ordinality(of: .day, in: .era, for: calendar.startOfDay(for: date)) ?? 0
    }

    static func index(on date: Date, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return dayNumber(date) % count
    }
}
