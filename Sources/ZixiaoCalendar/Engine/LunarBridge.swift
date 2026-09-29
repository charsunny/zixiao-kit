import Foundation
import LunarSwift

/// 某个民用日在 lunar-swift 里能取到的、本模块用得上的全部原始事实。
///
/// 为什么要先拍成快照: lunar-swift 的 `Solar` / `Lunar` 是可变的 NSObject 子类
/// (非 Sendable), 而且 `LunarYear` 用一个 `static var CACHE_YEAR` 做单年缓存 ——
/// 多线程同时算会数据竞争。所以对它的一切调用都关在 `LunarBridge` 的锁里, 出锁前
/// 转成这个纯值类型, lunar-swift 的对象永远不逃出锁外。
struct LunarSnapshot: Sendable {
    let date: ZXCivilDate
    /// 农历年 (以正月初一换年)。
    let lunarYear: Int
    /// lunar 库的月: 闰月为负数。
    let lunarMonthSigned: Int
    let lunarDay: Int
    /// 「闰六」「腊」等, lunar 库的 monthInChinese。
    let monthInChinese: String
    /// 「初三」「廿九」, lunar 库的 dayInChinese。
    let dayInChinese: String
    let yearGanzhiExact: String
    let monthGanzhiExact: String
    let dayGanzhi: String
    /// 当天恰是交节日则为节气名, 否则空串 (lunar 库 jieQi)。
    let jieQi: String
    /// 当令节气 (交节当天整天算新节气, wholeDay)。
    let houTerm: String
    /// 1 初候 · 2 二候 · 3 三候。
    let houOrder: Int
    /// 下一个节气 (严格晚于今天的那一个, wholeDay)。
    let nextTerm: String
    let nextTermDate: ZXCivilDate
}

enum LunarBridge {
    /// 见 `LunarSnapshot` 的说明。用普通锁而非 actor: 历法是同步的纯计算,
    /// 调用方 (SwiftUI 视图、Widget 时间线) 不该为此变成 async。
    private static let lock = NSLock()

    /// `hour` 只影响「精确」干支 (年按立春交节时刻、月按节交节时刻换); 其余字段
    /// 只看年月日。默认取正午, 与 Flutter 版 AlmanacEngine 一致。
    static func snapshot(_ date: ZXCivilDate, hour: Int = 12) -> LunarSnapshot {
        withLunar(date, hour: hour) { lunar in snapshot(date, lunar: lunar) }
    }

    /// 在锁里以 `date` 的 `hour:00` 建一个 `Lunar` 交给 `body`, 由它转成值类型再出锁。
    ///
    /// `T: Sendable` 是这里的闸门: lunar-swift 的对象都不是 Sendable, 编译器因此不允许
    /// `body` 把 `Lunar` / `Solar` 原样带出锁外。各类快照 (岁时、历注) 都经这一个入口。
    static func withLunar<T: Sendable>(_ date: ZXCivilDate, hour: Int = 12, _ body: (Lunar) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        let solar = Solar.fromYmdHms(year: date.year, month: date.month, day: date.day, hour: hour, minute: 0, second: 0)
        return body(solar.lunar)
    }

    /// 只在 `withLunar` 的锁内调用。
    private static func snapshot(_ date: ZXCivilDate, lunar: Lunar) -> LunarSnapshot {
        // 形如「秋分 初候」。与 Flutter 版 houPositionOf 同一取法。
        let parts = lunar.hou.split(separator: " ").map(String.init)
        let houTerm = parts.first ?? ""
        let houOrder = parts.count > 1 ? (ZXHou.orderLabels.firstIndex(of: parts[1]).map { $0 + 1 } ?? 1) : 1

        // wholeDay: true —— 只比日期不比时刻, 交节当天不算「下一个」。与 Dart 的
        // `lunar.getNextJieQi(true)` 相同。
        let next = lunar.getNextJieQi(wholeDay: true)
        let nextSolar = next?.solar
        let nextDate = nextSolar.map { ZXCivilDate(year: $0.year, month: $0.month, day: $0.day) } ?? date

        return LunarSnapshot(
            date: date,
            lunarYear: lunar.year,
            lunarMonthSigned: lunar.month,
            lunarDay: lunar.day,
            monthInChinese: lunar.monthInChinese,
            dayInChinese: lunar.dayInChinese,
            yearGanzhiExact: lunar.yearInGanZhiExact,
            monthGanzhiExact: lunar.monthInGanZhiExact,
            dayGanzhi: lunar.dayInGanZhi,
            jieQi: lunar.jieQi,
            houTerm: houTerm,
            houOrder: houOrder,
            nextTerm: next?.name ?? "",
            nextTermDate: nextDate
        )
    }
}

/// 一次推算内复用快照。节日判定要反复问「某天是不是清明」「明天是不是初一」,
/// 七日窗口里这些日子大量重叠; 每次重建 `Lunar` 要重算整年节气表, 不缓存会慢一个量级。
/// 只在单次调用内活着 (局部变量), 不跨线程共享, 所以不需要锁。
final class LunarSnapshotCache {
    private var store: [ZXCivilDate: LunarSnapshot] = [:]

    func callAsFunction(_ date: ZXCivilDate) -> LunarSnapshot {
        if let hit = store[date] { return hit }
        let s = LunarBridge.snapshot(date)
        store[date] = s
        return s
    }
}
