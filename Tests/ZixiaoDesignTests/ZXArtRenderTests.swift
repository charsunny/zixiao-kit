//  ZXArtRenderTests.swift — 出图 + 计时
//
//  生成 PNG 到 /tmp/zxart-shots/ (模拟器进程能直接写宿主 /tmp), 并打印每张图的生成 / 渲染
//  用时 (3 次取中位数)。计时断言只在 Release (-O) 构建里生效: Debug 下 Swift 比 -O 慢一个量级,
//  只记录不判定。环境变量 ZXART_SHOTS=0 可跳过写图。

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ZixiaoDesign

final class ZXArtRenderTests: XCTestCase {
    static let outDir = URL(fileURLWithPath: "/tmp/zxart-shots", isDirectory: true)
    static let reps = 3

    #if DEBUG
    static let optimized = false
    #else
    static let optimized = true
    #endif

    struct Timing { var name: String; var gen: Double; var render: Double; var shapes: Int; var points: Int }

    static func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    static func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }

    static func writePNG(_ img: CGImage, _ name: String) {
        if ProcessInfo.processInfo.environment["ZXART_SHOTS"] == "0" { return }
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent(name)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }

    static func log(_ rows: [Timing], _ title: String) {
        var s = "\n== \(title) (\(optimized ? "Release -O" : "Debug -Onone"), median of \(reps)) ==\n"
        s += "name | gen ms | render ms | total ms | shapes | points\n"
        for r in rows {
            s += String(format: "%@ | %.1f | %.1f | %.1f | %d | %d\n", r.name, r.gen, r.render, r.gen + r.render, r.shapes, r.points)
        }
        print(s)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent("timings-\(optimized ? "release" : "debug").txt")
        let prev = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (prev + s).write(to: url, atomically: true, encoding: .utf8)
    }

    /// 生成 + 渲染, 各计 `reps` 次取中位数; 返回最后一张图。
    static func timed(_ name: String, gen: () -> ZXArt.Drawing, size: CGSize, scale: CGFloat) -> (Timing, CGImage?) {
        let clock = ContinuousClock()
        var gens: [Double] = [], rens: [Double] = []
        var img: CGImage?
        var drawing: ZXArt.Drawing?
        for _ in 0..<reps {
            var d: ZXArt.Drawing?
            gens.append(ms(clock.measure { d = gen() }))
            drawing = d
            rens.append(ms(clock.measure { img = ZXArt.render(d!, size: size, scale: scale) }))
        }
        return (Timing(name: name, gen: median(gens), render: median(rens),
                       shapes: drawing?.shapeCount ?? 0, points: drawing?.pointCount ?? 0), img)
    }

    func testShanShuiPhoneFrames() throws {
        let size = CGSize(width: 402, height: 874)  // 1206 × 2622 @3x
        var rows: [Timing] = []
        let palettes: [(String, ZXArt.Palette)] = [("paperink", .paperInk), ("night", .night)]
        for seed in [1, 42, 2026] {
            for (pname, pal) in palettes {
                let params = ZXArt.ShanShui.Params(palette: pal, density: 0.5, variant: .alpine)
                let (t, img) = Self.timed("shanshui-\(seed)-\(pname)", gen: {
                    ZXArt.ShanShui.generate(seed: ZXArt.Seed(seed), size: size, params: params)
                }, size: size, scale: 3)
                let image = try XCTUnwrap(img)
                XCTAssertEqual(image.width, 1206)
                XCTAssertEqual(image.height, 2622)
                Self.writePNG(image, "shanshui-\(seed)-\(pname).png")
                rows.append(t)
                if Self.optimized { XCTAssertLessThan(t.gen + t.render, 500, "\(t.name) over the 500 ms budget") }
            }
        }
        Self.log(rows, "ShanShui 1206×2622 (alpine)")
    }

    func testShanShuiVariantsAndDeterminism() throws {
        let size = CGSize(width: 402, height: 874)
        for variant in ZXArt.ShanShui.Variant.allCases {
            let params = ZXArt.ShanShui.Params(variant: variant)
            let a = ZXArt.ShanShui.generate(seed: 42, size: size, params: params)
            let b = ZXArt.ShanShui.generate(seed: 42, size: size, params: params)
            XCTAssertEqual(a.shapeCount, b.shapeCount)
            XCTAssertEqual(a.pointCount, b.pointCount)
            XCTAssertEqual(a.layers[0].shapes.first?.points, b.layers[0].shapes.first?.points)
            XCTAssertEqual(a.layers[0].shapes.last?.points, b.layers[0].shapes.last?.points)
            let img = try XCTUnwrap(ZXArt.render(a, size: size, scale: 3))
            Self.writePNG(img, "shanshui-42-\(variant).png")
            // 留白区: 上 32% 不应有山 (允许极淡的远山边缘伸入 1%)
            if let q = a.quietRect {
                let intrusions = a.layers[0].shapes.filter { $0.points.contains { Double($0.y) < q.height * 0.97 } }
                XCTAssertLessThan(intrusions.count, 3, "\(variant): shapes inside the quiet zone")
            }
        }
        let night = ZXArt.ShanShui.generate(seed: 2026, size: size, params: .init(palette: .night, variant: .riverbank))
        Self.writePNG(try XCTUnwrap(ZXArt.render(night, size: size, scale: 3)), "shanshui-2026-riverbank-night.png")
    }

    func testShanShuiOriginalSceneRenders() throws {
        let d = ZXArt.ShanShui.originalScene(seed: 42)
        let img = try XCTUnwrap(ZXArt.render(d, size: CGSize(width: d.width, height: d.height), scale: 1))
        Self.writePNG(img, "shanshui-42-original-scroll.png")
    }

    func testFlowersWidgetAndPortrait() throws {
        let widget = CGSize(width: 1012.0 / 3, height: 476.0 / 3)
        let phone = CGSize(width: 402, height: 874)
        var rows: [Timing] = []
        for seed in [1, 42, 2026] {
            for (tag, size) in [("widget", widget), ("portrait", phone)] {
                let (t, img) = Self.timed("flowers-\(seed)-\(tag)", gen: {
                    ZXArt.Flowers.generate(seed: ZXArt.Seed(seed), size: size, params: .init())
                }, size: size, scale: 3)
                let image = try XCTUnwrap(img)
                XCTAssertEqual(image.width, tag == "widget" ? 1012 : 1206)
                XCTAssertEqual(image.height, tag == "widget" ? 476 : 2622)
                Self.writePNG(image, "flowers-\(seed)-\(tag).png")
                rows.append(t)
                if Self.optimized { XCTAssertLessThan(t.gen + t.render, 1500, "\(t.name) over the 1.5 s budget") }
            }
        }
        Self.log(rows, "Flowers (season: none = original parameter space)")
    }

    func testFlowerSeasonsAndNight() throws {
        let phone = CGSize(width: 402, height: 874)
        let widget = CGSize(width: 1012.0 / 3, height: 476.0 / 3)
        var rows: [Timing] = []
        for season in ZXArt.Flowers.Season.allCases where season != .none {
            for (tag, size) in [("portrait", phone), ("widget", widget)] {
                let (t, img) = Self.timed("flowers-42-\(season)-\(tag)", gen: {
                    ZXArt.Flowers.generate(seed: 42, size: size, params: .init(season: season))
                }, size: size, scale: 3)
                Self.writePNG(try XCTUnwrap(img), "flowers-42-\(season)-\(tag).png")
                rows.append(t)
            }
        }
        let night = ZXArt.Flowers.generate(seed: 7, size: widget, params: .init(palette: .night, season: .plum))
        Self.writePNG(try XCTUnwrap(ZXArt.render(night, size: widget, scale: 3)), "flowers-7-plum-widget-night.png")
        Self.log(rows, "Flowers seasons")
    }

    func testDrawingIsSendableAndRendersOffMain() async throws {
        let size = CGSize(width: 1012.0 / 3, height: 476.0 / 3)
        let d = await Task.detached { ZXArt.Flowers.generate(seed: 3, size: size, params: .init(season: .orchid)) }.value
        let w = await Task.detached { ZXArt.render(d, size: size, scale: 3)?.width }.value
        XCTAssertEqual(w, 1012)
    }
}

