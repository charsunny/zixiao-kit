import Foundation

/// Curated introductions live with the app's content, separate from primary texts.
public struct Editorial: Decodable, Sendable {
    public let lifeIntroduction: String
    public let corpusIntroduction: String
    public let epochNotes: [String: String]?
    public let collections: [ReadingCollection]
    public let searchPrompts: [SearchPrompt]
}

public struct ReadingCollection: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let introduction: String
    public let symbol: String
    public let works: [ReadingSelection]
}

public struct ReadingSelection: Decodable, Sendable, Identifiable, Hashable {
    public var id: UUID { poemId }
    public let poemId: UUID
    public let note: String
}

public struct SearchPrompt: Decodable, Sendable, Identifiable {
    public var id: String { query }
    public let label: String
    public let query: String
    public let hint: String
    public let symbol: String
}

struct ReadingJourney {
    let collection: ReadingCollection
    let poems: [Poem]
    func index(of poem: Poem) -> Int? { poems.firstIndex { $0.id == poem.id } }
    func next(after poem: Poem) -> Poem? {
        guard let i = index(of: poem), poems.indices.contains(i + 1) else { return nil }
        return poems[i + 1]
    }
}
