import Foundation

/// 农历日期。
public struct ZXLunarDate: Hashable, Sendable {
    /// 农历年 (以正月初一换年; 与干支纪年按立春换年不同)。
    public let year: Int
    /// 1–12。闰月也给正数, 另看 `isLeap` —— lunar 库用负数表示闰月, 那是库内约定,
    /// 不该漏到 API 上让每个调用方都记得取绝对值。
    public let month: Int
    public let day: Int
    public let isLeap: Bool
    /// 「闰六月初一」「腊月廿九」, 与 Flutter 版今日页同一写法 (lunar 库的 正 / 冬 / 腊 月名)。
    public let label: String
}

/// 干支纪日。
public struct ZXGanzhi: Hashable, Sendable {
    /// 年干支, 按立春交节时刻换年 (lunar 库 *Exact)。
    public let year: String
    /// 月干支, 按「节」的交节时刻换月 (lunar 库 *Exact)。
    public let month: String
    /// 日干支。
    public let day: String
}

/// 二十四节气之一。
public struct ZXSolarTerm: Hashable, Sendable {
    public let name: String
    /// 自立春起 0-based: 立春 = 0 … 大寒 = 23。
    ///
    /// 为什么从立春而不是冬至数: 七十二候、花信都以立春为岁首排序, 候的 index
    /// 正好是 `index * 3 + order`, 两套编号对得上。
    public let index: Int

    /// 自立春起的二十四节气名。
    public static let names: [String] = [
        "立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
        "立夏", "小满", "芒种", "夏至", "小暑", "大暑",
        "立秋", "处暑", "白露", "秋分", "寒露", "霜降",
        "立冬", "小雪", "大雪", "冬至", "小寒", "大寒",
    ]

    public init?(name: String) {
        guard let i = Self.names.firstIndex(of: name) else { return nil }
        self.name = name
        self.index = i
    }
}

/// 近期的一件岁时: 节气或节日。
public struct ZXUpcomingEvent: Hashable, Sendable {
    public let name: String
    public let date: ZXCivilDate
    /// 距起算日几天, 当天为 0。
    public let daysAway: Int
    /// 节日才有。
    public let festival: ZXFestival?
    /// 节气才有 (若 suishi.json 里配了诗)。
    public let termVerse: ZXTermVerse?

    public var isTerm: Bool { festival == nil }
}

/// 某一天的全部岁时信息。
///
/// 按当地正午取 (与 Flutter 版 AlmanacEngine 一致): 一天之内农历日、候、节气不变,
/// 只有「精确」年 / 月干支会在交节时刻换 —— 统一取正午, 同一天无论几点查都得同一结果,
/// 界面不会在交节的那个钟点突然跳字。
public struct ZXDay: Hashable, Sendable {
    public let gregorian: ZXCivilDate
    public let lunar: ZXLunarDate
    public let ganzhi: ZXGanzhi
    /// 当令节气: 交节当天整天算新节气。
    public let term: ZXSolarTerm
    /// 今天恰是交节日。
    public let isTermDay: Bool
    public let nextTerm: ZXSolarTerm
    public let nextTermDate: ZXCivilDate
    public let daysToNextTerm: Int
    /// 当日所在的一候 (文案取自 hou72.json)。
    public let hou: ZXHou
    /// 小寒至谷雨之间才有。
    public let huaxin: ZXHuaxin?
    /// 自今天起 7 天 (含当天, 共 8 天) 的节气与节日, 按日期排, 同日节气在前。
    public let upcoming: [ZXUpcomingEvent]

    /// 七日内节日的 id (不含节气), 与 fixture 的 festivalsWithin7Days 同义。
    public var festivalIDsWithin7Days: [String] {
        upcoming.compactMap { $0.festival?.id }
    }
}
