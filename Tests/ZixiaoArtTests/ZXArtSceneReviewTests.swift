//  ZXArtSceneReviewTests.swift — 山水审图样张 (只在设了 ZXART_REVIEW_DIR 时出图)
//
//  15 类场景各取一首代表诗, 按竖幅 / 横幅、浅色 / 深色出 PNG, 另拼一张竖幅浅色总览。
//  诗句框用淡线框出, 便于看景物与留白的关系。不做断言, 只给人看。
//      ZXART_REVIEW_DIR=/tmp/zxart-review swift test --filter ZXArtSceneReviewTests

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ZixiaoArt

final class ZXArtSceneReviewTests: XCTestCase {
    static let poems: [(id: String, title: String, text: String)] = [
        ("retreat", "山居秋暝", "空山新雨后，天气晚来秋。明月松间照，清泉石上流。竹喧归浣女，莲动下渔舟。"),
        ("fishing", "渔歌子", "西塞山前白鹭飞，桃花流水鳜鱼肥。青箬笠，绿蓑衣，斜风细雨不须归。"),
        ("water-town", "江南春", "千里莺啼绿映红，水村山郭酒旗风。南朝四百八十寺，多少楼台烟雨中。"),
        ("farewell", "送元二使安西", "渭城朝雨浥轻尘，客舍青青柳色新。劝君更尽一杯酒，西出阳关无故人。"),
        ("village", "归园田居·其一", "暧暧远人村，依依墟里烟。狗吠深巷中，鸡鸣桑树颠。"),
        ("spring", "江畔独步寻花·其六", "黄四娘家花满蹊，千朵万朵压枝低。留连戏蝶时时舞，自在娇莺恰恰啼。"),
        ("lotus", "小池", "泉眼无声惜细流，树阴照水爱晴柔。小荷才露尖尖角，早有蜻蜓立上头。"),
        ("autumn", "天净沙·秋思", "枯藤老树昏鸦，小桥流水人家，古道西风瘦马。夕阳西下，断肠人在天涯。"),
        ("winter", "逢雪宿芙蓉山主人", "日暮苍山远，天寒白屋贫。柴门闻犬吠，风雪夜归人。"),
        ("moon", "静夜思", "床前明月光，疑是地上霜。举头望明月，低头思故乡。"),
        ("temple", "题破山寺后禅院", "清晨入古寺，初日照高林。竹径通幽处，禅房花木深。"),
        ("courtyard", "蝶恋花·庭院深深深几许", "庭院深深深几许，杨柳堆烟，帘幕无重数。"),
        ("historic", "登幽州台歌", "前不见古人，后不见来者。念天地之悠悠，独怆然而涕下。"),
        ("desert", "使至塞上", "大漠孤烟直，长河落日圆。"),
        ("ocean", "望月怀远", "海上生明月，天涯共此时。"),
    ]

    func testSceneReviewSheets() throws {
        guard let dir = ProcessInfo.processInfo.environment["ZXART_REVIEW_DIR"] else {
            throw XCTSkip("设 ZXART_REVIEW_DIR 才出审图样张")
        }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let seedSuffix = ProcessInfo.processInfo.environment["ZXART_REVIEW_SEED"] ?? "review"
        let formats: [(String, CGSize)] = [("portrait", CGSize(width: 750, height: 1000)),
                                           ("wide", CGSize(width: 1200, height: 675))]
        let palettes: [(String, ZXArt.Palette)] = [("light", .paperInk), ("dark", .night)]
        var overview: [CGImage] = []
        for poem in Self.poems {
            let selection = ZXArt.poetryScene(text: poem.text, title: poem.title)
            for (format, size) in formats {
                for (tone, palette) in palettes {
                    let procedural = selection.paintingProcedural(seed: "\(seedSuffix)-\(poem.id)",
                                                                  verseSide: "right", columns: 2, chars: 7)
                    let image = try XCTUnwrap(ZXArt.render(procedural: procedural, palette: palette, pixelSize: size),
                                              poem.id)
                    let framed = try framedWithVerse(image, procedural: procedural, size: size, palette: palette)
                    try write(framed, to: out.appendingPathComponent("\(poem.id)-\(format)-\(tone).png"))
                    if format == "portrait" && tone == "light" { overview.append(framed) }
                }
            }
        }
        try write(try contactSheet(overview, columns: 5, cell: CGSize(width: 300, height: 400)),
                  to: out.appendingPathComponent("overview-portrait-light.png"))
    }

