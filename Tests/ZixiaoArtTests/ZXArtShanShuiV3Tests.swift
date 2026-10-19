// shanshui@3: 冻结构图、退回、留白、图层、样张与竖幅渲染基线。
// VPS 只写代码 / 审查; 在 Mac 执行。真实 v3 fixture 由 Mac 首次写入。
import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import ZixiaoArt

final class ZXArtShanShuiV3Tests: XCTestCase {
    static let sizes: [(String, CGSize)] = [
        ("square", CGSize(width: 510, height: 510)),
        ("portrait", CGSize(width: 1206, height: 2622)),
        ("wide", CGSize(width: 1062, height: 498)),
    ]

    static func recipe(_ c: ZXArtProceduralFixtureTests.Case) -> ZXArt.Procedural {
        .init(generator: c.generator, seed: c.seed, variant: c.variant,
              params: .init(density: c.density, quietTop: c.quietTop, verseSide: c.verseSide,
                            verseColumns: c.verseColumns, verseChars: c.verseChars))
    }

    func testRegistrationAndPureFallback() throws {
        let json = #"{"generator":"shanshui@3","seed":"秋分-1","variant":"江岸","params":{"density":1.4,"hue":17,"quiet_top":0.4,"verse_side":"left","verse_columns":4,"verse_chars":9}}"#
        let p = try JSONDecoder().decode(ZXArt.Procedural.self, from: Data(json.utf8))
        XCTAssertTrue(p.isSupported)
        XCTAssertTrue(ZXArt.Procedural.supportedGenerators.contains("shanshui@3"))
        XCTAssertEqual(try JSONDecoder().decode(ZXArt.Procedural.self, from: JSONEncoder().encode(p)), p)
        XCTAssertEqual(p.effectiveGenerator(), "shanshui@3")
        XCTAssertEqual(p.effectiveGenerator(allowsShanShuiV3: false), "shanshui@2")
        let down = p.downgraded()
        XCTAssertEqual(down.generator, "shanshui@2")
        XCTAssertEqual(down.seed, p.seed)
        XCTAssertEqual(down.variant, p.variant)
        XCTAssertEqual(down.params, p.params)
        XCTAssertEqual(down.downgraded(), down)
        for generator in ["shanshui@1", "shanshui@2", "nonflowers@2", "nonflowers@3", "shanshui@4"] {
            var other = p
            other.generator = generator
            XCTAssertEqual(other.downgraded(), other)
            XCTAssertEqual(other.effectiveGenerator(allowsShanShuiV3: false), generator)
        }
        for (_, size) in Self.sizes { XCTAssertEqual(p.verseLayout(pixelSize: size), down.verseLayout(pixelSize: size)) }
        var invalid = p
        invalid.params.verseSide = "bottom"
        XCTAssertFalse(invalid.isSupported)
        XCTAssertFalse(invalid.downgraded().isSupported)
        XCTAssertNil(ZXArt.drawing(procedural: invalid, palette: .paperInk, pixelSize: Self.sizes[0].1))
        invalid = p; invalid.variant = "梅"
        XCTAssertFalse(invalid.isSupported)
    }

    /// 比终态更强: 构图骨架逐笔逐点相同, 包括 fit/cull, 树、船、人和屋的位置。
    func testLayoutSkeletonAndEntropyMatchV2() throws {
        for (ci, c) in ZXArtProceduralFixtureTests.casesV3.enumerated() {
            for (si, seed) in ["秋分-1", "a", "2026"].enumerated() {
                let W = 420.0 * max(1, Double(c.width) / Double(c.height))
                let H = 420.0 * max(1, Double(c.height) / Double(c.width))
                var p = Self.recipe(c)
                p.seed = seed
                let density = [0.1, 0.45, 0.7, 1.0][(ci + si) % 4]
                let params = ZXArt.ShanShui.Params(density: density, variant: try XCTUnwrap(.init(rawValue: c.variant)),
                                                   quietTop: c.quietTop ?? 0.32, paperTexture: false)
                let verse = try XCTUnwrap(p.verseLayout(pixelSize: CGSize(width: c.width, height: c.height)))
                let old = ShanShuiEngine(seed: .init(seed)), new = ShanShuiEngine(seed: .init(seed))
                let a = old.composeV2(width: W, height: H, params: params, verse: verse)
                let b = new.composeV3(width: W, height: H, params: params, verse: verse)
                let label = "\(seed) \(c.variant) \(c.width)x\(c.height) \(c.verseSide ?? "right") d=\(density)"
                XCTAssertEqual(old.e.state, new.e.state, "\(label) PRNG")
                XCTAssertEqual(a.parts.count, b.parts.count, label)
                XCTAssertEqual(a.anchors, b.anchors, "\(label) 全部锚点逐位相同, 比山脊 ≤ 1 逻辑单位更严格")
                for (x, y) in zip(a.parts, b.parts) {
                    XCTAssertEqual(x.near, y.near, label)
                    XCTAssertEqual(x.canv.count, y.canv.count, label)
                    XCTAssertEqual(x.mist?.depth, y.mist?.depth, label)
                    XCTAssertEqual(x.mist?.peak, y.mist?.peak, label)
                    for (u, v) in zip(x.canv, y.canv) {
                        XCTAssertEqual(u.p, v.p, label)
                        XCTAssertEqual(u.fil, v.fil, label)
                        XCTAssertEqual(u.str, v.str, label)
                        XCTAssertEqual(u.wid, v.wid, label)
                    }
                }
            }
        }
    }

