//  ZXArtWashTests.swift — 湿墨、纸纹咬边、冻结旧分派与分块一致性
//  VPS 未编译 / 执行; Mac: 见 PR 的 xcodebuild 命令。样张支持 ZXART_WRITE_SHEETS。

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ZixiaoArt

// 冻结自 beba923 的 draw 分派 (仅适配 Geo 新增的 rect 字段)。
// 与新分派共用未改动的 raster / filter / mist / paper 辅助函数, 不走 wash / tooth 分支。
private extension ZXArt {
    static func drawBeforeLayerWash(_ prepared: Prepared, in ctx: CGContext, rect: CGRect, visible: CGRect, pixelsPerUnit: CGFloat,
                     ground: Bool = true) {
        let drawing = prepared.drawing
        let s = max(Double(rect.width) / drawing.width, Double(rect.height) / drawing.height)
        let ox = Double(rect.midX) - drawing.width * s / 2
        let oy = Double(rect.midY) - drawing.height * s / 2
        let view = visible.intersection(rect)
        guard !view.isNull, view.height > 0 else { return }
        // 可见范围 → 逻辑单位的 y 区间 (剔除用, 放宽 2 个单位)
        let vy0 = Float((Double(view.minY) - oy) / s - 2), vy1 = Float((Double(view.maxY) - oy) / s + 2)
        ctx.saveGState()
        ctx.clip(to: view)
        let bg = drawing.background
        if ground {
            withCG {
                ctx.setFillColor(red: bg.red, green: bg.green, blue: bg.blue, alpha: 1)
                ctx.fill(view)
            }
        }
        if ground, let paper = drawing.paper, let tile = paperTile(paper, paperColor: bg) {
            cgLock.lock()
            defer { cgLock.unlock() }
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(ox), y: CGFloat(oy))
            ctx.scaleBy(x: CGFloat(s * paper.texel), y: CGFloat(s * paper.texel))
            ctx.interpolationQuality = .low
            ctx.draw(tile, in: CGRect(x: 0, y: 0, width: PaperTexture.side, height: PaperTexture.side), byTiling: true)
            ctx.restoreGState()
        }
        let geo = Geo(s: s, ox: ox, oy: oy, ppu: Double(pixelsPerUnit), rect: rect, view: view, vy0: vy0, vy1: vy1)
        for (li, layer) in drawing.layers.enumerated() {
            if let filter = layer.filter {
                drawFiltered(prepared, li, filter: filter, in: ctx, geo)
            } else if let mist = layer.mist {
                drawMisted(prepared, li, mist: mist, in: ctx, geo)
            } else {
                withCG {
                    ctx.saveGState()
                    ctx.setBlendMode(layer.blend == .multiply ? .multiply : .normal)
                    ctx.setAlpha(CGFloat(layer.opacity))
                    if layer.opacity < 1 { ctx.beginTransparencyLayer(auxiliaryInfo: nil) }
                    ctx.translateBy(x: CGFloat(ox), y: CGFloat(oy))
                    ctx.scaleBy(x: CGFloat(s), y: CGFloat(s))
                    drawShapes(prepared, li, in: ctx, vy0: vy0, vy1: vy1)
                    if layer.opacity < 1 { ctx.endTransparencyLayer() }
                    ctx.restoreGState()
                }
            }
        }
        ctx.restoreGState()
    }
}

final class ZXArtWashTests: XCTestCase {
    typealias Brush = ZXArt.Brush

