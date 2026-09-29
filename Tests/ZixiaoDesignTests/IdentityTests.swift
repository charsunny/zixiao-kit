import SwiftUI
import XCTest
@testable import ZixiaoDesign

final class IdentityTests: XCTestCase {
    func testBothBundledIdentitiesDecode() throws {
        for which in ZXBundledIdentity.allCases {
            let identity = try ZXIdentity.bundled(which)
            XCTAssertFalse(identity.name.isEmpty, which.rawValue)
            XCTAssertFalse(identity.rationale.isEmpty, which.rawValue)
            XCTAssertNotNil(identity.slots.marker, which.rawValue)
        }
    }

    /// 内置身份是设计语言, 不是产品: 文件名、name 都用设计语言命名, 印文留给产品填。
    func testBundledIdentitiesAreProductNeutral() throws {
        XCTAssertEqual(ZXBundledIdentity.monochromeInk.rawValue, "monochrome-ink")
        XCTAssertEqual(ZXBundledIdentity.paperInkSeal.rawValue, "paper-ink-seal")
        XCTAssertEqual(try ZXIdentity.bundled(.monochromeInk).name, "单色墨系")
        XCTAssertEqual(try ZXIdentity.bundled(.paperInkSeal).name, "纸墨朱印")
        for which in ZXBundledIdentity.allCases {
            let identity = try ZXIdentity.bundled(which)
            XCTAssertNil(identity.slots.sealText, which.rawValue)
            for product in ["玄览", "苏轼", "东坡", "東坡", "xuanlan"] {
                XCTAssertFalse(identity.name.contains(product), which.rawValue)
            }
        }
    }

    /// 单色墨系: 深色按纸墨互换写在 JSON 里, 不由代码推导。
    func testMonochromeInkDarkSwapsPaperAndInk() throws {
        let p = try ZXIdentity.bundled(.monochromeInk).palette
        XCTAssertEqual(p.light.paper.description, "#F4F3F0")
        XCTAssertEqual(p.light.ink.description, "#121212")
        XCTAssertEqual(p.dark.paper, p.light.ink)
        XCTAssertEqual(p.dark.ink, p.light.paper)
        // 单色系没有强调色: 强调就是墨
        XCTAssertEqual(p.light.accent, p.light.ink)
        XCTAssertEqual(p.dark.accent, p.dark.ink)
        // 印不随纸墨互换; 深色提亮为 Flutter 深色版的朱
        XCTAssertEqual(p.light.seal.description, "#B8352E")
        XCTAssertEqual(p.dark.seal.description, "#E0776F")
        let rationale = try ZXIdentity.bundled(.monochromeInk).rationale
        XCTAssertTrue(rationale.contains("纸墨互换"))
        XCTAssertTrue(rationale.contains("#E0776F"))
    }

    func testPaperInkSealPalette() throws {
        let p = try ZXIdentity.bundled(.paperInkSeal).palette
        XCTAssertEqual(p.light.paper.description, "#F2EEE4")
        XCTAssertEqual(p.light.ink.description, "#272E2A")
        XCTAssertEqual(p.light.accent.description, "#963E31")
        XCTAssertEqual(p.light.seal.description, "#963E31")
        XCTAssertEqual(p.dark.paper.description, "#1C211F")
        XCTAssertEqual(p.dark.accent.description, "#E3A08B")
        XCTAssertEqual(p.accents?["江月青"]?.light.description, "#49697B")
        XCTAssertEqual(p.accents?["草堂绿"]?.dark.description, "#B3C399")
    }

    func testHexParsing() {
        XCTAssertEqual(ZXHex("#963E31")?.description, "#963E31")
        XCTAssertEqual(ZXHex("963e31")?.description, "#963E31")
        XCTAssertEqual(ZXHex("#12121280")?.alpha ?? 0, 128.0 / 255, accuracy: 0.0001)
        XCTAssertNil(ZXHex("#12345"))
        XCTAssertNil(ZXHex("#GG0000"))
        XCTAssertNil(ZXHex(""))
    }

