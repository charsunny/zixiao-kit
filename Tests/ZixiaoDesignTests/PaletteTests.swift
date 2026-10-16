//  PaletteTests.swift — 所有随包身份的配色契约。
import Foundation
import SwiftUI
import XCTest
@testable import ZixiaoDesign

final class PaletteTests: XCTestCase {
    func testEveryBundledIdentityMeetsContrastContract() throws {
        for bundled in ZXBundledIdentity.allCases {
            let identity = try ZXIdentity.bundled(bundled)
            for scheme in [ColorScheme.light, .dark] {
                for contrast in [ColorSchemeContrast.standard, .increased] {
                    let v = ZXColorTokens(identity: identity, colorScheme: scheme, contrast: contrast).values
                    let context = "\(bundled.rawValue) \(scheme) \(contrast)"
                    XCTAssertGreaterThanOrEqual(v.ink.contrast(with: v.paper), 7, context)
                    // 第五支为 secondary；所有信息色同时检查纸面和卡面。
                    for color in [v.muted, v.accent, v.seal, v.secondary, v.success, v.warning, v.danger, v.info] {
                        for background in [v.paper, v.surface] {
                            XCTAssertGreaterThanOrEqual(color.contrast(with: background), 4.5,
                                                        "\(context) \(color) on \(background)")
                        }
                    }
                    XCTAssertGreaterThanOrEqual(v.accentOn.contrast(with: v.accent), 4.5, context)
                }
            }
        }
    }

