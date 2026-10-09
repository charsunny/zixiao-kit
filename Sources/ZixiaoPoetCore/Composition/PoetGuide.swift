import Foundation

/// Reviewed reading paths and historical place overlays, bundled separately from raw archival records.
public struct PoetGuide: Decodable, Sendable {
    public let biography: String
    public let chronologyNote: String
    public let snapshotDate: String
    public let yearCounts: [String: Int]
    public let chapters: [LifeChapter]
    public let places: [HistoricalPlace]
    public let visits: [LifeVisit]
    public let featured: [FeaturedWork]
    public let poems: [Poem]
    public let sources: [GuideSource]

    public var archiveCounts: [Int: Int] {
        Dictionary(uniqueKeysWithValues: yearCounts.compactMap { key, value in Int(key).map { ($0, value) } })
    }
    public func chapter(_ epoch: Epoch) -> LifeChapter? { chapters.first { $0.id == epoch.sequence } }
    public func chapter(containing poemID: UUID) -> LifeChapter? { chapters.first { $0.workIDs.contains(poemID) } }
    public func poem(_ id: UUID) -> Poem? { poems.first { $0.id == id } }
    public func poems(_ ids: [UUID]) -> [Poem] {
        let indexed = Dictionary(uniqueKeysWithValues: poems.map { ($0.id, $0) })
        return ids.compactMap { indexed[$0] }
    }
    public func workOfDay(_ date: Date, form: String) -> Poem? {
        let choices = poems.filter { $0.form == form }
        guard let index = DailyRotation.index(on: date, count: choices.count) else { return nil }
        return choices[index]
    }
    public func title(_ poem: Poem) -> String { featured.first { $0.id == poem.id }?.title ?? poem.title }
    /// 解码随 App 包发的导读。查找与报错在 `PoetResources`。
    public static func decode(_ data: Data) throws -> PoetGuide {
        try JSONDecoder().decode(Self.self, from: data)
    }
}
public struct LifeChapter: Decodable, Sendable, Identifiable {
    public var id: Int { epoch.sequence }
    public let epoch: Epoch
    public let introduction: String
    public let paragraphs: [String]
    public let milestones: [LifeMilestone]
    public let workIDs: [UUID]
    public let sourceIDs: [String]
}
public struct LifeMilestone: Decodable, Sendable, Identifiable {
    public let id: String
    public let year: Int
    public let title: String
    public let detail: String
}
public struct HistoricalPlace: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let modernName: String
    public let latitude: Double
    public let longitude: Double
    public let note: String
    public let sourceIDs: [String]
}
public struct LifeVisit: Decodable, Sendable, Identifiable {
    public let id: Int
    public let placeID: String
    public let yearStart: Int
    public let yearEnd: Int
    public let chapterID: Int
    public let summary: String
    public var period: String { yearStart == yearEnd ? "\(yearStart) 年" : "\(yearStart)—\(yearEnd)" }
}
public struct FeaturedWork: Decodable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let note: String
    public let form: String
}
public struct GuideSource: Decodable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let url: URL?
    public let note: String
}

public extension CompositionContext {
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
