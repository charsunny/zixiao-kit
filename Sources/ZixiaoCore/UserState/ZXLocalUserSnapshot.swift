import Foundation

/// 偏好开关的键。开放式 (App 可以自己加), 内核只预置跨产品通用的。
///
/// 两类作用域:
/// - `.user`: 跟着账号走 (存在该 userId 的文件里), 换人即换一套, 删号时随账号清掉;
/// - `.device`: 跟着这台设备走 (存在 `device` 文件的 `deviceFlags` / `deviceSettings` 里), 不论谁登录都一样,
///   退出、删号、找回旧账号都不清理。显示类偏好属于这一类: 它描述的是「这台设备上怎么看」, 不是「这个人的数据」。
/// 字符串字面量默认 `.user`; 设备级的键要显式写 `ZXPreferenceKey("…", scope: .device)`。
public struct ZXPreferenceKey: Hashable, Sendable, ExpressibleByStringLiteral {
    public enum Scope: String, Sendable, Hashable {
        case user
        case device
    }

    public let rawValue: String
    public let scope: Scope

    public init(_ rawValue: String, scope: Scope = .user) {
        self.rawValue = rawValue
        self.scope = scope
    }

    public init(stringLiteral value: String) { self.init(value) }

    /// 历注: 今日页是否显示宜忌、冲煞、神方与时辰吉凶。默认关。设备级 —— 与 Flutter 版一致,
    /// Flutter `clearUserScopedState` 也特意保留 `settings:lizhu`。
    public static let liZhu = ZXPreferenceKey("lizhu", scope: .device)
}

/// 最近打开过的一样东西 (一本书、一卦、一个节气页……)。`kind` 由 App 定义, 内核不解释。
public struct ZXRecentItem: Codable, Sendable, Hashable, Identifiable {
    public var kind: String
    public var itemId: String
    public var title: String?
    public var openedAt: Date

    public var id: String { "\(kind):\(itemId)" }

    public init(kind: String, itemId: String, title: String? = nil, openedAt: Date = Date()) {
        self.kind = kind
        self.itemId = itemId
        self.title = title
        self.openedAt = openedAt
    }
}

/// 一个账号的本地态: 最近打开、连续天数、偏好开关。
///
/// 与 ZixiaoLibrary `ReadingState` 的分工: 那边是「书级」(读到哪一段、摘抄), 这里是「账号级」(这个人的习惯)。
/// 纯值类型, 所有规则是 mutating 函数, 与持久化分开 —— 连续天数这种按日历算的逻辑可以直接喂日期测。
public struct ZXLocalUserSnapshot: Codable, Sendable, Hashable {
    /// 最近打开列表的长度上限。
    public static let recentLimit = 20

    public var schema: Int
    /// 第一次打开的那天 (`yyyy-MM-dd`, 按记录时的时区)。「集候」等从这天起算。
    public var firstOpenedDay: String?
    public var lastOpenedAt: Date?
    public var lastOpenedDay: String?
    /// 当前连续打开天数。今天打开过即算今天。
    public var streak: Int
    public var longestStreak: Int
    /// 累计打开过的天数 (不要求连续)。
    public var totalDays: Int
    /// 新的在前, 同一样东西只留最近一次。
    public var recent: [ZXRecentItem]
    /// 账号级开关 (`.user` 作用域的键)。
    public var flags: [String: Bool]
    /// 小设置 (字符串值), 如提醒时间。
    public var settings: [String: String]
    /// 设备级开关 (`.device` 作用域的键)。只在 `device` 文件里有意义; 账号文件里恒为空。
    public var deviceFlags: [String: Bool]
    /// 设备级小设置 (字符串值; 数字由调用方转成字符串), 如阅读器排版方向、字号、晚省提醒时刻。
    /// 与 `deviceFlags` 同理: 只在 `device` 文件里有意义, 不随账号合并、清理。
    public var deviceSettings: [String: String]

