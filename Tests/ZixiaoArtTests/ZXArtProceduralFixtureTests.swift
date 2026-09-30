//  ZXArtProceduralFixtureTests.swift — @1 构图的冻结指纹 + 跨平台 (web JS 移植) 对拍金标
//
//  Fixtures/zxart/procedural-v1.json: 每个配方 (generator, seed, variant, params, 像素尺寸) 记录
//  - engine: 生成器原始输出 (山水 = 构图各部分的多边形, 逻辑单位; 花 = 原作 1200² 画布的多边形)
//    的多边形数 / 点数 / x、y 坐标和, 以及生成结束时的 PRNG 状态 (整数) —— 证明取随机数的次数与顺序一致;
//  - drawing: 映射到调色板、丢掉不可见多边形之后的图层 (类型 / 形状数 / 点数 / 坐标和, 逻辑单位)。
//  这些数只取决于几何, 与光栅化无关。@1 的任何构图改动都会让本测试失败 —— 那就说明要开 @2。
//
//  重新生成 (只在有意开新版本时):
//      TEST_RUNNER_ZXART_WRITE_FIXTURES=1 xcodebuild test … -only-testing:ZixiaoArtTests/ZXArtProceduralFixtureTests

import CoreGraphics
import Foundation
import XCTest
@testable import ZixiaoArt
import ZixiaoDesign

final class ZXArtProceduralFixtureTests: XCTestCase {
    struct Case {
        var generator: String, seed: String, variant: String
        var density: Double?, hue: Double?, quietTop: Double?
        var width: Int, height: Int
    }

    static let cases: [Case] = [
        Case(generator: "shanshui@1", seed: "秋分-1", variant: "江岸", width: 1206, height: 2622),
        Case(generator: "shanshui@1", seed: "a", variant: "远山", density: 1.4, width: 1062, height: 498),
        Case(generator: "shanshui@1", seed: "2026", variant: "高山", quietTop: 0.4, width: 510, height: 510),
        Case(generator: "nonflowers@1", seed: "42", variant: "梅", width: 1206, height: 2622),
        Case(generator: "nonflowers@1", seed: "秋分-1", variant: "荷", hue: 200, width: 1012, height: 476),
        Case(generator: "nonflowers@1", seed: "2026", variant: "菊", density: 0.7, width: 1206, height: 2622),
        Case(generator: "nonflowers@1", seed: "a", variant: "兰", width: 1062, height: 1116),
        Case(generator: "nonflowers@1", seed: "1", variant: "自然", width: 1206, height: 2622),
    ]

    static let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/zxart/procedural-v1.json")

    static func record(_ c: Case) throws -> [String: Any] {
        var params: [String: Any] = [:]
        if let v = c.density { params["density"] = v }
        if let v = c.hue { params["hue"] = v }
        if let v = c.quietTop { params["quiet_top"] = v }
        let p = ZXArt.Procedural(generator: c.generator, seed: c.seed, variant: c.variant,
                                 params: .init(density: c.density, hue: c.hue, quietTop: c.quietTop))
        let (d, t) = try XCTUnwrap(ZXArt.traced(procedural: p, palette: .paperInk,
                                                pixelSize: CGSize(width: c.width, height: c.height)))
        var layers: [[String: Any]] = []
        for l in d.layers {
            var np = 0, sx = 0.0, sy = 0.0
            for sh in l.shapes { for v in sh.points { np += 1; sx += Double(v.x); sy += Double(v.y) } }
            layers.append(["kind": l.mist != nil ? "mist" : (l.filter != nil ? "filter" : "plain"),
                           "shapes": l.shapes.count, "points": np, "sumX": sx, "sumY": sy])
        }
        var engine: [String: Any] = ["polys": t.polys, "points": t.points, "sumX": t.sumX, "sumY": t.sumY,
                                     "prngAfter": t.prngAfter]
        if !t.transform.isEmpty { engine["transform"] = t.transform }
        return ["generator": c.generator, "seed": c.seed, "variant": c.variant, "params": params,
                "pixelSize": [c.width, c.height], "palette": "paperInk (#F2EEE4 / #272E2A)",
                "logical": [d.width, d.height], "engine": engine, "drawing": ["layers": layers]]
    }

    func testProceduralV1Fingerprints() throws {
        let records = try Self.cases.map(Self.record)
        if ProcessInfo.processInfo.environment["ZXART_WRITE_FIXTURES"] == "1" {
            let doc: [String: Any] = [
                "note": "ZixiaoArt @1 cross-platform fixtures. engine = raw generator polygons (shanshui: composition parts in logical units; nonflowers: original 1200x1200 canvas, before transform [k, tx, ty]); drawing = after palette mapping, dropping polygons with < 2 points / no visible fill+stroke / non-finite points, points stored as Float32. Counts must match exactly; sums to ~1e-6 relative (drawing sums are over Float32-rounded points). prngAfter = PRNG integer state right after generation (before shanshui's background paper).",
                "cases": records,
            ]
            let data = try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: Self.fixtureURL)
            print("wrote \(Self.fixtureURL.path)")
            return
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "procedural-v1", withExtension: "json", subdirectory: "Fixtures/zxart"))
        let doc = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let want = try XCTUnwrap(doc["cases"] as? [[String: Any]])
        XCTAssertEqual(want.count, records.count)
        func close(_ a: Any?, _ b: Any?, _ label: String) {
            let x = (a as? NSNumber)?.doubleValue ?? .nan, y = (b as? NSNumber)?.doubleValue ?? .nan
            XCTAssertTrue(abs(x - y) <= 1e-9 * max(1, abs(x), abs(y)), "\(label): \(x) vs \(y)")
        }
        for (got, w) in zip(records, want) {
            let label = "\(got["generator"]!) \(got["seed"]!) \(got["variant"]!)"
            let ge = got["engine"] as! [String: Any], we = try XCTUnwrap(w["engine"] as? [String: Any])
            XCTAssertEqual(ge["polys"] as? Int, we["polys"] as? Int, "\(label) engine polys — @1 composition changed? bump to @2")
            XCTAssertEqual(ge["points"] as? Int, we["points"] as? Int, "\(label) engine points")
            close(ge["prngAfter"], we["prngAfter"], "\(label) engine PRNG state")
            close(ge["sumX"], we["sumX"], "\(label) engine Σx")
            close(ge["sumY"], we["sumY"], "\(label) engine Σy")
            let gl = (got["drawing"] as! [String: Any])["layers"] as! [[String: Any]]
            let wl = try XCTUnwrap((w["drawing"] as? [String: Any])?["layers"] as? [[String: Any]])
            XCTAssertEqual(gl.count, wl.count, "\(label) layer count")
            for (i, (a, b)) in zip(gl, wl).enumerated() {
                XCTAssertEqual(a["kind"] as? String, b["kind"] as? String, "\(label) layer \(i) kind")
                XCTAssertEqual(a["shapes"] as? Int, b["shapes"] as? Int, "\(label) layer \(i) shapes")
                XCTAssertEqual(a["points"] as? Int, b["points"] as? Int, "\(label) layer \(i) points")
                close(a["sumX"], b["sumX"], "\(label) layer \(i) Σx")
                close(a["sumY"], b["sumY"], "\(label) layer \(i) Σy")
            }
        }
    }
}
