//  ZXArtVerseTests.swift — @2 (shanshui@2 / nonflowers@2): 诗句框、构图让开诗句、评审图
//
//  评审图写到 /tmp/zxart-shots/v2/ (诗句框描红框; ZXART_SHOTS=0 跳过)。

import CoreGraphics
import Foundation
import XCTest
@testable import ZixiaoArt
import ZixiaoDesign

final class ZXArtVerseTests: XCTestCase {
    static let outDir = URL(fileURLWithPath: "/tmp/zxart-shots/v2", isDirectory: true)
    static let paperInk = ZXArtRenderTests.paperInk
    static let night = ZXArtRenderTests.night

    /// 三种版式 (1/3 尺寸: 构图只看长宽比)。
    static let sizes: [(String, CGSize)] = [
        ("portrait", CGSize(width: 402, height: 874)),
        ("wide", CGSize(width: 1062.0 / 2, height: 498.0 / 2)),
        ("square", CGSize(width: 1062.0 / 2, height: 1116.0 / 2)),
    ]

    static func p(_ g: String, _ seed: String, _ v: String, side: String?, columns: Int? = nil, chars: Int? = nil,
                  density: Double? = nil) -> ZXArt.Procedural {
        ZXArt.Procedural(generator: g, seed: seed, variant: v,
                         params: .init(density: density, verseSide: side, verseColumns: columns, verseChars: chars))
    }

    // MARK: - 契约