    /// 模拟同一底图在不同 visible 横带中绘制, 不把两张已经渲染好的图裁切后比较。
    static func raster(_ drawing: ZXArt.Drawing, width: Int, height: Int, cuts: [Int] = [],
                       ppu: Double = 1, origin: CGPoint = .zero, legacy: Bool = false,
                       transparent: Bool = false) throws -> CGImage {
        let ctx = try XCTUnwrap(ZXArt.makeBitmap(width: width, height: height))
        if !transparent {
            let ground = ZXArt.PaperGround(drawing, pixelWidth: width, pixelHeight: height)
            ground.fill(try XCTUnwrap(ctx.data), bytesPerRow: ctx.bytesPerRow, rows: 0..<height)
        }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: CGFloat(1 / ppu), y: CGFloat(-1 / ppu))
        ctx.translateBy(x: -origin.x, y: -origin.y)
        let rect = CGRect(x: origin.x, y: origin.y, width: Double(width) / ppu, height: Double(height) / ppu)
        let prepared = ZXArt.Prepared(drawing)
        let edges = [0] + cuts + [height]
        for (a, b) in zip(edges, edges.dropFirst()) {
            let view = CGRect(x: origin.x, y: Double(origin.y) + Double(a) / ppu,
                              width: rect.width, height: Double(b - a) / ppu)
            if legacy {
                ZXArt.drawBeforeLayerWash(prepared, in: ctx, rect: rect, visible: view, pixelsPerUnit: CGFloat(ppu), ground: false)
            } else {
                ZXArt.draw(prepared, in: ctx, rect: rect, visible: view, pixelsPerUnit: CGFloat(ppu), ground: false)
            }
        }
        return try XCTUnwrap(ctx.makeImage())
    }

    static func pixels(_ image: CGImage) throws -> Data {
        try XCTUnwrap(image.dataProvider?.data as Data?)
    }

    static func paper(_ palette: ZXArt.Palette) -> ZXArt.PaperTexture {
        let shades = (0..<(ZXArt.PaperTexture.side * ZXArt.PaperTexture.side)).map { i in
            UInt8((ZXArt.WashNoise.value(Double(i % 512) * 0.7, Double(i / 512) * 0.7, seed: 42) * 30).rounded())
        }
        return .init(shade: shades, texel: 0.7, tint: palette.ink)
    }

    static func strokes() -> (strokes: [Brush.Stroke], styles: [Brush.Style]) {
        var strokes: [Brush.Stroke] = [], styles: [Brush.Style] = []
        for (row, profile) in [Brush.Profile.brush, .tip, .nail, .press].enumerated() {
            for (column, dry) in [0.0, 0.4, 0.8].enumerated() {
                let x = 30.0 + Double(column) * 130, y = 40.0 + Double(row) * 65
                let style = Brush.Style(width: 14, dry: dry, wet: 0.65, side: column == 1 ? 0.8 : 0, profile: profile)
                strokes.append(Brush.stroke([SIMD3(x, y, 1), SIMD3(x + 45, y - 8, 1), SIMD3(x + 100, y + 7, 1)],
                                            style: style, seed: UInt32(row * 3 + column + 42)))
                styles.append(style)
            }
        }
        // 大湿笔与细干笔交叉, 同时检查水线、密度、飞白与分块边缘。
        for (i, width) in [30.0, 60, 95].enumerated() {
            let y = 330.0 + Double(i) * 130
            let style = Brush.Style(width: width, tone: 0.60, dry: 0.08, wet: 0.85, side: 0.4, profile: .brush)
            strokes.append(Brush.stroke([SIMD3(-10, y, 1), SIMD3(170, y - 23, 1), SIMD3(430, y + 24, 0.7)],
                                        style: style, seed: UInt32(i + 73)))
            styles.append(style)
        }
        let ring = Brush.Style(width: 3, dry: 0.55, wet: 0.4, side: 0.8, gapLength: 500)
        strokes.append(Brush.ring(center: SIMD2(210, 745), radius: 150, squash: 0.3, style: ring, seed: 42))
        styles.append(ring)
        return (strokes, styles)
    }

    static func drawing(palette: ZXArt.Palette = .paperInk, wash: Bool = true, tooth: Bool = true,
                        textured: Bool = true) -> ZXArt.Drawing {
        let sample = strokes()
        let layers = ZXArt.layers(from: sample.strokes, styles: sample.styles, palette: palette,
                                  wash: wash ? .init(bleed: 4, rim: 0.7, grain: 0.25) : nil,
                                  tooth: tooth ? 0.4 : nil)
        return .init(width: 420, height: 820, background: palette.paper,
                     paper: textured ? paper(palette) : nil, layers: [layers.wet, layers.dry])
    }

    func testNilEffectsKeepSixFrozenRecipesByteForByte() throws {
        // 从既有 procedural fixture cases 取 @1 / @2 各三个, 同时覆盖 mist / plain / flower filter。
        let all = ZXArtProceduralFixtureTests.cases, v2 = ZXArtProceduralFixtureTests.casesV2
        for c in [all[0], all[1], all[4], v2[0], v2[5], v2[8]] {
            let size = CGSize(width: c.width, height: c.height)
            let p = ZXArt.Procedural(generator: c.generator, seed: c.seed, variant: c.variant,
                params: .init(density: c.density, hue: c.hue, quietTop: c.quietTop, verseSide: c.verseSide,
                              verseColumns: c.verseColumns, verseChars: c.verseChars))
            let d = try XCTUnwrap(ZXArt.drawing(procedural: p, palette: .paperInk, pixelSize: size))
            XCTAssertTrue(d.layers.allSatisfy { $0.wash == nil && $0.tooth == nil })
            let before = try Self.raster(d, width: c.width, height: c.height, legacy: true)
            let after = try XCTUnwrap(ZXArt.render(d, pixelWidth: c.width, pixelHeight: c.height))
            XCTAssertEqual(try Self.pixels(before), try Self.pixels(after), "\(c.generator) \(c.seed) \(c.variant)")
        }
    }

    func testWholeAndDifferentRowPartitionsMatchExactly() throws {
        for palette in [ZXArt.Palette.paperInk, .night] {
            for textured in [true, false] {
                let d = Self.drawing(palette: palette, textured: textured)
                for ppu in [1.0, 2.0] {
                    // 奇数设备边长、非整数 CTM 与非零原点, 每种切法都重新栅格化 / 处理。
                    let args = (width: 303, height: 593, origin: CGPoint(x: 3.25, y: -5.75))
                    let whole = try Self.raster(d, width: args.width, height: args.height, ppu: ppu,
                                                origin: args.origin, transparent: true)
                    for cuts in [[1, 127, 257, 592], [73, 200, 371, 510]] {
                        let bands = try Self.raster(d, width: args.width, height: args.height, cuts: cuts, ppu: ppu,
                                                    origin: args.origin, transparent: true)
                        XCTAssertEqual(try Self.pixels(whole), try Self.pixels(bands), "ppu \(ppu), \(cuts), paper \(textured)")
                    }
                }
            }
        }
    }

    func testDeterministicAndOptIn() throws {
        let d = Self.drawing()
        let a = try Self.raster(d, width: 420, height: 820)
        let b = try Self.raster(d, width: 420, height: 820)
        XCTAssertEqual(try Self.pixels(a), try Self.pixels(b))
        let plain = Self.drawing(wash: false, tooth: false)
        let off = try Self.raster(plain, width: 420, height: 820)
        XCTAssertNotEqual(try Self.pixels(a), try Self.pixels(off))
        // tooth 只在显式干层上生效; 不改变任何几何。
        XCTAssertNil(d.layers[0].tooth)
        XCTAssertNil(d.layers[1].wash)
        XCTAssertEqual(d.shapeCount, plain.shapeCount)
    }

    func testLayerSplitPreservesBodyAndAllBristles() throws {
        let style = Brush.Style(width: 20, dry: 0.4, wet: 0.7)
        let stroke = Brush.stroke([SIMD3(0, 0, 1), SIMD3(100, 20, 1)], style: style, seed: 42)
        let hash = Set([stroke])
        let layers = ZXArt.layers(from: [stroke], styles: [style], wash: .init(), tooth: 0.3)
        let plain = ZXArt.shapes(from: stroke)
        XCTAssertEqual(layers.dry.shapes.count, plain.count)
        for (a, b) in zip(layers.dry.shapes, plain) {
            XCTAssertEqual(a.points, b.points)
            XCTAssertEqual(a.fill, b.fill)
            XCTAssertEqual(a.stroke, b.stroke)
            XCTAssertEqual(a.lineWidth, b.lineWidth)
        }
        XCTAssertEqual(layers.wet.shapes.count, 1)
        XCTAssertEqual(layers.wet.shapes[0].points, stroke.body)
        XCTAssertEqual(try XCTUnwrap(layers.wet.shapes[0].fill).alpha,
                       try XCTUnwrap(plain[0].fill).alpha * style.wet, accuracy: 1e-12)
        XCTAssertTrue(layers.wet.shapes.allSatisfy { $0.stroke == nil })
        XCTAssertTrue(hash.contains(stroke), "拆层不改变 Stroke Hashable")
        var zero = style; zero.wet = 0
        XCTAssertTrue(ZXArt.layers(from: [stroke], styles: [zero]).wet.shapes.isEmpty)
        XCTAssertTrue(ZXArt.layers(from: [], styles: []).dry.shapes.isEmpty)
    }

    func testToothUsesPaperAndLogicalFallback() {
        let s = ZXArt.PaperTexture.side
        var paper = ZXArt.PaperTexture(shade: [UInt8](repeating: 0, count: s * s), texel: 0.5)
        paper.shade[0] = 51 // shade × 5 = 1
        XCTAssertEqual(ZXArt.WashNoise.tooth(0.6, paper: paper, x: 0.1, y: 0.1), 0.4, accuracy: 1e-12)
        XCTAssertEqual(ZXArt.WashNoise.tooth(0.6, paper: paper, x: 0.6, y: 0.1), 1)
        XCTAssertEqual(ZXArt.WashNoise.tooth(0.6, paper: paper, x: -256 + 0.1, y: 256 + 0.1), 0.4, accuracy: 1e-12)
        XCTAssertEqual(ZXArt.WashNoise.tooth(nil, paper: paper, x: 0.1, y: 0.1), 1)
        let a = ZXArt.WashNoise.tooth(0.6, paper: nil, x: -17.5, y: 23.25)
        XCTAssertEqual(a, ZXArt.WashNoise.tooth(0.6, paper: nil, x: -17.5, y: 23.25))
        XCTAssertGreaterThanOrEqual(a, 0.4)
        XCTAssertLessThanOrEqual(a, 1)
    }

    func testNoiseAndDiskAreBoundedAndStateless() {
        for x in [-100.5, -0.01, 0, 17.25, 904.3] {
            for y in [-86.2, 0, 731.1] {
                let n = ZXArt.WashNoise.value(x, y, seed: 42)
                XCTAssertEqual(n, ZXArt.WashNoise.value(x, y, seed: 42))
                XCTAssertTrue((0...1).contains(n))
                let d = ZXArt.WashNoise.displacement(x, y, bleed: 4)
                XCTAssertLessThanOrEqual(abs(d.x), 4 * 0.38)
                XCTAssertLessThanOrEqual(abs(d.y), 4 * 0.38)
            }
        }
        let disk = ZXArt.WashNoise.disk
        XCTAssertEqual(disk.count, 12)
        for (i, p) in disk.enumerated() {
            XCTAssertLessThanOrEqual(p.x * p.x + p.y * p.y, 1)
            for q in disk.dropFirst(i + 1) {
                let delta = p - q
                XCTAssertGreaterThan(delta.x * delta.x + delta.y * delta.y, 0.38 * 0.38)
            }
        }
    }

    func testEffectOnlyLayersTinyCanvasAndEmptyLayer() throws {
        for wet in [true, false] {
            var d = Self.drawing(textured: false)
            d.layers = [d.layers[wet ? 0 : 1]]
            d.layers[0].opacity = 0.63
            let a = try Self.raster(d, width: 201, height: 391, transparent: true)
            let b = try Self.raster(d, width: 201, height: 391, cuts: [1, 129, 390], transparent: true)
            XCTAssertEqual(try Self.pixels(a), try Self.pixels(b))
            XCTAssertGreaterThan(try Self.pixels(a).filter { $0 > 0 }.count, 100)
            let tiny = try Self.raster(d, width: 1, height: 1)
            XCTAssertEqual(tiny.width, 1)
            XCTAssertEqual(tiny.height, 1)
        }
        let empty = ZXArt.Drawing(width: 1, height: 1, background: ZXArt.Palette.paperInk.paper,
                                  layers: [.init(wash: .init(), tooth: 0.5)])
        let pixels = try Self.pixels(Self.raster(empty, width: 1, height: 1, transparent: true))
        XCTAssertEqual([UInt8](pixels), [0, 0, 0, 0])
    }

    func testToothModulatesAlphaAndLayerOpacityOnce() throws {
        let palette = ZXArt.Palette.paperInk
        let square = ZXArt.Shape(points: [SIMD2(0, 0), SIMD2(16, 0), SIMD2(16, 16), SIMD2(0, 16)],
                                 fill: palette.ink.opacity(0.8), stroke: nil, lineWidth: 0, closed: true)
        let texture = ZXArt.PaperTexture(shade: [UInt8](repeating: 51, count: 512 * 512))
        let d = ZXArt.Drawing(width: 16, height: 16, background: palette.paper, paper: texture,
                              layers: [.init(blend: .multiply, opacity: 0.5, tooth: 0.5, shapes: [square])])
        let pixels = [UInt8](try Self.pixels(Self.raster(d, width: 16, height: 16, transparent: true)))
        let index = (8 * 16 + 8) * 4
        XCTAssertEqual(pixels[index + 3], 51, "0.8 × tooth 0.5 × layer opacity 0.5")
        XCTAssertEqual(Double(pixels[index]) / 51, palette.ink.red, accuracy: 1.0 / 51)
        XCTAssertEqual(Double(pixels[index + 1]) / 51, palette.ink.green, accuracy: 1.0 / 51)
        XCTAssertEqual(Double(pixels[index + 2]) / 51, palette.ink.blue, accuracy: 1.0 / 51)
    }

    func testWashComposesAfterMistOrFilterAndKeepsPartitions() throws {
        for filtered in [false, true] {
            var d = Self.drawing(textured: false)
            var layer = d.layers[0]
            layer.opacity = 0.63
            if filtered {
                let table = (0..<4096).map { Brush.random(42, UInt32($0)) }
                layer.filter = .init(passes: [.fade, .wispy], scale: 1, offsetX: -11, offsetY: 17, perlin: table)
            } else {
                let ridge = ZXArt.LayerMist.ridge(of: layer.shapes, step: 2)
                layer.mist = .init(depth: 150, blur: 2, ridge: ridge.ridge, ridgeX0: ridge.x0, ridgeStep: 2)
            }
            d.layers = [layer]
            let a = try Self.raster(d, width: 201, height: 391, transparent: true)
            let b = try Self.raster(d, width: 201, height: 391, cuts: [1, 129, 390], transparent: true)
            let bytes = [UInt8](try Self.pixels(a))
            XCTAssertEqual(try Self.pixels(a), try Self.pixels(b))
            let alphas = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
            XCTAssertGreaterThan(alphas.max() ?? 0, 0)
            XCTAssertLessThanOrEqual(alphas.max() ?? 0, 161, "layer opacity 只在最后应用")
        }
    }

    func testWashModelSheets() throws {
        for (name, palette) in [("paperink", ZXArt.Palette.paperInk), ("night", .night)] {
            for enabled in [false, true] {
                let d = Self.drawing(palette: palette, wash: enabled)
                let width = 840, height = 1640
                let image = try XCTUnwrap(ZXArt.render(d, pixelWidth: width, pixelHeight: height))
                let ctx = try XCTUnwrap(ZXArt.makeBitmap(width: width, height: height))
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                let font = CTFontCreateWithName("Menlo" as CFString, 14, nil)
                let color = CGColor(red: palette.ink.red, green: palette.ink.green, blue: palette.ink.blue, alpha: 1)
                var labels: [(String, Double, Double)] = [
                    ("wash \(enabled ? "ON" : "OFF") | dry: 0 / 0.4 / 0.8 | tooth 0.4", 12, 20),
                    ("large wet strokes: width 30 / 60 / 95; wet 0.85", 12, 585),
                    ("open ring: dry 0.55; wet 0.4", 12, 1400)]
                for (i, profile) in [Brush.Profile.brush, .tip, .nail, .press].enumerated() {
                    labels.append((profile.rawValue, 12, 42 + Double(i) * 130))
                }
                for (text, x, y) in labels {
                    let attributes: [NSAttributedString.Key: Any] = [
                        NSAttributedString.Key(kCTFontAttributeName as String): font,
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
                    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes) as CFAttributedString)
                    ctx.textPosition = CGPoint(x: x, y: Double(height) - y)
                    CTLineDraw(line, ctx)
                }
                let png = NSMutableData()
                let destination = try XCTUnwrap(CGImageDestinationCreateWithData(png as CFMutableData,
                    UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(destination, try XCTUnwrap(ctx.makeImage()), nil)
                XCTAssertTrue(CGImageDestinationFinalize(destination))
                let filename = "wash-model-sheet-\(name)-\(enabled ? "on" : "off").png"
                let attachment = XCTAttachment(data: png as Data, uniformTypeIdentifier: UTType.png.identifier)
                attachment.name = filename
                attachment.lifetime = .keepAlways
                add(attachment)
                if let directory = ProcessInfo.processInfo.environment["ZXART_WRITE_SHEETS"] {
                    let url = URL(fileURLWithPath: directory, isDirectory: true)
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    try (png as Data).write(to: url.appendingPathComponent(filename), options: .atomic)
                }
            }
        }
    }

    func testPortraitWithoutWashPerformanceBaseline() {
        let d = Self.drawing(wash: false)
        measure { XCTAssertNotNil(ZXArt.render(d, pixelWidth: 1206, pixelHeight: 2622)) }
    }

    func testPortraitWashPerformanceBaseline() {
        let d = Self.drawing()
        // 只记录竖幅湿墨基线, 不设耗时断言; A15 增量 ≤ 30% 留待设备验收。
        measure { XCTAssertNotNil(ZXArt.render(d, pixelWidth: 1206, pixelHeight: 2622)) }
    }
}
