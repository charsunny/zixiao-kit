//  ZXArtAnchorsTests.swift — shanshui@1 / @2 的意象锚点: 只记录不改画 + 锚点合理
//
//  「不改画」靠两层:
//  1. `Fixtures/zxart/procedural-v1.json` / `procedural-v2.json` (ZXArtProceduralFixtureTests) 记录了 @1 / @2 的几何指纹与
//     生成后的 PRNG 状态, 由加锚点之前的代码生成 —— 加了记录之后指纹不变, 就证明出图与取随机数的顺序没变;
//  2. 本文件: 同一个种子、同一个版式, 记录开 / 关各生成一遍, 构图的每一笔 (坐标、颜色、线宽) 与 PRNG 状态逐位相同,
//     @2 覆盖三种 variant × 三种版式 × 三种诗句边 × 多个种子与密度, @1 覆盖三种 variant × 三种版式 (含横幅小组件) ×
//     多个种子与密度 (比指纹那几个配方宽得多)。
//  「锚点合理」: 都在 0…1 内、不落在诗句框里、船在水面带附近、人站在船上、天空带在所有山脊之上、被 cull 的东西不记。

import CoreGraphics
import Foundation
import XCTest
@testable import ZixiaoArt

final class ZXArtAnchorsTests: XCTestCase {
    typealias Variant = ZXArt.ShanShui.Variant

    static let sizes: [CGSize] = [CGSize(width: 402, height: 874), CGSize(width: 531, height: 249),
                                  CGSize(width: 531, height: 558)]
    static let seeds = ["秋分-1", "a", "2026", "枫桥", "寒露"]
    static let sides: [ZXArt.VerseSide] = [.right, .left, .top]

    /// 配方 (契约密度 0.5–1.5) 的 @2 山水。
    static func procedural(_ seed: String, _ variant: Variant, side: ZXArt.VerseSide, density: Double) -> ZXArt.Procedural {
        ZXArt.Procedural(generator: "shanshui@2", seed: seed, variant: variant.rawValue,
                         params: .init(density: density, verseSide: side.rawValue))
    }

    static func drawing(_ seed: String, _ variant: Variant, _ size: CGSize, side: ZXArt.VerseSide,
                        density: Double = 1.2) throws -> ZXArt.Drawing {
        try XCTUnwrap(ZXArt.drawing(procedural: procedural(seed, variant, side: side, density: density),
                                    palette: .paperInk, pixelSize: size))
    }

    static func drawingV1(_ seed: String, _ variant: Variant, _ size: CGSize, density: Double = 1.3) throws -> ZXArt.Drawing {
        try XCTUnwrap(ZXArt.drawing(procedural: .init(generator: "shanshui@1", seed: seed, variant: variant.rawValue,
                                                      params: .init(density: density)),
                                    palette: .paperInk, pixelSize: size))
    }

    // MARK: - 记录不改画

    private struct Composed {
        var parts: [ShanShuiEngine.Part]
        var anchors: ZXArt.Anchors?
        var state: Double
    }

    /// 与 `ShanShui.generateTraced` 同样的参数, 直接开引擎构图, 可关记录。
    private func compose(_ seed: String, _ variant: Variant, _ pixel: CGSize, side: ZXArt.VerseSide, density: Double,
                         records: Bool) -> Composed {
        let aspect = Double(pixel.height / pixel.width)
        let short = ZXArt.ShanShui.logicalShortSide
        let (W, H) = aspect >= 1 ? (short, short * aspect) : (short / aspect, short)
        let frame = ZXArt.Frame(pixelSize: pixel)
        let quiet = frame.defaultQuietTop
        var params = ZXArt.ShanShui.Params(palette: .paperInk, density: density, variant: variant, quietTop: quiet)
        let verse = ZXArt.verseLayout(side: side, frame: frame, aspect: Double(pixel.width / pixel.height),
                                      quietTop: quiet, columns: nil, chars: nil)
        params.verse = verse
        let engine = ShanShuiEngine(seed: ZXArt.Seed(seed))
        engine.recordsAnchors = records
        let composed = engine.composeV2(width: W, height: H, params: params, verse: verse)
        return Composed(parts: composed.parts, anchors: composed.anchors, state: engine.e.state)
    }

