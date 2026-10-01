import Foundation

/// Reviewed reading paths and historical place overlays, bundled separately from raw archival records.
struct PoetGuide: Decodable, Sendable {
    let biography: String
    let chronologyNote: String
    let snapshotDate: String
    let yearCounts: [String: Int]
    let chapters: [LifeChapter]
    let places: [HistoricalPlace]
    let visits: [LifeVisit]
    let featured: [FeaturedWork]
    let poems: [Poem]
    let sources: [GuideSource]

    var archiveCounts: [Int: Int] {
        Dictionary(uniqueKeysWithValues: yearCounts.compactMap { key, value in Int(key).map { ($0, value) } })
    }
    func chapter(_ epoch: Epoch) -> LifeChapter? { chapters.first { $0.id == epoch.sequence } }
    func chapter(containing poemID: UUID) -> LifeChapter? { chapters.first { $0.workIDs.contains(poemID) } }
    func poem(_ id: UUID) -> Poem? { poems.first { $0.id == id } }
    func poems(_ ids: [UUID]) -> [Poem] {
        let indexed = Dictionary(uniqueKeysWithValues: poems.map { ($0.id, $0) })
        return ids.compactMap { indexed[$0] }
    }
    func workOfDay(_ date: Date, form: String) -> Poem? {
        let choices = poems.filter { $0.form == form }
        guard let index = DailyRotation.index(on: date, count: choices.count) else { return nil }
        return choices[index]
    }
    func title(_ poem: Poem) -> String { featured.first { $0.id == poem.id }?.title ?? poem.title }
    /// 解码随 App 包发的导读。查找与报错在 `PoetResources`。
    static func decode(_ data: Data) throws -> PoetGuide {
        try JSONDecoder().decode(Self.self, from: data)
    }
}
struct LifeChapter: Decodable, Sendable, Identifiable {
    var id: Int { epoch.sequence }
    let epoch: Epoch
    let introduction: String
    let paragraphs: [String]
    let milestones: [LifeMilestone]
    let workIDs: [UUID]
    let sourceIDs: [String]
}
struct LifeMilestone: Decodable, Sendable, Identifiable {
    let id: String
    let year: Int
    let title: String
    let detail: String
}
struct HistoricalPlace: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let modernName: String
    let latitude: Double
    let longitude: Double
    let note: String
    let sourceIDs: [String]
}
struct LifeVisit: Decodable, Sendable, Identifiable {
    let id: Int
    let placeID: String
    let yearStart: Int
    let yearEnd: Int
    let chapterID: Int
    let summary: String
    var period: String { yearStart == yearEnd ? "\(yearStart) 年" : "\(yearStart)—\(yearEnd)" }
}
struct FeaturedWork: Decodable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let note: String
    let form: String
}
struct GuideSource: Decodable, Sendable, Identifiable {
    let id: String
    let title: String
    let url: URL?
    let note: String
}

extension CompositionContext {
    var lifeEpochs: [Epoch] { (guide?.chapters.map(\.epoch) ?? store.epochs).sorted { $0.sequence < $1.sequence } }
    var literaryGenres: [Genre] {
        let available = (composition.placement(.corpus)?.genres ?? []).filter(\.isBrowsable)
        return ["shi", "ci", "wen", "fu"].compactMap { id in available.first { $0.id == id } }
    }
    func genre(for poem: Poem) -> Genre {
        literaryGenres.first { $0.id == poem.form } ?? Genre(id: poem.form, label: "诗文", count: nil, status: .ready)
    }
    /// Familiar titles (a cipai work known by its theme) may not occur in the archive's cipai-only title.
    func featuredPoems(matching query: String, form: String? = nil) -> [Poem] {
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let normalized = query.components(separatedBy: separators).joined()
        guard !normalized.isEmpty else { return [] }
        return guide?.poems.filter { poem in
            guard form == nil || poem.form == form else { return false }
            let title = workTitle(poem).components(separatedBy: separators).joined()
            return title.localizedStandardContains(normalized) || poem.content.localizedStandardContains(query)
        } ?? []
    }
    func combiningFeatured(_ fetched: [Poem], query: String, form: String? = nil) -> [Poem] {
        var seen = Set<UUID>()
        return Array((featuredPoems(matching: query, form: form) + fetched).filter { seen.insert($0.id).inserted }.prefix(200))
    }
    func workTitle(_ poem: Poem) -> String { guide?.title(poem) ?? poem.title }
}
