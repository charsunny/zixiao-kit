@testable import ZixiaoPoetCore
import Foundation
import XCTest
@testable import ZixiaoPoet

/// 编成的可选 `library` 块: 解码、默认值、分组次序; 缺省时为 nil (书房不显示书架)。
final class PoetLibraryDecodingTests: XCTestCase {
    private static let sampleLibrary = """
    {
      "prominence": "section",
      "label": "占位著述",
      "books": [
        {"id": "dz-0000000000000001", "title": "甲书", "author": "占位", "dynasty": "唐",
         "url": "https://example.com/books/v1/dz/dz-0000000000000001/1/book.json.gz",
         "hash": "sha256:\(String(repeating: "a", count: 64))", "version": 2, "bytes": 2048, "group": "笔记"},
        {"id": "dz-0000000000000002", "title": "宋史 卷三百三十八　列传第九十七　某传", "shortTitle": "宋史·某传",
         "url": "https://example.com/books/v1/dz/dz-0000000000000002/1/book.json.gz",
         "hash": "sha256:\(String(repeating: "b", count: 64))", "group": "生平"},
        {"id": "dz-0000000000000003", "title": "丙书", "author": "占位",
         "url": "https://example.com/books/v1/dz/dz-0000000000000003/1/book.json.gz",
         "hash": "sha256:\(String(repeating: "c", count: 64))", "bytes": 10, "group": "笔记"}
      ]
    }
    """

    func testDecodesLibraryBlock() throws {
        let library = try JSONDecoder().decode(PoetLibrary.self, from: Data(Self.sampleLibrary.utf8))
        XCTAssertEqual(library.label, "占位著述")
        XCTAssertEqual(library.prominence, "section")
        XCTAssertEqual(library.books.count, 3)
        let first = library.books[0]
        XCTAssertEqual(first.id, "dz-0000000000000001")
        XCTAssertEqual(first.version, 2)
        XCTAssertEqual(first.bytes, 2048)
        XCTAssertEqual(first.byline, "唐 · 占位")
        XCTAssertEqual(first.coverTitle, "甲书")
        XCTAssertEqual(first.downloadURL?.host, "example.com")
        XCTAssertTrue(first.hash.hasPrefix("sha256:"))
    }

    func testOptionalFieldsDefault() throws {
        let library = try JSONDecoder().decode(PoetLibrary.self, from: Data(Self.sampleLibrary.utf8))
        let second = library.books[1]
        XCTAssertEqual(second.version, 1)
        XCTAssertNil(second.bytes)
        XCTAssertNil(second.author)
        XCTAssertNil(second.byline)
        XCTAssertEqual(second.coverTitle, "宋史·某传")
        XCTAssertEqual(second.title, "宋史 卷三百三十八　列传第九十七　某传")
    }

    func testGroupsKeepFirstAppearanceOrderAndBookOrder() throws {
        let library = try JSONDecoder().decode(PoetLibrary.self, from: Data(Self.sampleLibrary.utf8))
        XCTAssertEqual(library.groups.map(\.name), ["笔记", "生平"])
        XCTAssertEqual(library.groups[0].books.map(\.id), ["dz-0000000000000001", "dz-0000000000000003"])
        XCTAssertEqual(library.groups[1].books.map(\.id), ["dz-0000000000000002"])
    }

    func testLibraryRoundTrips() throws {
        let library = try JSONDecoder().decode(PoetLibrary.self, from: Data(Self.sampleLibrary.utf8))
        let again = try JSONDecoder().decode(PoetLibrary.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(library, again)
    }

    func testCompositionWithoutLibraryHasNone() throws {
        let composition = try PoetFixtures.composition(cards: ["work-of-day"], includesOnThisDayConfig: false,
                                                       dayPrecise: 0)
        XCTAssertNil(composition.library)
    }

    func testCompositionDecodesLibraryWhenPresent() throws {
        let base = try PoetFixtures.compositionJSON(cards: ["work-of-day"], includesOnThisDayConfig: false,
                                                    dayPrecise: 0)
        let withLibrary = base.replacingOccurrences(
            of: "\"schemaVersion\": 1,", with: "\"schemaVersion\": 1, \"library\": \(Self.sampleLibrary),")
        let composition = try JSONDecoder().decode(PoetComposition.self, from: Data(withLibrary.utf8))
        XCTAssertEqual(composition.library?.books.count, 3)
        XCTAssertEqual(composition.library?.label, "占位著述")
    }
}