    /// @1: 没有诗句框。
    private func composeV1(_ seed: String, _ variant: Variant, _ pixel: CGSize, density: Double, records: Bool) -> Composed {
        let aspect = Double(pixel.height / pixel.width)
        let short = ZXArt.ShanShui.logicalShortSide
        let (W, H) = aspect >= 1 ? (short, short * aspect) : (short / aspect, short)
        let params = ZXArt.ShanShui.Params(palette: .paperInk, density: density, variant: variant,
                                           quietTop: ZXArt.Frame(pixelSize: pixel).defaultQuietTop)
        let engine = ShanShuiEngine(seed: ZXArt.Seed(seed))
        engine.recordsAnchors = records
        let composed = engine.compose(width: W, height: H, params: params)
        return Composed(parts: composed.parts, anchors: composed.anchors, state: engine.e.state)
    }

    private func assertSame(_ a: ZXArt.SSCanv, _ b: ZXArt.SSCanv, _ label: String, file: StaticString = #filePath,
                            line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, "\(label) polys", file: file, line: line)
        for (i, (pa, pb)) in zip(a, b).enumerated() {
            XCTAssertEqual(pa.p.count, pb.p.count, "\(label) poly \(i) points", file: file, line: line)
            XCTAssertEqual(pa.wid, pb.wid, "\(label) poly \(i) width", file: file, line: line)
            XCTAssertEqual(pa.wash, pb.wash, "\(label) poly \(i) wash", file: file, line: line)
            XCTAssertEqual(pa.fil, pb.fil, "\(label) poly \(i) fill", file: file, line: line)
            XCTAssertEqual(pa.str, pb.str, "\(label) poly \(i) stroke", file: file, line: line)
            // 逐位比较 (含 NaN / inf)。
            let same = zip(pa.p, pb.p).allSatisfy { $0.x.bitPattern == $1.x.bitPattern && $0.y.bitPattern == $1.y.bitPattern }
            XCTAssertTrue(same, "\(label) poly \(i) coordinates", file: file, line: line)
            if !same { return }
        }
    }

    func testRecordingDoesNotChangeTheComposition() {
        var checked = 0
        for (si, seed) in Self.seeds.enumerated() {
            for variant in Variant.allCases {
                for (zi, size) in Self.sizes.enumerated() {
                    for side in Self.sides {
                        let density = [0.1, 0.45, 0.7, 1.0][(si + zi) % 4]
                        let on = compose(seed, variant, size, side: side, density: density, records: true)
                        let off = compose(seed, variant, size, side: side, density: density, records: false)
                        let label = "\(seed) \(variant.rawValue) \(Int(size.width))x\(Int(size.height)) \(side) d=\(density)"
                        XCTAssertNotNil(on.anchors, label)
                        XCTAssertNil(off.anchors, label)
                        XCTAssertEqual(on.state, off.state, "\(label): PRNG state after composition")
                        XCTAssertEqual(on.parts.count, off.parts.count, "\(label): parts")
                        for (k, (a, b)) in zip(on.parts, off.parts).enumerated() {
                            assertSame(a.canv, b.canv, "\(label) part \(k)")
                            XCTAssertEqual(a.mist?.depth, b.mist?.depth, "\(label) part \(k) mist depth")
                            XCTAssertEqual(a.mist?.peak, b.mist?.peak, "\(label) part \(k) mist peak")
                            XCTAssertEqual(a.mist?.floorY, b.mist?.floorY, "\(label) part \(k) mist floor")
                        }
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(checked, Self.seeds.count * Variant.allCases.count * Self.sizes.count * Self.sides.count)
    }

    func testRecordingDoesNotChangeTheV1Composition() {
        var checked = 0
        for (si, seed) in (Self.seeds + ["b", "42"]).enumerated() {
            for variant in Variant.allCases {
                for (zi, size) in Self.sizes.enumerated() {
                    for density in [0.1, 0.45, 0.7, 1.0] where (si + zi) % 2 == Int(density * 10) % 2 {
                        let on = composeV1(seed, variant, size, density: density, records: true)
                        let off = composeV1(seed, variant, size, density: density, records: false)
                        let label = "@1 \(seed) \(variant.rawValue) \(Int(size.width))x\(Int(size.height)) d=\(density)"
                        XCTAssertNotNil(on.anchors, label)
                        XCTAssertNil(off.anchors, label)
                        XCTAssertEqual(on.state, off.state, "\(label): PRNG state after composition")
                        XCTAssertEqual(on.parts.count, off.parts.count, "\(label): parts")
                        for (k, (a, b)) in zip(on.parts, off.parts).enumerated() {
                            assertSame(a.canv, b.canv, "\(label) part \(k)")
                            XCTAssertEqual(a.mist?.depth, b.mist?.depth, "\(label) part \(k) mist depth")
                            XCTAssertEqual(a.mist?.peak, b.mist?.peak, "\(label) part \(k) mist peak")
                            XCTAssertEqual(a.mist?.floorY, b.mist?.floorY, "\(label) part \(k) mist floor")
                        }
                        checked += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 60)
    }

    func testMountainRecordingDoesNotChangeTheMountain() {
        for seed in ["m1", "m2", "m3", "m4"] {
            let on = ShanShuiEngine(seed: ZXArt.Seed(seed))
            on.anchorLog = []
            let off = ShanShuiEngine(seed: ZXArt.Seed(seed))
            let a = on.mountain(200, 300, 7, hei: 220, wid: 320, tex: 100)
            let b = off.mountain(200, 300, 7, hei: 220, wid: 320, tex: 100)
            assertSame(a, b, "mountain \(seed)")
            XCTAssertEqual(on.e.state, off.e.state, "mountain \(seed) PRNG state")
            XCTAssertNil(off.anchorLog, "记录关着时什么也不记")
        }
    }

    func testMountainReportsItsTreesAndHousesInItsOwnCoordinates() {
        var reported = 0
        for seed in ["m1", "m2", "m3", "m4", "m5", "m6"] {
            let engine = ShanShuiEngine(seed: ZXArt.Seed(seed))
            engine.anchorLog = []
            let canv = engine.mountain(200, 300, 7, hei: 220, wid: 320, tex: 100)
            let log = engine.takeAnchorLog()
            XCTAssertEqual(engine.anchorLog?.count, 0, "取走后清空")
            for piece in log {
                reported += 1
                switch piece.kind {
                case .tree, .building: break
                default: XCTFail("mountain() 只报树与屋: \(piece.kind)")
                }
                // 报上来的每一笔都原样在山的笔画里。
                for poly in piece.canv {
                    XCTAssertTrue(canv.contains { $0.p == poly.p }, "\(seed): 报上来的笔画不在山里")
                }
            }
        }
        XCTAssertGreaterThan(reported, 0, "几座山里总会长出树")
    }

    // MARK: - 谁有锚点

    func testShanShuiV1AndV2CarryAnchorsFlowersDoNot() throws {
        let size = CGSize(width: 402, height: 874)
        let v2 = try Self.drawing("枫桥", .riverbank, size, side: .right)
        XCTAssertNotNil(v2.anchors)
        XCTAssertEqual(v2.anchors?.isEmpty, false)
        for variant in Variant.allCases {
            let v1 = try Self.drawingV1("枫桥", variant, size)
            XCTAssertEqual(v1.anchors?.isEmpty, false, "@1 \(variant.rawValue) 有锚点")
        }
        for generator in ["nonflowers@1", "nonflowers@2"] {
            let flower = try XCTUnwrap(ZXArt.drawing(procedural: .init(generator: generator, seed: "42", variant: "梅"),
                                                     palette: .paperInk, pixelSize: size))
            XCTAssertNil(flower.anchors, "花不加: \(generator)")
        }
        XCTAssertNil(ZXArt.ShanShui.originalScene(seed: "42").anchors, "原作第一屏不加")
    }

    func testAnchorsAreDeterministic() throws {
        let size = CGSize(width: 402, height: 874)
        let a = try Self.drawing("寒露", .alpine, size, side: .left, density: 1.4)
        let b = try Self.drawing("寒露", .alpine, size, side: .left, density: 1.4)
        XCTAssertEqual(a.anchors, b.anchors)
    }

    // MARK: - 合理性

    /// 所有版式 × variant × 诗句边 × 种子的 @2 山水, 再加所有版式 × variant × 种子的 @1 山水 (没有诗句框: `verse` 为 nil)。
    private func forEveryRecipe(_ body: (String, ZXArt.Drawing, ZXArt.Anchors, ZXArt.VerseLayout?) throws -> Void) throws {
        for seed in Self.seeds {
            for variant in Variant.allCases {
                for size in Self.sizes {
                    let v1 = try Self.drawingV1(seed, variant, size)
                    let label1 = "@1 \(seed) \(variant.rawValue) \(Int(size.width))x\(Int(size.height))"
                    try body(label1, v1, try XCTUnwrap(v1.anchors, label1), nil)
                    for side in Self.sides {
                        let d = try Self.drawing(seed, variant, size, side: side, density: 1.3)
                        let label = "\(seed) \(variant.rawValue) \(Int(size.width))x\(Int(size.height)) \(side)"
                        let anchors = try XCTUnwrap(d.anchors, label)
                        let verse = try XCTUnwrap(d.verseLayout, label)
                        try body(label, d, anchors, verse)
                    }
                }
            }
        }
    }

    func testAnchorsAreInsideTheCanvas() throws {
        var ridges = 0, trees = 0, boats = 0
        try forEveryRecipe { label, _, a, _ in
            func inside(_ v: Double, _ what: String) {
                XCTAssertTrue((0...1).contains(v), "\(label): \(what) = \(v)")
            }
            XCTAssertFalse(a.ridges.isEmpty, "\(label): 总有山脊")
            for ridge in a.ridges {
                ridges += 1
                XCTAssertGreaterThanOrEqual(ridge.points.count, 2, label)
                for (p, q) in zip(ridge.points, ridge.points.dropFirst()) {
                    XCTAssertLessThan(p.x, q.x, "\(label): 山脊按 x 递增")
                }
                for p in ridge.points {
                    inside(Double(p.x), "ridge x")
                    inside(Double(p.y), "ridge y")
                }
            }
            if let w = a.water {
                inside(w.x.lowerBound, "water x0"); inside(w.x.upperBound, "water x1")
                inside(w.y.lowerBound, "water y0"); inside(w.y.upperBound, "water y1")
            }
            for b in a.boats {
                boats += 1
                inside(b.x, "boat x"); inside(b.y, "boat y"); inside(b.length, "boat length")
                XCTAssertGreaterThan(b.length, 0, label)
            }
            for f in a.figures {
                inside(f.x, "figure x"); inside(f.baseY, "figure baseY"); inside(f.topY, "figure topY")
                XCTAssertLessThanOrEqual(f.topY, f.baseY, label)
                XCTAssertTrue(f.wearsStrawHat, "船上的渔人戴斗笠")
            }
            for t in a.trees {
                trees += 1
                inside(t.x, "tree x"); inside(t.baseY, "tree baseY"); inside(t.topY, "tree topY"); inside(t.width, "tree width")
                XCTAssertLessThanOrEqual(t.topY, t.baseY, label)
            }
            for b in a.buildings {
                inside(b.x, "building x"); inside(b.baseY, "building baseY"); inside(b.roofY, "building roofY")
                inside(b.width, "building width")
                XCTAssertLessThanOrEqual(b.roofY, b.baseY, label)
            }
            if let s = a.sky {
                inside(s.y.lowerBound, "sky y0"); inside(s.y.upperBound, "sky y1")
                XCTAssertEqual(s.x, 0...1, label)
            }
        }
        XCTAssertGreaterThan(ridges, 0)
        XCTAssertGreaterThan(boats, 0, "密度 1.3 的画里总有船")
        XCTAssertGreaterThan(trees, 0, "江岸近岸总有树")
    }

    /// 船、人、树、屋的基准点不落在诗句框里 (与 cull 同一个禁区; 被 cull 的整件不记)。
    func testNothingAnchoredInsideTheVerseBox() throws {
        try forEveryRecipe { label, _, a, verse in
            guard let verse else { return }   // @1 没有诗句框
            let box = verse.rect
            func outside(_ x: Double, _ y: Double, _ what: String) {
                XCTAssertFalse(box.contains(CGPoint(x: x, y: y)), "\(label): \(what) (\(x), \(y)) 落在诗句框 \(box) 里")
            }
            for b in a.boats { outside(b.x, b.y, "boat") }
            for f in a.figures { outside(f.x, f.baseY, "figure") }
            for t in a.trees { outside(t.x, t.baseY, "tree") }
            for b in a.buildings { outside(b.x, b.baseY, "building") }
        }
    }

    func testBoatsSitNearTheWaterAndFiguresStandOnBoats() throws {
        try forEveryRecipe { label, _, a, _ in
            XCTAssertEqual(a.boats.count, a.figures.count, "\(label): 每条船一个渔人")
            for (boat, figure) in zip(a.boats, a.figures) {
                XCTAssertLessThanOrEqual(abs(figure.x - boat.x), boat.length / 2 + 0.03, "\(label): 人在船上 (x)")
                XCTAssertLessThanOrEqual(figure.baseY, boat.y + 0.03, "\(label): 人不沉到船底以下")
                XCTAssertLessThan(figure.topY, boat.y, "\(label): 人高过船")
                if let water = a.water {
                    // 水纹是一把短线, 船比它宽一点也算; 竖向放宽 0.08 (水纹笔画的起伏与吃水)。
                    XCTAssertGreaterThanOrEqual(boat.y, water.y.lowerBound - 0.08, "\(label): 船在水面带之下")
                    XCTAssertLessThanOrEqual(boat.y, water.y.upperBound + 0.08, "\(label): 船在水面带之上")
                    XCTAssertGreaterThanOrEqual(boat.x, water.x.lowerBound - boat.length - 0.05, label)
                    XCTAssertLessThanOrEqual(boat.x, water.x.upperBound + boat.length + 0.05, label)
                } else {
                    XCTFail("\(label): 有船就有水")
                }
            }
        }
    }

    func testSkyBandSitsAboveEveryRidge() throws {
        var skies = 0
        try forEveryRecipe { label, _, a, _ in
            guard let sky = a.sky else { return }
            skies += 1
            XCTAssertEqual(sky.y.lowerBound, 0, label)
            for ridge in a.ridges {
                for p in ridge.points {
                    XCTAssertGreaterThanOrEqual(Double(p.y), sky.y.upperBound - 1e-6, "\(label): 山脊不进天空带")
                }
            }
            XCTAssertGreaterThanOrEqual(sky.y.upperBound, ZXArt.Anchors.minSkyHeight, label)
        }
        XCTAssertGreaterThan(skies, 0, "远山的构图里山顶在画顶之下")
    }

    // MARK: - 换算 (合成的笔画)

    private func line(_ pts: [(Double, Double)], fill: Bool = false) -> ZXArt.SSPoly {
        ZXArt.SSPoly(p: pts.map { ZXArt.P($0.0, $0.1) }, fil: fill ? .white : nil, str: .ink(0.5), wid: 1)
    }

    private let blockedRight: (Double, Double) -> Bool = { x, y in x > 150 && y < 100 }

    func testBuildTakesRidgeFromTheUpperEnvelopeOfTheDrawnStrokes() {
        let ridge = ZXArt.AnchorPiece(kind: .ridge(.main), canv: [
            line([(0, 100), (100, 40), (200, 100)]),
            line([(0, 150), (200, 150)]),
        ])
        let a = ZXArt.Anchors.build(pieces: [ridge], width: 200, height: 200, blocked: { _, _ in false })
        let r = a.ridges.first
        XCTAssertEqual(r?.role, .main)
        XCTAssertEqual(r?.points.first?.x, 0)
        XCTAssertEqual(r?.points.last?.x, 1)
        let peak = r?.points.min { $0.y < $1.y }
        XCTAssertEqual(Double(peak?.y ?? 9), 40.0 / 200, accuracy: 1e-6, "最高处 = 山顶")
        XCTAssertEqual(Double(peak?.x ?? 9), 0.5, accuracy: 0.02)
        XCTAssertEqual(a.sky?.y.lowerBound, 0)
        XCTAssertEqual(a.sky?.y.upperBound ?? 9, 40.0 / 200, accuracy: 1e-6, "天空带到最高山脊")
    }

    func testBuildDropsStrokesInTheBlockedZoneForRidgesAndWater() {
        // 右上禁区 (x > 150, y < 100): 山的右半边被 cull, 山脊只剩左半; 水纹只剩没被去掉的一条。
        let mountain = ZXArt.AnchorPiece(kind: .ridge(.back), canv: [
            line([(0, 120), (60, 60), (120, 120)]),
            line([(150, 130), (180, 40), (200, 130)]),
        ])
        let water = ZXArt.AnchorPiece(kind: .water, canv: [
            line([(20, 160), (90, 165)]),
            line([(160, 80), (190, 85)]),
        ])
        let a = ZXArt.Anchors.build(pieces: [mountain, water], width: 200, height: 200, blocked: blockedRight)
        XCTAssertLessThanOrEqual(Double(a.ridges.first?.points.last?.x ?? 9), 120.0 / 200 + 1e-6)
        XCTAssertEqual(a.water?.x, (20.0 / 200)...(90.0 / 200))
        XCTAssertEqual(a.water?.y, (160.0 / 200)...(165.0 / 200))
    }

    func testBuildKeepsOnlyWholeTreesBuildingsAndBoats() {
        let whole = ZXArt.AnchorPiece(kind: .tree(.tree01), canv: [line([(40, 110), (40, 140)]),
                                                                  line([(30, 110), (50, 110)])])
        let partlyCulled = ZXArt.AnchorPiece(kind: .tree(.tree03), canv: [line([(40, 110), (40, 140)]),
                                                                          line([(160, 90), (170, 90)])])
        let house = ZXArt.AnchorPiece(kind: .building(.house), canv: [line([(100, 120), (120, 120)], fill: true),
                                                                      line([(95, 100), (125, 100)], fill: true)])
        let a = ZXArt.Anchors.build(pieces: [whole, partlyCulled, house], width: 200, height: 200, blocked: blockedRight)
        XCTAssertEqual(a.trees.count, 1, "一笔被 cull 的树整棵不记")
        XCTAssertEqual(a.trees.first?.kind, .tree01)
        XCTAssertEqual(a.trees.first?.x ?? 9, 0.2, accuracy: 1e-9)
        XCTAssertEqual(a.trees.first?.baseY ?? 9, 0.7, accuracy: 1e-9)
        XCTAssertEqual(a.trees.first?.topY ?? 9, 0.55, accuracy: 1e-9)
        XCTAssertEqual(a.trees.first?.width ?? 9, 0.1, accuracy: 1e-9)
        XCTAssertEqual(a.buildings.count, 1)
        XCTAssertEqual(a.buildings.first?.kind, .house)
        XCTAssertEqual(a.buildings.first?.roofY ?? 9, 0.5, accuracy: 1e-9)
        XCTAssertEqual(a.buildings.first?.baseY ?? 9, 0.6, accuracy: 1e-9)
    }

    func testBuildSplitsABoatIntoHullAndFigure() {
        // 人 (两笔) + 船身 (填充 + 描边), 人在船身的左半: 船头朝右, 不翻转。
        let canv: ZXArt.SSCanv = [line([(60, 80), (64, 98)]), line([(58, 80), (68, 80)]),
                                  line([(60, 100), (100, 106)], fill: true), line([(60, 100), (100, 106)])]
        let boat = ZXArt.AnchorPiece(kind: .boat, canv: canv)
        let a = ZXArt.Anchors.build(pieces: [boat], width: 200, height: 200, blocked: { _, _ in false })
        XCTAssertEqual(a.boats.count, 1)
        XCTAssertEqual(a.boats.first?.x ?? 9, 0.4, accuracy: 1e-9)
        XCTAssertEqual(a.boats.first?.y ?? 9, 0.53, accuracy: 1e-9)
        XCTAssertEqual(a.boats.first?.length ?? 9, 0.2, accuracy: 1e-9)
        XCTAssertEqual(a.boats.first?.flipped, false)
        XCTAssertEqual(a.figures.count, 1)
        XCTAssertEqual(a.figures.first?.x ?? 9, 0.315, accuracy: 1e-9)
        XCTAssertEqual(a.figures.first?.baseY ?? 9, 0.49, accuracy: 1e-9)
        XCTAssertEqual(a.figures.first?.topY ?? 9, 0.4, accuracy: 1e-9)

        // 人在右半: 翻转。
        let mirrored: ZXArt.SSCanv = [line([(96, 80), (100, 98)]), line([(60, 100), (100, 106)], fill: true),
                                      line([(60, 100), (100, 106)])]
        let b = ZXArt.Anchors.build(pieces: [ZXArt.AnchorPiece(kind: .boat, canv: mirrored)], width: 200, height: 200,
                                    blocked: { _, _ in false })
        XCTAssertEqual(b.boats.first?.flipped, true)

        // 船身一笔被 cull: 整条船连人都不记。
        let c = ZXArt.Anchors.build(pieces: [ZXArt.AnchorPiece(kind: .boat, canv: canv)], width: 200, height: 200,
                                    blocked: { x, _ in x > 90 })
        XCTAssertTrue(c.boats.isEmpty)
        XCTAssertTrue(c.figures.isEmpty)
    }

    func testBuildSkipsThingsOutsideTheCanvas() {
        let off = ZXArt.AnchorPiece(kind: .tree(.tree02), canv: [line([(-60, 100), (-40, 100)])])
        let a = ZXArt.Anchors.build(pieces: [off], width: 200, height: 200, blocked: { _, _ in false })
        XCTAssertTrue(a.trees.isEmpty)
        XCTAssertTrue(a.isEmpty)
    }

    // MARK: - 平移

    func testTranslationRecoversPlacedAndFitShifts() {
        let canv: ZXArt.SSCanv = [line([(10, 20), (30, 40)]), line([(50, 60), (70, 80)])]
        let moved = ShanShuiEngine.shifted(canv, dx: 3, dy: -4.5)
        let t = ShanShuiEngine.translation(from: canv, to: moved)
        XCTAssertEqual(t.dx, 3, accuracy: 1e-12)
        XCTAssertEqual(t.dy, -4.5, accuracy: 1e-12)
        let same = ShanShuiEngine.translation(from: canv, to: canv)
        XCTAssertEqual(same.dx, 0)
        XCTAssertEqual(same.dy, 0)
        XCTAssertEqual(ShanShuiEngine.translation(from: [], to: []).dx, 0)
    }
}