    func testV2DecodesVerseParamsAndIsSupported() throws {
        let json = #"""
        {"generator":"shanshui@2","seed":"枫桥","variant":"江岸","params":{"density":null,"hue":null,"quiet_top":null,"verse_side":"left","verse_columns":4,"verse_chars":7}}
        """#
        let p = try JSONDecoder().decode(ZXArt.Procedural.self, from: Data(json.utf8))
        XCTAssertEqual(p.version, 2)
        XCTAssertEqual(p.params.verseSide, "left")
        XCTAssertEqual(p.params.verseColumns, 4)
        XCTAssertEqual(p.params.verseChars, 7)
        XCTAssertTrue(p.isSupported)
        let back = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        XCTAssertTrue(back.contains("\"verse_side\""), back)
        XCTAssertEqual(try JSONDecoder().decode(ZXArt.Procedural.self, from: Data(back.utf8)), p)
        // verse_side 缺省 = right; 认不出的边 → 不画
        XCTAssertEqual(Self.p("nonflowers@2", "a", "梅", side: nil).verseLayout(pixelSize: CGSize(width: 1206, height: 2622))?.side, .right)
        XCTAssertFalse(Self.p("nonflowers@2", "a", "梅", side: "bottom").isSupported)
        XCTAssertNil(ZXArt.render(procedural: Self.p("shanshui@2", "a", "高山", side: "bottom"), palette: Self.paperInk,
                                  pixelSize: CGSize(width: 100, height: 200)))
        // @1 没有诗句框 (verse 参数被忽略, 出图不变)
        XCTAssertNil(Self.p("shanshui@1", "a", "高山", side: "left").verseLayout(pixelSize: CGSize(width: 1206, height: 2622)))
        let d1 = try XCTUnwrap(ZXArt.drawing(procedural: Self.p("shanshui@1", "a", "高山", side: "left"), palette: Self.paperInk,
                                             pixelSize: CGSize(width: 300, height: 650)))
        XCTAssertNil(d1.verseRect)
    }

    /// 诗句框: 单位坐标、在画布内、竖幅在时钟区之下; Drawing 报的与 Procedural 算的是同一个框。
    func testVerseLayoutGeometry() throws {
        let cases: [(CGSize, ZXArt.Frame)] = [(CGSize(width: 1206, height: 2622), .portrait), (CGSize(width: 1062, height: 498), .wide),
                                              (CGSize(width: 510, height: 510), .square), (CGSize(width: 1062, height: 1116), .square)]
        for (size, frame) in cases {
            XCTAssertEqual(ZXArt.Frame(pixelSize: size), frame)
            for side in ["left", "right", "top"] {
                for (n, c) in [(nil, nil), (1, 4), (4, 7), (8, 16) as (Int?, Int?)] {
                    let p = Self.p("shanshui@2", "a", "江岸", side: side, columns: n, chars: c)
                    let v = try XCTUnwrap(p.verseLayout(pixelSize: size))
                    let r = v.rect
                    XCTAssertGreaterThan(r.width, 0.2, "\(frame) \(side)")
                    XCTAssertGreaterThan(r.height, 0.08, "\(frame) \(side)")
                    XCTAssertGreaterThanOrEqual(r.minX, 0.03); XCTAssertLessThanOrEqual(r.maxX, 0.97)
                    XCTAssertGreaterThanOrEqual(r.minY, 0.05); XCTAssertLessThanOrEqual(r.maxY, 0.95)
                    if frame == .portrait { XCTAssertGreaterThanOrEqual(r.minY, 0.32, "clock zone") }
                    if side == "right" && frame != .portrait { XCTAssertGreaterThan(r.midX, 0.5) }
                    if side == "left" { XCTAssertLessThan(r.midX, 0.5) }
                    XCTAssertEqual(v.isVertical, side != "top")
                    let d = try XCTUnwrap(ZXArt.drawing(procedural: p, palette: Self.paperInk, pixelSize: size))
                    let dr = try XCTUnwrap(d.verseRect)
                    XCTAssertEqual(dr.x / d.width, Double(r.minX), accuracy: 1e-9)
                    XCTAssertEqual(dr.y / d.height, Double(r.minY), accuracy: 1e-9)
                    XCTAssertEqual(dr.width / d.width, Double(r.width), accuracy: 1e-9)
                    XCTAssertEqual(d.verseLayout, v)
                }
            }
        }
        // 列数越多, 竖栏越宽 (到上限为止)
        let size = CGSize(width: 1206, height: 2622)
        let w2 = Self.p("nonflowers@2", "a", "梅", side: "right", columns: 2).verseLayout(pixelSize: size)!.rect.width
        let w4 = Self.p("nonflowers@2", "a", "梅", side: "right", columns: 4).verseLayout(pixelSize: size)!.rect.width
        XCTAssertGreaterThan(w4, w2)
    }

    // MARK: - 构图让开诗句框

    /// 诗句框里基本是空纸: 墨量 < 1.5%; 框外确实有画。竖幅的时钟区 (顶部 quiet_top) 同样 < 2%。
    func testVerseRectIsEmpty() throws {
        var worst: [String] = []
        for (fname, size) in Self.sizes {
            for (g, variants) in [("shanshui@2", ZXArtRenderTests.shanshuiVariants), ("nonflowers@2", ZXArtRenderTests.flowerVariants)] {
                for v in variants {
                    for seed in ["秋分-1", "a", "2026"] {
                        for side in ["left", "right", "top"] {
                            let p = Self.p(g, seed, v, side: side, columns: side == "top" ? 2 : 4, chars: 7)
                            let d = try XCTUnwrap(ZXArt.drawing(procedural: p, palette: Self.paperInk, pixelSize: size))
                            let vr = try XCTUnwrap(p.verseLayout(pixelSize: size)).rect(in: size)
                            let cov = ZXArtRenderTests.inkCoverage(d, palette: Self.paperInk, size: size, region: vr)
                            let label = "\(g) \(v) \(seed) \(side) \(fname)"
                            if cov > 0.008 { worst.append(String(format: "%@ %.4f", label, cov)) }
                            XCTAssertLessThan(cov, 0.015, "\(label): ink in verse rect \(cov)")
                            let whole = CGRect(origin: .zero, size: size)
                            XCTAssertGreaterThan(ZXArtRenderTests.inkCoverage(d, palette: Self.paperInk, size: size, region: whole), 0.0015,
                                                 "\(label): nothing drawn")
                            if fname == "portrait" {
                                let clock = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.32)
                                let c = ZXArtRenderTests.inkCoverage(d, palette: Self.paperInk, size: size, region: clock)
                                XCTAssertLessThan(c, 0.02, "\(label): ink in clock zone \(c)")
                            }
                        }
                    }
                }
            }
        }
        print("verse rect ink > 0.8%:\n" + worst.joined(separator: "\n"))
    }

    // MARK: - 评审图

    /// 把诗句框描成红框贴在图上。
    static func outlined(_ img: CGImage, _ rect: CGRect) -> CGImage {
        let w = img.width, h = img.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setStrokeColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 0.9)
        ctx.setLineWidth(max(2, CGFloat(w) / 300))
        ctx.stroke(CGRect(x: rect.minX, y: CGFloat(h) - rect.maxY, width: rect.width, height: rect.height))
        return ctx.makeImage()!
    }

    func testReviewShotsV2() throws {
        guard ZXArtRenderTests.writesShots else { return }
        try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        let full: [(String, CGSize)] = [("portrait", CGSize(width: 1206, height: 2622)), ("wide", CGSize(width: 1062, height: 498)),
                                        ("square", CGSize(width: 1062, height: 1116)), ("small", CGSize(width: 510, height: 510))]
        for (fname, size) in full {
            for (g, variants) in [("shanshui@2", ZXArtRenderTests.shanshuiVariants), ("nonflowers@2", ["梅", "菊", "荷", "兰"])] {
                for v in variants {
                    for seed in ["秋分-1", "a"] {
                        for side in fname == "portrait" ? ["right", "left", "top"] : ["right", "top"] {
                            let p = Self.p(g, seed, v, side: side, columns: side == "top" ? 2 : 4, chars: 7)
                            let pal = g.hasPrefix("shan") && seed == "a" ? Self.night : Self.paperInk
                            let img = try XCTUnwrap(ZXArt.render(procedural: p, palette: pal, pixelSize: size))
                            let vr = try XCTUnwrap(p.verseLayout(pixelSize: size)).rect(in: size)
                            let name = "\(g.replacingOccurrences(of: "@", with: "-"))-\(v)-\(seed)-\(side)-\(fname).png"
                            try ZXArtRenderTests.pngData(Self.outlined(img, vr)).write(to: Self.outDir.appendingPathComponent(name))
                        }
                    }
                }
            }
        }
    }
}
