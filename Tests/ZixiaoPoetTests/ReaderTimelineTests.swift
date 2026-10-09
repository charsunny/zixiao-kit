@testable import ZixiaoPoetCore
import Foundation
import XCTest
@testable import ZixiaoPoet

/// 读本「此时」的判定 (刻 > 事目 > 未编年)、同年作品的挑选、相关墨迹, 以及卡上的文字。纯函数, 不联网。
final class ReaderTimelineTests: XCTestCase {
    private let poem = UUID(uuidString: "0EC22989-9344-58E5-BEA7-C1AC04416648")!
    private let other = UUID(uuidString: "260C391B-7912-5B03-AE48-A38EF49A6F07")!
    private let poet = UUID(uuidString: "C825DAA8-E1A7-5BB5-B9A3-D1C4A29DF70A")!
    private let station = UUID(uuidString: "9DDB09CB-4EBA-4FA1-A6DA-B0F85862A346")!

    // MARK: fixture

    private func moments(workId: UUID?) -> PoetMoments {
        let date = PoetMoments.MomentDate(year: 1082, month: 3, lunar: "元丰五年三月（寒食）",
                                          eraLabel: "元丰五年", precision: .month)
        let moment = PoetMoments.Moment(id: "t-1082-03-rain", date: date, placeLabel: "黄州", title: "寒食雨",
                                        lede: "自我来黄州，已过三寒食。", body: "处境。", workId: workId,
                                        artworkId: "scroll-a")
        let stub = PoetMoments.Chapter(epochSequence: 3, title: "前卷", startYear: 1070, endYear: 1079,
                                       thesis: "旨。", placeSeed: "seed-a")
        let chapter = PoetMoments.Chapter(epochSequence: 4, title: "本卷", startYear: 1080, endYear: 1084,
                                          thesis: "旨。", placeSeed: "seed-b", moments: [moment])
        return PoetMoments(schemaVersion: 1, poet: "test", chapters: [stub, chapter])
    }

