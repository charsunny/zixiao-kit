//  ZXPaletteCatalog.swift — 配色目录与五行之季，不包含产品档位。
import Foundation

public enum ZXPaletteCatalog {
    public struct Entry: Identifiable, Sendable, Hashable {
        public let bundled: ZXBundledIdentity
        public let name: String
        public let imagery: String
        public let identity: ZXIdentity
        public let id: String
        public var light: ZXIdentity.Swatch { identity.palette.light }
        public var dark: ZXIdentity.Swatch { identity.palette.dark }

        public init(_ bundled: ZXBundledIdentity, imagery: String) throws {
            self.bundled = bundled
            self.id = bundled.rawValue
            self.identity = try ZXIdentity.bundled(bundled)
            self.name = identity.name
            self.imagery = imagery
        }

        /// 产品可把自身默认身份作为目录卡片，id 与展示名仍由产品决定。
        public init(_ bundled: ZXBundledIdentity, id: String, name: String,
                    imagery: String, identity: ZXIdentity) {
            self.bundled = bundled
            self.id = id
            self.name = name
            self.imagery = imagery
            self.identity = identity
        }
    }

    /// 目录仅列七套第四稿配色；既有单色墨系与纸墨朱印仍可独立加载。
    public static let entries: [Entry] = {
        do {
            return try [
                Entry(.yaqing, imagery: "苍黑、青灰、月白"),
                Entry(.moonWhite, imagery: "花青 × 赭石"),
                Entry(.xiangLeaf, imagery: "深缃 × 绀青"),
                Entry(.canglang, imagery: "石绿 × 赭石"),
                Entry(.ousi, imagery: "茄紫 × 柳绿"),
                Entry(.qingdai, imagery: "青黛 × 泥金"),
                Entry(.rouge, imagery: "胭脂 × 石绿")
            ]
        } catch { preconditionFailure("随包配色目录损坏：\(error)") }
    }()

    public static let seasonalID = "seasonal"

    public static func seasonalLabel(for season: ZXSeasonTint) -> String {
        let name: String
        switch season {
        case .spring: name = "春"
        case .summer: name = "夏"
        case .lateSummer: name = "长夏"
        case .autumn: name = "秋"
        case .winter: name = "冬"
        }
        let entry = entries.first { $0.bundled == palette(for: season) }
        return "随节气 · \(name) · \(entry?.name ?? "")"
    }

    public static func palette(for season: ZXSeasonTint) -> ZXBundledIdentity {
        switch season {
        case .spring: .canglang
        case .summer: .rouge
        case .lateSummer: .xiangLeaf
        case .autumn: .moonWhite
        case .winter: .qingdai
        }
    }
}
