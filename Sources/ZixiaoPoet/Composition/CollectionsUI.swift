import ZixiaoPoetCore
import Foundation
import ZixiaoDesign

public extension PoetCollections.Collection {
    var seasonTint: ZXSeasonTint? { season.flatMap(ZXSeasonTint.init(rawValue:)) }
}

// MARK: - 诗文根页上的「一张合集卡」

/// 选读里的一张卡: 来自合集文件; 没有合集文件时退回编成里的主题共读, 再加导读的「名篇」一组。
/// 三种来路在界面上一视同仁 (画屏 + 竖排题 + 旨), 合集页也只认它。
struct CorpusSelection: Identifiable, Hashable, Sendable {
    struct Entry: Hashable, Sendable, Identifiable {
        var id: UUID { workID }
        let workID: UUID
        let note: String?
    }

    let id: String
    let title: String
    let thesis: String
    let intro: String
    /// 画屏配方 (seed 来自数据: 合集的地望, 或编成里的合集 id)。
    let art: PoetScreenArt
    let entries: [Entry]

    var workIDs: [UUID] { entries.map(\.workID) }

    /// 读本「接着读」用的共读 (`ReadingJourney` 只认 `ReadingCollection`)。
    var readingCollection: ReadingCollection {
        ReadingCollection(id: id, title: title, subtitle: thesis, introduction: intro, symbol: "book",
                          works: entries.map { ReadingSelection(poemId: $0.workID, note: $0.note ?? "") })
    }

    init(id: String, title: String, thesis: String, intro: String, art: PoetScreenArt, entries: [Entry]) {
        self.id = id
        self.title = title
        self.thesis = thesis
        self.intro = intro
        self.art = art
        self.entries = entries
    }

    init(_ collection: PoetCollections.Collection) {
        self.init(id: collection.id, title: collection.title, thesis: collection.thesis, intro: collection.intro,
                  art: PoetScreenArt(seed: collection.placeSeed, season: collection.seasonTint),
                  entries: collection.workIds.map { Entry(workID: $0, note: collection.note(for: $0)) })
    }

    /// 编成里的主题共读 (旧格式): 没有地望, 画屏的 seed 用合集 id。
    init(_ collection: ReadingCollection) {
        self.init(id: "editorial.\(collection.id)", title: collection.title, thesis: collection.subtitle,
                  intro: collection.introduction, art: PoetScreenArt(seed: collection.id),
                  entries: collection.works.map { Entry(workID: $0.poemId, note: $0.note) })
    }

    /// 选读的全部卡片。合集文件在就只用它; 不在就是编成的主题共读 + 导读的名篇一组。都没有为空 (整节收起)。
    static func shelf(collections: PoetCollections?, editorial: [ReadingCollection],
                      featured: [FeaturedWork], featuredIntro: String?, seed: String) -> [CorpusSelection] {
        if let collections, !collections.collections.isEmpty {
            return collections.collections.filter { !$0.workIds.isEmpty }.map(CorpusSelection.init)
        }
        var shelf = editorial.filter { !$0.works.isEmpty }.map(CorpusSelection.init)
        if !featured.isEmpty {
            shelf.append(CorpusSelection(
                id: featuredID, title: "名篇", thesis: "从代表作读起",
                intro: featuredIntro ?? "从代表作开始，慢慢读进这位诗人的作品。",
                art: PoetScreenArt(seed: "\(seed)#featured"),
                entries: featured.map { Entry(workID: $0.id, note: $0.note) }))
        }
        return shelf
    }

    static let featuredID = "guide.featured"
}

extension CompositionContext {
    /// 诗文根页「选读」的卡片 (见 `CorpusSelection.shelf`)。
    var corpusSelections: [CorpusSelection] {
        CorpusSelection.shelf(collections: collections, editorial: composition.editorial?.collections ?? [],
                              featured: guide?.featured ?? [], featuredIntro: composition.editorial?.corpusIntroduction,
                              seed: composition.poet.slug)
    }
}
