//  ZXArtSceneReviewTests.swift — 山水审图样张 (只在设了 ZXART_REVIEW_DIR 时出图)
//
//  15 类场景各取一首代表诗, 按竖幅 / 横幅、浅色 / 深色出 PNG, 另拼一张竖幅浅色总览。
//  诗句框用淡线框出, 便于看景物与留白的关系。不做断言, 只给人看。
//      ZXART_REVIEW_DIR=/tmp/zxart-review swift test --filter ZXArtSceneReviewTests

import CoreGraphics
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
