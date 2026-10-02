import Foundation
import XCTest
@testable import ZixiaoPoet

/// 「按年读」: 逐年篇数的聚合 (RPC 行与客户端退路) 与年份轴模型。
final class CorpusYearAxisTests: XCTestCase {
    private let a = UUID(uuidString: PoetFixtures.poemA)!
    private let b = UUID(uuidString: PoetFixtures.poemB)!
    private let c = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    func testRPCRowsSplitDatedAndUndated() {
        let years = PoetWorkYears(rows: [.init(year: 1082, n: 3), .init(year: 1084, n: 0),
                                         .init(year: 1082, n: 1), .init(year: nil, n: 40)])
        XCTAssertEqual(years.counts, [1082: 4], "零篇的年不留; 同一年两行取和")
        XCTAssertEqual(years.undated, 40)
        XCTAssertFalse(years.isEmpty)
        XCTAssertTrue(PoetWorkYears(rows: []).isEmpty)
    }

    func testClientEdgesCountDistinctWorksPerYear() {
        // 同一篇同一年挂两条事目只算一次; 跨两年各算一次, 但系年总篇数去重。
        let years = PoetWorkYears(edges: [(a, 1082), (a, 1082), (b, 1082), (b, 1083), (c, 1083)])
        XCTAssertEqual(years.counts, [1082: 2, 1083: 2])
        XCTAssertEqual(years.datedWorks, 3)
        XCTAssertNil(years.undated, "客户端退路不知道库里总篇数")
    }

    func testOrderedIDsKeepFirstOccurrence() {
        XCTAssertEqual(PoetWorkYears.orderedIDs([b, a, b, c, a]), [b, a, c])
    }

    func testRPCParamsEncodeLowercasedID() throws {
        let id = UUID(uuidString: "C825DAA8-E1A7-5BB5-B9A3-D1C4A29DF70A")!
        let data = try JSONEncoder().encode(PoetRPC.WorksOfYearParams(poetId: id, year: 1082))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["p_poet_id"] as? String, "c825daa8-e1a7-5bb5-b9a3-d1c4a29df70a")
        XCTAssertEqual(json["p_year"] as? Int, 1082)
        let rows = try JSONDecoder().decode([PoetRPC.YearWork].self, from: Data("""
        [{"poem_id":"\(PoetFixtures.poemA)","month":3,"day":7},{"poem_id":"\(PoetFixtures.poemB)","month":null,"day":null}]
        """.utf8))
        XCTAssertEqual(rows.map(\.poemId), [a, b])
        XCTAssertNil(rows[1].month)
    }

    private var chapters: [CorpusYearAxis.Chapter] {
        [.init(start: 1036, end: 1056, label: "少年"), .init(start: 1080, end: 1084, label: "谪居"),
         .init(start: 1057, end: 1079, label: "仕宦")]
    }

    func testAxisSpansLifeAndMarksChapterStarts() throws {
        let axis = CorpusYearAxis(lifespan: 1037...1101, counts: [1059: 4, 1082: 53, 1087: 265, 1102: 1],
                                  chapters: chapters, undated: 12)
        // 生年到卒年每年一格; 越出卒年的系年也收进来。
        XCTAssertEqual(axis.cells.first?.year, 1037)
        XCTAssertEqual(axis.cells.last?.year, 1102)
        XCTAssertEqual(axis.cells.count, 1102 - 1037 + 1)
        XCTAssertEqual(axis.maxCount, 265)
        XCTAssertEqual(axis.totalDated, 4 + 53 + 265 + 1)
        XCTAssertEqual(axis.undated, 12)
        XCTAssertFalse(axis.isEmpty)

        // 分期按起始年排; 起始年早于生年的那一卷不在轴上画分隔, 其后各卷的起始年画。
        XCTAssertEqual(axis.chapters.map(\.start), [1036, 1057, 1080])
        XCTAssertEqual(axis.cells.filter(\.startsChapter).map(\.year), [1057, 1080])
        XCTAssertEqual(axis.cell(1037)?.chapterLabel, "少年")
        XCTAssertEqual(axis.cell(1082)?.chapterLabel, "谪居")
        XCTAssertEqual(axis.cell(1090)?.chapterLabel, "谪居", "末卷之后的空档归最后一卷")
        XCTAssertEqual(axis.cell(1082)?.count, 53)
        XCTAssertEqual(axis.cell(1040)?.hasWorks, false)
    }

    func testPeakYearAndFocusRange() {
        let axis = CorpusYearAxis(lifespan: 1037...1101, counts: [1059: 4, 1060: 4, 1082: 53, 1087: 265],
                                  chapters: chapters, undated: nil)
        XCTAssertEqual(axis.peakYear(), 1087)
        XCTAssertEqual(axis.peakYear(in: 1080...1084), 1082)
        XCTAssertEqual(axis.peakYear(in: 1057...1079), 1059, "同数取早")
        XCTAssertEqual(axis.peakYear(in: 1040...1045), 1087, "这段一篇没有就取全轴")

        // 当前一卷: 读过的卷 → 编好的长卷 → 作品最多的那一卷。
        XCTAssertEqual(CorpusYearAxis.focusRange(readChapter: 1057...1079, writtenChapter: 1080...1084, axis: axis), 1057...1079)
        XCTAssertEqual(CorpusYearAxis.focusRange(readChapter: nil, writtenChapter: 1080...1084, axis: axis), 1080...1084)
        XCTAssertEqual(CorpusYearAxis.focusRange(readChapter: nil, writtenChapter: nil, axis: axis), 1080...1084,
                       "1087 落在末卷 (1080 起) 里")
    }

    func testEmptyAxisCollapses() {
        let axis = CorpusYearAxis(lifespan: 701...762, counts: [:], chapters: [], undated: nil)
        XCTAssertTrue(axis.isEmpty)
        XCTAssertEqual(axis.cells.count, 62)
        XCTAssertNil(axis.peakYear())
        XCTAssertNil(CorpusYearAxis.focusRange(readChapter: nil, writtenChapter: nil, axis: axis))
    }
}
