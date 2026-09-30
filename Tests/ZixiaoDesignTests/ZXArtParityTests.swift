//  ZXArtParityTests.swift — Swift 移植 vs 原 JS 的对拍
//
//  金标由 Tools/zxart-fixtures/generate.cjs 跑原作 JS 生成 (Fixtures/zxart/*.json)。
//  - PRNG: 逐位相等 (整数状态 + 前 64 个输出)。
//  - Perlin / 几何: 逐点比较, 容差 1e-9 (JS 与 Apple libm 的 sin/cos/atan2 末位可能差 1 ulp)。
//  - 每个用例结束时的 PRNG 状态逐位相等 —— 证明随机数的消耗次数与顺序完全一致。

import XCTest
@testable import ZixiaoDesign

final class ZXArtParityTests: XCTestCase {
    static let seeds = ["1", "42", "2026"]

    static func fixture(_ name: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/zxart/\(name).json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func num(_ v: Any?) -> Double {
        if let n = v as? NSNumber { return n.doubleValue }
        return .nan  // JSON null ← JS NaN
    }

    static func close(_ a: Double, _ b: Double, rel: Double = 1e-9, abs absTol: Double = 1e-9) -> Bool {
        if a.isNaN && b.isNaN { return true }
        return Swift.abs(a - b) <= max(absTol, rel * max(Swift.abs(a), Swift.abs(b)))
    }

    // MARK: PRNG + noise

    func testPRNGMatchesOriginalExactly() throws {
        for seed in Self.seeds {
            for file in ["shanshui-\(seed)", "nonflowers-\(seed)"] {
                let fx = try Self.fixture(file)
                var prng = ZXArt.PRNG(seed: ZXArt.Seed(seed))
                XCTAssertEqual(prng.state, Self.num(fx["intSeed"]), "\(file) int seed")
                // 输出以字符串存 (JS Number#toString 可精确往返; JSONSerialization 解析浮点不保证)。
                let seq = try XCTUnwrap(fx["prng"] as? [String])
                let states = try XCTUnwrap(fx["prngStates"] as? [NSNumber])
                XCTAssertEqual(seq.count, 64)
                for (i, v) in seq.enumerated() {
                    let got = prng.next()
                    let want = try XCTUnwrap(Double(v))
                    XCTAssertEqual(got.bitPattern, want.bitPattern, "\(file) prng[\(i)] \(got) vs \(v)")
                    XCTAssertEqual(prng.state, states[i].doubleValue, "\(file) state[\(i)]")
                }
            }
        }
    }

    func testIntegerAndStringSeedsAgree() {
        XCTAssertEqual(ZXArt.PRNG(seed: 42).state, ZXArt.PRNG(seed: "42").state)
    }

    func testPerlinMatchesOriginal() throws {
        for seed in Self.seeds {
            let fx = try Self.fixture("shanshui-\(seed)")
            let e = ZXArt.Entropy(seed: ZXArt.Seed(seed))
            let pts = try XCTUnwrap(fx["noise"] as? [[NSNumber]])
            for p in pts {
                let v = e.noise(p[0].doubleValue, p[1].doubleValue, p[2].doubleValue)
                XCTAssertTrue(Self.close(v, p[3].doubleValue, rel: 1e-12, abs: 1e-12),
                              "seed \(seed) noise\(p.prefix(3).map(\.doubleValue)) = \(v) vs \(p[3])")
            }
            XCTAssertEqual(e.state, Self.num(fx["prngAfterNoise"]), "seed \(seed): perlin table consumed 4096 randoms")
        }
    }

    // MARK: shan-shui

    struct Summary {
        var n = 0, np = 0
        var sx = 0.0, sy = 0.0, wsum = 0.0
        var styles: [String: Int] = [:]
    }

    static func canon(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t == "none" { return "none" }
        if t == "white" { return fmt(255, 255, 255, 1) }
        if t.hasPrefix("rgb") {
            let inner = t.drop(while: { $0 != "(" }).dropFirst().dropLast()
            let parts = inner.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? .nan }
            return fmt(parts[0], parts[1], parts[2], parts.count > 3 ? parts[3] : 1)
        }
        return "?" + t
    }

