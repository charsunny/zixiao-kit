import Foundation
import XCTest
@testable import ZixiaoPoet

/// 书画清单的新增可选字段 (epochSequence / relatedPoemIDs / license) 可解, 旧清单仍可解。
final class ArtworkDecodingTests: XCTestCase {
    private func entry(extra: String) -> String {
        """
        {
          "id": "scroll-a", "title": "测试卷", "kind": "书法", "attribution": "测试（馆藏著录）",
          "dateLabel": "测试 · 某年", "medium": "纸本", "dimensions": "本幅 1 × 2 厘米",
          "collection": "测试馆", "subtitle": "副题。", "introduction": "简介。", "lookingNotes": "看点。",
          "sourceTitle": "馆藏资料", "sourceURL": "https://example.com/record/1",
          "imageCredit": "测试卷 测试馆，CC BY 4.0。", "imageSourceURL": "https://example.com/record/1",
          "licenseURL": "https://example.com/terms", "cover": "scroll-a-1.jpg",
          "images": [{"asset": "scroll-a-1.jpg", "caption": "正文"}],
          "relatedPoemID": null, "relatedPoemTitle": null\(extra)
        }
        """
    }

    func testNewOptionalFieldsDecode() throws {
        let extra = """
        ,
          "epochSequence": 4,
          "relatedPoemIDs": ["\(PoetFixtures.poemA)", "\(PoetFixtures.poemB)"],
          "license": {"name": "CC BY 4.0", "url": "https://creativecommons.org/licenses/by/4.0/", "holder": "测试馆"}
        """
        let list = try Artwork.decodeList(Data("[\(entry(extra: extra))]".utf8))
        let artwork = try XCTUnwrap(list.first)
        XCTAssertEqual(artwork.epochSequence, 4)
        XCTAssertEqual(artwork.relatedPoemIDs, [UUID(uuidString: PoetFixtures.poemA)!, UUID(uuidString: PoetFixtures.poemB)!])
        XCTAssertEqual(artwork.license?.name, "CC BY 4.0")
        XCTAssertEqual(artwork.license?.holder, "测试馆")
        XCTAssertEqual(artwork.license?.url.absoluteString, "https://creativecommons.org/licenses/by/4.0/")
    }

    func testLicenseWithoutHolderAndEntriesWithoutNewFieldsStillDecode() throws {
        let withLicense = entry(extra: #", "license": {"name": "PD-Art", "url": "https://creativecommons.org/publicdomain/mark/1.0/"}"#)
        let list = try Artwork.decodeList(Data("[\(withLicense), \(entry(extra: ""))]".utf8))
        XCTAssertEqual(list.count, 2)
        XCTAssertNil(list[0].license?.holder)
        XCTAssertNil(list[1].epochSequence)
        XCTAssertNil(list[1].relatedPoemIDs)
        XCTAssertNil(list[1].license)
    }
}
