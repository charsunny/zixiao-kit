import Foundation

// 文化数据: 七十二候、花信、十二时辰 / 五更、节气诗、节日。
//
// 来源是 Resources/*.json (从 qizen/app/assets/culture 原样复制), 这里只把它们
// 解成不可变值类型, 不做推算。推算 (今天哪一候、几时、近期有什么节) 在 ZXCalendar。
// 字段名与 Flutter 版 culture_models.dart 一一对应, 便于两端对照维护。

/// 七十二候之一。`index` 自立春初候起计 1–72。
public struct ZXHou: Hashable, Decodable, Sendable {
    public let index: Int
    /// 节气名, 如「秋分」。
    public let term: String
    /// 1 初候 · 2 二候 · 3 三候。
    public let order: Int
    /// 候名, 以 hou72.json 为准 (lunar 库的候名用字各本略异, 不拿来显示)。
    public let name: String
    /// 自撰解说, 40–80 字。
    public let text: String

    public var orderLabel: String { ZXHou.orderLabels[order - 1] }

    static let orderLabels = ["初候", "二候", "三候"]
}

/// 二十四番花信风之一: 小寒至谷雨, 每气三候, 一候一花。
public struct ZXHuaxin: Hashable, Decodable, Sendable {
    /// 1…24。
    public let index: Int
    public let term: String
    /// 1…3, 初候 / 二候 / 三候。
    public let order: Int
    public let flower: String
    public let note: String

    public var orderLabel: String { ZXHou.orderLabels[order - 1] }
}

/// 一个节气配的一句诗。
public struct ZXTermVerse: Hashable, Decodable, Sendable {
    public let term: String
    public let line: String
    public let author: String
    public let title: String
    public let gloss: String
}

/// 传统节日。按农历日 (`lunarMonth`, `lunarDay`; 日为 -1 表示该月末日) 或按节气
/// (`term` 加 `offsetDays`) 定日子。
public struct ZXFestival: Hashable, Decodable, Sendable {
    public let id: String
    public let name: String
    public let lunarMonth: Int?
    public let lunarDay: Int?
    public let term: String?
    /// 相对节气的偏移天数: 寒食 = 清明 -2。
    public let offsetDays: Int
    public let customs: [String]
    public let food: String
    public let line: String
    public let author: String
    public let title: String

    public var isTermBased: Bool { term != nil }

    private enum CodingKeys: String, CodingKey {
        case id, name, lunar, term, offsetDays, customs, food, line, author, title
    }

    // suishi.json 里农历日写成 `"lunar": [月, 日]`, 与 Flutter 版同一 schema, 这里拆开。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        let lunar = try c.decodeIfPresent([Int].self, forKey: .lunar)
        lunarMonth = lunar?.first
        lunarDay = lunar.flatMap { $0.count > 1 ? $0[1] : nil }
        term = try c.decodeIfPresent(String.self, forKey: .term)
        offsetDays = try c.decodeIfPresent(Int.self, forKey: .offsetDays) ?? 0
        customs = try c.decode([String].self, forKey: .customs)
        food = try c.decode(String.self, forKey: .food)
        line = try c.decode(String.self, forKey: .line)
        author = try c.decode(String.self, forKey: .author)
        title = try c.decode(String.self, forKey: .title)
    }
}

/// shichen.json 里的一条时辰文案。子时跨日: start 23, end 1。
struct ZXShichenEntry: Decodable, Sendable {
    let branch: String
    let ancient: String
    let start: Int
    let end: Int
    let gloss: String
}

/// shichen.json 里的一条更点文案。
struct ZXGengEntry: Decodable, Sendable {
    let name: String
    let ancient: String
    let start: Int
}

/// 五个 JSON 读进来之后的整体。进程内只读一次。
struct ZXCultureData: Sendable {
    let hou: [ZXHou]
    let huaxin: [ZXHuaxin]
    let shichen: [ZXShichenEntry]
    let geng: [ZXGengEntry]
    let termVerses: [ZXTermVerse]
    let festivals: [ZXFestival]

    /// `static let` 由 Swift 保证线程安全的惰性初始化, 首次用到才读盘。
    static let shared: ZXCultureData = load()

    private struct Items<T: Decodable>: Decodable { let items: [T] }
    private struct ShichenFile: Decodable { let items: [ZXShichenEntry]; let geng: [ZXGengEntry] }
    private struct SuishiFile: Decodable { let terms: [ZXTermVerse]; let festivals: [ZXFestival] }

    private static func load() -> ZXCultureData {
        let shichen: ShichenFile = decode("shichen")
        let suishi: SuishiFile = decode("suishi")
        return ZXCultureData(
            hou: (decode("hou72") as Items<ZXHou>).items,
            huaxin: (decode("huaxin") as Items<ZXHuaxin>).items,
            shichen: shichen.items,
            geng: shichen.geng,
            termVerses: suishi.terms,
            festivals: suishi.festivals
        )
    }

    /// 随包资源缺失或解不开是打包错误, 不是运行时可恢复的情况 —— 直接崩并说清楚是哪个文件,
    /// 比悄悄返回空表、让界面显示一片空白好查。
    static func decode<T: Decodable>(_ name: String) -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            preconditionFailure("ZixiaoCalendar: 随包资源 \(name).json 缺失")
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            preconditionFailure("ZixiaoCalendar: \(name).json 解析失败: \(error)")
        }
    }

    func hou(term: String, order: Int) -> ZXHou? {
        hou.first { $0.term == term && $0.order == order }
    }

    func huaxin(term: String, order: Int) -> ZXHuaxin? {
        huaxin.first { $0.term == term && $0.order == order }
    }

    func termVerse(_ term: String) -> ZXTermVerse? {
        termVerses.first { $0.term == term }
    }
}