    static func fmt(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> String {
        String(format: "%.0f,%.0f,%.0f,%.4f", r, g, b, a)
    }

    static func canon(_ c: ZXArt.SSColor?) -> String {
        guard let c else { return "none" }
        return fmt(c.r, c.g, c.b, c.a)
    }

    static func canonStyleKey(_ key: String) -> String {
        let parts = key.components(separatedBy: "|")
        return canon(parts[0]) + "|" + canon(parts[1]) + "|" + String(format: "%.4f", Double(parts[2]) ?? .nan)
    }

    static func summarize(_ canv: ZXArt.SSCanv) -> Summary {
        var s = Summary()
        var k = 0
        for (i, p) in canv.enumerated() {
            let key = canon(p.fil) + "|" + canon(p.str) + "|" + String(format: "%.4f", p.wid)
            s.styles[key, default: 0] += 1
            for v in p.p {
                s.np += 1; s.sx += v.x; s.sy += v.y
                k += 1
                s.wsum += Double((k % 1000) + 1) * (v.x + 2 * v.y) + Double(i % 97) * v.x
            }
        }
        s.n = canv.count
        return s
    }

    static func shanCase(_ name: String, _ e: ShanShuiEngine) -> ZXArt.SSCanv {
        typealias P = ZXArt.P
        func sine(_ n: Int, _ x0: Double, _ y0: Double, _ dx: Double, _ amp: Double) -> [P] {
            (0..<n).map { i in P(x0 + Double(i) * dx, y0 + sin(Double(i) * 0.4) * amp) }
        }
        switch name {
        case "stroke": return e.stroke(sine(30, 50, 100, 7, 12), wid: 3)
        case "stroke_fun":
            return e.stroke(sine(12, 10, 10, 5, 3), wid: 1.5, col: .gray(100, 0.4), noi: 0, out: 0,
                            fun: { cos($0 * Double.pi / 2) })
        case "blob": return e.blob(100, 120, len: 40, wid: 10, ang: 0.3)
        case "texture":
            var pl: [[P]] = []
            for j in 0..<10 {
                var row: [P] = []
                for i in 0..<50 {
                    let x = (Double(i) / 50 - 0.5) * Double.pi
                    row.append(P(x / Double.pi * 300 * (1 - Double(j) / 10), -cos(x) * 200 * (1 - Double(j) / 10)))
                }
                pl.append(row)
            }
            return e.texture(pl, xof: 300, yof: 400, tex: 60, sha: 2)
        case "tree01": return e.tree01(200, 400)
        case "tree02": return e.tree02(200, 400)
        case "tree03": return e.tree03(200, 400, hei: 80)
        case "tree04": return e.tree04(200, 400)
        case "tree05": return e.tree05(200, 400, hei: 150)
        case "tree06": return e.tree06(200, 400, hei: 90)
        case "tree07": return e.tree07(200, 400)
        case "tree08": return e.tree08(200, 400)
        case "rock": return e.rock(200, 400, 5, hei: 30, wid: 40, sha: 2)
        case "mountain": return e.mountain(300, 500, 7)
        case "flatMount": return e.flatMount(300, 600, 3, hei: 100, wid: 700, cho: 0.6)
        case "distMount": return e.distMount(0, 300, 11, hei: 150, len: 1000)
        case "arch01": return e.arch01(300, 400, 0.5, hei: 90, wid: 180, per: 0.5)
        case "arch02": return e.arch02(300, 400, 0, wid: 60, rot: 0.3, sto: 2, sty: 3)
        case "arch03": return e.arch03(300, 400, 0, sto: 5)
        case "arch04": return e.arch04(300, 400, 0, sto: 2)
        case "boat01": return e.boat01(300, 400, 0.5, sca: 0.6, fli: true)
        case "man": return e.man(100, 200, sca: 0.5)
        case "water": return e.water(300, 500, 2)
        case "tower": return e.transmissionTower01(300, 500, 0)
        case "scene": return e.originalScene(xmin: 0, xmax: 3000)
        default: return []
        }
    }

    static func comparePolys(_ got: [ZXArt.SSPoly], _ want: [[String: Any]], _ label: String) {
        XCTAssertLessThanOrEqual(want.count, got.count, label)
        for (i, w) in want.enumerated() where i < got.count {
            let pts = (w["p"] as? [[Any]]) ?? []
            XCTAssertEqual(pts.count, got[i].p.count, "\(label) poly \(i) point count")
            for (j, v) in pts.enumerated() where j < got[i].p.count {
                let x = num(v[0]), y = num(v[1])
                if !close(x, got[i].p[j].x) || !close(y, got[i].p[j].y) {
                    XCTFail("\(label) poly \(i) pt \(j): swift (\(got[i].p[j].x), \(got[i].p[j].y)) js (\(x), \(y))")
                    return
                }
            }
            XCTAssertEqual(canon(got[i].fil), canon((w["f"] as? String) ?? "?"), "\(label) poly \(i) fill")
            XCTAssertEqual(canon(got[i].str), canon((w["s"] as? String) ?? "?"), "\(label) poly \(i) stroke")
            XCTAssertTrue(close(got[i].wid, num(w["w"])), "\(label) poly \(i) width")
        }
    }

    func testShanShuiGeometryMatchesOriginal() throws {
        for seed in Self.seeds {
            let fx = try Self.fixture("shanshui-\(seed)")
            let cases = try XCTUnwrap(fx["cases"] as? [String: [String: Any]])
            for name in cases.keys.sorted() {
                let want = cases[name]!
                let e = ShanShuiEngine(seed: ZXArt.Seed(seed))
                let canv = Self.shanCase(name, e)
                let label = "shanshui seed \(seed) \(name)"
                let s = Self.summarize(canv)
                XCTAssertEqual(e.e.state, Self.num(want["prngAfter"]), "\(label): PRNG state after (random consumption)")
                XCTAssertEqual(s.n, (want["n"] as? Int) ?? -1, "\(label): polygon count")
                XCTAssertEqual(s.np, (want["np"] as? Int) ?? -1, "\(label): point count")
                XCTAssertTrue(Self.close(s.sx, Self.num(want["sx"])), "\(label): Σx \(s.sx) vs \(Self.num(want["sx"]))")
                XCTAssertTrue(Self.close(s.sy, Self.num(want["sy"])), "\(label): Σy \(s.sy) vs \(Self.num(want["sy"]))")
                XCTAssertTrue(Self.close(s.wsum, Self.num(want["wsum"])), "\(label): weighted checksum")
                var wantStyles: [String: Int] = [:]
                for (k, v) in (want["styles"] as? [String: Int]) ?? [:] { wantStyles[Self.canonStyleKey(k), default: 0] += v }
                XCTAssertEqual(s.styles, wantStyles, "\(label): style histogram")
                if let all = want["polys"] as? [[String: Any]] {
                    Self.comparePolys(canv, all, label)
                } else if let head = want["head"] as? [[String: Any]] {
                    Self.comparePolys(canv, head, label + " head")
                    if let tail = want["tail"] as? [[String: Any]], canv.count >= tail.count {
                        Self.comparePolys(Array(canv.suffix(tail.count)), tail, label + " tail")
                    }
                }
            }
        }
    }

    func testShanShuiPureHelpers() throws {
        typealias P = ZXArt.P
        let fx = try Self.fixture("shanshui-42")
        let pure = try XCTUnwrap(fx["pure"] as? [String: Any])
        func pts(_ v: Any?) -> [P] { ((v as? [[NSNumber]]) ?? []).map { P($0[0].doubleValue, $0[1].doubleValue) } }
        func eq(_ a: [P], _ b: [P], _ l: String) {
            XCTAssertEqual(a.count, b.count, l)
            for (x, y) in zip(a, b) { XCTAssertTrue(Self.close(x.x, y.x) && Self.close(x.y, y.y), "\(l) \(x) vs \(y)") }
        }
        eq(ZXArt.div([P(0, 0), P(10, 5), P(13, -4)], 4), pts(pure["div"]), "div")
        eq(ZXArt.bezmh([P(0, 0), P(10, 20), P(30, 5), P(40, 40)], 2), pts(pure["bezmh"]), "bezmh")
        let tri = ZXArt.triangulate([P(0, 0), P(100, 0), P(120, 60), P(60, 110), P(-10, 70)], area: 300, convex: true, optimize: false)
        let triW = (pure["triangulate"] as? [Any]) ?? []
        XCTAssertEqual(tri.count, triW.count, "triangulate count")
        for (a, b) in zip(tri, triW) { eq(a, pts(b), "triangulate") }
        let tri2 = ZXArt.triangulate([P(0, 0), P(100, 0), P(50, 30), P(100, 80), P(0, 80)], area: 500, convex: false, optimize: true)
        let tri2W = (pure["triangulateOpt"] as? [Any]) ?? []
        XCTAssertEqual(tri2.count, tri2W.count, "triangulateOpt count")
        for (a, b) in zip(tri2, tri2W) { eq(a, pts(b), "triangulateOpt") }
    }

    // MARK: nonflowers

    struct FSummary {
        var n = 0, np = 0
        var sx = 0.0, sy = 0.0, wsum = 0.0, csum = 0.0
        var colors = Set<String>()
        var layers: [String: Int] = [:]
    }

    static func cssString(_ c: ZXArt.FColor) -> String {
        func i(_ v: Double) -> String { v.isNaN ? "NaN" : String(Int(v)) }
        let a = c.a.isNaN ? "NaN" : String(format: "%.3f", c.a)
        return "rgba(\(i(c.r)),\(i(c.g)),\(i(c.b)),\(a == "-0.000" ? "-0.000" : a))"
    }

    static func summarize(_ polys: [ZXArt.FPoly], layerNames: [Int: String]) -> FSummary {
        var s = FSummary()
        var k = 0
        for (i, p) in polys.enumerated() {
            s.colors.insert(cssString(p.col))
            s.layers[layerNames[p.layer] ?? "?", default: 0] += 1
            for v in p.p {
                s.np += 1; s.sx += v.x; s.sy += v.y; k += 1
                s.wsum += Double((k % 1000) + 1) * (v.x + 2 * v.y) + Double(i % 97) * v.x
            }
            let c = p.col
            // 与 harness 的正则一致: 只统计非负分量的 rgba
            if c.r >= 0, c.g >= 0, c.b >= 0, !(c.a < 0), !c.a.isNaN {
                s.csum += Double((i % 101) + 1) * (c.r + 2 * c.g + 3 * c.b + 1000 * c.a)
            }
        }
        s.n = polys.count
        return s
    }

    static func compareF(_ s: FSummary, _ want: [String: Any], _ label: String) {
        XCTAssertEqual(s.n, (want["n"] as? Int) ?? -1, "\(label): polygon count")
        XCTAssertEqual(s.np, (want["np"] as? Int) ?? -1, "\(label): point count")
        XCTAssertTrue(close(s.sx, num(want["sx"])), "\(label): Σx \(s.sx) vs \(num(want["sx"]))")
        XCTAssertTrue(close(s.sy, num(want["sy"])), "\(label): Σy \(s.sy) vs \(num(want["sy"]))")
        XCTAssertTrue(close(s.wsum, num(want["wsum"])), "\(label): weighted checksum")
        XCTAssertTrue(close(s.csum, num(want["csum"])), "\(label): colour checksum \(s.csum) vs \(num(want["csum"]))")
        XCTAssertEqual(s.colors.count, (want["colorCount"] as? Int) ?? -1, "\(label): distinct colours")
        XCTAssertEqual(s.layers, (want["layers"] as? [String: Int]) ?? [:], "\(label): per-layer counts")
    }

    func testNonflowersPageSequenceMatchesOriginal() throws {
        for seed in Self.seeds {
            let fx = try Self.fixture("nonflowers-\(seed)")
            let e = FlowersEngine(seed: ZXArt.Seed(seed))
            for (key, col, tex, spr) in [("paperBG", (1.0, 0.99, 0.9), 10.0, 0.0), ("paperCanvas", (0.98, 0.91, 0.74), 20.0, 1.0)] {
                var sum = 0.0, count = 0
                var first: [[Double]] = []
                _ = e.paper(col: col, tex: tex, spr: spr) { r, g, b in
                    count += 1
                    sum += Double((count % 1000) + 1) * (r + 3 * g + 7 * b)
                    if first.count < 8 { first.append([r, g, b]) }
                }
                let want = try XCTUnwrap(fx[key] as? [String: Any])
                XCTAssertEqual(count, want["count"] as? Int, "seed \(seed) \(key) count")
                XCTAssertEqual(sum, Self.num(want["sum"]), "seed \(seed) \(key) texel checksum")
                XCTAssertEqual(first, (want["first"] as? [[Double]]) ?? [], "seed \(seed) \(key) first texels")
                XCTAssertEqual(e.e.state, Self.num(want["prngAfter"]), "seed \(seed) \(key) PRNG after")
            }
            let woody = e.r() <= 0.5
            XCTAssertEqual(woody, fx["woody"] as? Bool, "seed \(seed) woody/herbal coin")
            let par = e.genParams()
            XCTAssertEqual(e.e.state, Self.num(fx["prngAfterParams"]), "seed \(seed) PRNG after genParams")
            try Self.compareParams(par, try XCTUnwrap(fx["params"] as? [String: Any]), "seed \(seed)")
            if woody { e.woody(par) } else { e.herbal(par) }
            let want = try XCTUnwrap(fx["plant"] as? [String: Any])
            XCTAssertEqual(e.e.state, Self.num(want["prngAfter"]), "seed \(seed) plant PRNG after")
            let s = Self.summarize(e.polys, layerNames: [0: "3", 1: "4"])
            Self.compareF(s, want, "nonflowers seed \(seed) plant")
            if let head = want["head"] as? [[String: Any]] { Self.compareFPolys(e.polys, head, "seed \(seed) plant head") }
        }
    }

    static func compareFPolys(_ got: [ZXArt.FPoly], _ want: [[String: Any]], _ label: String) {
        for (i, w) in want.enumerated() where i < got.count {
            let pts = (w["p"] as? [[Any]]) ?? []
            XCTAssertEqual(pts.count, got[i].p.count, "\(label) poly \(i) point count")
            for (j, v) in pts.enumerated() where j < got[i].p.count {
                let x = num(v[0]), y = num(v[1])
                if !close(x, got[i].p[j].x) || !close(y, got[i].p[j].y) {
                    XCTFail("\(label) poly \(i) pt \(j): swift (\(got[i].p[j].x), \(got[i].p[j].y)) js (\(x), \(y))")
                    return
                }
            }
            XCTAssertEqual(cssString(got[i].col), w["c"] as? String, "\(label) poly \(i) colour")
            XCTAssertEqual(got[i].fil, w["f"] as? Bool, "\(label) poly \(i) fill flag")
            XCTAssertEqual(got[i].str, w["s"] as? Bool, "\(label) poly \(i) stroke flag")
        }
    }

    static func compareParams(_ p: FlowersEngine.PAR, _ want: [String: Any], _ label: String) throws {
        func n(_ k: String, _ v: Double) { XCTAssertTrue(close(v, num(want[k]), rel: 1e-12, abs: 1e-12), "\(label) PAR.\(k) \(v) vs \(want[k] ?? "nil")") }
        func f(_ k: String, _ fn: (Double) -> Double) {
            let samples = (want[k] as? [Any]) ?? []
            XCTAssertEqual(samples.count, 11, "\(label) PAR.\(k) samples")
            for (i, sv) in samples.enumerated() {
                let v = fn(Double(i) / 10)
                XCTAssertTrue(close(v, num(sv), rel: 1e-9, abs: 1e-9), "\(label) PAR.\(k)(\(Double(i) / 10)) \(v) vs \(sv)")
            }
        }
        func c(_ k: String, _ r: ZXArt.HSVRange) {
            let w = (want[k] as? [String: [NSNumber]]) ?? [:]
            for (a, b) in zip(r.min, w["min"] ?? []) { XCTAssertTrue(close(a, b.doubleValue, rel: 1e-12, abs: 1e-12), "\(label) PAR.\(k).min") }
            for (a, b) in zip(r.max, w["max"] ?? []) { XCTAssertTrue(close(a, b.doubleValue, rel: 1e-12, abs: 1e-12), "\(label) PAR.\(k).max") }
        }
        n("flowerChance", p.flowerChance); n("leafChance", p.leafChance)
        XCTAssertEqual(p.leafType, ((want["leafType"] as? [NSNumber]) ?? []).map(\.doubleValue), "\(label) leafType")
        f("flowerShape", p.flowerShape); f("leafShape", p.leafShape)
        c("flowerColor", p.flowerColor); c("leafColor", p.leafColor)
        f("flowerOpenCurve") { p.flowerOpenCurve($0, 0.5) }
        f("flowerColorCurve", p.flowerColorCurve)
        n("leafLength", p.leafLength); n("flowerLength", p.flowerLength); n("pedicelLength", p.pedicelLength)
        n("leafWidth", p.leafWidth); n("flowerWidth", p.flowerWidth); n("stemWidth", p.stemWidth)
        n("stemBend", p.stemBend); n("stemLength", p.stemLength); n("stemCount", p.stemCount)
        n("sheathLength", p.sheathLength); n("sheathWidth", p.sheathWidth); n("shootCount", p.shootCount)
        n("shootLength", p.shootLength); n("leafPosition", Double(p.leafPosition)); n("flowerPetal", p.flowerPetal)
        n("innerLength", p.innerLength); n("innerWidth", p.innerWidth); f("innerShape", p.innerShape)
        c("innerColor", p.innerColor)
        n("branchWidth", p.branchWidth); n("branchTwist", p.branchTwist); n("branchDepth", p.branchDepth)
        n("branchFork", p.branchFork); c("branchColor", p.branchColor)
    }

    func testNonflowersPrimitivesMatchOriginal() throws {
        typealias V3 = ZXArt.V3
        for seed in Self.seeds {
            let fx = try Self.fixture("nonflowers-\(seed)")
            let cases = try XCTUnwrap(fx["cases"] as? [String: [String: Any]])
            for (name, want) in cases.sorted(by: { $0.key < $1.key }) {
                let e = FlowersEngine(seed: ZXArt.Seed(seed))
                var ret: [(Double, [V3])] = []
                switch name {
                case "leaf":
                    var a = FlowersEngine.LeafArgs()
                    a.xof = 300; a.yof = 300; a.len = 60; a.seg = 12; a.vei = [1, 3]; a.rot = V3(1.1, 0.4, 0)
                    e.leaf(0, a)
                case "leafFlo":
                    var a = FlowersEngine.LeafArgs()
                    a.flo = true; a.xof = 200; a.yof = 200; a.len = 30; a.seg = 10; a.vei = [0]; a.rot = V3(0.3, -0.7, 1.2)
                    a.col = ZXArt.HSVRange(min: [340, 0.4, 0.9, 1], max: [20, 0.1, 1, 0.8])
                    a.cof = { FlowersEngine.sigmoid($0, 8) }
                    a.wid = { sin($0 * Double.pi) * 12 }
                    a.ben = { x in V3(x < 0.3 ? 6 : 1, 0, 0) }
                    e.leaf(0, a)
                case "stem":
                    e.stem(0, FlowersEngine.StemArgs(xof: 300, yof: 500, rot: V3(Double.pi / 2, 0, 0.4), len: 120, seg: 10))
                case "branch":
                    ret = e.branch(0, FlowersEngine.BranchArgs(xof: 300, yof: 500, len: 200, seg: 20, wid: 1, twi: 4, dep: 2, frk: 4))
                default:
                    XCTFail("unknown case \(name)")
                }
                let label = "nonflowers seed \(seed) \(name)"
                XCTAssertEqual(e.e.state, Self.num(want["prngAfter"]), "\(label): PRNG state after")
                Self.compareF(Self.summarize(e.polys, layerNames: [0: "0"]), want, label)
                if let all = want["polys"] as? [[String: Any]] { Self.compareFPolys(e.polys, all, label) }
                if let head = want["head"] as? [[String: Any]] { Self.compareFPolys(e.polys, head, label + " head") }
                if let r = want["ret"] as? [[Any]] {
                    XCTAssertEqual(ret.count, r.count, "\(label) branch count")
                    for (g, w) in zip(ret, r) {
                        XCTAssertEqual(g.0, Self.num(w[0]), "\(label) dep")
                        XCTAssertEqual(g.1.count, (w[1] as? Int) ?? -1, "\(label) len")
                        let last = (w[2] as? [NSNumber]) ?? []
                        if let gl = g.1.last, last.count == 3 {
                            XCTAssertTrue(Self.close(gl.x, last[0].doubleValue) && Self.close(gl.y, last[1].doubleValue)
                                          && Self.close(gl.z, last[2].doubleValue), "\(label) branch tip")
                        }
                    }
                }
            }
        }
    }

    func testNonflowersPureHelpers() throws {
        typealias V3 = ZXArt.V3
        let fx = try Self.fixture("nonflowers-42")
        let pure = try XCTUnwrap(fx["pure"] as? [String: Any])
        let inputs: [V3] = [V3(1, 0, 0), V3(0, 1, 0), V3(0.3, -0.5, 0.8), V3(-0.2, 0.9, 0.1)]
        let te = (pure["toeuler"] as? [[NSNumber]]) ?? []
        for (v, w) in zip(inputs, te) {
            let r = ZXArt.V3Math.toeuler(v)
            XCTAssertTrue(Self.close(r.x, w[0].doubleValue) && Self.close(r.y, w[1].doubleValue) && Self.close(r.z, w[2].doubleValue),
                          "toeuler(\(v)) = \(r) vs \(w)")
        }
        let rv = ZXArt.V3Math.roteuler(V3(1, 2, 3), V3(0.3, -0.2, 1.1))
        let rw = ((pure["rotvec"] as? [NSNumber]) ?? []).map(\.doubleValue)
        XCTAssertTrue(Self.close(rv.x, rw[0]) && Self.close(rv.y, rw[1]) && Self.close(rv.z, rw[2]), "roteuler")
        let hs = (pure["hsv"] as? [String]) ?? []
        let hin: [[Double]] = [[0, 0.5, 0.5, 1], [123.4, 0.3, 0.9, 0.7], [359.9, 1, 1, 0.25], [200, 0.05, 0.4, 1]]
        for (a, w) in zip(hin, hs) { XCTAssertEqual(Self.cssString(ZXArt.hsv(a[0], a[1], a[2], a[3])), w, "hsv\(a)") }
        let lh = ((pure["lerpHue"] as? [NSNumber]) ?? []).map(\.doubleValue)
        let lin: [[Double]] = [[10, 350, 0.3], [100, 200, 0.5], [340, 20, 0.75]]
        for (a, w) in zip(lin, lh) { XCTAssertTrue(Self.close(ZXArt.lerpHue(a[0], a[1], a[2]), w), "lerpHue\(a)") }
    }
}
