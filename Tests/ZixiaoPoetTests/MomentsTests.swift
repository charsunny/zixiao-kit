import Foundation
import XCTest
@testable import ZixiaoPoet

/// 刻 (moments-<slug>.json) 的解码、载入与日期行。
///
/// 真实数据的裁剪样本在仓库根 `Fixtures/moments-trimmed.json` (经 `#filePath` 读, 与历法金标同法 ——
/// 测试目标不声明资源); 完整数据随产品 App 包发, 在旁边的 zhi 仓库里时顺带整份解一遍。
final class MomentsTests: XCTestCase {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ZixiaoPoetTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // 仓库根
    }

    private func fixture() throws -> Data {
        let url = Self.repoRoot.appendingPathComponent("Fixtures/moments-trimmed.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("缺少 fixture: \(url.path)")
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    func testDecodesTrimmedRealChapters() throws {
        let moments = try PoetMoments.decode(fixture())
        XCTAssertEqual(moments.schemaVersion, 1)
        XCTAssertEqual(moments.chapters.count, 2)

        let stub = try XCTUnwrap(moments.chapters.first)
        XCTAssertTrue(stub.isStub)
        XCTAssertNil(stub.overview)
        XCTAssertEqual(stub.yearsLabel, "\(String(stub.startYear)) 年", "起止同年只写一年")

        let written = try XCTUnwrap(moments.chapters.last)
        XCTAssertFalse(written.isStub)
        XCTAssertNotNil(written.overview)
        XCTAssertEqual(written.seasonTint, "autumn")
        XCTAssertEqual(written.moments.count, 3)
        XCTAssertEqual(moments.momentCount, 3)
        XCTAssertEqual(moments.writtenChapterCount, 1)
        XCTAssertNotNil(moments.chapter(sequence: written.epochSequence))

        for moment in written.moments {
            XCTAssertFalse(moment.sources.isEmpty, moment.id)
            XCTAssertNotNil(moment.workId, moment.id)
            XCTAssertNotNil(moment.workQuote, moment.id)
            XCTAssertTrue(written.contains(year: moment.date.year), moment.id)
        }
        // 一刻有墨迹、有人; 人的并集按首次出现去重。
        XCTAssertEqual(written.moments.compactMap(\.artworkId).count, 2)
        XCTAssertEqual(written.people.count, Set(written.people).count)
        XCTAssertFalse(written.people.isEmpty)
    }

    func testDateLineFollowsPrecisionAndEditorialWording() throws {
        let written = try XCTUnwrap(PoetMoments.decode(fixture()).chapters.last)
        let labels = written.moments.map(\.date.displayLabel)
        // 日精度: 年号 · 月日; 编辑的写法 (既望、寒食) 原样保留。
        XCTAssertEqual(labels[0], "\(written.moments[0].date.eraLabel) · 二月初一")
        XCTAssertTrue(labels[1].hasSuffix("· 三月（寒食）"), labels[1])
        XCTAssertTrue(labels[2].hasSuffix("· 七月既望"), labels[2])
    }

    func testDateLineWithoutEditorialWording() {
        typealias D = PoetMoments.MomentDate
        XCTAssertEqual(D(year: 700, month: 3, day: 7, eraLabel: "某元年", precision: .day).displayLabel, "某元年 · 三月初七")
        XCTAssertEqual(D(year: 700, month: 1, day: 21, eraLabel: "某元年", precision: .day).displayLabel, "某元年 · 正月二十一")
        XCTAssertEqual(D(year: 700, month: 9, eraLabel: "某元年", precision: .month).displayLabel, "某元年 · 九月")
        // 精度只到年: 即使给了月日也不显示 (不编造日期)。
        XCTAssertEqual(D(year: 700, month: 9, day: 1, eraLabel: "某元年", precision: .year).displayLabel, "某元年")
        // lunar 只有年号本身时按月日拼。
        XCTAssertEqual(D(year: 700, month: 12, lunar: "某元年", eraLabel: "某元年", precision: .month).displayLabel,
                       "某元年 · 十二月")
    }

    func testStubChapterAndOptionalFieldsDecode() throws {
        let json = """
        {"schemaVersion": 1, "poet": "placeholder", "chapters": [
          {"epochSequence": 0, "title": "少年", "startYear": 700, "endYear": 720,
           "thesis": "占位旨。", "placeSeed": "somewhere", "moments": []},
          {"epochSequence": 1, "title": "晚年", "startYear": 721, "endYear": 760,
           "thesis": "占位旨。", "overview": "占位概述。", "placeSeed": "elsewhere", "seasonTint": null,
           "moments": [
             {"id": "placeholder-721-a", "date": {"year": 721, "eraLabel": "某元年", "precision": "year"},
              "placeId": null, "placeLabel": "某地", "title": "一刻", "lede": "按语。", "body": "处境。",
              "eventIds": [], "workId": null, "workQuote": null, "artworkId": null,
              "sources": [{"book": "某书", "chapter": "某章", "quote": "某句"}],
              "_workTitle": "调试字段忽略"}
           ]}
        ]}
        """
        let moments = try PoetMoments.decode(Data(json.utf8))
        XCTAssertTrue(moments.chapters[0].isStub)
        XCTAssertEqual(moments.chapters[0].people, [])
        let moment = try XCTUnwrap(moments.moment(id: "placeholder-721-a"))
        XCTAssertNil(moment.people)
        XCTAssertEqual(moment.allPeople, [])
        XCTAssertNil(moment.workId)
        XCTAssertNil(moment.sources[0].ref)
        XCTAssertEqual(moment.date.displayLabel, "某元年")
    }

    func testNewerSchemaVersionIsRejected() {
        let json = #"{"schemaVersion": 2, "poet": "placeholder", "chapters": []}"#
        XCTAssertThrowsError(try PoetMoments.decode(Data(json.utf8)))
    }

    func testMissingFileHidesFeatureAndBrokenFileIsReported() throws {
        let empty = try PoetFixtures.bundle(files: [:])
        XCTAssertNil(PoetMoments.load(from: empty, poetSlug: "placeholder"))
        XCTAssertNil(try PoetResources(bundle: empty, slug: "placeholder", productName: "占位志").moments())

        let broken = try PoetFixtures.bundle(files: ["moments-placeholder.json": "{ not json"])
        XCTAssertNil(PoetMoments.load(from: broken, poetSlug: "placeholder"))
        XCTAssertThrowsError(try PoetResources(bundle: broken, slug: "placeholder", productName: "占位志").moments()) {
            guard case .unreadable(let product, let resource, _) = $0 as? PoetResourceError else {
                return XCTFail("应报 unreadable: \($0)")
            }
            XCTAssertEqual(product, "占位志")
            XCTAssertEqual(resource, "moments-placeholder.json")
        }

        let good = try PoetFixtures.bundle(files: ["moments-placeholder.json": String(decoding: try fixture(), as: UTF8.self)])
        XCTAssertEqual(PoetMoments.load(from: good, poetSlug: "placeholder")?.chapters.count, 2)
    }

    func testChapterOrdinals() {
        XCTAssertEqual(PoetMoments.Chapter.ordinalLabel(1), "卷一")
        XCTAssertEqual(PoetMoments.Chapter.ordinalLabel(5), "卷五")
        XCTAssertEqual(PoetMoments.Chapter.ordinalLabel(10), "卷十")
        XCTAssertEqual(PoetMoments.Chapter.ordinalLabel(12), "卷十二")
        XCTAssertEqual(PoetMoments.Chapter.ordinalLabel(21), "卷二十一")
    }

    /// 完整的产品数据 (旁边的 zhi 仓库在时): 整份能解, 卷按分期升序, 每个已编卷的刻都有出处。
    func testFullBundledFileDecodesWhenAvailable() throws {
        let dir = Self.repoRoot.deletingLastPathComponent().appendingPathComponent("zhi/DongpoZhi/App/Resources")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
            .filter { $0.hasPrefix("moments-") && $0.hasSuffix(".json") } ?? []
        guard !files.isEmpty else { throw XCTSkip("旁边没有 zhi 仓库的 moments 数据") }
        for file in files {
            let moments = try PoetMoments.decode(Data(contentsOf: dir.appendingPathComponent(file)))
            XCTAssertEqual(moments.chapters.map(\.epochSequence), moments.chapters.map(\.epochSequence).sorted(), file)
            XCTAssertGreaterThan(moments.writtenChapterCount, 0, file)
            for chapter in moments.chapters where !chapter.isStub {
                XCTAssertNotNil(chapter.overview, "\(file) \(chapter.title)")
                for moment in chapter.moments { XCTAssertFalse(moment.sources.isEmpty, moment.id) }
            }
        }
    }
}
