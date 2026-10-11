@testable import ZixiaoPoetCore
import Foundation
import XCTest
@testable import ZixiaoPoet

/// 选读合集 (collections-<slug>.json) 的解码、载入与根页卡片的退路。
final class CollectionsTests: XCTestCase {
    /// 与内容代理的 schema 同形的小样本 (D10 的 collections-<slug>.json)。
    static let fixture = """
    {
      "schemaVersion": 1,
      "poet": "test",
      "collections": [
        {
          "id": "rain",
          "title": "风雨也从容",
          "thesis": "一场雨里看见的从容",
          "intro": "先听一场雨，再看一条向西流的溪水，最后问一问何处是故乡。",
          "placeSeed": "riverside",
          "season": "autumn",
          "workIds": ["\(PoetFixtures.poemA)", "not-a-uuid", "\(PoetFixtures.poemB.uppercased())"],
          "notes": { "\(PoetFixtures.poemA)": "从脚下的一场雨开始。", "\(PoetFixtures.poemB.uppercased())": "  " }
        },
        {
          "id": "moon",
          "title": "月亮照见谁",
          "thesis": "同一轮月",
          "intro": "几首写月的诗。",
          "placeSeed": "lake",
          "season": null,
          "workIds": ["\(PoetFixtures.poemB)"]
        }
      ]
    }
    """

    func testDecodesCollectionsAndToleratesOneBadWorkID() throws {
        let decoded = try PoetCollections.decode(Data(Self.fixture.utf8))
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.poet, "test")
        XCTAssertEqual(decoded.collections.map(\.id), ["rain", "moon"])

        let rain = try XCTUnwrap(decoded.collection(id: "rain"))
        // 写坏的一条 id 只丢那一篇; 大写 uuid 照样认。
        XCTAssertEqual(rain.workIds, [UUID(uuidString: PoetFixtures.poemA), UUID(uuidString: PoetFixtures.poemB)])
        XCTAssertEqual(rain.seasonTint, .autumn)
        XCTAssertEqual(rain.note(for: try XCTUnwrap(UUID(uuidString: PoetFixtures.poemA))), "从脚下的一场雨开始。")
        // 空白按语当作没有; 没有 notes 的合集也解得开。
        XCTAssertNil(rain.note(for: try XCTUnwrap(UUID(uuidString: PoetFixtures.poemB))))
        let moon = try XCTUnwrap(decoded.collection(id: "moon"))
        XCTAssertNil(moon.seasonTint)
        XCTAssertNil(moon.notes)
    }

    func testRejectsNewerSchema() {
        let newer = Self.fixture.replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 2")
        XCTAssertThrowsError(try PoetCollections.decode(Data(newer.utf8)))
    }

    func testLoaderToleratesAbsenceAndReportsCorruption() throws {
        // 包里没有: 不是错, 返回 nil (选读退回编成与导读)。
        let empty = try PoetFixtures.bundle(files: [:])
        XCTAssertNil(try PoetResources(bundle: empty, slug: "test", productName: "测试志").collections())
        XCTAssertNil(PoetCollections.load(from: empty, poetSlug: "test"))

        // 有就读出来。
        let bundle = try PoetFixtures.bundle(files: ["collections-test.json": Self.fixture])
        XCTAssertEqual(PoetCollections.load(from: bundle, poetSlug: "test")?.collections.count, 2)

        // 有但解不开: 诊断入口抛错, 便捷入口收起 (nil)。
        let broken = try PoetFixtures.bundle(files: ["collections-test.json": "{ nope"])
        let resources = PoetResources(bundle: broken, slug: "test", productName: "测试志")
        XCTAssertThrowsError(try resources.collections()) { error in
            guard case .unreadable(product: "测试志", resource: "collections-test.json", _)? = error as? PoetResourceError
            else { return XCTFail("unexpected \(error)") }
        }
        XCTAssertNil(PoetCollections.load(from: broken, poetSlug: "test"))
    }

    func testShelfPrefersCollectionsFileThenFallsBack() throws {
        let file = try PoetCollections.decode(Data(Self.fixture.utf8))
        let a = try XCTUnwrap(UUID(uuidString: PoetFixtures.poemA))
        let editorial = [ReadingCollection(id: "weather", title: "旧合集", subtitle: "旧副题", introduction: "旧导读",
                                           symbol: "cloud", works: [ReadingSelection(poemId: a, note: "按语")])]
        let featured = [FeaturedWork(id: a, title: "名篇一", note: "名篇按语", form: "shi")]

        // 合集文件在: 只用它, 画屏 seed 与季节来自数据。
        let shelf = CorpusSelection.shelf(collections: file, editorial: editorial, featured: featured,
                                          featuredIntro: nil, seed: "test")
        XCTAssertEqual(shelf.map(\.id), ["rain", "moon"])
        XCTAssertEqual(shelf[0].art.seed, "riverside")
        XCTAssertEqual(shelf[0].art.season, .autumn)
        XCTAssertEqual(shelf[0].entries.first?.note, "从脚下的一场雨开始。")
        // 读本「接着读」用的共读保持篇序。
        XCTAssertEqual(shelf[0].readingCollection.works.map(\.poemId), shelf[0].workIDs)

        // 不在: 编成的主题共读 + 导读名篇一组。
        let fallback = CorpusSelection.shelf(collections: nil, editorial: editorial, featured: featured,
                                             featuredIntro: "从代表作读起。", seed: "test")
        XCTAssertEqual(fallback.map(\.title), ["旧合集", "名篇"])
        XCTAssertEqual(fallback.last?.id, CorpusSelection.featuredID)
        XCTAssertEqual(fallback.last?.entries.first?.note, "名篇按语")
        XCTAssertEqual(fallback.last?.intro, "从代表作读起。")

        // 什么都没有: 整节收起。
        XCTAssertTrue(CorpusSelection.shelf(collections: nil, editorial: [], featured: [], featuredIntro: nil,
                                            seed: "test").isEmpty)
    }

    /// 旁边的 zhi 仓库里已有正式合集文件时, 整份解一遍 (没有就跳过)。
    func testBundledCollectionsDecodeWhenPresent() throws {
        let url = PoetFixtures.workspaceRoot
            .appendingPathComponent("zhi/apple/App/Resources")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let collections = files.filter { $0.hasPrefix("collections-") && $0.hasSuffix(".json") }
        try XCTSkipIf(collections.isEmpty, "zhi 仓库里还没有合集文件")
        for name in collections {
            let decoded = try PoetCollections.decode(Data(contentsOf: url.appendingPathComponent(name)))
            XCTAssertFalse(decoded.collections.isEmpty, name)
            for collection in decoded.collections {
                XCTAssertFalse(collection.workIds.isEmpty, "\(name) · \(collection.id)")
            }
        }
    }
}
