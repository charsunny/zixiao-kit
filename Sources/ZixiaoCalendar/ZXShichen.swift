import Foundation

/// 五更之一: 入夜后 19 点起一更, 每两小时一更, 到寅时 (5 点) 五更尽。
public struct ZXGeng: Hashable, Sendable {
    /// 1…5。
    public let index: Int
    /// 「一更」…「五更」。
    public let name: String
    /// 古名: 黄昏、人定、夜半、鸡鸣、平旦。
    public let ancientName: String
}

/// 某一时刻所在的时辰。
public struct ZXShichen: Hashable, Sendable {
    /// 地支: 子、丑、寅……
    public let branch: String
    /// 0…11, 子 = 0。
    public let branchIndex: Int
    /// 古名: 夜半、鸡鸣、平旦……
    public let ancientName: String
    /// 一句古人此时的作息。
    public let gloss: String
    /// 本时辰起止 (墙上时间的整点)。子时跨日: 23:30 查得的子时止于次日 01:00,
    /// 00:30 查得的子时起于前一日 23:00。
    public let start: Date
    public let end: Date
    /// 入夜后才有更点, 白天为 nil。
    public let geng: ZXGeng?

    /// 「23:00–01:00」。
    public var rangeLabel: String {
        let s = ZXShichen.startHour(ofBranch: branchIndex)
        return String(format: "%02d:00–%02d:00", s, (s + 2) % 24)
    }

    /// 几点钟是哪个时辰: 子时 23–1, 之后每两小时一支。与 Flutter 版 branchIndexOfHour 同式。
    static func branchIndex(ofHour hour: Int) -> Int { ((hour + 1) / 2) % 12 }

    static func startHour(ofBranch index: Int) -> Int { (index * 2 + 23) % 24 }

    /// 入夜后的五更 (19 点一更起, 每两小时一更), 白天返回 nil。与 Flutter 版 gengOfHour 同式。
    static func gengIndex(ofHour hour: Int) -> Int? {
        if hour >= 19 { return (hour - 19) / 2 + 1 }
        if hour < 5 { return (hour + 5) / 2 + 1 }
        return nil
    }

    static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
}
