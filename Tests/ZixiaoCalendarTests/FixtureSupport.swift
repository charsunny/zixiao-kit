import Foundation
import XCTest

/// 金标 fixture 的定位与解码。
///
/// 用 `#filePath` 回溯到仓库根的 Fixtures/ 读取 —— 模拟器进程能直接读宿主机文件系统。
///
/// 为什么不走测试包资源: Package.swift 里 testTarget 声明了 `.copy("../../Fixtures")`,
/// 但该路径在目标目录之外, Xcode 的 SPM 集成不为它生成资源包 (测试目标里没有
/// `Bundle.module`, 编译报 inaccessible)。按冲刺约定不改 Package.swift, 改为直接读源码树。
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ZixiaoCalendarTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // 仓库根
        let url = root.appendingPathComponent("Fixtures/\(name).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            // 不用 XCTSkip: 金标缺失必须是失败, 否则「全绿」会掩盖根本没比对。
            throw Missing(message: "找不到 fixture \(name).json (查找路径 \(url.path))")
        }
        return try Data(contentsOf: url)
    }

    struct Missing: Error, CustomStringConvertible { let message: String; var description: String { message } }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(name))
    }
}

// MARK: - calendar-2025-2027.json 的形状

struct CalendarFixture: Decodable {
    let timeZone: String
    let sampleHour: Int
    let days: [DayRow]

    struct DayRow: Decodable, Equatable, CustomStringConvertible {
        struct Lunar: Decodable, Equatable { let year, month, day: Int; let isLeap: Bool; let label: String }
        struct Ganzhi: Decodable, Equatable { let year, month, day: String }
        struct Term: Decodable, Equatable { let name: String; let index: Int }
        struct Hou: Decodable, Equatable { let index: Int; let term: String; let order: Int; let name: String }
        struct Huaxin: Decodable, Equatable { let index: Int; let term: String; let order: Int; let flower: String }

        let gregorian: String
        let lunar: Lunar
        let ganzhi: Ganzhi
        let term: Term
        let isTermDay: Bool
        let nextTerm: String
        let daysToNextTerm: Int
        let hou: Hou
        let huaxin: Huaxin?
        let festivalsWithin7Days: [String]

        var description: String {
            "\(gregorian) 农历\(lunar.year)-\(lunar.isLeap ? "闰" : "")\(lunar.month)-\(lunar.day)(\(lunar.label)) "
                + "\(ganzhi.year)/\(ganzhi.month)/\(ganzhi.day) \(term.name)#\(term.index)"
                + "\(isTermDay ? "[交节]" : "") →\(nextTerm) \(daysToNextTerm)天 "
                + "候\(hou.index) \(hou.term)\(hou.order) \(hou.name) "
                + "花信\(huaxin.map { "\($0.index)\($0.flower)" } ?? "-") 节日\(festivalsWithin7Days)"
        }
    }
}

// MARK: - shichen.json 的形状

struct ShichenFixture: Decodable {
    let probes: [Probe]

    struct Probe: Decodable {
        struct Geng: Decodable, Equatable { let index: Int; let name: String }
        let of: String
        let probe: String
        let time: String
        let iso: String
        let branch: String
        let ancientName: String
        let geng: Geng?
    }
}

// MARK: - almanac-2026.json 的形状

struct AlmanacFixture: Decodable {
    let timeZone: String
    let sampleHour: Int
    let days: [DayRow]

    struct DayRow: Decodable, Equatable, CustomStringConvertible {
        struct Deities: Decodable, Equatable { let xi, cai, fu: String }
        struct Xiu: Decodable, Equatable { let name, zheng, animal, luck: String }
        struct PengZu: Decodable, Equatable { let gan, zhi: String }
        struct Hour: Decodable, Equatable, CustomStringConvertible {
            let branch, ganZhi, tianShen: String
            let auspicious: Bool
            let yi, ji: [String]
            var description: String {
                "\(branch)\(ganZhi)\(tianShen)\(auspicious ? "吉" : "凶") 宜\(yi.joined(separator: "、")) 忌\(ji.joined(separator: "、"))"
            }
        }

        let gregorian: String
        let yi, ji: [String]
        let officer, tianShen, huangDao: String
        let auspicious: Bool
        let clashZodiac, sha: String
        let deities: Deities
        let xiu: Xiu
        let pengZu: PengZu
        let hours: [Hour]

        var description: String {
            "\(gregorian) 宜\(yi.joined(separator: "、")) 忌\(ji.joined(separator: "、")) \(officer)日 "
                + "\(tianShen)\(huangDao)\(auspicious ? "吉" : "凶") 冲\(clashZodiac)煞\(sha) "
                + "喜\(deities.xi)财\(deities.cai)福\(deities.fu) \(xiu.name)\(xiu.zheng)\(xiu.animal)\(xiu.luck) "
                + "\(pengZu.gan) \(pengZu.zhi)"
        }
    }
}