    func testCasesAndResourceFilesAreOneToOne() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("Sources/ZixiaoDesign/Resources/identities")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }
        XCTAssertEqual(Set(files), Set(ZXBundledIdentity.allCases.map(\.rawValue)))
        XCTAssertEqual(files.count, ZXBundledIdentity.allCases.count)
        for bundled in ZXBundledIdentity.allCases {
            let identity = try ZXIdentity.bundled(bundled)
            XCTAssertFalse(identity.rationale.isEmpty)
            XCTAssertNil(identity.slots.sealText)
        }
        XCTAssertEqual(ZXPaletteCatalog.entries.count, 7)
        XCTAssertEqual(ZXBundledIdentity.allCases.count, 9)
        XCTAssertEqual(ZXPaletteCatalog.entries.first?.bundled, .yaqing)
        XCTAssertFalse(ZXPaletteCatalog.entries.contains { $0.bundled == .paperInkSeal })
        XCTAssertNoThrow(try ZXIdentity.bundled(.paperInkSeal))
    }

    func testFiveSeasons() {
        XCTAssertEqual(ZXPaletteCatalog.palette(for: .spring), .canglang)
        XCTAssertEqual(ZXPaletteCatalog.palette(for: .summer), .rouge)
        XCTAssertEqual(ZXPaletteCatalog.palette(for: .lateSummer), .xiangLeaf)
        XCTAssertEqual(ZXPaletteCatalog.palette(for: .autumn), .moonWhite)
        XCTAssertEqual(ZXPaletteCatalog.palette(for: .winter), .qingdai)
    }

    func testSeasonalLabelsAndRenamedPaletteSources() throws {
        let labels: [(ZXSeasonTint, String)] = [
            (.spring, "随节气 · 春 · 苍筤"), (.summer, "随节气 · 夏 · 胭脂"),
            (.lateSummer, "随节气 · 长夏 · 缃叶"), (.autumn, "随节气 · 秋 · 月白"),
            (.winter, "随节气 · 冬 · 青黛")
        ]
        for (season, label) in labels {
            XCTAssertEqual(ZXPaletteCatalog.seasonalLabel(for: season), label)
            let palette = try ZXIdentity.bundled(ZXPaletteCatalog.palette(for: season))
            let entry = try XCTUnwrap(ZXPaletteCatalog.entries.first { $0.name == palette.name })
            XCTAssertEqual(entry.light, palette.palette.light)
            XCTAssertEqual(entry.dark, palette.palette.dark)
        }
        XCTAssertEqual(ZXBundledIdentity.ousi.rawValue, "ousi")
        XCTAssertEqual(ZXBundledIdentity.qingdai.rawValue, "qingdai")
        let ousi = try ZXIdentity.bundled(.ousi)
        XCTAssertEqual(ousi.name, "藕丝")
        for source in ["粉霞红绶藕丝裙", "李贺", "天上谣", "681fe831-2fb0-4bae-bb2a-41d499309c7a"] {
            XCTAssertTrue(ousi.rationale.contains(source))
        }
        let qingdai = try ZXIdentity.bundled(.qingdai)
        XCTAssertEqual(qingdai.name, "青黛")
        for source in ["一螺青黛镜中心", "雍陶", "题君山", "2f5e562a-ff78-42e3-8c1b-d9b3686907c5"] {
            XCTAssertTrue(qingdai.rationale.contains(source))
        }
    }

    func testFourthDraftSixPrimarySlots() throws {
        let fixtures: [(ZXBundledIdentity, String, String)] = [
            (.yaqing, "#F4F5F3 #121E21 #3E625C #8A5A3A #A63A2B #5A6364", "#121E21 #F2F2E8 #AEC5C0 #D9B08C #EE9C88 #AAAEA8"),
            (.moonWhite, "#F3F6F7 #1F2A33 #2D5876 #8A5532 #B0412D #636B72", "#111A20 #E4ECEE #9EC3D8 #D9A47C #EE9C88 #A0A9AC"),
            (.xiangLeaf, "#F6F5F2 #2A231C #7A5718 #2A3F5F #A63A28 #6B6660", "#17150F #F0E8D6 #E0BF6E #A8BBD6 #EE9C88 #ABA496"),
            (.canglang, "#F3F5F2 #1E2922 #2E6A4E #94562F #B03C2A #626A65", "#0F1612 #E3EBE2 #8FCBA8 #D9A27A #EE9C88 #9FA79F"),
            (.ousi, "#F6F4F5 #2D2027 #6D3F5A #5F6E33 #A2333A #6D6469", "#161115 #F0E5EB #D7AECB #C2CC8E #F0A0A6 #AAA1A7"),
            (.qingdai, "#F3F4F5 #1B2636 #2B4566 #7E6024 #A7392A #606873", "#101A2B #E8E4D8 #D8B56C #A9BEDB #EE9C88 #A3A3A1"),
            (.rouge, "#F7F5F4 #2A1A18 #9D2933 #2F6B57 #B5452C #6C605E", "#170F0F #F3E7E1 #F0A0A3 #8FCBB4 #F4A98C #ADA29E")
        ]
        for (bundled, light, dark) in fixtures {
            let identity = try ZXIdentity.bundled(bundled)
            for (swatch, expected) in [(identity.palette.light, light), (identity.palette.dark, dark)] {
                XCTAssertEqual([swatch.paper, swatch.ink, swatch.accent, try XCTUnwrap(swatch.secondary),
                                swatch.seal, swatch.muted].map(\.description).joined(separator: " "), expected)
            }
        }
        let rationale = try ZXIdentity.bundled(.yaqing).rationale
        for source in ["张矩", "虞美人", "粉褪香腮零乱、鬓鸦青", "4a0d028f-eb81-5af6-b2a5-8af79cc3ff83",
                       "#121E21", "#AEC5C0", "#72968F", "#F2F2E8"] {
            XCTAssertTrue(rationale.contains(source))
        }
    }

    func testApplyingPalettePreservesProductTypeAndSlots() throws {
        let original = try ZXIdentity.bundled(.monochromeInk)
        let product = ZXIdentity(name: "测试产品", rationale: "测试身份", palette: original.palette,
                                 type: .init(display: "system", body: "system", ui: "system"),
                                 slots: .init(surface: "custom", rule: .frame, marker: .dot, sealText: "测试"))
        for bundled in ZXBundledIdentity.allCases {
            let applied = try product.applyingPalette(bundled)
            XCTAssertEqual(applied.type, product.type)
            XCTAssertEqual(applied.slots, product.slots)
            XCTAssertEqual(applied.palette, try ZXIdentity.bundled(bundled).palette)
            XCTAssertTrue(applied.rationale.contains(product.rationale))
        }
    }

    func testHighContrastOverridesAndLegacyFallback() throws {
        let base = try ZXIdentity.bundled(.paperInkSeal)
        let other = try ZXIdentity.bundled(.moonWhite)
        let custom = ZXIdentity(name: base.name, rationale: base.rationale,
            palette: .init(light: base.palette.light, dark: base.palette.dark,
                           highContrastLight: other.palette.light, highContrastDark: other.palette.dark),
            type: base.type, slots: base.slots)
        for scheme in [ColorScheme.light, .dark] {
            XCTAssertEqual(ZXColorTokens(identity: custom, colorScheme: scheme, contrast: .increased).values,
                           ZXColorTokens(identity: other, colorScheme: scheme).values)
            XCTAssertEqual(ZXColorTokens(identity: base, colorScheme: scheme, contrast: .increased).values,
                           ZXColorTokens(identity: base, colorScheme: scheme).values)
        }
    }
}
