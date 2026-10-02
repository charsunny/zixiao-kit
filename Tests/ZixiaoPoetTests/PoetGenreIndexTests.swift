import Foundation
import XCTest
@testable import ZixiaoPoet

final class PoetGenreIndexTests: XCTestCase {
    private typealias Row = PoetRPC.GenreCount

    func testGroupsOrderByCountWithOtherLast() {
        let index = PoetGenreIndex(rows: [
            Row(genreGroup: "题跋", genre: "书后", n: 537),
            Row(genreGroup: "书简", genre: "尺牍", n: 1_300),
            Row(genreGroup: "书简", genre: "启", n: 134),
            Row(genreGroup: nil, genre: nil, n: 2_000),      // 「其他」再多也殿后
            Row(genreGroup: "制诰", genre: "内制口宣", n: 255),
            Row(genreGroup: "制诰", genre: "外制制敕", n: 818),
        ])
        XCTAssertEqual(index.groups.map(\.label), ["书简", "制诰", "题跋", PoetGenreIndex.otherGroup])
        XCTAssertEqual(index.groups.map(\.count), [1_434, 1_073, 537, 2_000])
        XCTAssertEqual(index.total, 5_044)
        XCTAssertTrue(index.isGrouped)
        XCTAssertEqual(index.group("制诰")?.genres.map(\.label), ["外制制敕", "内制口宣"])
    }

    func testTiesBreakByLabelAndLiteralOtherMergesWithNull() {
        let index = PoetGenreIndex(rows: [
            Row(genreGroup: "颂", genre: "颂", n: 35),
            Row(genreGroup: "序", genre: "叙", n: 35),
            Row(genreGroup: "其他", genre: "杂著", n: 4),
            Row(genreGroup: nil, genre: nil, n: 31),
            Row(genreGroup: "  ", genre: "", n: 1),             // 空白等同于空
        ])
        XCTAssertEqual(index.groups.map(\.label), ["序", "颂", "其他"])
        let other = index.group("其他")
        XCTAssertEqual(other?.count, 36)
        XCTAssertEqual(other?.genres.map(\.label), ["杂著"])  // 空细体裁只计数, 不单列
        XCTAssertEqual(other?.hasFineGenres, false)
        XCTAssertEqual(other?.isOther, true)
    }

    func testClientFallbackRowsDecodeWithoutCountAndAccumulate() throws {
        let json = #"[{"genre_group":"书简","genre":"尺牍"},{"genre_group":"书简","genre":"尺牍"},"#
            + #"{"genre_group":"书简","genre":"启"},{"genre_group":null,"genre":null}]"#
        let rows = try JSONDecoder().decode([Row].self, from: Data(json.utf8))
        XCTAssertEqual(rows.map(\.n), [1, 1, 1, 1])
        let index = PoetGenreIndex(rows: rows)
        XCTAssertEqual(index.groups.map(\.label), ["书简", "其他"])
        XCTAssertEqual(index.group("书简")?.genres.map(\.count), [2, 1])
        XCTAssertEqual(index.group("书简")?.hasFineGenres, true)
    }

    func testSingleGroupIsNotGrouped() {
        // 诗词: genre_group 全空 → 只有「其他」一类, 目录页退回平铺列表。
        XCTAssertFalse(PoetGenreIndex(rows: [Row(genreGroup: nil, genre: nil, n: 3_000)]).isGrouped)
        XCTAssertFalse(PoetGenreIndex(rows: []).isGrouped)
        XCTAssertTrue(PoetGenreIndex(rows: [Row(genreGroup: "x", genre: nil, n: 0)]).groups.isEmpty)
    }

    func testRPCRowsDecodeAndParamsEncode() throws {
        let rows = try JSONDecoder().decode([Row].self, from: Data(
            #"[{"genre_group":"书简","genre":"尺牍","n":1258},{"genre_group":"其他","genre":null,"n":31}]"#.utf8))
        XCTAssertEqual(rows, [Row(genreGroup: "书简", genre: "尺牍", n: 1_258), Row(genreGroup: "其他", genre: nil, n: 31)])

        let id = try XCTUnwrap(UUID(uuidString: "6F0B3C2A-1D4E-4B8A-9C55-0123456789AB"))
        let data = try JSONEncoder().encode(PoetRPC.GenreGroupsParams(poetId: id, form: "wen"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object, ["p_poet_id": "6f0b3c2a-1d4e-4b8a-9c55-0123456789ab", "p_form": "wen"])
        XCTAssertEqual(PoetRPC.genreGroups, "poet_genre_groups")
    }

    func testPoemDecodesGenreAndProvenanceSourceLine() throws {
        let json = #"""
        {"id":"1F516051-4B3F-59F5-AAC7-56CB9AACEBC8","title":"甲","form":"wen","content":"正文",
         "genre":"叙","genre_group":"序",
         "provenance":{"book_id":"dz-x","book_title":"某集","chapter_title":"叙二十五首","chapter_index":37,
                       "flags":["duplicate-across-books"],"also_in":[{"book_title":"另集"}]}}
        """#
        let poem = try JSONDecoder().decode(Poem.self, from: Data(json.utf8))
        XCTAssertEqual(poem.genreGroup, "序")
        XCTAssertEqual(poem.provenance?.bookTitle, "某集")
        XCTAssertEqual(poem.sourceLine, "叙 · 某集 叙二十五首")
        // Codable 往返不丢字段。
        XCTAssertEqual(try JSONDecoder().decode(Poem.self, from: JSONEncoder().encode(poem)), poem)

        let bare = try JSONDecoder().decode(Poem.self, from: Data(
            #"{"id":"1F516051-4B3F-59F5-AAC7-56CB9AACEBC8","title":"乙","form":"shi","content":"句"}"#.utf8))
        XCTAssertNil(bare.sourceLine)
        let genreOnly = try JSONDecoder().decode(Poem.self, from: Data(
            #"{"id":"1F516051-4B3F-59F5-AAC7-56CB9AACEBC8","title":"丙","form":"wen","content":"句","genre":"尺牍","provenance":{}}"#.utf8))
        XCTAssertEqual(genreOnly.sourceLine, "尺牍")
    }
}
