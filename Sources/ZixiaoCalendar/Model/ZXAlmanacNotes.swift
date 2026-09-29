import Foundation

/// 某一天的「历注」: 传统黄历在这一天写的全部条目。
///
/// 字段与 Flutter 版今日页「历注」区一一对应 —— 引擎部分出自
/// `AlmanacEngine.calculate` (qizen/app/lib/domain/v2/timing/almanac_engine.dart),
/// 神方 / 廿八宿 / 彭祖出自 `LiZhuSection` (today_widgets.dart) 直接问 lunar 的那几行。
/// 由 Fixtures/almanac-2026.json 逐日对齐。
///
/// 有意不移植的: Flutter 版引擎在历注之上加的「打分」(overallScore / grade、时辰 score)。
/// V3 计划: 只呈现传统历注原文, 不出现「大吉」之类的评分。
///
/// 全部按当地正午取 (与 `ZXDay` 同理): 历注都是「日」级的量, 一天之内不变。
public struct ZXAlmanacNotes: Hashable, Sendable {
    /// 这份历注属于哪一天。
    public let date: ZXCivilDate

    /// 宜 (lunar `dayYi`, 完整列表, 顺序即历书顺序)。Flutter 版界面只显示前 8 条。
    public let suitable: [String]
    /// 忌 (lunar `dayJi`)。
    public let avoid: [String]

    /// 建除十二值之一: 建 除 满 平 定 执 破 危 成 收 开 闭 (lunar `zhiXing`)。
    public let dayOfficer: String

    /// 值日天神 (青龙、明堂、天刑…, lunar `dayTianShen`)。
    public let dutyGod: String
    /// 值神属黄道还是黑道 (lunar `dayTianShenType`)。
    public let dutyGodPath: ZXAlmanacPath

    /// 冲煞。
    public let clash: ZXAlmanacClash
    /// 二十八宿值日。
    public let mansion: ZXLunarMansion
    /// 彭祖百忌两句。
    public let pengZu: ZXPengZu
    /// 吉神方位: 喜神、财神、福神。
    public let deities: ZXAlmanacDeities

    /// 当日十二时辰, 子 → 亥。子为早子时 (起于前一日 23:00), 与 `ZXCalendar.allShichen(on:)` 同序同义。
    public let hours: [ZXAlmanacHour]

    public init(
        date: ZXCivilDate,
        suitable: [String],
        avoid: [String],
        dayOfficer: String,
        dutyGod: String,
        dutyGodPath: ZXAlmanacPath,
        clash: ZXAlmanacClash,
        mansion: ZXLunarMansion,
        pengZu: ZXPengZu,
        deities: ZXAlmanacDeities,
        hours: [ZXAlmanacHour]
    ) {
        self.date = date
        self.suitable = suitable
        self.avoid = avoid
        self.dayOfficer = dayOfficer
        self.dutyGod = dutyGod
        self.dutyGodPath = dutyGodPath
        self.clash = clash
        self.mansion = mansion
        self.pengZu = pengZu
        self.deities = deities
        self.hours = hours
    }

    /// `branchIndex` (0 子 … 11 亥) 那个时辰; 越界为 nil。
    public func hour(branchIndex: Int) -> ZXAlmanacHour? {
        hours.indices.contains(branchIndex) ? hours[branchIndex] : nil
    }
}

/// 黄道 / 黑道。
public enum ZXAlmanacPath: String, Hashable, Sendable {
    /// 黄道: 青龙、明堂、金匮、天德、玉堂、司命。
    case yellow = "黄道"
    /// 黑道: 天刑、朱雀、白虎、天牢、玄武、勾陈。
    case black = "黑道"

    /// 「黄道」「黑道」。
    public var label: String { rawValue }

    /// 历书的读法: 黄道为吉、黑道为凶 (lunar `TIAN_SHEN_TYPE_LUCK`)。
    public var isAuspicious: Bool { self == .yellow }
}

/// 冲煞: 「冲马 · 煞南」。
public struct ZXAlmanacClash: Hashable, Sendable {
    /// 所冲生肖 (lunar `dayChongShengXiao`), 如「马」。
    public let zodiac: String
    /// 煞方 (lunar `daySha`), 如「南」。
    public let shaDirection: String

    public init(zodiac: String, shaDirection: String) {
        self.zodiac = zodiac
        self.shaDirection = shaDirection
    }
}

/// 二十八宿值日: 「井木犴 · 吉」。
public struct ZXLunarMansion: Hashable, Sendable {
    /// 宿名 (lunar `xiu`), 如「井」。
    public let name: String
    /// 七政 (lunar `zheng`), 如「木」。
    public let element: String
    /// 禽 (lunar `animal`), 如「犴」。
    public let animal: String
    /// 「吉」或「凶」(lunar `xiuLuck`)。
    public let luck: String

    public init(name: String, element: String, animal: String, luck: String) {
        self.name = name
        self.element = element
        self.animal = animal
        self.luck = luck
    }

    /// 「井木犴」, 历书的全称。
    public var fullName: String { name + element + animal }
}

/// 彭祖百忌: 按日干一句、日支一句。
public struct ZXPengZu: Hashable, Sendable {
    /// 日干那句 (lunar `pengZuGan`), 如「乙不栽植千株不长」。
    public let stem: String
    /// 日支那句 (lunar `pengZuZhi`), 如「亥不嫁娶不利新郎」。
    public let branch: String

    public init(stem: String, branch: String) {
        self.stem = stem
        self.branch = branch
    }
}

/// 吉神方位 (lunar `dayPosition*Desc`, 如「西北」「正南」)。
public struct ZXAlmanacDeities: Hashable, Sendable {
    /// 喜神。
    public let joy: String
    /// 财神。
    public let wealth: String
    /// 福神 (lunar 默认流派 sect 2, 与 Flutter 版同)。
    public let fortune: String

    public init(joy: String, wealth: String, fortune: String) {
        self.joy = joy
        self.wealth = wealth
        self.fortune = fortune
    }
}

/// 一个时辰的历注: 时干支、值神、黄黑道、宜忌。
public struct ZXAlmanacHour: Hashable, Sendable, Identifiable {
    /// 地支「子」…「亥」。
    public let branch: String
    /// 0 子 … 11 亥。
    public let branchIndex: Int
    /// 时干支 (按日干五鼠遁), 如「丙子」。
    public let ganZhi: String
    /// 值时天神 (lunar 时 `tianShen`)。
    public let dutyGod: String
    /// 值时天神属黄道 / 黑道。
    public let path: ZXAlmanacPath
    /// 时宜 (lunar `LunarUtil.getTimeYi`)。没有时历书写「无」, 原样保留。
    public let suitable: [String]
    /// 时忌 (lunar `LunarUtil.getTimeJi`)。可能是「无」或「诸事不宜」, 原样保留。
    public let avoid: [String]

    public init(branch: String, branchIndex: Int, ganZhi: String, dutyGod: String,
                path: ZXAlmanacPath, suitable: [String], avoid: [String]) {
        self.branch = branch
        self.branchIndex = branchIndex
        self.ganZhi = ganZhi
        self.dutyGod = dutyGod
        self.path = path
        self.suitable = suitable
        self.avoid = avoid
    }

    public var id: Int { branchIndex }

    /// 黄道时为吉 (Flutter 版 `AlmanacTimeWindow.auspicious`)。
    public var isAuspicious: Bool { path.isAuspicious }
}