    /// 树谱: 六种树 × 四个种子, 看同种之间的形态变化。
    func testTreeReviewSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["ZXART_REVIEW_DIR"] else {
            throw XCTSkip("设 ZXART_REVIEW_DIR 才出审图样张")
        }
        let kinds: [ZXArt.SceneMotif] = [.pine, .blossom, .layeredTree, .maple, .bareTree, .willow]
        let cell = 200.0
        var shapes: [ZXArt.Shape] = []
        for (row, kind) in kinds.enumerated() {
            for col in 0..<4 {
                let engine = ShanShuiEngine(seed: .init("tree-review-\(kind.rawValue)-\(col)"))
                let canv = engine.paintingTree(kind).map { poly -> ZXArt.SSPoly in
                    var q = poly
                    q.p = poly.p.map { ZXArt.P($0.x * 0.95 + Double(col) * cell + 30, $0.y * 0.95 + Double(row) * cell + 10) }
                    return q
                }
                ZXArt.appendShapes(canv, palette: .paperInk, into: &shapes)
            }
        }
        let drawing = ZXArt.Drawing(width: cell * 4, height: cell * Double(kinds.count),
                                    background: ZXArt.Palette.paperInk.paper, layers: [.init(shapes: shapes)])
        let image = try XCTUnwrap(ZXArt.render(drawing, pixelWidth: 800, pixelHeight: 1200))
        try write(image, to: URL(fileURLWithPath: dir).appendingPathComponent("trees.png"))
    }

    /// 岸谱: 汀渚、陡岸、边角石矶各四个种子，保留模型的高宽差异。
    func testBankReviewSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["ZXART_REVIEW_DIR"] else {
            throw XCTSkip("设 ZXART_REVIEW_DIR 才出审图样张")
        }
        var shapes: [ZXArt.Shape] = []
        for (row, style) in [ShanShuiEngine.BankStyle.shoal, .cliff, .headland].enumerated() {
            for column in 0..<4 {
                let engine = ShanShuiEngine(seed: .init("bank-outline-\(column)"))
                let canv = engine.paintingSlope(style).map { poly -> ZXArt.SSPoly in
                    var p = poly
                    p.p = poly.p.map { ZXArt.P($0.x * 0.78 + Double(column) * 290 + 10,
                        $0.y * 0.78 + Double(row) * 145 + 15) }
                    p.wid *= 0.78
                    return p
                }
                ZXArt.appendShapes(canv, palette: .paperInk, into: &shapes)
            }
        }
        let drawing = ZXArt.Drawing(width: 1160, height: 435, background: ZXArt.Palette.paperInk.paper,
            layers: [.init(shapes: shapes)])
        let image = try XCTUnwrap(ZXArt.render(drawing, pixelWidth: 1160, pixelHeight: 435))
        try write(image, to: URL(fileURLWithPath: dir).appendingPathComponent("banks.png"))
    }

    /// 景物图谱: 每种景物单独画六个种子, 按同一比例排成一行, 看意象准不准、种子之间有没有变化。
    /// 每页 10 行, 左栏写景物名; 格内按原始尺寸统一缩放 (scale), 大小关系保留。
    func testElementAtlasSheets() throws {
        guard let dir = ProcessInfo.processInfo.environment["ZXART_REVIEW_DIR"] else {
            throw XCTSkip("设 ZXART_REVIEW_DIR 才出审图样张")
        }
        typealias Make = (ShanShuiEngine) -> ZXArt.SSCanv
        var entries: [(String, Make)] = ZXArt.SceneMotif.allCases.map { motif in
            (motif.rawValue, { engine in
                switch motif {
                case .stream: return engine.paintingChannel(width: 260, height: 120)
                case .window: return engine.paintingWindow(embedded: true)
                default: return engine.paintingAsset(motif)
                }
            })
        }
        entries.append(("crow.perched", { $0.paintingPerchedCrow() }))
        for style in [ShanShuiEngine.BankStyle.shoal, .cliff, .headland] {
            entries.append(("slope.\(style)", { $0.paintingSlope(style) }))
        }
        for form in PaintingMountainProfile.Form.allCases {
            entries.append(("massif.\(form)", { $0.paintingMountain(form: form) }))
        }
        entries += [("massif.terraced", { $0.paintingMountain(form: .folded, terraced: true) }),
                    ("farShore", { $0.paintingFarShore() }),
                    ("distant.0", { $0.paintingDistant(0) }), ("distant.1", { $0.paintingDistant(1) }),
                    ("rock", { $0.paintingRock() }), ("dunes.far", { $0.paintingDunes(far: true) }),
                    ("longRiver", { $0.paintingLongRiver() }), ("riverRibbon", { $0.paintingRiverRibbon() }),
                    ("channel.river", { $0.paintingChannel(width: 320, height: 120, river: true) }),
                    ("reflection", { $0.paintingReflection(width: 200, height: 80) })]
        for kind in PaintingWaterKind.allCases {
            entries.append(("water.\(kind.rawValue)", { $0.paintingSurface(kind, width: 320, height: 140) }))
        }
        let label = 150.0, cell = CGSize(width: 190, height: 150), columns = 6, perPage = 10
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for page in stride(from: 0, to: entries.count, by: perPage) {
            let rows = Array(entries[page..<min(entries.count, page + perPage)])
            var shapes: [ZXArt.Shape] = []
            var notes: [String] = []
            for (row, entry) in rows.enumerated() {
                let canvases = (0..<columns).map { entry.1(ShanShuiEngine(seed: .init("atlas-\(entry.0)-\($0)"))) }
                let boxes = canvases.map { canv -> CGRect in
                    let xs = canv.flatMap { $0.p.map(\.x) }, ys = canv.flatMap { $0.p.map(\.y) }
                    guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return .zero }
                    return CGRect(x: x0, y: y0, width: max(1, x1 - x0), height: max(1, y1 - y0))
                }
                // One scale per row, so the seeds of one element keep their size differences.
                let scale = min(1.6, boxes.map { min((cell.width - 16) / $0.width, (cell.height - 16) / $0.height) }.min() ?? 1)
                notes.append(["rain", "snow"].contains(entry.0) ? "\(entry.0): overlay" : String(format: "%@  ×%.2f", entry.0, scale))
                for (col, canv) in canvases.enumerated() {
                    let box = boxes[col]
                    let ox = label + Double(col) * cell.width + (cell.width - box.width * scale) / 2
                    let oy = Double(row) * cell.height + cell.height - 8 - box.height * scale
                    let placed = canv.map { poly -> ZXArt.SSPoly in
                        var q = poly
                        q.p = poly.p.map { ZXArt.P(($0.x - box.minX) * scale + ox, ($0.y - box.minY) * scale + oy) }
                        q.wid *= scale
                        return q
                    }
                    ZXArt.appendPaintingShapes(placed, motif: ZXArt.SceneMotif(rawValue: entry.0), palette: .paperInk, into: &shapes)
                }
            }
            let size = CGSize(width: label + cell.width * Double(columns), height: cell.height * Double(rows.count))
            let drawing = ZXArt.Drawing(width: size.width, height: size.height, background: ZXArt.Palette.paperInk.paper,
                                        layers: [.init(shapes: shapes)])
            let image = try XCTUnwrap(ZXArt.render(drawing, pixelWidth: Int(size.width), pixelHeight: Int(size.height)))
            let ctx = try bitmap(size)
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
            ctx.setStrokeColor(CGColor(red: 0.85, green: 0.25, blue: 0.2, alpha: 0.25))
            ctx.setLineWidth(1)
            for row in 1..<rows.count { ctx.stroke(CGRect(x: 0, y: Double(row) * cell.height, width: size.width, height: 0)) }
            let font = CTFontCreateWithName("Menlo" as CFString, 13, nil)
            for (row, note) in notes.enumerated() {
                let text = NSAttributedString(string: note, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0.7, green: 0.15, blue: 0.1, alpha: 1)])
                ctx.textPosition = CGPoint(x: 8, y: size.height - Double(row) * cell.height - 22)
                CTLineDraw(CTLineCreateWithAttributedString(text), ctx)
            }
            try write(try XCTUnwrap(ctx.makeImage()),
                      to: out.appendingPathComponent(String(format: "elements-%02d.png", page / perPage + 1)))
        }
    }

    /// Seven groups rendered by the production stage: the crop changes framing, never proportions.
    func testGroupReviewSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["ZXART_REVIEW_DIR"] else {
            throw XCTSkip("设 ZXART_REVIEW_DIR 才出审图样张")
        }
        let groups: [(String, ZXArt.PoetryScene, [ZXArt.SceneMotif])] = [
            ("小桥流水人家", .waterTown, [.bridge, .stream, .house, .willow]),
            ("古道西风瘦马", .autumnTravel, [.path, .traveler, .horse]),
            ("枯藤老树昏鸦", .autumnTravel, [.oldTree, .vine, .crow]),
            ("渔舟", .fishing, [.angler, .reeds]),
            ("山居", .village, [.hut, .fence, .cookingSmoke, .pine]),
            ("长亭送别", .farewell, [.pavilion, .willow, .traveler, .path]),
            ("山寺", .temple, [.templeGate, .pagoda, .bamboo])
        ]
        let cell = CGSize(width: 400, height: 260)
        var images: [CGImage] = []
        for (title, scene, motifs) in groups {
            for seed in 0..<4 {
                let selection = ZXArt.SceneSelection(scene: scene, options: .init(motifs: motifs), matched: [])
                let recipe = selection.paintingProcedural(seed: "group-\(scene.rawValue)-\(seed)",
                    verseSide: nil, composition: .corner)
                let size = CGSize(width: 1000, height: 750)
                let drawing = try XCTUnwrap(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: size))
                let image = try XCTUnwrap(ZXArt.render(drawing, pixelWidth: 1000, pixelHeight: 750))
                let focus = drawing.sceneElements.filter { motifs.map(\.rawValue).contains($0.motif) || $0.motif == "groundBank" }
                    .reduce(CGRect.null) { $0.union($1.bounds.cgRect) }
                let crop = CGRect(x: focus.minX * size.width, y: focus.minY * size.height,
                                  width: focus.width * size.width, height: focus.height * size.height)
                    .insetBy(dx: -16, dy: -16).intersection(CGRect(origin: .zero, size: size))
                let detail = try XCTUnwrap(image.cropping(to: crop.integral))
                let ctx = try bitmap(cell)
                ctx.setFillColor(CGColor(red: 0.953, green: 0.937, blue: 0.898, alpha: 1))
                ctx.fill(CGRect(origin: .zero, size: cell))
                let scale = min((cell.width - 12) / Double(detail.width), (cell.height - 34) / Double(detail.height))
                let width = Double(detail.width) * scale, height = Double(detail.height) * scale
                ctx.draw(detail, in: CGRect(x: (cell.width - width) / 2, y: 8, width: width, height: height))
                let label = NSAttributedString(string: "\(title) · \(seed + 1)", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("PingFangSC-Regular" as CFString, 15, nil),
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.3, alpha: 1)])
                ctx.textPosition = CGPoint(x: 10, y: cell.height - 22)
                CTLineDraw(CTLineCreateWithAttributedString(label), ctx)
                images.append(try XCTUnwrap(ctx.makeImage()))
            }
        }
        try write(try contactSheet(images, columns: 4, cell: cell),
                  to: URL(fileURLWithPath: dir).appendingPathComponent("groups.png"))
    }

    /// 种子谱: 每类场景取四个种子的竖幅浅色, 看同一首诗换种子后构图是否真的变化。
    func testSeedVarietySheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["ZXART_REVIEW_DIR"] else {
            throw XCTSkip("设 ZXART_REVIEW_DIR 才出审图样张")
        }
        let size = CGSize(width: 375, height: 500)
        var images: [CGImage] = []
        for poem in Self.poems {
            let selection = ZXArt.poetryScene(text: poem.text, title: poem.title)
            for k in 0..<4 {
                let procedural = selection.paintingProcedural(seed: "variety-\(k)-\(poem.id)",
                                                              verseSide: "right", columns: 2, chars: 7)
                images.append(try XCTUnwrap(ZXArt.render(procedural: procedural, palette: .paperInk, pixelSize: size)))
            }
        }
        // 15 rows × 4 seeds, split in three pages of five scenes so each page stays legible.
        for page in 0..<3 {
            let slice = Array(images[(page * 20)..<min(images.count, page * 20 + 20)])
            try write(try contactSheet(slice, columns: 4, cell: CGSize(width: 300, height: 400)),
                      to: URL(fileURLWithPath: dir).appendingPathComponent("variety-\(page + 1).png"))
        }
    }

    /// 在画上用淡线框出诗句框。
    private func framedWithVerse(_ image: CGImage, procedural: ZXArt.Procedural, size: CGSize,
                                 palette: ZXArt.Palette) throws -> CGImage {
        let ctx = try bitmap(size)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        if let verse = procedural.verseLayout(pixelSize: size) {
            let r = verse.rect(in: size)
            ctx.setStrokeColor(CGColor(red: 0.85, green: 0.25, blue: 0.2, alpha: 0.35))
            ctx.setLineWidth(1)
            ctx.stroke(CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height))
        }
        return try XCTUnwrap(ctx.makeImage())
    }

    private func contactSheet(_ images: [CGImage], columns: Int, cell: CGSize) throws -> CGImage {
        let rows = (images.count + columns - 1) / columns
        let size = CGSize(width: cell.width * Double(columns), height: cell.height * Double(rows))
        let ctx = try bitmap(size)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.interpolationQuality = .high
        for (i, image) in images.enumerated() {
            let col = i % columns, row = i / columns
            let rect = CGRect(x: Double(col) * cell.width, y: size.height - Double(row + 1) * cell.height,
                              width: cell.width, height: cell.height).insetBy(dx: 2, dy: 2)
            ctx.draw(image, in: rect)
        }
        return try XCTUnwrap(ctx.makeImage())
    }

    private func bitmap(_ size: CGSize) throws -> CGContext {
        try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
}
