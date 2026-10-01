import Foundation

struct Artwork: Decodable, Identifiable, Sendable {
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

    func matches(_ query: String) -> Bool {
        [title, kind, subtitle, introduction, collection, attribution].joined(separator: " ")
            .localizedStandardContains(query)
    }
    /// 解码随 App 包发的书画清单。查找与报错在 `PoetResources`。
    static func decodeList(_ data: Data) throws -> [Artwork] {
        try JSONDecoder().decode([Artwork].self, from: data)
    }
}
struct ArtworkImage: Decodable, Identifiable, Sendable {
    var id: String { asset }
    let asset: String
    let caption: String
}
