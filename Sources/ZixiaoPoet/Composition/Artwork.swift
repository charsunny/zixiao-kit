import Foundation

struct Artwork: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let kind: String
    let attribution: String
    let dateLabel: String
    let medium: String
    let dimensions: String
    let collection: String
    let subtitle: String
    let introduction: String
    let lookingNotes: String
    let sourceTitle: String
    let sourceURL: URL
    let imageCredit: String
    let imageSourceURL: URL
    let licenseURL: URL
    let cover: String
    let images: [ArtworkImage]
    let relatedPoemID: UUID?
    let relatedPoemTitle: String?
    /// 对应导读章节的序号 (`guide.chapters[].epoch.sequence`)。未定年段的作品不写。
    let epochSequence: Int?
    /// 与作品相关的诗文 id (可多首; 单值 `relatedPoemID` 仍保留)。
    let relatedPoemIDs: [UUID]?
    /// 图像授权的简要标示 (如 CC BY 4.0)。完整出处与链接仍看 `imageCredit` / `licenseURL`。
    let license: ArtworkLicense?

    func matches(_ query: String) -> Bool {
        [title, kind, subtitle, introduction, collection, attribution].joined(separator: " ")
            .localizedStandardContains(query)
    }
    /// 解码随 App 包发的书画清单。查找与报错在 `PoetResources`。
    static func decodeList(_ data: Data) throws -> [Artwork] {
        try JSONDecoder().decode([Artwork].self, from: data)
    }
}
struct ArtworkImage: Codable, Identifiable, Sendable {
    var id: String { asset }
    let asset: String
    let caption: String
}
struct ArtworkLicense: Codable, Sendable, Equatable {
    let name: String
    let url: URL
    let holder: String?
}