    func testBadColorFailsAtDecode() throws {
        var json = try String(contentsOf: bundledURL(ZXBundledIdentity.monochromeInk.rawValue), encoding: .utf8)
        json = json.replacingOccurrences(of: "\"#F4F3F0\"", with: "\"#F4F3F\"")
        XCTAssertThrowsError(try ZXIdentity.decode(from: Data(json.utf8)))
    }

    func testRationaleIsRequired() throws {
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: bundledURL(ZXBundledIdentity.paperInkSeal.rawValue))) as? [String: Any])
        obj["rationale"] = nil
        let data = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertThrowsError(try ZXIdentity.decode(from: data))
    }

    func testFaceDescriptors() {
        XCTAssertEqual(ZXFace(descriptor: "Source Han Serif CN Bold"), .serifBold)
        XCTAssertEqual(ZXFace(descriptor: "Source Han Serif CN"), .serif)
        XCTAssertEqual(ZXFace(descriptor: "Noto Serif SC 200"), .serif)
        XCTAssertEqual(ZXFace(descriptor: "Noto Serif SC 700"), .serifBold)
        XCTAssertEqual(ZXFace(descriptor: "QiuHongKai"), .kai)
        XCTAssertEqual(ZXFace(descriptor: "system"), .system)
    }

    private func bundledURL(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "identities")
            ?? Bundle.module.url(forResource: name, withExtension: "json"))
    }
}

@MainActor
final class ThemeTests: XCTestCase {
    func testEnvironmentDefaultIsMonochromeLight() throws {
        let theme = EnvironmentValues().zxTheme
        XCTAssertEqual(theme.colorScheme, .light)
        XCTAssertEqual(theme.identity, try ZXIdentity.bundled(.monochromeInk))
    }

    func testInkAndPaperFollowSchemeAndAlpha() throws {
        let identity = try ZXIdentity.bundled(.monochromeInk)
        let light = ZXTheme(identity, colorScheme: .light)
        let dark = ZXTheme(identity, colorScheme: .dark)
        XCTAssertEqual(rgba(light.ink()), rgba(dark.paper()))
        XCTAssertEqual(rgba(light.paper()), rgba(dark.ink()))
        XCTAssertEqual(rgba(light.ink(0.55)).a, 0.55, accuracy: 0.01)
        XCTAssertEqual(rgba(light.ink()).r, 0x12 / 255.0, accuracy: 0.01)
        XCTAssertTrue(dark.isDark)
    }

    func testAlternateAccent() throws {
        let identity = try ZXIdentity.bundled(.paperInkSeal)
        let base = ZXTheme(identity, colorScheme: .light)
        let blue = ZXTheme(identity, colorScheme: .light, accentName: "江月青")
        let missing = ZXTheme(identity, colorScheme: .light, accentName: "不存在")
        XCTAssertEqual(rgba(base.accent).r, 0x96 / 255.0, accuracy: 0.01)
        XCTAssertEqual(rgba(blue.accent).b, 0x7B / 255.0, accuracy: 0.01)
        XCTAssertEqual(rgba(missing.accent), rgba(base.accent))
        // 备选强调色只换 accent, 印泥不动
        XCTAssertEqual(rgba(blue.seal), rgba(base.seal))
    }

    func testFacesComeFromIdentity() throws {
        let poet = ZXTheme(try ZXIdentity.bundled(.paperInkSeal), colorScheme: .light)
        XCTAssertEqual(poet.displayFace, .serifBold)
        XCTAssertEqual(poet.bodyFace, .serif)
        XCTAssertEqual(poet.uiFace, .system)
        let mono = ZXTheme(try ZXIdentity.bundled(.monochromeInk), colorScheme: .light)
        XCTAssertEqual(mono.uiFace, .serif)
    }

    private struct RGBA: Equatable { var r, g, b, a: Double }
    private func rgba(_ color: Color) -> RGBA {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func q(_ v: CGFloat) -> Double { (Double(v) * 1000).rounded() / 1000 }
        return RGBA(r: q(r), g: q(g), b: q(b), a: q(a))
    }
}