    /// PostgREST 内连接返回的行形状 (`match_score, poet_events!inner(…, poet_id, poet_stations(source_name))`)。
    private func link(id: String, year: Int, month: Int?, day: Int?, score: Double?,
                      content: String = "1082年3月5日，在黄冈，任黄州团练副使。清明，友人分新火，有诗。作品：《某诗》。",
                      stationName: String? = "黄冈市") throws -> WorkEventLink {
        func json(_ v: Int?) -> String { v.map(String.init) ?? "null" }
        let station = stationName.map { #"{"source_name": "\#($0)"}"# } ?? "null"
        let row = """
        {"match_score": \(score.map { String($0) } ?? "null"),
         "poet_events": {"id": "\(id)", "station_id": "\(self.station)", "year": \(year), "month": \(json(month)),
           "day": \(json(day)), "is_leap_month": false, "date_precision": "\(day == nil ? (month == nil ? "year" : "month") : "day")",
           "content": "\(content)", "work_titles": ["某诗"], "source_ref": null,
           "poet_id": "\(poet)", "poet_stations": \(station)}}
        """
        return try JSONDecoder().decode(WorkEventLink.self, from: Data(row.utf8))
    }

    private func artworks() throws -> [Artwork] {
        func entry(_ id: String, single: String?, many: [String]?) -> String {
            let manyJSON = many.map { "[" + $0.map { "\"\($0)\"" }.joined(separator: ",") + "]" } ?? "null"
            return """
            {"id": "\(id)", "title": "\(id)", "kind": "书法", "attribution": "a", "dateLabel": "d", "medium": "m",
             "dimensions": "x", "collection": "c", "subtitle": "s", "introduction": "i", "lookingNotes": "l",
             "sourceTitle": "t", "sourceURL": "https://example.com/1", "imageCredit": "c",
             "imageSourceURL": "https://example.com/1", "licenseURL": "https://example.com/t", "cover": "\(id).jpg",
             "images": [], "relatedPoemID": \(single.map { "\"\($0)\"" } ?? "null"), "relatedPoemTitle": null,
             "relatedPoemIDs": \(manyJSON)}
            """
        }
        let list = [entry("many", single: nil, many: [other.uuidString, poem.uuidString]),
                    entry("none", single: nil, many: nil),
                    entry("single", single: poem.uuidString, many: nil),
                    entry("elsewhere", single: other.uuidString, many: [other.uuidString])]
        return try Artwork.decodeList(Data("[\(list.joined(separator: ","))]".utf8))
    }

    // MARK: 判定

    func testMomentWinsOverEventLinks() throws {
        let links = [try link(id: "00000000-0000-4000-8000-000000000001", year: 1081, month: 1, day: 1, score: 1)]
        let placement = ReaderTimeline.placement(of: poem, moments: moments(workId: poem), links: links)
        guard case .moment(let moment) = placement else { return XCTFail("应取刻: \(placement)") }
        XCTAssertEqual(moment.id, "t-1082-03-rain")
        XCTAssertEqual(placement.year, 1082, "年份取刻的, 不取事目的")
        XCTAssertNil(placement.poetID, "刻不带诗人 id, 要另查作者")
        XCTAssertEqual(ReaderTimeline.momentLine(moment), "元丰五年 · 三月（寒食） · 黄州")
    }

    func testEventLinksWhenNoMomentPinsPrimaryYear() throws {
        let links = [
            try link(id: "00000000-0000-4000-8000-000000000001", year: 1084, month: nil, day: nil, score: 0.6),
            try link(id: "00000000-0000-4000-8000-000000000002", year: 1082, month: 7, day: 16, score: 1),
            try link(id: "00000000-0000-4000-8000-000000000003", year: 1082, month: 3, day: 5, score: 0.9),
            try link(id: "00000000-0000-4000-8000-000000000002", year: 1082, month: 7, day: 16, score: 1), // 重复边
        ]
        let placement = ReaderTimeline.placement(of: poem, moments: moments(workId: other), links: links)
        guard case .events(let events) = placement else { return XCTFail("应取事目: \(placement)") }
        XCTAssertEqual(events.map(\.event.month), [3, 7], "主事目 (分最高) 那一年, 按月日排, 去重; 别年不混入")
        XCTAssertEqual(placement.year, 1082)
        XCTAssertEqual(placement.poetID, poet)
    }

    func testScoreTieFallsBackToEarliestAndMissingScoreRanksLast() throws {
        let links = [
            try link(id: "00000000-0000-4000-8000-000000000001", year: 1090, month: 1, day: 1, score: nil),
            try link(id: "00000000-0000-4000-8000-000000000002", year: 1085, month: nil, day: nil, score: 0.8),
            try link(id: "00000000-0000-4000-8000-000000000003", year: 1083, month: 2, day: 1, score: 0.8),
        ]
        XCTAssertEqual(ReaderTimeline.placement(of: poem, moments: nil, links: links).year, 1083)
    }

    func testUndatedWithoutMomentOrLinks() {
        let placement = ReaderTimeline.placement(of: poem, moments: moments(workId: other), links: [])
        XCTAssertEqual(placement, .undated)
        XCTAssertNil(placement.year)
        XCTAssertEqual(ReaderTimeline.placement(of: poem, moments: nil, links: []), .undated)
    }

    // MARK: 同年作品 / 墨迹 / 计数

    func testContextualReadingKeepsLifeLinkWithoutClaimingAWorkYear() throws {
        let moment = PoetMoments.Moment(id: "reading-context", date: .init(year: 742,
            eraLabel: "天宝初", precision: .year), placeLabel: "诗中长安", title: "去留",
            lede: "按主题与人生背景并读。", body: "作年尚无定论。", workId: poem, workDating: .contextual)
        let source = PoetMoments(schemaVersion: 1, poet: "test", chapters: [.init(epochSequence: 0, title: "一卷", startYear: 740,
            endYear: 745, thesis: "人生背景", placeSeed: "test", moments: [moment])])
        let decoded = try PoetMoments.decode(JSONEncoder().encode(source))
        let placement = ReaderTimeline.placement(of: poem, moments: decoded, links: [])
        XCTAssertEqual(placement, .moment(moment))
        XCTAssertNil(placement.year, "背景中的排序节点不能成为诗篇系年或触发同年查询")
        XCTAssertEqual(ReaderTimeline.momentLine(moment), "主题选读 · 诗中长安")
        XCTAssertEqual(LifeJump.resolve(year: 742, in: decoded.chapters)?.chapter, 0)
        XCTAssertNil(LifeJump.resolve(year: 742, in: decoded.chapters)?.moment,
                     "按背景年份跳卷时不能把主题选读当作当年作品")
        XCTAssertEqual(LifeJump.resolve(year: 1082, in: moments(workId: poem).chapters)?.moment,
                       "t-1082-03-rain", "旧版已编年的刻仍跳到原来的日期")
    }

    func testSameYearIDsSortDedupeExcludeAndLimit() {
        let ids = (0..<6).map { UUID(uuidString: "00000000-0000-4000-8000-00000000000\($0)")! }
        let rows = [
            YearWorkRow(poemId: ids[1], month: nil, day: nil),
            YearWorkRow(poemId: ids[2], month: 7, day: 16),
            YearWorkRow(poemId: poem, month: 3, day: 1),     // 当前这篇
            YearWorkRow(poemId: ids[3], month: 3, day: 7),
            YearWorkRow(poemId: ids[2], month: 10, day: 15), // 同篇再系一次
            YearWorkRow(poemId: ids[4], month: 3, day: nil),
            YearWorkRow(poemId: ids[5], month: 1, day: 2),
        ]
        XCTAssertEqual(ReaderTimeline.sameYearIDs(rows, excluding: poem, limit: 8),
                       [ids[5], ids[3], ids[4], ids[2], ids[1]])
        XCTAssertEqual(ReaderTimeline.sameYearIDs(rows, excluding: poem, limit: 2), [ids[5], ids[3]])
        XCTAssertEqual(ReaderTimeline.sameYearIDs(rows, excluding: poem, limit: 0), [])
    }

    func testRelatedArtworksMatchListOrSingleField() throws {
        XCTAssertEqual(ReaderTimeline.relatedArtworks(for: poem, in: try artworks()).map(\.id), ["many", "single"])
        XCTAssertEqual(ReaderTimeline.relatedArtworks(for: UUID(), in: try artworks()).map(\.id), [])
    }

    func testRemainingCountNeverNegative() {
        XCTAssertEqual(ReaderTimeline.remainingCount(yearTotal: 135, shown: 2), 133)
        XCTAssertEqual(ReaderTimeline.remainingCount(yearTotal: 1, shown: 2), 0)
    }

    // MARK: 文字

    func testEventLineAndExcerpt() throws {
        let day = try link(id: "00000000-0000-4000-8000-000000000001", year: 1082, month: 3, day: 5, score: 1)
        let place = ReaderTimeline.placeName(stationID: day.event.stationId, stations: [], fallback: day.stationName)
        XCTAssertEqual(place, "黄冈", "没有预载驻点时去掉行政后缀")
        XCTAssertEqual(ReaderTimeline.eventLine(day.event, eraLabel: "元丰五年", place: place), "元丰五年 · 三月初五 · 黄冈")
        XCTAssertEqual(ReaderTimeline.excerpt(day.event), "清明，友人分新火，有诗。", "去掉纪年、处境套语与作品尾")

        let yearOnly = try link(id: "00000000-0000-4000-8000-000000000002", year: 1084, month: nil, day: nil, score: 1,
                                content: "1084年，赴汝州途中。往来庐山南北。作品：《某诗》。", stationName: nil)
        XCTAssertEqual(ReaderTimeline.eventLine(yearOnly.event, eraLabel: "元丰七年", place: nil), "元丰七年")
        XCTAssertEqual(ReaderTimeline.excerpt(yearOnly.event), "往来庐山南北。")

        let onlySituation = try link(id: "00000000-0000-4000-8000-000000000003", year: 1080, month: 2, day: 1, score: 1,
                                     content: "1080年2月1日，在黄冈。")
        XCTAssertEqual(ReaderTimeline.excerpt(onlySituation.event), "在黄冈。", "去完为空时保留原叙事")
    }

    func testCoverTitleShortensLongTitles() {
        XCTAssertEqual(ReaderSameYearShelf.coverTitle("寒食雨二首  其一"), "寒食雨二首其一")
        let long = ReaderSameYearShelf.coverTitle("七年九月自广陵召还复馆于浴室东堂八年六月乞会稽")
        XCTAssertEqual(long.count, 12)
        XCTAssertTrue(long.hasSuffix("…"))
    }
}
