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
    }

    func testFiveSeasons() {
        XCTAssertEqual(ZXPaletteCatalog.palette(for: .spring), .canglang)
        XCTAssertEqual(ZXPaletteCatalog.palette(for: .summer), .rouge)
        XCTAssertEqual(ZXPaletteCatalog.palette(for: .lateSummer), .xiangLeaf)
        XCTAssertEqual(ZXPaletteCatalog.palette(for: .autumn), .moonWhite)
        XCTAssertEqual(ZXPaletteCatalog.palette(for: .winter), .daiBlue)
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
