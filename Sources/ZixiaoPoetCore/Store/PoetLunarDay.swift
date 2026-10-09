//  PoetLunarDay.swift — 今天是农历哪一天 (ZixiaoCalendar 的薄适配)
//
//  年谱纪年全是夏历 (「某年七月十六日」不是公历), 所以「旧日此时」必须拿农历月日去比。
//  农历推算交给 ZixiaoCalendar (`ZXCalendar.day(for:)`, 东八区); 这里只补一个今日页标题要的
//  「农历年干支」—— `ZXGanzhi.year` 按立春换年 (术数口径), 而页面上「丙午年 · 腊月廿三」
//  要跟农历年走 (正月初一换年), 两者在立春与春节之间会差一年。

import Foundation
import ZixiaoCalendar

public struct PoetLunarDay: Sendable, Hashable {
    /// 农历日 (月为正数, 闰月看 `isLeap`)。
    public let lunar: ZXLunarDate
    /// 农历年干支, 如「丙午」(正月初一换年)。
    public let sexagenary: String

    public var month: Int { lunar.month }
    public var day: Int { lunar.day }
    public var isLeapMonth: Bool { lunar.isLeap }
    /// 「九月初三」「闰六月初一」。
    public var label: String { lunar.label }

    public init(lunar: ZXLunarDate) {
        self.lunar = lunar
        self.sexagenary = Self.sexagenary(ofLunarYear: lunar.year)
    }

    /// `date` 在东八区那一天的农历。
    public static func of(_ date: Date = .now,
                          timeZone: TimeZone = ZXCalendar.defaultTimeZone) -> PoetLunarDay {
        PoetLunarDay(lunar: ZXCalendar.day(for: date, timeZone: timeZone).lunar)
    }

    private static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]

    /// 公元 4 年为甲子; 农历年号 (以正月初一换年) 直接按 60 取模。
    static func sexagenary(ofLunarYear year: Int) -> String {
        let offset = year - 4
        return stems[((offset % 10) + 10) % 10] + branches[((offset % 12) + 12) % 12]
    }
}
