import Foundation
// @preconcurrency: 时辰部分要读 lunar-swift 的查表常量 (`LunarUtil.GAN` 等), 库里声明成
// `public static var`, 严格并发检查会把每次引用都报成「共享可变状态」。这些表库内从不写,
// 且这里的读都在 `LunarBridge.withLunar` 的锁内, 故按「未做并发标注的旧库」导入。
// 只作用于本文件; LunarBridge.swift 仍是普通 import, `withLunar` 的 Sendable 闸门不受影响。
@preconcurrency import LunarSwift

extension LunarBridge {
    /// 某个民用日的历注, 在锁内由一个正午 `Lunar` 算完再出锁。
    ///
    /// 性能: 一天只建一次 `Lunar`。十二时辰的时干支、值神、宜忌都能由「日干支 + 时支」查表
    /// 得到, 不必像 Flutter 版 `AlmanacEngine._timeWindows` 那样每个时辰再建一个 `Lunar`
    /// (那样每天要多算 12 次, 每次都要走一遍农历年表)。等价性:
    /// - 引擎的十二个取样点是当天 00:00、02:00 … 22:00, 都在 23:00 之前, 所以 lunar 的
    ///   「精确日干支」(按 23:00 换日) 与正午相同, 即当天的日干支;
    /// - lunar 的时干 = (精确日干 % 5 × 2 + 时支) % 10 (五鼠遁, 见 `LunarTime.init`);
    /// - 时值神 = TIAN_SHEN[(时支 + ZHI_TIAN_SHEN_OFFSET[精确日支]) % 12 + 1] (见 `Lunar.timeTianShen`);
    /// - 时宜忌 = LunarUtil.getTimeYi / getTimeJi(精确日干支, 时干支) (见 `LunarTime.yi / ji`)。
    /// 全年 365 × 12 个时辰由 Fixtures/almanac-2026.json 逐一核对。
    static func almanac(_ date: ZXCivilDate) -> ZXAlmanacNotes {
        withLunar(date, hour: 12) { lunar in
            ZXAlmanacNotes(
                date: date,
                // sect 2 = 月干支按「节」的交节时刻换 (monthInGanZhiExact)。Flutter 版所用的 Dart
                // lunar 1.7.8 的 getDayYi() / getDayJi() 就是这样取的; lunar-swift 的无参 `dayYi`
                // 是 sect 1 (按日换月), 交节那天会查到上个月的宜忌 —— 2026 年有 8 个节日因此不同。
                suitable: lunar.getDayYi(sect: 2),
                avoid: lunar.getDayJi(sect: 2),
                dayOfficer: lunar.zhiXing,
                dutyGod: lunar.dayTianShen,
                dutyGodPath: path(of: lunar.dayTianShenType),
                clash: ZXAlmanacClash(zodiac: lunar.dayChongShengXiao, shaDirection: lunar.daySha),
                mansion: ZXLunarMansion(name: lunar.xiu, element: lunar.zheng, animal: lunar.animal, luck: lunar.xiuLuck),
                pengZu: ZXPengZu(stem: lunar.pengZuGan, branch: lunar.pengZuZhi),
                deities: ZXAlmanacDeities(
                    joy: lunar.dayPositionXiDesc,
                    wealth: lunar.dayPositionCaiDesc,
                    fortune: lunar.dayPositionFuDesc
                ),
                hours: hours(of: lunar)
            )
        }
    }

    /// 只在 `withLunar` 的锁内调用: 读 lunar-swift 的静态表 (`LunarUtil.*` 是 `static var`)。
    private static func hours(of lunar: Lunar) -> [ZXAlmanacHour] {
        let dayGanIndex = lunar.dayGanIndexExact
        let dayGanZhi = lunar.dayInGanZhiExact
        let offset = LunarUtil.ZHI_TIAN_SHEN_OFFSET[lunar.dayZhiExact] ?? 0
        return (0..<12).map { zhi in
            let gan = (dayGanIndex % 5 * 2 + zhi) % 10
            let ganZhi = LunarUtil.GAN[gan + 1] + LunarUtil.ZHI[zhi + 1]
            let god = LunarUtil.TIAN_SHEN[(zhi + offset) % 12 + 1]
            return ZXAlmanacHour(
                branch: LunarUtil.ZHI[zhi + 1],
                branchIndex: zhi,
                ganZhi: ganZhi,
                dutyGod: god,
                path: path(of: LunarUtil.TIAN_SHEN_TYPE[god] ?? ""),
                suitable: LunarUtil.getTimeYi(dayGanZhi: dayGanZhi, timeGanZhi: ganZhi),
                avoid: LunarUtil.getTimeJi(dayGanZhi: dayGanZhi, timeGanZhi: ganZhi)
            )
        }
    }

    private static func path(of type: String) -> ZXAlmanacPath {
        guard let path = ZXAlmanacPath(rawValue: type) else {
            preconditionFailure("ZixiaoCalendar: lunar 库给出未知的值神类型「\(type)」")
        }
        return path
    }
}
