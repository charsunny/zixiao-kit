import Foundation

public struct Artwork: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let kind: String
    public let attribution: String
    public let dateLabel: String
    public let medium: String
    public let dimensions: String
    public let collection: String
    public let subtitle: String
    public let introduction: String
    public let lookingNotes: String
    public let sourceTitle: String
    public let sourceURL: URL
    public let imageCredit: String
    public let imageSourceURL: URL
    public let licenseURL: URL
    public let cover: String
    public let images: [ArtworkImage]
    public let relatedPoemID: UUID?
    public let relatedPoemTitle: String?
    /// 对应导读章节的序号 (`guide.chapters[].epoch.sequence`)。未定年段的作品不写。
    public let epochSequence: Int?
    /// 与作品相关的诗文 id (可多首; 单值 `relatedPoemID` 仍保留)。
    public let relatedPoemIDs: [UUID]?
    /// 图像授权的简要标示 (如 CC BY 4.0)。完整出处与链接仍看 `imageCredit` / `licenseURL`。
    public let license: ArtworkLicense?

    public func matches(_ query: String) -> Bool {
        [title, kind, subtitle, introduction, collection, attribution].joined(separator: " ")
            .localizedStandardContains(query)
    }
    /// 解码随 App 包发的书画清单。查找与报错在 `PoetResources`。
    public static func decodeList(_ data: Data) throws -> [Artwork] {
        try JSONDecoder().decode([Artwork].self, from: data)
    }
}
public struct ArtworkImage: Codable, Identifiable, Sendable {
    public var id: String { asset }
    public let asset: String
    public let caption: String
}
public struct ArtworkLicense: Codable, Sendable, Equatable {
    public let name: String
    public let url: URL
    public let holder: String?
}