    func testFallbackRendersByteForByteAsV2() throws {
        for c in ZXArtProceduralFixtureTests.casesV3 {
            let p = Self.recipe(c)
            let size = CGSize(width: Double(c.width) / 3, height: Double(c.height) / 3)
            var v2 = p
            v2.generator = "shanshui@2"
            for palette in [ZXArt.Palette.paperInk, .night] {
                let a = try XCTUnwrap(ZXArt.render(procedural: p, palette: palette, pixelSize: size, allowsShanShuiV3: false))
                let b = try XCTUnwrap(ZXArt.render(procedural: v2, palette: palette, pixelSize: size))
                XCTAssertEqual(try ZXArtWashTests.pixels(a), try ZXArtWashTests.pixels(b))
                let d = try XCTUnwrap(ZXArt.drawing(procedural: p, palette: palette, pixelSize: size, allowsShanShuiV3: false))
                let fromDrawing = try XCTUnwrap(ZXArt.render(d, pixelWidth: a.width, pixelHeight: a.height))
                XCTAssertEqual(try ZXArtWashTests.pixels(fromDrawing), try ZXArtWashTests.pixels(b))
                let explicit = try XCTUnwrap(ZXArt.render(procedural: p, paper: palette.paper, ink: palette.ink,
                                                         wash: palette.wash, pixelSize: size, allowsShanShuiV3: false))
                XCTAssertEqual(try ZXArtWashTests.pixels(explicit), try ZXArtWashTests.pixels(b))
            }
        }
    }

    func testReplacementPrimitivesKeepEntropyIncludingLazyNoiseTable() {
        let paths: [[ZXArt.P]] = [[], [.init(0, 0)], [.init(0, 0), .init(10, 5)],
                                  [.init(0, 0), .init(4, 3), .init(10, 8), .init(20, 4)]]
        for points in paths {
            let old = ShanShuiEngine(seed: "42"), new = ShanShuiEngine(seed: "42")
            let a = old.stroke(points), b = new.strokeV3(points)
            XCTAssertEqual(old.e.state, new.e.state)
            XCTAssertEqual(a.map(\.p), b.map(\.p))
        }
        for clusters in [2, 3, 6] {
            let old = ShanShuiEngine(seed: "a"), new = ShanShuiEngine(seed: "a")
            let a = old.water(20, 80, clu: clusters), b = new.waterV3(20, 80, clu: clusters)
            XCTAssertEqual(old.e.state, new.e.state)
            XCTAssertEqual(a.map(\.p), b.map(\.p))
        }
    }

    func testWidthProfilesIncludeTheDoubleLobedBoatStroke() {
        let engine = ShanShuiEngine(seed: "42")
        XCTAssertEqual(engine.profileV3 { sin($0 * .pi) }, .lens)
        XCTAssertEqual(engine.profileV3 { sin($0 * .pi * 2) }, .nail)
        XCTAssertEqual(engine.profileV3 { _ in 1 }, .even)
        XCTAssertEqual(engine.profileV3 { cos($0 * .pi / 2) }, .brush)
        XCTAssertEqual(engine.profileV3 { $0 }, .rise)
    }

    func testV3VerseCoverageAndDeterminism() throws {
        for c in ZXArtProceduralFixtureTests.casesV3 {
            let p = Self.recipe(c)
            let size = CGSize(width: Double(c.width) / 3, height: Double(c.height) / 3)
            for palette in [ZXArt.Palette.paperInk, .night] {
                let generated = try XCTUnwrap(ZXArt.traced(procedural: p, palette: palette, pixelSize: size))
                let d = generated.drawing
                let verse = try XCTUnwrap(d.verseLayout).rect(in: size)
                let label = "\(c.variant) \(c.width)x\(c.height) \(c.verseSide ?? "right") dark=\(palette.isDark)"
                XCTAssertLessThan(ZXArtRenderTests.inkCoverage(d, palette: palette, size: size, region: verse), 0.015, label)
                XCTAssertTrue(d.layers.contains { $0.wash != nil }, label)
                XCTAssertTrue(d.layers.contains { $0.tooth != nil }, label)
                XCTAssertEqual(d.layers.contains { $0.rim != nil }, c.variant != "远山" || (c.density ?? 1) > 1, label)
                XCTAssertNotNil(d.anchors)
                let a = try XCTUnwrap(ZXArt.render(d, pixelWidth: Int(size.width), pixelHeight: Int(size.height)))
                let b = try XCTUnwrap(ZXArt.render(procedural: p, palette: palette, pixelSize: size))
                // 整数像素尺寸要一致 (横幅 / 竖幅的 /3 恰为整数)。
                XCTAssertEqual(try ZXArtWashTests.pixels(a), try ZXArtWashTests.pixels(b), label)
                let full = CGRect(origin: .zero, size: size)
                let ink = ZXArtRenderTests.inkCoverage(d, palette: palette, size: size, region: full)
                XCTAssertGreaterThan(ink, 0.001, label)
                let legacy = try XCTUnwrap(ZXArt.traced(procedural: p.downgraded(), palette: palette, pixelSize: size))
                XCTAssertEqual(generated.trace.prngAfter, legacy.trace.prngAfter, "\(label): 公开生成入口的 PRNG 终态")
                XCTAssertEqual(d.anchors, legacy.drawing.anchors, "\(label): 公开生成入口的山脊 / 点景锚点")
                let old = legacy.drawing
                let oldInk = ZXArtRenderTests.inkCoverage(old, palette: palette, size: size, region: full)
                print("v3 ink / v2 ink \(label): \(ink) / \(oldInk)")
                XCTAssertLessThanOrEqual(ink, oldInk + 0.0001, "\(label): 留白不少于 @2 (8-bit 量化容差)")
            }
        }
    }

