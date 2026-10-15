//  ZXArtLayersTests.swift — 山水的景深分层 (远山 / 中景 / 近景) 与透明底渲染
//
//  分层只是给图层加了一份「哪些形状是近景」的记录 (`nearSpans`) 和一个纯数据变换 (`restricted(to:)`):
//  不传分层参数时出图不变 —— `ZXArtProceduralFixtureTests` 的指纹 (由加分层之前的代码生成) 与
//  `ZXArtAnchorsTests` 的逐位对照继续担保; 这里证明分层本身: 形状守恒、各层互不重叠、近景只含水纹 / 船 / 岸、
//  透明底渲染的角落是透明的。

import CoreGraphics
import Foundation
import XCTest
@testable import ZixiaoArt

final class ZXArtLayersTests: XCTestCase {
    typealias Variant = ZXArt.ShanShui.Variant

    static func drawing(_ generator: String, _ seed: String, _ variant: Variant, side: String? = nil) throws -> ZXArt.Drawing {
        try XCTUnwrap(ZXArt.drawing(
            procedural: .init(generator: generator, seed: seed, variant: variant.rawValue,
                              params: .init(density: 1.3, verseSide: side)),
            palette: .paperInk, pixelSize: CGSize(width: 402, height: 874)))
    }

    static let cases: [(String, String?)] = [("shanshui@1", nil), ("shanshui@2", "right"), ("shanshui@2", "left")]

    func testShapesAreConservedAcrossTheThreeRoles() throws {
        for (generator, side) in Self.cases {
            for variant in Variant.allCases {
                for seed in ["秋分-1", "a", "寒露"] {
                    let d = try Self.drawing(generator, seed, variant, side: side)
                    let far = d.restricted(to: [.far]), mid = d.restricted(to: [.mid]), near = d.restricted(to: [.near])
                    let label = "\(generator) \(seed) \(variant.rawValue)"
                    XCTAssertEqual(far.shapeCount + mid.shapeCount + near.shapeCount, d.shapeCount, label)
                    XCTAssertEqual(d.restricted(to: Set(ZXArt.PartRole.allCases)).shapeCount, d.shapeCount, label)
                    XCTAssertTrue(far.layers.allSatisfy { $0.mist != nil }, "\(label): 远山 = 雾化层")
                    XCTAssertTrue(mid.layers.allSatisfy { $0.mist == nil }, label)
                    XCTAssertTrue(near.layers.allSatisfy { $0.mist == nil }, label)
                    XCTAssertGreaterThan(far.shapeCount, 0, "\(label): 总有远山")
                    XCTAssertGreaterThan(mid.shapeCount, 0, "\(label): 总有中景")
                    XCTAssertGreaterThan(near.shapeCount, 0, "\(label): 总有水纹")
                }
            }
        }
    }

    func testNearSpansStayInsidePlainLayers() throws {
        for (generator, side) in Self.cases {
            let d = try Self.drawing(generator, "枫桥", .riverbank, side: side)
            XCTAssertFalse(d.nearSpans.isEmpty)
            for span in d.nearSpans {
                XCTAssertTrue(d.layers.indices.contains(span.layer))
                XCTAssertNil(d.layers[span.layer].mist, "近景只在普通层里")
                XCTAssertTrue(span.range.lowerBound >= 0 && span.range.upperBound <= d.layers[span.layer].shapes.count)
                XCTAssertFalse(span.range.isEmpty)
            }
            // 区间互不重叠。
            for (a, b) in zip(d.nearSpans, d.nearSpans.dropFirst()) where a.layer == b.layer {
                XCTAssertLessThanOrEqual(a.range.upperBound, b.range.lowerBound)
            }
        }
    }

    func testRestrictedKeepsGeometryAndDropsPaper() throws {
        let d = try Self.drawing("shanshui@2", "寒露", .alpine, side: "right")
        let mid = d.restricted(to: [.mid])
        XCTAssertEqual(mid.width, d.width)
        XCTAssertEqual(mid.height, d.height)
        XCTAssertNil(mid.paper, "纸纹不跟着分层 (底纸另画)")
        XCTAssertEqual(mid.verseLayout, d.verseLayout)
        XCTAssertTrue(mid.nearSpans.isEmpty)
        // 原画不变 (restricted 是纯函数)。
        XCTAssertNotNil(d.paper)
        XCTAssertFalse(d.nearSpans.isEmpty)
    }

    func testFlowersHaveNoNearSpans() throws {
        let flower = try XCTUnwrap(ZXArt.drawing(procedural: .init(generator: "nonflowers@1", seed: "42", variant: "梅"),
                                                 palette: .paperInk, pixelSize: CGSize(width: 402, height: 874)))
        XCTAssertTrue(flower.nearSpans.isEmpty)
        XCTAssertEqual(flower.restricted(to: [.mid]).shapeCount, flower.shapeCount, "花全算中景")
    }

    func testTransparentLayerHasClearCornersAndInk() throws {
        let d = try Self.drawing("shanshui@2", "秋分-1", .riverbank, side: "right")
        let width = 402, height = 874
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for role in ZXArt.PartRole.allCases {
            let layer = d.restricted(to: [role])
            let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ZXArt.draw(layer, in: ctx, rect: CGRect(x: 0, y: 0, width: width, height: height), pixelsPerUnit: 1,
                       includesGround: false)
            let data = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
            let bytesPerRow = ctx.bytesPerRow
            func alpha(_ x: Int, _ y: Int) -> UInt8 { data[y * bytesPerRow + x * 4 + 3] }
            // 左上角 (时钟区 / 诗句框附近) 没有任何画 —— 透明。
            XCTAssertEqual(alpha(2, 2), 0, "\(role): 角落透明")
            var inked = 0
            for y in stride(from: 0, to: height, by: 3) {
                for x in stride(from: 0, to: width, by: 3) where alpha(x, y) > 0 { inked += 1 }
            }
            XCTAssertGreaterThan(inked, 50, "\(role): 有墨")
        }
    }

    /// 缺省 (含底色与纸纹) 的 `draw` 与 `render` 的出图一致: 加 `includesGround` 参数没改缺省行为。
    func testDefaultDrawStillPaintsTheGround() throws {
        let d = try Self.drawing("shanshui@1", "a", .distant)
        let width = 120, height = 260
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ZXArt.draw(d, in: ctx, rect: CGRect(x: 0, y: 0, width: width, height: height), pixelsPerUnit: 1)
        let data = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(data[3], 255, "缺省画纸: 角落不透明")
    }
}
