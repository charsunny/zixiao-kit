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

    public init(id: String, title: String, subtitle: String, introduction: String,
                symbol: String, works: [ReadingSelection]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.introduction = introduction
        self.symbol = symbol
        self.works = works
    }
}

public struct ReadingSelection: Decodable, Sendable, Identifiable, Hashable {
    public var id: UUID { poemId }
    public let poemId: UUID
    public let note: String

    public init(poemId: UUID, note: String) {
        self.poemId = poemId
        self.note = note
    }
}

public struct SearchPrompt: Decodable, Sendable, Identifiable {
    public var id: String { query }
    public let label: String
    public let query: String
    public let hint: String
    public let symbol: String
}

public struct ReadingJourney: Sendable {
    public let collection: ReadingCollection
    public let poems: [Poem]
    public init(collection: ReadingCollection, poems: [Poem]) {
        self.collection = collection
        self.poems = poems
    }
    public func index(of poem: Poem) -> Int? { poems.firstIndex { $0.id == poem.id } }
    public func next(after poem: Poem) -> Poem? {
        guard let i = index(of: poem), poems.indices.contains(i + 1) else { return nil }
        return poems[i + 1]
    }
}