    func testV3DepthSplitsRetainEffectsAndNearSpans() throws {
        let p = ZXArt.Procedural(generator: "shanshui@3", seed: "秋分-1", variant: "江岸", params: .init(density: 1.5))
        let d = try XCTUnwrap(ZXArt.drawing(procedural: p, palette: .paperInk, pixelSize: Self.sizes[1].1))
        XCTAssertTrue(d.restricted(to: [.far]).layers.allSatisfy { $0.mist != nil && $0.wash != nil })
        let near = d.restricted(to: [.near])
        XCTAssertFalse(near.layers.isEmpty)
        XCTAssertTrue(near.layers.contains { $0.tooth != nil })
        XCTAssertTrue(d.nearSpans.allSatisfy { $0.layer < d.layers.count && $0.range.upperBound <= d.layers[$0.layer].shapes.count })
    }

    func testV3WholeAndTiledRenderingMatch() throws {
        for (i, variant) in ["高山", "江岸", "远山"].enumerated() {
            let p = ZXArt.Procedural(generator: "shanshui@3", seed: "秋分-1", variant: variant,
                                     params: .init(density: 1.5, verseSide: ["left", "right", "top"][i]))
            let size = Self.sizes[i].1
            let width = Int(size.width) / 3, height = Int(size.height) / 3
            for palette in [ZXArt.Palette.paperInk, .night] {
                let d = try XCTUnwrap(ZXArt.drawing(procedural: p, palette: palette, pixelSize: size))
                let whole = try ZXArtWashTests.raster(d, width: width, height: height)
                let tiles = try ZXArtWashTests.raster(d, width: width, height: height,
                                                      cuts: [1, height / 3, height / 2, height - 1])
                XCTAssertEqual(try ZXArtWashTests.pixels(whole), try ZXArtWashTests.pixels(tiles), variant)
            }
        }
    }

    /// 十八张全尺寸样张: 3 variants × 3 frames × light/dark; verse side 在三类画幅间轮换。
    func testReviewSheetsV3() throws {
        for variant in ["高山", "江岸", "远山"] {
            for (fi, entry) in Self.sizes.enumerated() {
                let (frame, size) = entry
                let side = ["right", "left", "top"][fi]
                let p = ZXArt.Procedural(generator: "shanshui@3", seed: "秋分-1", variant: variant,
                                         params: .init(density: 1.3, verseSide: side, verseColumns: 2, verseChars: 7))
                for (name, palette) in [("light", ZXArt.Palette.paperInk), ("dark", .night)] {
                    let image = try XCTUnwrap(ZXArt.render(procedural: p, palette: palette, pixelSize: size))
                    let data = ZXArtRenderTests.pngData(image)
                    let filename = "shanshui-v3-\(variant)-\(frame)-\(side)-\(name).png"
                    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.png.identifier)
                    attachment.name = filename
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    if let directory = ProcessInfo.processInfo.environment["ZXART_WRITE_SHEETS"] {
                        let url = URL(fileURLWithPath: directory, isDirectory: true)
                        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        try data.write(to: url.appendingPathComponent(filename), options: .atomic)
                    }
                }
            }
        }
    }

    func testPortraitV3RenderBaseline() throws {
        let p = ZXArt.Procedural(generator: "shanshui@3", seed: "秋分-1", variant: "江岸")
        let drawing = try XCTUnwrap(ZXArt.drawing(procedural: p, palette: .paperInk, pixelSize: Self.sizes[1].1))
        measure { XCTAssertNotNil(ZXArt.render(drawing, pixelWidth: 1206, pixelHeight: 2622)) }
    }

    func testPortraitV2RenderBaseline() throws {
        let p = ZXArt.Procedural(generator: "shanshui@2", seed: "秋分-1", variant: "江岸")
        let drawing = try XCTUnwrap(ZXArt.drawing(procedural: p, palette: .paperInk, pixelSize: Self.sizes[1].1))
        measure { XCTAssertNotNil(ZXArt.render(drawing, pixelWidth: 1206, pixelHeight: 2622)) }
    }
}
