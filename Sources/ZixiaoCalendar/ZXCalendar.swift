import Foundation

/// 岁时推算的入口: 某日的农历 / 干支 / 节气 / 候 / 花信 / 近期节日, 某刻的时辰与更点。
///
/// 全部是无状态的静态函数: 历法是纯计算, 没有需要持有的东西; 做成 enum 也省得
/// 调用方纠结要不要注入一个实例。时区默认 Asia/Shanghai —— 节气交节、农历初一都是
/// 按东八区定的, 在海外看「今天是什么节气」也应该与国内一致; 需要按用户本地日历
/// 落日子时 (例如海外用户希望「今天」跟随本地午夜), 显式传 `timeZone`。
///
/// 算法从 Flutter 版 (qizen/app/lib/domain/v2/timing/hou_calendar.dart) 逐行移植,
/// 由 Fixtures/ 下的 Dart 金标逐日对齐。
public enum ZXCalendar {
    /// Asia/Shanghai。
    public static let defaultTimeZone: TimeZone =
        TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600)!

    /// 默认的「近期」窗口: 7 天 (含当天共 8 天, 与 Flutter 版 upcomingEvents 同义)。
    public static let defaultWindowDays = 7

    // MARK: - 某日

    /// `date` 在 `timeZone` 墙上日历里那一天的全部岁时信息。
    public static func day(for date: Date, timeZone: TimeZone = defaultTimeZone) -> ZXDay {
        day(ZXCivilDate(date, timeZone: timeZone))
    }

    /// 某个民用日的全部岁时信息。与时区无关。
    public static func day(_ civil: ZXCivilDate) -> ZXDay {
        let cache = LunarSnapshotCache()
        let s = cache(civil)
        let culture = ZXCultureData.shared

        guard let term = ZXSolarTerm(name: s.houTerm) else {
            preconditionFailure("ZixiaoCalendar: lunar 库给出未知节气「\(s.houTerm)」(\(civil))")
        }
        // 候按 (节气, 候序) 找, 不按候名找 —— 与 Flutter 版 houOf 相同, 候名各本用字略异。
        guard let hou = culture.hou(term: term.name, order: s.houOrder) else {
            preconditionFailure("ZixiaoCalendar: hou72.json 缺 \(term.name) 第\(s.houOrder)候")
        }
        let nextTerm = ZXSolarTerm(name: s.nextTerm) ?? term

        return ZXDay(
            gregorian: civil,
            lunar: ZXLunarDate(
                year: s.lunarYear,
                month: abs(s.lunarMonthSigned),
                day: s.lunarDay,
                isLeap: s.lunarMonthSigned < 0,
                label: "\(s.monthInChinese)月\(s.dayInChinese)"
            ),
            ganzhi: ZXGanzhi(year: s.yearGanzhiExact, month: s.monthGanzhiExact, day: s.dayGanzhi),
            term: term,
            isTermDay: !s.jieQi.isEmpty,
            nextTerm: nextTerm,
            nextTermDate: s.nextTermDate,
            daysToNextTerm: s.nextTermDate.days(since: civil),
            hou: hou,
            huaxin: culture.huaxin(term: term.name, order: s.houOrder),
            upcoming: upcomingEvents(from: civil, days: defaultWindowDays, cache: cache)
        )
    }

    // MARK: - 近期节气与节日

    /// 自 `date` 那天起 `days` 天内 (含当天, 共 days + 1 天) 的节气与节日, 按日期排,
    /// 同日节气在前、节日按 suishi.json 顺序。节气也一并返回, 因为岁时卡把两者排在同一条
    /// 时间线上; 只要节日就取 `festival != nil` 的那些。
    public static func festivals(
        within days: Int = defaultWindowDays,
        from date: Date,
        timeZone: TimeZone = defaultTimeZone
    ) -> [ZXUpcomingEvent] {
        festivals(within: days, from: ZXCivilDate(date, timeZone: timeZone))
    }

    public static func festivals(within days: Int = defaultWindowDays, from civil: ZXCivilDate) -> [ZXUpcomingEvent] {
        upcomingEvents(from: civil, days: days, cache: LunarSnapshotCache())
    }

    static func upcomingEvents(from start: ZXCivilDate, days: Int, cache: LunarSnapshotCache) -> [ZXUpcomingEvent] {
        guard days >= 0 else { return [] }
        let culture = ZXCultureData.shared
        var events: [ZXUpcomingEvent] = []
        for i in 0...days {
            let date = start.adding(days: i)
            let s = cache(date)
            if !s.jieQi.isEmpty {
                events.append(ZXUpcomingEvent(
                    name: s.jieQi, date: date, daysAway: i,
                    festival: nil, termVerse: culture.termVerse(s.jieQi)
                ))
            }
            for f in culture.festivals where fallsOn(f, date: date, snapshot: s, cache: cache) {
                events.append(ZXUpcomingEvent(name: f.name, date: date, daysAway: i, festival: f, termVerse: nil))
            }
        }
        return events
    }

    /// 与 Flutter 版 `_fallsOn` 同一判法。
    private static func fallsOn(_ f: ZXFestival, date: ZXCivilDate, snapshot s: LunarSnapshot, cache: LunarSnapshotCache) -> Bool {
        if let term = f.term {
            // 寒食 = 清明前二日 (offsetDays = -2): 看 date - offset 那天是不是清明。
            return cache(date.adding(days: -f.offsetDays)).jieQi == term
        }
        // 闰月不过节: lunar 库里闰月是负数, 与正数的节日月永不相等。
        guard s.lunarMonthSigned == f.lunarMonth else { return false }
        if f.lunarDay == -1 {
            // 月末 (除夕): 明天是初一。不写死廿九 / 三十, 大小月都对。
            return cache(date.adding(days: 1)).lunarDay == 1
        }
        return s.lunarDay == f.lunarDay
    }

    // MARK: - 时辰与更点

    /// `date` 在 `timeZone` 墙上时间里所处的时辰 (含入夜后的更点)。
    public static func shichen(at date: Date, timeZone: TimeZone = defaultTimeZone) -> ZXShichen {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour], from: date)
        let civil = ZXCivilDate(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
        let hour = c.hour ?? 0
        let index = ZXShichen.branchIndex(ofHour: hour)
        // 子时跨日: 0 点属于前一日 23 点起的那个子时。
        let startDay = (index == 0 && hour < 23) ? civil.adding(days: -1) : civil
        return makeShichen(index: index, startDay: startDay, gengHour: hour, timeZone: timeZone)
    }

    /// 某个民用日的十二时辰, 子时起于前一日 23:00 (与 Flutter 版 AlmanacEngine 的
    /// 时辰窗一致: 午夜换日, 晚子时归次日)。更点按各时辰起始钟点取。
    public static func allShichen(on civil: ZXCivilDate, timeZone: TimeZone = defaultTimeZone) -> [ZXShichen] {
        (0..<12).map { index in
            let startDay = index == 0 ? civil.adding(days: -1) : civil
            return makeShichen(index: index, startDay: startDay,
                               gengHour: ZXShichen.startHour(ofBranch: index), timeZone: timeZone)
        }
    }

    private static func makeShichen(index: Int, startDay: ZXCivilDate, gengHour: Int, timeZone: TimeZone) -> ZXShichen {
        let culture = ZXCultureData.shared
        let branch = ZXShichen.branches[index]
        guard let entry = culture.shichen.first(where: { $0.branch == branch }) else {
            preconditionFailure("ZixiaoCalendar: shichen.json 缺「\(branch)」")
        }
        let startHour = ZXShichen.startHour(ofBranch: index)
        let endHour = (startHour + 2) % 24
        let endDay = endHour < startHour ? startDay.adding(days: 1) : startDay
        let geng = ZXShichen.gengIndex(ofHour: gengHour).flatMap { i -> ZXGeng? in
            guard culture.geng.indices.contains(i - 1) else { return nil }
            let g = culture.geng[i - 1]
            return ZXGeng(index: i, name: g.name, ancientName: g.ancient)
        }
        return ZXShichen(
            branch: branch,
            branchIndex: index,
            ancientName: entry.ancient,
            gloss: entry.gloss,
            start: startDay.date(hour: startHour, timeZone: timeZone),
            end: endDay.date(hour: endHour, timeZone: timeZone),
            geng: geng
        )
    }

    // MARK: - 文化数据

    /// 七十二候, 按 index 1–72 排。
    public static var allHou: [ZXHou] { ZXCultureData.shared.hou }

    /// 第 `index` 候 (1–72); 越界返回 nil。
    public static func hou(_ index: Int) -> ZXHou? {
        ZXCultureData.shared.hou.first { $0.index == index }
    }

    /// 二十四番花信, 按 index 1–24 排。
    public static var allHuaxin: [ZXHuaxin] { ZXCultureData.shared.huaxin }

    /// 某节气某候的花信; 不在小寒–谷雨之间返回 nil。
    public static func huaxin(term: String, order: Int) -> ZXHuaxin? {
        ZXCultureData.shared.huaxin(term: term, order: order)
    }

    /// 花信所在的八个节气, 小寒起。
    public static var huaxinTerms: [String] {
        var seen: [String] = []
        for h in ZXCultureData.shared.huaxin where !seen.contains(h.term) { seen.append(h.term) }
        return seen
    }

    /// suishi.json 里的全部节日, 按文件顺序。
    public static var allFestivals: [ZXFestival] { ZXCultureData.shared.festivals }

    /// 某节气配的诗, 没配返回 nil。
    public static func termVerse(_ term: String) -> ZXTermVerse? {
        ZXCultureData.shared.termVerse(term)
    }
}
