//  ZXArtRenderTests.swift — 出图、确定性、构图检查、计时
//
//  评审图写到 /tmp/zxart-shots/v1/ (模拟器进程能直接写宿主 /tmp; 计时追加写入 timings-*.txt, 重跑前先清目录);
//  环境变量 ZXART_SHOTS=0 跳过写图。
//  计时断言只在 Release (-O) 构建里生效 (Debug 下 Swift 比 -O 慢一个量级, 只记录不判定):
//
//      xcodebuild test -scheme ZixiaoKit-Package -configuration Release ENABLE_TESTABILITY=YES \
//        -destination 'platform=iOS Simulator,name=…' -only-testing:ZixiaoArtTests

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ZixiaoArt
import ZixiaoDesign

final class ZXArtRenderTests: XCTestCase {
    static let outDir = URL(fileURLWithPath: "/tmp/zxart-shots/v1", isDirectory: true)
    static let phone = CGSize(width: 1206, height: 2622)
    static let widget = CGSize(width: 1012, height: 476)

    #if DEBUG
    static let optimized = false
    #else
    static let optimized = true
    #endif

    static let paperInk = ZXArt.Palette(paper: ZXHex("#F2EEE4")!, ink: ZXHex("#272E2A")!)
    static let night = ZXArt.Palette(paper: ZXHex("#1C211F")!, ink: ZXHex("#EEE9DD")!)

