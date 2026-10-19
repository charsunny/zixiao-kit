//  ZXArtProceduralFixtureTests.swift — @1 构图的冻结指纹 + 跨平台 (web JS 移植) 对拍金标
//
//  Fixtures/zxart/procedural-v1.json: 每个配方 (generator, seed, variant, params, 像素尺寸) 记录
//  - engine: 生成器原始输出 (山水 = 构图各部分的多边形, 逻辑单位; 花 = 原作 1200² 画布的多边形)
//    的多边形数 / 点数 / x、y 坐标和, 以及生成结束时的 PRNG 状态 (整数) —— 证明取随机数的次数与顺序一致;
//  - drawing: 映射到调色板、丢掉不可见多边形之后的图层 (类型 / 形状数 / 点数 / 坐标和, 逻辑单位)。
//  这些数只取决于几何, 与光栅化无关。@1 的任何构图改动都会让本测试失败 —— 那就说明要开 @2。
//
//  Fixtures/zxart/procedural-v2.json: 同样的指纹给 @2 (shanshui@2 / nonflowers@2, 带 verse_side 等参数), 另记
//  诗句框 verseRect (单位坐标)。@2 定稿后同样冻结。
//
//  重新生成 (只在有意开新版本时; 只写还没有的版本请用 ZXART_WRITE_FIXTURES=v2):
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
        var verseSide: String? = nil, verseColumns: Int? = nil, verseChars: Int? = nil
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

    /// @2: 各版式 × 三种诗句边 × 两个生成器; 密度覆盖到各分支 (次峰数、矮山、近岸、远山层数)。
    static let casesV2: [Case] = [
        Case(generator: "shanshui@2", seed: "秋分-1", variant: "江岸", width: 1206, height: 2622,
             verseSide: "right", verseColumns: 4, verseChars: 7),
        Case(generator: "shanshui@2", seed: "a", variant: "远山", density: 1.4, width: 1206, height: 2622, verseSide: "left"),
        Case(generator: "shanshui@2", seed: "2026", variant: "高山", density: 1.5, width: 1062, height: 1116,
             verseSide: "right", verseColumns: 2, verseChars: 5),
        Case(generator: "shanshui@2", seed: "枫桥", variant: "江岸", density: 1.2, width: 1206, height: 2622, verseSide: "top"),
        Case(generator: "shanshui@2", seed: "a", variant: "高山", width: 1062, height: 498, verseSide: "right", verseColumns: 4),
        Case(generator: "shanshui@2", seed: "b", variant: "远山", quietTop: 0.4, width: 1062, height: 498, verseSide: "top"),
        Case(generator: "nonflowers@2", seed: "42", variant: "梅", width: 1206, height: 2622,
             verseSide: "right", verseColumns: 2, verseChars: 7),
        Case(generator: "nonflowers@2", seed: "秋分-1", variant: "菊", width: 1206, height: 2622, verseSide: "left"),
        Case(generator: "nonflowers@2", seed: "2026", variant: "荷", hue: 200, width: 1062, height: 498, verseSide: "right"),
        Case(generator: "nonflowers@2", seed: "a", variant: "兰", width: 1062, height: 1116, verseSide: "top", verseColumns: 2),
        Case(generator: "nonflowers@2", seed: "1", variant: "自然", density: 0.8, width: 510, height: 510, verseSide: "right"),
    ]

    static let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/zxart/procedural-v1.json")
    static let fixtureURLV2 = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/zxart/procedural-v2.json")

    /// @3: 三种变体 × 三种画幅 × 三种诗句边; 密度、种子和 quiet_top 覆盖分支。
    static let casesV3: [Case] = {
        var result: [Case] = []
        let sizes = [(510, 510), (1206, 2622), (1062, 498)]
        for (vi, variant) in ["高山", "江岸", "远山"].enumerated() {
            for (fi, size) in sizes.enumerated() {
                for (si, side) in ["left", "right", "top"].enumerated() {
                    let i = vi + fi + si
                    result.append(Case(generator: "shanshui@3", seed: ["秋分-1", "a", "2026"][i % 3], variant: variant,
                                       density: [0.6, 1.0, 1.5][i % 3], quietTop: i % 2 == 0 ? 0.4 : nil,
                                       width: size.0, height: size.1, verseSide: side,
                                       verseColumns: side == "top" ? 2 : 4, verseChars: 7))
                }
            }
        }
        return result
    }()

    static let fixtureURLV3 = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/zxart/procedural-v3.json")

    static func record(_ c: Case) throws -> [String: Any] {
        var params: [String: Any] = [:]
        if let v = c.density { params["density"] = v }
        if let v = c.hue { params["hue"] = v }
        if let v = c.quietTop { params["quiet_top"] = v }
        if let v = c.verseSide { params["verse_side"] = v }
        if let v = c.verseColumns { params["verse_columns"] = v }
        if let v = c.verseChars { params["verse_chars"] = v }
        let p = ZXArt.Procedural(generator: c.generator, seed: c.seed, variant: c.variant,
                                 params: .init(density: c.density, hue: c.hue, quietTop: c.quietTop,
                                               verseSide: c.verseSide, verseColumns: c.verseColumns, verseChars: c.verseChars))
        let (d, t) = try XCTUnwrap(ZXArt.traced(procedural: p, palette: .paperInk,
                                                pixelSize: CGSize(width: c.width, height: c.height)))
        var layers: [[String: Any]] = []
        for l in d.layers {
            var np = 0, sx = 0.0, sy = 0.0
            for sh in l.shapes { for v in sh.points { np += 1; sx += Double(v.x); sy += Double(v.y) } }
            var layer: [String: Any] = ["kind": l.mist != nil ? "mist" : (l.rim != nil ? "rim" : (l.filter != nil ? "filter" : "plain")),
                                        "shapes": l.shapes.count, "points": np, "sumX": sx, "sumY": sy]
            if c.generator == "shanshui@3" {
                layer["blend"] = l.blend == .multiply ? "multiply" : "normal"
                layer["opacity"] = l.opacity
                layer["tooth"] = l.tooth ?? 0
                layer["wash"] = l.wash.map { [$0.bleed, $0.rim, $0.grain] } ?? []
                layer["rim"] = l.rim.map { [$0.width, $0.power, $0.peakOpacity, $0.ridgeX0, $0.ridgeStep, Double($0.seed)] } ?? []
                layer["alphaSum"] = l.shapes.reduce(0.0) { $0 + ($1.fill?.alpha ?? 0) + ($1.stroke?.alpha ?? 0) }
            }
            layers.append(layer)
        }
        var engine: [String: Any] = ["polys": t.polys, "points": t.points, "sumX": t.sumX, "sumY": t.sumY,
                                     "prngAfter": t.prngAfter]
        if !t.transform.isEmpty { engine["transform"] = t.transform }
        var out: [String: Any] = ["generator": c.generator, "seed": c.seed, "variant": c.variant, "params": params,
                                  "pixelSize": [c.width, c.height], "palette": "paperInk (#F2EEE4 / #272E2A)",
                                  "logical": [d.width, d.height], "engine": engine, "drawing": ["layers": layers]]
        if let v = d.verseLayout {
            out["verse"] = ["side": v.side.rawValue,
                            "rect": [Double(v.rect.minX), Double(v.rect.minY), Double(v.rect.width), Double(v.rect.height)]]
        }
        return out
    }

    func testProceduralV1Fingerprints() throws {
        try check(Self.cases, url: Self.fixtureURL, resource: "procedural-v1", writeTag: "1",
                  note: "ZixiaoArt @1 cross-platform fixtures. engine = raw generator polygons (shanshui: composition parts in logical units; nonflowers: original 1200x1200 canvas, before transform [k, tx, ty]); drawing = after palette mapping, dropping polygons with < 2 points / no visible fill+stroke / non-finite points, points stored as Float32. Counts must match exactly; sums to ~1e-6 relative (drawing sums are over Float32-rounded points). prngAfter = PRNG integer state right after generation (before shanshui's background paper).")
    }

    func testProceduralV2Fingerprints() throws {
        try check(Self.casesV2, url: Self.fixtureURLV2, resource: "procedural-v2", writeTag: "v2",
                  note: "ZixiaoArt @2 cross-platform fixtures (verse-aware composition). Same fields as procedural-v1.json; engine for shanshui@2 = the composition parts after fit/cull (what is drawn); verse = the verse rect in unit coordinates (x, y, width, height; origin top-left) that the art keeps clear and the client typesets into. Counts must match exactly; sums to ~1e-6 relative; verse rect to 1e-9.")
    }

    func testProceduralV3Fingerprints() throws {
        try check(Self.casesV3, url: Self.fixtureURLV3, resource: "procedural-v3", writeTag: "v3",
                  note: "shanshui@3 Swift-first fixtures. engine = frozen @2 layout skeleton after fit/cull; drawing = final Brush bodies/bristles, rims, wash and tooth. 4b will port these to JS. Generated on Mac only; never synthesize a golden on the VPS.",
                  skipMissing: true)
    }

    /// 写 (ZXART_WRITE_FIXTURES=1 写全部 / =v2 只写 @2) 或逐项比对。
    func check(_ cases: [Case], url fixtureURL: URL, resource: String, writeTag: String, note: String, skipMissing: Bool = false) throws {
        let flag = ProcessInfo.processInfo.environment["ZXART_WRITE_FIXTURES"]
        let bundled = Bundle.module.url(forResource: resource, withExtension: "json", subdirectory: "Fixtures/zxart")
        let source = FileManager.default.fileExists(atPath: fixtureURL.path) ? fixtureURL : nil
        if skipMissing, flag != "1", flag != writeTag, bundled == nil, source == nil {
            throw XCTSkip("尚无 \(resource).json; 请在 Mac 首次运行 ZXART_WRITE_FIXTURES=v3，审阅样张后提交真实金标。")
        }
        let records = try cases.map(Self.record)
        if flag == "1" || flag == writeTag {
            let doc: [String: Any] = ["note": note, "cases": records]
            let data = try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fixtureURL)
            print("wrote \(fixtureURL.path)")
            return
        }
        let url = try XCTUnwrap(bundled ?? (skipMissing ? source : nil))
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
            XCTAssertEqual(ge["polys"] as? Int, we["polys"] as? Int, "\(label) engine polys — composition changed? bump the version")
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
                if got["generator"] as? String == "shanshui@3" {
                    XCTAssertEqual(a["blend"] as? String, b["blend"] as? String)
                    for key in ["opacity", "tooth", "alphaSum"] { close(a[key], b[key], "\(label) layer \(i) \(key)") }
                    for key in ["wash", "rim"] {
                        let av = try XCTUnwrap(a[key] as? [Double]), bv = try XCTUnwrap(b[key] as? [Double])
                        XCTAssertEqual(av.count, bv.count)
                        for (x, y) in zip(av, bv) { close(x, y, "\(label) layer \(i) \(key)") }
                    }
                }
            }
            let gv = got["verse"] as? [String: Any], wv = w["verse"] as? [String: Any]
            XCTAssertEqual(gv == nil, wv == nil, "\(label) verse rect presence")
            if let gv, let wv {
                XCTAssertEqual(gv["side"] as? String, wv["side"] as? String, "\(label) verse side")
                let gr = gv["rect"] as? [Double] ?? [], wr = wv["rect"] as? [Double] ?? []
                XCTAssertEqual(gr.count, wr.count)
                for (a, b) in zip(gr, wr) { close(a, b, "\(label) verse rect") }
            }
        }
    }
}
