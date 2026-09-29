import Foundation

/// 年号纪年: 公元 1082 → 「元丰五年」。
///
/// 从 PoetKit (Theme.swift 的 EraNaming) 移植。年号是【朝代】级的公共参照数据,
/// 不是某位诗人的私产 —— 唐宋诗人共用同一张表, 所以放在内核的历法模块里,
/// 各产品按身份 JSON 的 chronology.style 选择纪年风格。
///
/// 表 (Resources/eras.json) 只到年级: 以改元当年为该年号元年, 不处理年中改元
/// (1101 年正月改元建中靖国, 按年取即为「建中靖国元年」; 同年前朝旧号不再体现)。
public struct EraNaming: Hashable, Sendable {
    public enum Style: String, Decodable, Hashable, Sendable {
        /// 「元丰五年」。
        case eraName = "era-name"
        /// 「1082年」。
        case gregorian
        /// 「约元丰五年」: 年份本身只是约数时用, 避免把推测写成定论。
        case eraNameApprox = "era-name-approx"
    }

    struct Era: Decodable, Sendable {
        let start: Int
        let name: String
    }

    /// 按起始年升序。`static let` 惰性且线程安全。
    static let eras: [Era] = {
        let list: [Era] = ZXCultureData.decode("eras")
        return list.sorted { $0.start < $1.start }
    }()

    /// 数字表只到「二十二」, 超出回落到公元纪年 —— 与 PoetKit 原实现保持一致 (有意不改):
    /// 贞观 23 年、开元 23–29 年、绍兴 23–32 年因此会显示公元年, 是否放宽待架构师定。
    private static let cn = ["元", "二", "三", "四", "五", "六", "七", "八", "九", "十",
                             "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八",
                             "十九", "二十", "二十一", "二十二"]

    public let style: Style

    public init(style: Style) { self.style = style }

    /// 1082 → 「元丰五年」。approx 风格前缀「约」; gregorian 风格或表外年份 → 「1082年」。
    public func label(_ year: Int) -> String {
        guard style != .gregorian,
              let era = Self.eras.last(where: { $0.start <= year })
        else { return "\(year)年" }
        let nth = year - era.start
        guard nth >= 0, nth < Self.cn.count else { return "\(year)年" }
        let core = "\(era.name)\(Self.cn[nth])年"
        return style == .eraNameApprox ? "约\(core)" : core
    }

    /// 某年所在的年号名 (不含第几年); gregorian 风格同样可查, 表外返回 nil。
    public func eraName(of year: Int) -> String? {
        guard let era = Self.eras.last(where: { $0.start <= year }),
              year - era.start < Self.cn.count
        else { return nil }
        return era.name
    }
}