    public init(schema: Int = 1, firstOpenedDay: String? = nil, lastOpenedAt: Date? = nil,
                lastOpenedDay: String? = nil, streak: Int = 0, longestStreak: Int = 0, totalDays: Int = 0,
                recent: [ZXRecentItem] = [], flags: [String: Bool] = [:], settings: [String: String] = [:],
                deviceFlags: [String: Bool] = [:], deviceSettings: [String: String] = [:]) {
        self.schema = schema
        self.firstOpenedDay = firstOpenedDay
        self.lastOpenedAt = lastOpenedAt
        self.lastOpenedDay = lastOpenedDay
        self.streak = streak
        self.longestStreak = longestStreak
        self.totalDays = totalDays
        self.recent = recent
        self.flags = flags
        self.settings = settings
        self.deviceFlags = deviceFlags
        self.deviceSettings = deviceSettings
    }

    /// 宽松解码: 缺字段按默认值。以后加字段时, 旧文件照样读得出来, 不会因一个新键整份作废。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schema: try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1,
            firstOpenedDay: try c.decodeIfPresent(String.self, forKey: .firstOpenedDay),
            lastOpenedAt: try c.decodeIfPresent(Date.self, forKey: .lastOpenedAt),
            lastOpenedDay: try c.decodeIfPresent(String.self, forKey: .lastOpenedDay),
            streak: try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0,
            longestStreak: try c.decodeIfPresent(Int.self, forKey: .longestStreak) ?? 0,
            totalDays: try c.decodeIfPresent(Int.self, forKey: .totalDays) ?? 0,
            recent: try c.decodeIfPresent([ZXRecentItem].self, forKey: .recent) ?? [],
            flags: try c.decodeIfPresent([String: Bool].self, forKey: .flags) ?? [:],
            settings: try c.decodeIfPresent([String: String].self, forKey: .settings) ?? [:],
            deviceFlags: try c.decodeIfPresent([String: Bool].self, forKey: .deviceFlags) ?? [:],
            deviceSettings: try c.decodeIfPresent([String: String].self, forKey: .deviceSettings) ?? [:]
        )
    }

    public static let empty = ZXLocalUserSnapshot()

    /// 内核默认的换日时区 (与 ZixiaoCalendar 一致)。不做成 `TimeZone` 的扩展, 免得与其他模块撞名。
    public static let defaultTimeZone = TimeZone(identifier: "Asia/Shanghai")!

    // MARK: - 连续天数

    /// 记一次打开。同一天多次只算一次; 隔天续上 +1; 断了从 1 重来。
    ///
    /// - Parameter timeZone: 按哪里的午夜换日。内核默认 Asia/Shanghai, App 传 `TimeZone.current`
    ///   (架构决定 5: 海外用户按本地午夜换日)。
    /// - Returns: 是否是今天的第一次打开 (App 可据此播「连续 N 天」动画)。
    @discardableResult
    public mutating func recordOpen(at date: Date = Date(), timeZone: TimeZone = ZXLocalUserSnapshot.defaultTimeZone) -> Bool {
        let today = Self.dayKey(for: date, timeZone: timeZone)
        lastOpenedAt = date
        if firstOpenedDay == nil { firstOpenedDay = today }
        guard today != lastOpenedDay else { return false }

        if let last = lastOpenedDay, let gap = Self.daysBetween(last, today) {
            // gap < 0: 时钟被往回拨或换到更西的时区, 不当作断签, 也不加。
            if gap == 1 { streak += 1 } else if gap > 1 { streak = 1 } else { return false }
        } else {
            streak = 1
        }
        totalDays += 1
        longestStreak = max(longestStreak, streak)
        lastOpenedDay = today
        return true
    }

    /// 按「今天」看的连续天数: 昨天之前就断了的, 显示 0 而不是一个过期的数。
    public func currentStreak(asOf date: Date = Date(), timeZone: TimeZone = ZXLocalUserSnapshot.defaultTimeZone) -> Int {
        guard let last = lastOpenedDay,
              let gap = Self.daysBetween(last, Self.dayKey(for: date, timeZone: timeZone)) else { return 0 }
        return gap <= 1 ? streak : 0
    }

    // MARK: - 最近打开

    public mutating func noteOpened(_ item: ZXRecentItem) {
        recent.removeAll { $0.id == item.id }
        recent.insert(item, at: 0)
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
    }

    // MARK: - 偏好

    /// 按键的作用域读对应的字典。注意设备级的键只有在 `device` 那份快照上读才有值 ——
    /// 通过 `ZXLocalUserState.flag(_:for:)` 读就不必操心, 它会自动路由。
    public func flag(_ key: ZXPreferenceKey, default defaultValue: Bool = false) -> Bool {
        switch key.scope {
        case .user: return flags[key.rawValue] ?? defaultValue
        case .device: return deviceFlags[key.rawValue] ?? defaultValue
        }
    }

    public mutating func setFlag(_ key: ZXPreferenceKey, _ value: Bool) {
        switch key.scope {
        case .user: flags[key.rawValue] = value
        case .device: deviceFlags[key.rawValue] = value
        }
    }

    /// 按键的作用域读小设置: `.user` 读 `settings`, `.device` 读 `deviceSettings`。
    public func setting(_ key: ZXPreferenceKey) -> String? {
        switch key.scope {
        case .user: return settings[key.rawValue]
        case .device: return deviceSettings[key.rawValue]
        }
    }

    /// 按键的作用域写小设置; `nil` 删除该项 (回到调用方的默认值)。
    public mutating func setSetting(_ key: ZXPreferenceKey, _ value: String?) {
        switch key.scope {
        case .user: settings[key.rawValue] = value
        case .device: deviceSettings[key.rawValue] = value
        }
    }

    /// 只保留设备级部分 (把设备名下的账号级态交出去、或清掉之后, 设备偏好要留下)。
    public var devicePortion: ZXLocalUserSnapshot {
        ZXLocalUserSnapshot(deviceFlags: deviceFlags, deviceSettings: deviceSettings)
    }

    // MARK: - 合并

    /// 把 `other` (通常是首启离线时记在设备名下的) 的**账号级**部分并进来。本账号已有的值优先, 对方只补空缺;
    /// 连续天数取最后打开更晚的那一方, 最近打开按时间合并。设备级开关与设置 (`deviceFlags` / `deviceSettings`)
    /// 不并 —— 它们留在设备文件里 (`result` 从 `self` 起步, 保留的是本方的, 账号文件里恒为空)。
    public func merged(with other: ZXLocalUserSnapshot) -> ZXLocalUserSnapshot {
        var result = self
        result.firstOpenedDay = [firstOpenedDay, other.firstOpenedDay].compactMap { $0 }.min()
        if (other.lastOpenedDay ?? "") > (lastOpenedDay ?? "") {
            result.lastOpenedDay = other.lastOpenedDay
            result.lastOpenedAt = other.lastOpenedAt
            result.streak = other.streak
        }
        result.longestStreak = max(longestStreak, other.longestStreak)
        result.totalDays = max(totalDays, other.totalDays)
        var combined = recent
        for item in other.recent where !combined.contains(where: { $0.id == item.id }) { combined.append(item) }
        result.recent = Array(combined.sorted { $0.openedAt > $1.openedAt }.prefix(Self.recentLimit))
        result.flags = other.flags.merging(flags) { _, mine in mine }
        result.settings = other.settings.merging(settings) { _, mine in mine }
        return result
    }

    // MARK: - 日期

    /// `yyyy-MM-dd`, 公历, 按给定时区。字符串可直接比较先后。
    public static func dayKey(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 两个日键相差的天数 (to - from)。按 UTC 解析, 与时区无关, 所以不受夏令时影响。
    static func daysBetween(_ from: String, _ to: String) -> Int? {
        guard let a = utcDate(from), let b = utcDate(to) else { return nil }
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
    }

    private static func utcDate(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
