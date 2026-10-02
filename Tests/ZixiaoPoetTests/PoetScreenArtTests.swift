import CoreGraphics
import CryptoKit
import Foundation
import XCTest
import ZixiaoDesign
@testable import ZixiaoPoet

final class PoetScreenArtTests: XCTestCase {
    /// 小尺寸足够验证确定性, Debug 构建下也快。
    static let size = CGSize(width: 240, height: 160)

    static func digest(_ image: CGImage) -> String {
        let data = (image.dataProvider?.data as Data?) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PoetScreenArtTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: 配方

    func testSameRecipeRendersIdenticalPixels() throws {
        let recipe = PoetScreenArt(seed: "place-a#1", season: .autumn)
        let a = try XCTUnwrap(PoetScreenArtCache.render(recipe, pixelSize: Self.size, dark: false))
        let b = try XCTUnwrap(PoetScreenArtCache.render(PoetScreenArt(seed: "place-a#1", season: .autumn),
                                                        pixelSize: Self.size, dark: false))
        XCTAssertEqual(a.width, 240)
        XCTAssertEqual(a.height, 160)
        XCTAssertEqual(Self.digest(a), Self.digest(b))
    }

    func testDifferentSeedsAndSchemesDiffer() throws {
        let a = try XCTUnwrap(PoetScreenArtCache.render(PoetScreenArt(seed: "place-a#1"), pixelSize: Self.size, dark: false))
        let b = try XCTUnwrap(PoetScreenArtCache.render(PoetScreenArt(seed: "place-b#1"), pixelSize: Self.size, dark: false))
        let night = try XCTUnwrap(PoetScreenArtCache.render(PoetScreenArt(seed: "place-a#1"), pixelSize: Self.size, dark: true))
        XCTAssertNotEqual(Self.digest(a), Self.digest(b))
        XCTAssertNotEqual(Self.digest(a), Self.digest(night))
    }

    func testForPlaceDerivesSeedFromPlaceAndEpoch() {
        XCTAssertEqual(PoetScreenArt.forPlace("p", epoch: 3).seed, "p#3")
        XCTAssertEqual(PoetScreenArt.forPlace("p", epoch: nil).seed, "p#0")
        XCTAssertEqual(PoetScreenArt.forPlace("p", epoch: 3, season: .winter).season, .winter)
        XCTAssertEqual(PoetScreenArt.forPlace("p", epoch: 3).generator, PoetScreenArt.shanshui)
        XCTAssertNotEqual(PoetScreenArt.forPlace("p", epoch: 1), PoetScreenArt.forPlace("p", epoch: 2))
    }

    func testVariantIsStableAndSupported() {
        for seed in ["a", "b", "c", "地#1", "x#7"] {
            let recipe = PoetScreenArt(seed: seed)
            XCTAssertTrue(["高山", "江岸"].contains(recipe.resolvedVariant), seed)
            XCTAssertEqual(recipe.resolvedVariant, PoetScreenArt(seed: seed).resolvedVariant)
            XCTAssertTrue(recipe.isSupported, seed)
        }
        XCTAssertEqual(PoetScreenArt(seed: "a", variant: "远山").resolvedVariant, "远山")
        XCTAssertEqual(PoetScreenArt(seed: "a", generator: PoetScreenArt.flowers, season: .winter).resolvedVariant, "梅")
        XCTAssertEqual(PoetScreenArt(seed: "a", generator: PoetScreenArt.flowers).resolvedVariant, "自然")
        XCTAssertTrue(PoetScreenArt(seed: "a", generator: PoetScreenArt.flowers, season: .autumn).isSupported)
        XCTAssertFalse(PoetScreenArt(seed: "a", generator: "bamboo@1").isSupported)
    }

    /// 季节偏色与 ZXColorTokens 同法: 只揉纸, 比例 3.5% / 2%, 墨不动。
    func testSeasonTintMixesPaperLikeTheTheme() {
        let plain = PoetScreenArt(seed: "a")
        for season in ZXSeasonTint.allCases {
            let tinted = PoetScreenArt(seed: "a", season: season)
            for dark in [false, true] {
                let base = plain.palette(dark: dark)
                let p = tinted.palette(dark: dark)
                let bias = dark ? season.bias.dark : season.bias.light
                let amount = dark ? ZXSeasonTint.darkMixAmount : ZXSeasonTint.lightMixAmount
                XCTAssertEqual(p.ink, base.ink)
                XCTAssertEqual(p.paper, base.paper.mixed(with: bias, amount: amount))
                XCTAssertNotEqual(p.paper, base.paper)
            }
        }
        XCTAssertTrue(plain.palette(dark: true).isDark)
        XCTAssertFalse(plain.palette(dark: false).isDark)
    }

    func testPixelSizeQuantizesAndCaps() {
        XCTAssertEqual(PoetScreenArtCache.pixelSize(forPoints: CGSize(width: 100, height: 50), scale: 3),
                       CGSize(width: 304, height: 152))
        let big = PoetScreenArtCache.pixelSize(forPoints: CGSize(width: 1366, height: 1024), scale: 2)
        XCTAssertLessThanOrEqual(max(big.width, big.height), PoetScreenArtCache.maxPixelSide)
        XCTAssertEqual(PoetScreenArtCache.pixelSize(forPoints: .zero, scale: 3), .zero)
    }

    // MARK: 缓存

    func testCacheHitsMemoryThenDisk() async throws {
        let dir = try temporaryDirectory()
        let key = PoetScreenArtCache.Key(recipe: PoetScreenArt(seed: "place-c#2", season: .spring),
                                         pixelWidth: 240, pixelHeight: 160, dark: false)
        let cache = PoetScreenArtCache(directory: dir)
        XCTAssertNil(cache.cachedImage(key))

        let first = try await XCTUnwrapAsync(await cache.load(key))
        XCTAssertEqual(first.source, .rendered)
        let renders = await cache.renderCount
        XCTAssertEqual(renders, 1)
        XCTAssertNotNil(cache.cachedImage(key))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(key.fileName).path))