extension ZXArtRenderTests {
    /// 花卉渲染耗时拆分: 矢量填描 vs 逐像素滤镜 (滤镜层去掉 filter 再渲一次求差)。
    func testFlowerRenderBreakdown() throws {
        let phone = CGSize(width: 402, height: 874)
        var rows: [Timing] = []
        for (name, params) in [("plum-portrait", ZXArt.Flowers.Params(season: .plum)), ("1-portrait", .init())] {
            let seed: ZXArt.Seed = name.hasPrefix("1") ? 1 : 42
            let d = ZXArt.Flowers.generate(seed: seed, size: phone, params: params)
            var noFilter = d
            noFilter.layers = d.layers.map { var l = $0; l.filter = nil; return l }
            var noPaper = noFilter
            noPaper.paper = nil
            let clock = ContinuousClock()
            func med(_ x: ZXArt.Drawing) -> Double {
                Self.median((0..<Self.reps).map { _ in Self.ms(clock.measure { _ = ZXArt.render(x, size: phone, scale: 3) }) })
            }
            let full = med(d), vec = med(noFilter), bare = med(noPaper)
            rows.append(Timing(name: "\(name) full", gen: 0, render: full, shapes: d.shapeCount, points: d.pointCount))
            rows.append(Timing(name: "\(name) vector+paper (no filter)", gen: 0, render: vec, shapes: d.shapeCount, points: d.pointCount))
            rows.append(Timing(name: "\(name) vector only", gen: 0, render: bare, shapes: d.shapeCount, points: d.pointCount))
        }
        Self.log(rows, "Flowers render breakdown")
    }
}
