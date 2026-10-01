import Foundation
import XCTest
@testable import ZixiaoPoet

final class PoetResourcesTests: XCTestCase {
    /// 包里缺导读: 错误里带产品名 (来自编成) 与缺的文件名, 不写死任何诗人。
    func testMissingGuideNamesTheProductFromTheComposition() throws {
        let composition = try PoetFixtures.composition(cards: [], includesOnThisDayConfig: false, dayPrecise: 0)
        let bundle = try PoetFixtures.bundle(files: [:])
        let resources = PoetResources(bundle: bundle, composition: composition)

        XCTAssertThrowsError(try resources.guide()) { error in
            XCTAssertEqual(error as? PoetResourceError,
                           .missing(product: "测试志", resource: "guide-test.json"))
            XCTAssertEqual((error as? LocalizedError)?.errorDescription,
                           "测试志 的 App 包里缺少资源 guide-test.json")
        }
        // 书画是可选资源: 缺了不是错误。
        XCTAssertEqual(try resources.artworks().count, 0)
    }

    func testCorruptGuideIsReportedAsUnreadable() throws {
        let bundle = try PoetFixtures.bundle(files: ["guide-test.json": "{ not json"])
        let resources = PoetResources(bundle: bundle, slug: "test", productName: "测试志")
        XCTAssertThrowsError(try resources.guide()) { error in
            guard case .unreadable(product: "测试志", resource: "guide-test.json", _)? = error as? PoetResourceError
            else { return XCTFail("unexpected \(error)") }
        }
    }

    func testImagesResolveFromTheSameBundle() throws {
        let bundle = try PoetFixtures.bundle(files: ["scroll-1.jpg": "jpg"])
        let resources = PoetResources(bundle: bundle, slug: "test", productName: "测试志")
        XCTAssertNotNil(resources.url(forAsset: "scroll-1.jpg"))
        XCTAssertNil(resources.url(forAsset: "scroll-2.jpg"))
    }
}
