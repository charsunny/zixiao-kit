import CoreGraphics
import Foundation
import XCTest
@testable import ZixiaoArt

final class ZXArtRimTests: XCTestCase {
    func testRimDefaultsAndInvalidRidges() {
        XCTAssertNil(ZXArt.Layer().rim)
        let rim = ZXArt.LayerRim(ridge: [40, 40, 40], ridgeX0: 0, seed: 42)
        XCTAssertEqual(rim.width, 16)
        XCTAssertEqual(rim.keep(x: 2, y: 39), 0)
        XCTAssertEqual(ZXArt.LayerRim(ridge: []).keep(x: 0, y: 100), 0)
        XCTAssertEqual(ZXArt.LayerRim(ridge: [.infinity]).keep(x: 0, y: 100), 0)
        var invalid = rim
        invalid.width = .nan
        XCTAssertEqual(invalid.keep(x: 0, y: 100), 0)
        invalid = rim; invalid.ridgeStep = 0
        XCTAssertEqual(invalid.keep(x: 0, y: 100), 0)
        // power 包络的上界随深度递减; 横向雾带会把部分列截断。
        var cut = 0, dark = 0
        for y in 40..<240 {
            let k = rim.keep(x: 2, y: Double(y))
            let envelope = rim.peakOpacity * pow(1 + Double(y - 40) / rim.width, -rim.power)
            XCTAssertGreaterThanOrEqual(k, 0)
            XCTAssertLessThanOrEqual(k, envelope + 1e-12)
            if k == 0 { cut += 1 }
            if k > envelope * 0.5 { dark += 1 }
        }
        XCTAssertGreaterThan(cut, 0)
        XCTAssertGreaterThan(dark, 0)
    }

    func testRimAloneAndWithWashMatchWholeAndTiledRendering() throws {
        for palette in [ZXArt.Palette.paperInk, .night] {
            let points: [SIMD2<Float>] = [SIMD2(-20, 85), SIMD2(80, 35), SIMD2(190, 60),
                                          SIMD2(320, 28), SIMD2(440, 100), SIMD2(440, 440), SIMD2(-20, 440)]
            let shape = ZXArt.Shape(points: points, fill: palette.ink, stroke: nil, lineWidth: 0, closed: true)
            let ridge = ZXArt.LayerMist.ridge(of: [shape], step: 2)
            for wet in [false, true] {
                let layer = ZXArt.Layer(blend: palette.isDark ? .normal : .multiply, opacity: 0.87,
                                         rim: .init(ridge: ridge.ridge, ridgeX0: ridge.x0, seed: 42),
                                         wash: wet ? .init(bleed: 3, rim: 0.5, grain: 0.12) : nil,
                                         tooth: wet ? 0.2 : nil, shapes: [shape])
                let d = ZXArt.Drawing(width: 420, height: 420, background: palette.paper,
                                      paper: ZXArtWashTests.paper(palette), layers: [layer])
                for ppu in [1.0, 1.7] {
                    let whole = try ZXArtWashTests.raster(d, width: 391, height: 533, ppu: ppu, origin: CGPoint(x: 11.25, y: -7.5))
                    let tiled = try ZXArtWashTests.raster(d, width: 391, height: 533, cuts: [1, 91, 128, 257, 532],
                                                         ppu: ppu, origin: CGPoint(x: 11.25, y: -7.5))
                    XCTAssertEqual(try ZXArtWashTests.pixels(whole), try ZXArtWashTests.pixels(tiled), "wet=\(wet) ppu=\(ppu)")
                }
            }
        }
    }

    func testVerseCullUsesEdgesAndFilledInterior() {
        let rect = CGRect(x: 40, y: 20, width: 20, height: 20)
        func shape(_ points: [SIMD2<Float>], fill: Bool) -> ZXArt.Shape {
            .init(points: points, fill: fill ? ZXArt.Palette.paperInk.ink : nil,
                  stroke: nil, lineWidth: 0, closed: fill)
        }
        XCTAssertFalse(ZXArt.clearsVerseV3(shape([SIMD2(0, 30), SIMD2(100, 30)], fill: false), rect: rect))
        XCTAssertFalse(ZXArt.clearsVerseV3(shape([SIMD2(0, 0), SIMD2(100, 0), SIMD2(100, 100), SIMD2(0, 100)], fill: true), rect: rect))
        // L 形绕过诗句框; 包围盒与框相交并不代表画进框。
        let around = shape([SIMD2(0, 0), SIMD2(20, 0), SIMD2(20, 60), SIMD2(100, 60), SIMD2(100, 100), SIMD2(0, 100)], fill: true)
        XCTAssertTrue(ZXArt.clearsVerseV3(around, rect: rect))
    }
}