        let second = try await XCTUnwrapAsync(await cache.load(key))
        XCTAssertEqual(second.source, .memory)
        XCTAssertEqual(Self.digest(first.image), Self.digest(second.image))

        // 冷启动: 新实例只有磁盘。
        let cold = PoetScreenArtCache(directory: dir)
        let third = try await XCTUnwrapAsync(await cold.load(key))
        XCTAssertEqual(third.source, .disk)
        let coldRenders = await cold.renderCount
        XCTAssertEqual(coldRenders, 0)
        XCTAssertEqual(third.image.width, 240)

        await cache.removeAll(includingDisk: true)
        XCTAssertNil(cache.cachedImage(key))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testConcurrentRequestsShareOneRender() async throws {
        let cache = PoetScreenArtCache(directory: nil)
        let key = PoetScreenArtCache.Key(recipe: PoetScreenArt(seed: "place-d#1"), pixelWidth: 160, pixelHeight: 160, dark: true)
        async let a = cache.load(key)
        async let b = cache.load(key)
        let (ra, rb) = await (a, b)
        XCTAssertNotNil(ra)
        XCTAssertNotNil(rb)
        let renders = await cache.renderCount
        XCTAssertEqual(renders, 1)
    }

    func testUnsupportedRecipeLoadsNothing() async {
        let cache = PoetScreenArtCache(directory: nil)
        let key = PoetScreenArtCache.Key(recipe: PoetScreenArt(seed: "a", generator: "shanshui@9"),
                                         pixelWidth: 100, pixelHeight: 100, dark: false)
        let loaded = await cache.load(key)
        XCTAssertNil(loaded)
    }

    func testKeyIdentifierIsStableAndDistinguishesInputs() {
        let recipe = PoetScreenArt(seed: "a")
        let k = PoetScreenArtCache.Key(recipe: recipe, pixelWidth: 10, pixelHeight: 10, dark: false)
        XCTAssertEqual(k.fileName, PoetScreenArtCache.Key(recipe: recipe, pixelWidth: 10, pixelHeight: 10, dark: false).fileName)
        XCTAssertNotEqual(k.fileName, PoetScreenArtCache.Key(recipe: recipe, pixelWidth: 10, pixelHeight: 10, dark: true).fileName)
        XCTAssertNotEqual(k.fileName, PoetScreenArtCache.Key(recipe: recipe, pixelWidth: 10, pixelHeight: 12, dark: false).fileName)
        XCTAssertNotEqual(k.fileName, PoetScreenArtCache.Key(recipe: PoetScreenArt(seed: "a", season: .summer),
                                                             pixelWidth: 10, pixelHeight: 10, dark: false).fileName)
    }
}

/// `XCTUnwrap` 不能直接接 async 表达式。
private func XCTUnwrapAsync<T>(_ value: @autoclosure () async throws -> T?, file: StaticString = #filePath,
                               line: UInt = #line) async throws -> T {
    let v = try await value()
    return try XCTUnwrap(v, file: file, line: line)
}
