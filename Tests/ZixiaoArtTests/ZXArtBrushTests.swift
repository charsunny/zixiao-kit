//  ZXArtBrushTests.swift — 笔触确定性、动画稳定性、跨平台金标与目视样张
//
//  Mac 生成 fixture: TEST_RUNNER_ZXART_WRITE_FIXTURES=brush-v1 xcodebuild test …
//      -only-testing:ZixiaoArtTests/ZXArtBrushTests/testBrushFixture
//  样张随 xcresult 附件保留; TEST_RUNNER_ZXART_WRITE_SHEETS=/tmp/zxart-brush 可同时写盘。

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ZixiaoArt

final class ZXArtBrushTests: XCTestCase {
    typealias Brush = ZXArt.Brush
    static let path: [SIMD3<Double>] = [SIMD3(10, 30, 0.8), SIMD3(65, 10, 1),
                                       SIMD3(120, 65, 0.6), SIMD3(210, 30, 1)]

    /// 几何逐点相等, 不通过光栅结果间接判断。
    func equal(_ a: Brush.Stroke, _ b: Brush.Stroke, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.body, b.body, file: file, line: line)
        XCTAssertEqual(a.bodyAlpha.start, b.bodyAlpha.start, file: file, line: line)
        XCTAssertEqual(a.bodyAlpha.end, b.bodyAlpha.end, file: file, line: line)
        XCTAssertEqual(a.bristles.count, b.bristles.count, file: file, line: line)
        for (x, y) in zip(a.bristles, b.bristles) {
            XCTAssertEqual(x.runs, y.runs, file: file, line: line)
            XCTAssertEqual(x.width, y.width, file: file, line: line)
            XCTAssertEqual(x.alpha, y.alpha, file: file, line: line)
        }
    }

    func testDeterminismAndSeeds() {
        for profile in Brush.Profile.allCases {
            let style = Brush.Style(width: 12, dry: 0.65, side: 0.8, profile: profile)
            let a = Brush.stroke(Self.path, style: style, seed: 42)
            equal(a, Brush.stroke(Self.path, style: style, seed: 42))
            XCTAssertNotEqual(a.body, Brush.stroke(Self.path, style: style, seed: 43).body)
        }
        let center = SIMD2<Double>(80, 50)
        equal(Brush.ring(center: center, radius: 30, squash: 0.3, style: .init(), seed: 42),
              Brush.ring(center: center, radius: 30, squash: 0.3, style: .init(), seed: 42))
        let blot = Brush.blot(center: center, radius: 8, squash: 0.6, angle: 0.4, seed: 42)
        XCTAssertEqual(blot, Brush.blot(center: center, radius: 8, squash: 0.6, angle: 0.4, seed: 42))
        XCTAssertNotEqual(blot, Brush.blot(center: center, radius: 8, squash: 0.6, angle: 0.4, seed: 43))
    }

    func testProgressIsAnExactPrefix() {
        for dry in [0.0, 0.4, 0.8, 1.0] {
            for profile in Brush.Profile.allCases {
                let style = Brush.Style(width: 10, dry: dry, gapLength: 240, profile: profile)
                let full = Brush.stroke(Self.path, style: style, seed: 42)
                equal(full, Brush.stroke(Self.path, style: style, seed: 42, progress: 1))
                for p in [0.0, 0.1, 0.5, 0.9, 1.0] {
                    let part = Brush.stroke(Self.path, style: style, seed: 42, progress: p)
                    if p == 0 {
                        XCTAssertTrue(part.body.isEmpty)
                        XCTAssertTrue(part.bristles.isEmpty)
                        continue
                    }
                    XCTAssertEqual(part.bristles.count, full.bristles.count)
                    for (a, b) in zip(part.bristles, full.bristles) {
                        XCTAssertEqual(a.width, b.width)
                        XCTAssertEqual(a.alpha, b.alpha)
                        XCTAssertLessThanOrEqual(a.runs.count, b.runs.count)
                        for (run, whole) in zip(a.runs, b.runs) {
                            XCTAssertLessThanOrEqual(run.count, whole.count)
                            XCTAssertEqual(run, Array(whole.prefix(run.count)))
                        }
                    }
                    if !part.body.isEmpty {
                        let n = part.body.count / 2, m = full.body.count / 2
                        XCTAssertEqual(Array(part.body.prefix(n)), Array(full.body.prefix(n)))
                        XCTAssertEqual(Array(part.body.suffix(n)), Array(full.body.suffix(m).suffix(n)))
                    }
                }
            }
        }
    }

    func testFixedGapLengthKeepsNormalizedBreaks() {
        // 直笔只改长度、不改宽度, x / length 就是归一化弧长。
        let style = Brush.Style(width: 9, dry: 0.8, gapLength: 200, profile: .even)
        let a = Brush.stroke([SIMD3(0, 0, 1), SIMD3(200, 0, 1)], style: style, seed: 73)
        let b = Brush.stroke([SIMD3(0, 0, 1), SIMD3(240, 0, 1)], style: style, seed: 73)
        var fragments = 0
        for (x, y) in zip(a.bristles, b.bristles) {
            XCTAssertEqual(x.runs.count, y.runs.count)
            fragments += x.runs.count
            for (r, s) in zip(x.runs, y.runs) {
                XCTAssertEqual(r.count, s.count)
                for (p, q) in zip(r, s) { XCTAssertEqual(p.x / 200, q.x / 240, accuracy: 1e-6) }
            }
        }
        XCTAssertGreaterThan(fragments, a.bristles.count, "用例必须确实覆盖断墨")
        // 墨圈半径 r → 1.2r; 同比缩放线宽以便直接比较所有点的归一化坐标。
        var ringStyle = style
        ringStyle.width = 2
        ringStyle.bristles = 4
        let r = Brush.ring(center: .zero, radius: 80, squash: 0.3, style: ringStyle, seed: 73)
        let grown = Brush.ring(center: .zero, radius: 96, squash: 0.3, style: ringStyle, seed: 73)
        XCTAssertEqual(r.bristles.count, grown.bristles.count)
        for (x, y) in zip(r.bristles, grown.bristles) {
            XCTAssertEqual(x.runs.map(\.count), y.runs.map(\.count))
        }
        ringStyle.width *= 1.2
        let s = Brush.ring(center: .zero, radius: 96, squash: 0.3, style: ringStyle, seed: 73)
        XCTAssertEqual(r.bristles.count, s.bristles.count)
        for (x, y) in zip(r.bristles, s.bristles) {
            // 显式给笔毫数, 避免宽度自动推导造成根数变化。
            XCTAssertEqual(x.runs.count, y.runs.count)
            for (u, v) in zip(x.runs, y.runs) {
                XCTAssertEqual(u.count, v.count)
                for (p, q) in zip(u, v) {
                    XCTAssertEqual(p.x / 80, q.x / 96, accuracy: 1e-6)
                    XCTAssertEqual(p.y / 80, q.y / 96, accuracy: 1e-6)
                }
            }
        }
    }

    func testDryBoundariesAndSide() {
        let wet = Brush.stroke(Self.path, style: .init(width: 12, dry: 0), seed: 42)
        XCTAssertGreaterThan(wet.bodyAlpha.start, 0)
        for hair in wet.bristles { XCTAssertEqual(hair.runs.count, 1) }
        let dry = Brush.stroke(Self.path, style: .init(width: 12, dry: 1), seed: 42)
        XCTAssertEqual(dry.bodyAlpha.start, 0)
        XCTAssertEqual(dry.bodyAlpha.end, 0)
        XCTAssertTrue(dry.bristles.contains { !$0.runs.isEmpty })
        let a = Brush.stroke(Self.path, style: .init(width: 12, side: 0), seed: 42)
        let b = Brush.stroke(Self.path, style: .init(width: 12, side: 0.8), seed: 42)
        XCTAssertEqual(a.body, b.body)
        for (x, y) in zip(a.bristles, b.bristles) {
            XCTAssertEqual(x.runs, y.runs)
            XCTAssertTrue(y.alpha == x.alpha || abs(y.alpha - x.alpha * 0.2) < 1e-6)
        }
        XCTAssertTrue(zip(a.bristles, b.bristles).contains { pair in pair.0.alpha > pair.1.alpha })
        var style = Brush.Style(width: 12)
        let before = Brush.stroke(Self.path, style: style, seed: 42)
        style.wet = 1
        equal(before, Brush.stroke(Self.path, style: style, seed: 42))
    }

    /// 左右墨边的中点复原中心线, 排除宽度对缺口角度与压扁比的影响。
    func testRingGapAndSquash() {
        for sweep in [1.86 * Double.pi, 1.5 * Double.pi] {
            for seed in [UInt32(0), 42, UInt32.max] {
                let center = SIMD2<Double>(100, 90), radius = 80.0, squash = 0.3
                let stroke = Brush.ring(center: center, radius: radius, squash: squash,
                                        style: .init(width: 2), seed: seed, sweep: sweep)
                let n = stroke.body.count / 2
                XCTAssertGreaterThan(n, 2)
                let line = (0..<n).map { i -> SIMD2<Double> in
                    let p = (stroke.body[i] + stroke.body[2 * n - 1 - i]) * 0.5
                    return SIMD2(Double(p.x) - center.x, Double(p.y) - center.y)
                }
                guard let first = line.first, let last = line.last else { return XCTFail("墨圈为空") }
                func angle(_ p: SIMD2<Double>) -> Double { atan2(p.y / squash, p.x) }
                var gap = angle(first) - angle(last)
                while gap < 0 { gap += 2 * .pi }
                XCTAssertEqual(gap, 2 * .pi - sweep, accuracy: 1e-4)
                let xs = line.map(\.x), ys = line.map(\.y)
                let ratio = (ys.max()! - ys.min()!) / (xs.max()! - xs.min()!)
                // 1.5π 的开口会截掉椭圆极值, 只在缺口较小的默认圈上量包围盒。
                if sweep > 1.8 * .pi { XCTAssertEqual(ratio, squash, accuracy: 0.015) }
                for p in line {
                    XCTAssertEqual(p.x * p.x / (radius * radius) + p.y * p.y / (radius * radius * squash * squash),
                                   1, accuracy: 0.002)
                }
            }
        }
    }

    func testShapeConversion() throws {
        let stroke = Brush.stroke(Self.path, style: .init(width: 12, tone: 0.6, dry: 0.4), seed: 42)
        for palette in [ZXArt.Palette.paperInk, .night] {
            let shapes = ZXArt.shapes(from: stroke, palette: palette)
            XCTAssertEqual(shapes.count, 1 + stroke.bristles.reduce(0) { $0 + $1.runs.count })
            let body = try XCTUnwrap(shapes.first)
            XCTAssertTrue(body.closed)
            XCTAssertNil(body.stroke)
            XCTAssertEqual(body.lineWidth, 0)
            let fill = try XCTUnwrap(body.fill)
            XCTAssertEqual(fill.red, palette.ink.red)
            XCTAssertEqual(fill.green, palette.ink.green)
            XCTAssertEqual(fill.blue, palette.ink.blue)
            XCTAssertEqual(fill.alpha, Double(stroke.bodyAlpha.start + stroke.bodyAlpha.end) * 0.5)
            var index = 1
            for hair in stroke.bristles {
                for run in hair.runs {
                    let shape = shapes[index]
                    XCTAssertEqual(shape.points, run)
                    XCTAssertNil(shape.fill)
                    XCTAssertFalse(shape.closed)
                    XCTAssertEqual(shape.lineWidth, hair.width)
                    XCTAssertEqual(shape.stroke?.alpha, Double(hair.alpha))
                    index += 1
                }
            }
        }
    }

    func testDegenerateInputsAndSampleCap() {
        let paths: [[SIMD3<Double>]] = [[], [SIMD3(0, 0, 1)], [SIMD3(1, 1, 1), SIMD3(1, 1, 1)],
                                       [SIMD3(.nan, 0, 1), SIMD3(1, 1, 1)]]
        for path in paths {
            let s = Brush.stroke(path, style: .init(), seed: 0)
            XCTAssertTrue(s.body.isEmpty)
            XCTAssertTrue(s.bristles.isEmpty)
        }
        let long = Brush.stroke([SIMD3(0, 0, 1), SIMD3(100_000, 0, 1)],
                                style: .init(width: 0.5, dry: 0), seed: 0)
        XCTAssertEqual(long.body.count, 1200)
        for hair in long.bristles { XCTAssertLessThanOrEqual(hair.runs.flatMap { $0 }.count, 600) }
        XCTAssertTrue(Brush.stroke(Self.path, style: .init(width: 0), seed: 0).body.isEmpty)
        XCTAssertTrue(Brush.stroke(Self.path, style: .init(), seed: 0, progress: .nan).body.isEmpty)
        equal(Brush.stroke(Self.path, style: .init(), seed: 0),
              Brush.stroke(Self.path, style: .init(), seed: 0, progress: 2))
    }

    // MARK: - 跨平台 fixture (Mac 首次生成, VPS 不伪造金标)

    static let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/zxart/brush-v1.json")

    static func points(_ ps: [SIMD2<Float>]) -> [[Double]] { ps.map { [Double($0.x), Double($0.y)] } }
    static func record(_ stroke: Brush.Stroke) -> [String: Any] {
        ["body": points(stroke.body), "bodyAlpha": [Double(stroke.bodyAlpha.start), Double(stroke.bodyAlpha.end)],
         "bristles": stroke.bristles.map { ["width": Double($0.width), "alpha": Double($0.alpha),
                                           "runs": $0.runs.map(points)] as [String: Any] }]
    }

    static func fixture() -> [String: Any] {
        var cases: [[String: Any]] = []
        for (i, profile) in Brush.Profile.allCases.enumerated() {
            for dry in [0.0, 0.4, 0.8, 1.0] {
                let style = Brush.Style(width: 8, tone: 0.82, dry: dry, side: 0.8, bristles: 8,
                                        rough: 0.2, gapLength: 240, profile: profile)
                let seed = UInt32(i) &* 0x9E3779B9
                let input: [String: Any] = ["centerline": path.map { [$0.x, $0.y, $0.z] }, "seed": seed,
                    "style": ["width": 8, "tone": 0.82, "dry": dry, "wet": 0, "side": 0.8, "bristles": 8,
                              "rough": 0.2, "fade": NSNull(), "gapLength": 240, "profile": profile.rawValue]]
                for p in [0.5, 1.0] {
                    cases.append(["kind": "stroke", "input": input, "progress": p,
                                  "output": record(Brush.stroke(path, style: style, seed: seed, progress: p))])
                }
            }
        }
        for seed in [UInt32(0), 42, UInt32.max] {
            cases.append(["kind": "ring", "input": ["center": [0, 0], "radius": 80, "squash": 0.3,
                "seed": seed, "sweep": 1.86 * Double.pi,
                "style": ["width": 2, "tone": 0.82, "dry": 0.55, "wet": 0, "side": 0, "bristles": NSNull(),
                          "rough": 0.2, "fade": NSNull(), "gapLength": 240, "profile": "brush"]],
                "output": record(Brush.ring(center: .zero, radius: 80, squash: 0.3,
                                           style: .init(width: 2, dry: 0.55, gapLength: 240), seed: seed))])
            cases.append(["kind": "blot", "input": ["center": [10, 20], "radius": 8, "squash": 0.6,
                "angle": 0.4, "seed": seed],
                "output": points(Brush.blot(center: SIMD2(10, 20), radius: 8, squash: 0.6, angle: 0.4, seed: seed))])
        }
        let hashes = [UInt32(0), 42, UInt32.max].map { seed in
            ["seed": seed, "values": (0..<8).map { Brush.hash(seed, UInt32($0)) }] as [String: Any]
        }
        let noise = [-1.5, 0, 0.125, 1, 3.75, 240].map { ["x": $0, "value": Brush.noise(42, $0)] }
        return ["version": 1, "note": "Swift Brush v1. UInt32 hashes exact; floating-point tolerance 1e-9 relative/absolute, as ZXArtParityTests. Geometry and alpha are Float32 (JS must use Math.fround). Coordinates in logical units; runs are open; body is closed without a repeated endpoint.",
                "hashes": hashes, "noise": noise, "cases": cases]
    }

    func testBrushFixture() throws {
        let flag = ProcessInfo.processInfo.environment["ZXART_WRITE_FIXTURES"]
        if flag == "1" || flag == "brush-v1" {
            let data = try JSONSerialization.data(withJSONObject: Self.fixture(), options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(at: Self.fixtureURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: Self.fixtureURL, options: .atomic)
            print("wrote \(Self.fixtureURL.path)")
            return
        }
        guard FileManager.default.fileExists(atPath: Self.fixtureURL.path) else {
            throw XCTSkip("缺少 Fixtures/zxart/brush-v1.json; 请在 Mac 用 TEST_RUNNER_ZXART_WRITE_FIXTURES=brush-v1 仅运行 testBrushFixture 生成并提交金标。")
        }
        let want = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.fixtureURL))
        let got = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: Self.fixture()))
        compare(got, want, path: "brush-v1")
    }

    func compare(_ got: Any, _ want: Any, path: String) {
        if let a = got as? [String: Any], let b = want as? [String: Any] {
            XCTAssertEqual(Set(a.keys), Set(b.keys), path)
            for key in a.keys.sorted() { if let w = b[key] { compare(a[key]!, w, path: path + "." + key) } }
        } else if let a = got as? [Any], let b = want as? [Any] {
            XCTAssertEqual(a.count, b.count, path)
            for (i, pair) in zip(a, b).enumerated() { compare(pair.0, pair.1, path: path + "[\(i)]") }
        } else if let a = got as? NSNumber, let b = want as? NSNumber {
            let exact = path.contains("hashes") || !path.contains("output") && !path.contains("noise")
            let tolerance = exact ? 0 : 1e-9
            XCTAssertEqual(a.doubleValue, b.doubleValue,
                           accuracy: tolerance * max(1, abs(a.doubleValue), abs(b.doubleValue)), path)
        } else if got is NSNull, want is NSNull { return }
        else if let a = got as? String, let b = want as? String { XCTAssertEqual(a, b, path) }
        else { XCTFail("\(path): fixture 字段类型不一致") }
    }

    // MARK: - 目视样张

    func testModelSheet() throws {
        let width = 1620, height = 1430
        for (name, palette) in [("paperink", ZXArt.Palette.paperInk), ("night", .night)] {
            var shapes: [ZXArt.Shape] = [], labels: [(String, Double, Double)] = []
            for (column, pair) in [(0.0, 0.0), (0.0, 0.8), (0.4, 0.0), (0.4, 0.8), (0.8, 0.0), (0.8, 0.8)].enumerated() {
                let x = 120.0 + Double(column) * 245
                labels.append(("dry \(pair.0) / side \(pair.1)", x, 30))
                for (row, profile) in Brush.Profile.allCases.enumerated() {
                    let y = 90.0 + Double(row) * 110
                    if column == 0 { labels.append((profile.rawValue, 12, y)) }
                    let path: [SIMD3<Double>] = [SIMD3(x, y, 1), SIMD3(x + 55, y - 12, 1),
                                               SIMD3(x + 130, y + 14, 1), SIMD3(x + 210, y, 1)]
                    let style = Brush.Style(width: 20, dry: pair.0, side: pair.1, profile: profile)
                    shapes += ZXArt.shapes(from: Brush.stroke(path, style: style, seed: 42), palette: palette)
                }
            }
            labels.append(("rings: seeds 1 / 42 / 73; blots: squash 1 / 0.6 / 0.3", 12, 1200))
            for (i, seed) in [UInt32(1), 42, 73].enumerated() {
                let center = SIMD2<Double>(240 + Double(i) * 430, 1280)
                shapes += ZXArt.shapes(from: Brush.ring(center: center, radius: 110, squash: 0.3,
                    style: .init(width: 4, dry: 0.55, side: 0.8, gapLength: 500), seed: seed), palette: palette)
                for (j, squash) in [1.0, 0.6, 0.3].enumerated() {
                    let p = center + SIMD2<Double>(Double(j - 1) * 48, 95)
                    shapes.append(.init(points: Brush.blot(center: p, radius: 12, squash: squash, angle: -0.3, seed: seed),
                                        fill: palette.ink, stroke: nil, lineWidth: 0, closed: true))
                }
            }
            let drawing = ZXArt.Drawing(width: Double(width), height: Double(height), background: palette.paper,
                                         layers: [.init(blend: palette.isDark ? .normal : .multiply, shapes: shapes)])
            let image = try XCTUnwrap(ZXArt.render(drawing, pixelWidth: width, pixelHeight: height))
            let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let font = CTFontCreateWithName("Menlo" as CFString, 15, nil)
            let color = CGColor(red: palette.ink.red, green: palette.ink.green, blue: palette.ink.blue, alpha: 1)
            for (text, x, y) in labels {
                let attributes: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes) as CFAttributedString)
                ctx.textPosition = CGPoint(x: x, y: Double(height) - y)
                CTLineDraw(line, ctx)
            }
            let png = NSMutableData()
            let dest = try XCTUnwrap(CGImageDestinationCreateWithData(png as CFMutableData, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), nil)
            XCTAssertTrue(CGImageDestinationFinalize(dest))
            let filename = "brush-v1-model-sheet-\(name).png"
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
