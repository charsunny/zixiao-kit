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

    /// 单色墨系仍是可加载身份，目录只列供产品选择的七套配色。
    public static let entries: [Entry] = {
        do {
            return try [
                Entry(.paperInkSeal, imagery: "暖纸、墨色、朱印"),
                Entry(.moonWhite, imagery: "冷月、青灰"),
                Entry(.xiangLeaf, imagery: "旧书缃帙、暖黄"),
                Entry(.canglang, imagery: "新竹、青绿"),
                Entry(.ouhe, imagery: "藕粉、淡紫"),
                Entry(.daiBlue, imagery: "远山黛、沉静"),
                Entry(.rouge, imagery: "胭脂、喜气")
            ]
        } catch { preconditionFailure("随包配色目录损坏：\(error)") }
    }()

    public static let seasonalID = "seasonal"

    public static func palette(for season: ZXSeasonTint) -> ZXBundledIdentity {
        switch season {
        case .spring: .canglang
        case .summer: .rouge
        case .lateSummer: .xiangLeaf
        case .autumn: .moonWhite
        case .winter: .daiBlue
        }
    }
}