    static func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    static func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }

    static var writesShots: Bool { ProcessInfo.processInfo.environment["ZXART_SHOTS"] != "0" }

    static func pngData(_ img: CGImage) -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    static func writePNG(_ img: CGImage, _ name: String) {
        guard writesShots else { return }
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try? pngData(img).write(to: outDir.appendingPathComponent(name))
    }

    /// 位图的 RGBA8 字节。render 出的图本来就是 RGBA8 预乘: 直接取数据, 不经过 CG 绘制
    /// (CG 并发绘制本身不保证逐字节一致, 测试不能引入它)。
    static func pixels(_ img: CGImage) -> [UInt8] {
        if img.bitsPerPixel == 32, img.bytesPerRow == img.width * 4,
           img.bitmapInfo.rawValue == ZXArt.bitmapInfo, let data = img.dataProvider?.data as Data? {
            return [UInt8](data)
        }
        return drawnPixels(img)
    }

    static func drawnPixels(_ img: CGImage) -> [UInt8] {
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return buf
    }

    static func sha(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// 「墨量」: 画面相对纯纸 (同纸纹、无图层) 往墨色偏了多少, 0 = 纸, 1 = 墨。按区域 (像素) 求平均。
    static func inkCoverage(_ drawing: ZXArt.Drawing, palette: ZXArt.Palette, size: CGSize, region: CGRect) -> Double {
        var bare = drawing
        bare.layers = []
        let a = pixels(ZXArt.render(drawing, pixelWidth: Int(size.width), pixelHeight: Int(size.height))!)
        let b = pixels(ZXArt.render(bare, pixelWidth: Int(size.width), pixelHeight: Int(size.height))!)
        let span = max(abs(palette.ink.red - palette.paper.red) + abs(palette.ink.green - palette.paper.green)
                       + abs(palette.ink.blue - palette.paper.blue), 0.05) * 255
        let w = Int(size.width)
        let x0 = max(0, Int(region.minX)), x1 = min(w, Int(region.maxX))
        let y0 = max(0, Int(region.minY)), y1 = min(Int(size.height), Int(region.maxY))
        var sum = 0.0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * w + x) * 4
                sum += Double(abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2])))
            }
        }
        return sum / span / Double(max(1, (x1 - x0) * (y1 - y0)))
    }

    static let shanshuiVariants = ["高山", "江岸", "远山"]
    static let flowerVariants = ["梅", "荷", "菊", "兰", "自然"]

    // MARK: - 契约

    func testProceduralDecodesContractJSON() throws {
        let json = #"""
        {"generator":"shanshui@1","seed":"秋分-1","variant":"江岸","params":{"density":1.2,"quiet_top":0.3}}
        """#
        let p = try JSONDecoder().decode(ZXArt.Procedural.self, from: Data(json.utf8))
        XCTAssertEqual(p.generatorName, "shanshui")
        XCTAssertEqual(p.version, 1)
        XCTAssertEqual(p.seed, "秋分-1")
        XCTAssertEqual(p.params.density, 1.2)
        XCTAssertEqual(p.params.quietTop, 0.3)
        XCTAssertNil(p.params.hue)
        XCTAssertTrue(p.isSupported)
        // 往返: 键仍是 snake_case
        let back = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        XCTAssertTrue(back.contains("\"quiet_top\""), back)
        XCTAssertEqual(try JSONDecoder().decode(ZXArt.Procedural.self, from: Data(back.utf8)), p)
        // 缺 params、数字种子
        let q = try JSONDecoder().decode(ZXArt.Procedural.self,
                                         from: Data(#"{"generator":"nonflowers@1","seed":42,"variant":"梅"}"#.utf8))
        XCTAssertEqual(q.seed, "42")
        XCTAssertEqual(q.params, .init())
        XCTAssertTrue(q.isSupported)
    }

    func testUnknownGeneratorVersionOrVariantRendersNil() {
        let size = CGSize(width: 300, height: 600)
        for (g, v) in [("shanshui@2", "高山"), ("shanshui", "高山"), ("nonflowers@0", "梅"), ("bamboo@1", "竹"),
                       ("shanshui@1", "梅"), ("nonflowers@1", "高山"), ("nonflowers@1", "竹")] {
            let p = ZXArt.Procedural(generator: g, seed: "a", variant: v)
            XCTAssertFalse(p.isSupported, "\(g) \(v)")
            XCTAssertNil(ZXArt.render(procedural: p, palette: Self.paperInk, pixelSize: size), "\(g) \(v)")
        }
        XCTAssertNil(ZXArt.render(procedural: .init(generator: "shanshui@1", seed: "a", variant: "高山"),
                                  palette: Self.paperInk, pixelSize: .zero))
    }

    func testWashDefaultsToInkFortyPercentOverPaper() {
        let pal = ZXArt.Palette(paper: ZXHex("#F2EEE4")!, ink: ZXHex("#272E2A")!)
        let want = ZXHex("#272E2A")!.opacity(0.4).composited(over: ZXHex("#F2EEE4")!)
        XCTAssertEqual(pal.wash, want)
        XCTAssertEqual(ZXArt.Palette(paper: pal.paper, ink: pal.ink, wash: ZXHex("#808080")!).wash, ZXHex("#808080")!)
    }

    // MARK: - 确定性

    /// 同一配方 → 逐字节相同的 PNG; 并发渲染与串行结果相同 (渲染只读 Drawing, 分带条数固定)。
    func testDeterministicBytesAndThreadSafe() async throws {
        let recipes: [(ZXArt.Procedural, CGSize)] = [
            (.init(generator: "shanshui@1", seed: "秋分-1", variant: "江岸"), Self.phone),
            (.init(generator: "shanshui@1", seed: "a", variant: "远山", params: .init(density: 1.4)), Self.widget),
            (.init(generator: "nonflowers@1", seed: "2026", variant: "梅"), Self.widget),
            (.init(generator: "nonflowers@1", seed: "b", variant: "荷", params: .init(hue: 200, quietTop: 0.4)),
             CGSize(width: 510, height: 510)),
        ]
        for (p, size) in recipes {
            let a = try XCTUnwrap(ZXArt.render(procedural: p, palette: Self.night, pixelSize: size))
            let b = try XCTUnwrap(ZXArt.render(procedural: p, palette: Self.night, pixelSize: size))
            XCTAssertEqual(a.width, Int(size.width))
            XCTAssertEqual(a.height, Int(size.height))
            let ha = Self.sha(Self.pixels(a))
            XCTAssertEqual(ha, Self.sha(Self.pixels(b)), "\(p.generator) \(p.variant): pixels differ between runs")
            XCTAssertEqual(Self.pngData(a), Self.pngData(b), "\(p.generator) \(p.variant): PNG bytes differ")
            // 4 个任务同时渲染同一配方
            let hashes = await withTaskGroup(of: String.self) { group in
                for _ in 0..<4 {
                    group.addTask { Self.sha(Self.pixels(ZXArt.render(procedural: p, palette: Self.night, pixelSize: size)!)) }
                }
                var out: [String] = []
                for await h in group { out.append(h) }
                return out
            }
            XCTAssertEqual(Set(hashes), [ha], "\(p.generator) \(p.variant): concurrent renders differ")
        }
        // 换种子 → 换画
        let s1 = ZXArt.render(procedural: .init(generator: "shanshui@1", seed: "a", variant: "高山"),
                              palette: Self.paperInk, pixelSize: Self.widget)!
        let s2 = ZXArt.render(procedural: .init(generator: "shanshui@1", seed: "b", variant: "高山"),
                              palette: Self.paperInk, pixelSize: Self.widget)!
        XCTAssertNotEqual(Self.sha(Self.pixels(s1)), Self.sha(Self.pixels(s2)))
    }

    // MARK: - 构图

    /// 顶部留白区 (时钟 + 诗句) 基本是空纸: 墨量平均 < 2% (远山的雾、极少的树梢允许)。
    func testQuietTopIsMostlyEmpty() throws {
        let size = CGSize(width: 402, height: 874)  // 1/3 尺寸, 构图相同
        for (g, variants) in [("shanshui@1", Self.shanshuiVariants), ("nonflowers@1", Self.flowerVariants)] {
            for v in variants {
                for seed in ["秋分-1", "a", "2026"] {
                    for qt in [0.32, 0.45] {
                        let p = ZXArt.Procedural(generator: g, seed: seed, variant: v, params: .init(quietTop: qt))
                        let d = try XCTUnwrap(ZXArt.drawing(procedural: p, palette: Self.paperInk, pixelSize: size))
                        let region = CGRect(x: 0, y: 0, width: size.width, height: size.height * qt)
                        let cov = Self.inkCoverage(d, palette: Self.paperInk, size: size, region: region)
                        XCTAssertLessThan(cov, 0.02, "\(g) \(v) seed \(seed) quiet_top \(qt): ink \(cov)")
                        // 画面下方确实有画
                        let below = CGRect(x: 0, y: size.height * qt, width: size.width, height: size.height * (1 - qt))
                        XCTAssertGreaterThan(Self.inkCoverage(d, palette: Self.paperInk, size: size, region: below), 0.004,
                                             "\(g) \(v) seed \(seed): nothing drawn")
                    }
                }
            }
        }
    }

    /// 中号小组件 (横幅): 主体靠右, 左侧 40% 留给诗句 (墨量 < 1.5%)。
    func testWideWidgetKeepsLeftSideForVerse() throws {
        let size = CGSize(width: 1062.0 / 2, height: 498.0 / 2)
        for (g, variants) in [("shanshui@1", Self.shanshuiVariants), ("nonflowers@1", Self.flowerVariants)] {
            for v in variants {
                for seed in ["秋分-1", "a"] {
                    let d = try XCTUnwrap(ZXArt.drawing(procedural: .init(generator: g, seed: seed, variant: v),
                                                        palette: Self.paperInk, pixelSize: size))
                    let left = CGRect(x: 0, y: 0, width: size.width * 0.4, height: size.height)
                    let right = CGRect(x: size.width * 0.5, y: 0, width: size.width * 0.5, height: size.height)
                    let l = Self.inkCoverage(d, palette: Self.paperInk, size: size, region: left)
                    let r = Self.inkCoverage(d, palette: Self.paperInk, size: size, region: right)
                    XCTAssertLessThan(l, 0.015, "\(g) \(v) \(seed): left verse zone ink \(l)")
                    XCTAssertGreaterThan(r, l, "\(g) \(v) \(seed): subject not on the right")
                }
            }
        }
    }

    // MARK: - 评审图 + 计时

    struct Timing { var name: String; var gen: Double; var render: Double; var shapes: Int }

    /// 生成 + 渲染各 `reps` 次, 取中位数; 返回最后一张图。
    static func timed(_ name: String, _ p: ZXArt.Procedural, _ pal: ZXArt.Palette, _ size: CGSize,
                      reps: Int) -> (Timing, CGImage?) {
        let clock = ContinuousClock()
        var gens: [Double] = [], rens: [Double] = []
        var img: CGImage?
        var shapes = 0
        for _ in 0..<reps {
            var d: ZXArt.Drawing?
            gens.append(ms(clock.measure { d = ZXArt.drawing(procedural: p, palette: pal, pixelSize: size) }))
            shapes = d?.shapeCount ?? 0
            rens.append(ms(clock.measure { img = d.flatMap { ZXArt.render($0, pixelWidth: Int(size.width), pixelHeight: Int(size.height)) } }))
        }
        return (Timing(name: name, gen: median(gens), render: median(rens), shapes: shapes), img)
    }

    static func log(_ rows: [Timing], _ title: String) {
        var s = "\n== \(title) (\(optimized ? "Release -O" : "Debug -Onone"), median) ==\n"
        s += "name | gen ms | render ms | total ms | shapes\n"
        for r in rows {
            s += String(format: "%@ | %.1f | %.1f | %.1f | %d\n", r.name, r.gen, r.render, r.gen + r.render, r.shapes)
        }
        print(s)
        guard writesShots else { return }
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent("timings-\(optimized ? "release" : "debug").txt")
        let prev = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (prev + s).write(to: url, atomically: true, encoding: .utf8)
    }

    /// 评审集: 山水 3 型 × 3 种子 × 纸墨 / 夜色 (整屏); 花 5 型 × 2 种子 × 整屏 / 小组件。
    func testReviewSetAndTimings() throws {
        let reps = Self.optimized ? 3 : 1
        var rows: [Timing] = []
        for v in Self.shanshuiVariants {
            for seed in ["秋分-1", "a", "2026"] {
                for (pname, pal) in [("paperink", Self.paperInk), ("night", Self.night)] {
                    let name = "shanshui-\(v)-\(seed)-\(pname)-1206x2622"
                    let (t, img) = Self.timed(name, .init(generator: "shanshui@1", seed: seed, variant: v), pal, Self.phone, reps: reps)
                    Self.writePNG(try XCTUnwrap(img), name + ".png")
                    rows.append(t)
                    if Self.optimized { XCTAssertLessThan(t.gen + t.render, 500, "\(name) over 500 ms") }
                }
            }
        }
        Self.log(rows, "shanshui@1 1206×2622")
        rows = []
        for v in Self.flowerVariants {
            for seed in ["秋分-1", "2026"] {
                for size in [Self.phone, Self.widget] {
                    let name = "nonflowers-\(v)-\(seed)-paperink-\(Int(size.width))x\(Int(size.height))"
                    let (t, img) = Self.timed(name, .init(generator: "nonflowers@1", seed: seed, variant: v), Self.paperInk, size, reps: reps)
                    Self.writePNG(try XCTUnwrap(img), name + ".png")
                    rows.append(t)
                    // 「自然」是原作的参数空间 (个别种子形状多达 4 万), 预算放宽
                    if Self.optimized { XCTAssertLessThan(t.gen + t.render, v == "自然" ? 1500 : 1000, "\(name) over budget") }
                }
            }
        }
        // 夜色各一张
        for v in Self.flowerVariants {
            let name = "nonflowers-\(v)-秋分-1-night-1206x2622"
            let (t, img) = Self.timed(name, .init(generator: "nonflowers@1", seed: "秋分-1", variant: v), Self.night, Self.phone, reps: 1)
            Self.writePNG(try XCTUnwrap(img), name + ".png")
            rows.append(t)
        }
        Self.log(rows, "nonflowers@1")
    }

    /// 梅 整屏是最重的一张 (两万多个形状 + 两层逐像素滤镜): Release 下 < 1 s (5 次中位数)。
    func testPlumPortraitUnderOneSecond() throws {
        var rows: [Timing] = []
        for seed in ["42", "秋分-1", "2026", "a"] {
            let p = ZXArt.Procedural(generator: "nonflowers@1", seed: seed, variant: "梅")
            let (t, _) = Self.timed("梅-\(seed)-1206x2622", p, Self.paperInk, Self.phone, reps: Self.optimized ? 5 : 1)
            rows.append(t)
            if Self.optimized { XCTAssertLessThan(t.gen + t.render, 1000, "\(t.name) over 1 s") }
        }
        Self.log(rows, "梅 portrait")
    }

    /// 小组件家族的预渲染尺寸都能出图, 尺寸正确; 记录耗时与峰值内存 (phys_footprint 采样)。
    func testWidgetFamiliesAndMemory() throws {
        let sizes: [(String, CGSize)] = [("small", CGSize(width: 510, height: 510)), ("medium", CGSize(width: 1062, height: 498)),
                                         ("large", CGSize(width: 1062, height: 1116)), ("wallpaper", Self.phone)]
        var rows: [Timing] = []
        var mem = "\n== peak memory above baseline (phys_footprint, sampled) ==\n"
        for (fam, size) in sizes {
            for (g, v) in [("shanshui@1", "江岸"), ("nonflowers@1", "梅"), ("nonflowers@1", "荷")] {
                let p = ZXArt.Procedural(generator: g, seed: "秋分-1", variant: v)
                let name = "\(fam)-\(g.prefix(8))-\(v)-\(Int(size.width))x\(Int(size.height))"
                let (t, img) = Self.timed(name, p, Self.paperInk, size, reps: 1)
                let image = try XCTUnwrap(img, name)
                XCTAssertEqual(image.width, Int(size.width))
                XCTAssertEqual(image.height, Int(size.height))
                rows.append(t)
                if fam == "small" || fam == "large" { Self.writePNG(image, name + ".png") }
                let peak = Self.peakFootprint { _ = ZXArt.render(procedural: p, palette: Self.paperInk, pixelSize: size) }
                mem += String(format: "%@ | %.1f MB\n", name, Double(peak) / 1_048_576)
            }
        }
        Self.log(rows, "widget families")
        print(mem)
        if Self.writesShots {
            let url = Self.outDir.appendingPathComponent("memory-\(Self.optimized ? "release" : "debug").txt")
            try? mem.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    /// 在后台线程每 0.5 ms 采样一次 phys_footprint, 返回 work 期间的峰值 − 开始前。
    static func peakFootprint(_ work: () -> Void) -> Int64 {
        final class Box: @unchecked Sendable { var peak: Int64 = 0; var running = true; let lock = NSLock() }
        let box = Box()
        let base = footprint()
        box.peak = base
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            while box.lock.withLock({ box.running }) {
                let f = footprint()
                box.lock.withLock { if f > box.peak { box.peak = f } }
                usleep(500)
            }
            done.signal()
        }
        work()
        box.lock.withLock { box.running = false }
        done.wait()
        return max(0, box.peak - base)
    }

    // MARK: - 其他

    func testShanShuiOriginalSceneRenders() throws {
        let d = ZXArt.ShanShui.originalScene(seed: 42)
        let img = try XCTUnwrap(ZXArt.render(d, size: CGSize(width: d.width, height: d.height), scale: 1))
        Self.writePNG(img, "shanshui-42-original-scroll.png")
    }

    func testDrawingIsSendableAndRendersOffMain() async throws {
        let size = CGSize(width: 1012.0 / 3, height: 476.0 / 3)
        let d = await Task.detached { ZXArt.Flowers.generate(seed: 3, size: size, params: .init(season: .orchid)) }.value
        let w = await Task.detached { ZXArt.render(d, size: size, scale: 3)?.width }.value
        XCTAssertEqual(w, 1012)
    }
}
