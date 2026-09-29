import SwiftUI
import XCTest
@testable import ZixiaoDesign

/// token 分组: 颜色派生 (两套身份 × 浅深)、字号阶、间距圆角、动效。
final class ColorTokenTests: XCTestCase {
    private let schemes: [ColorScheme] = [.light, .dark]

    private func tokens(_ which: ZXBundledIdentity, _ scheme: ColorScheme, accent: String? = nil) throws -> ZXColorTokens.Values {
        ZXColorTokens(identity: try ZXIdentity.bundled(which), colorScheme: scheme, accentName: accent).values
    }

    /// 压在 accent 上的字 ≥ 4.5:1 (WCAG 正文)。含系列里的备选强调色。
    func testAccentOnContrast() throws {
        for which in ZXBundledIdentity.allCases {
            let identity = try ZXIdentity.bundled(which)
            let names: [String?] = [nil] + (identity.palette.accents.map { Array($0.keys) } ?? [])
            for scheme in schemes {
                for name in names {
                    let v = try tokens(which, scheme, accent: name)
                    let ratio = v.accentOn.contrast(with: v.accent.composited(over: v.bg))
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(which) \(scheme) \(name ?? "默认") → \(ratio)")
                }
            }
        }
    }

    /// 状态色与 neutral 上压 statusOn 的字 ≥ 4.5:1; 正文压在纸与卡面上也 ≥ 4.5:1。
    func testStatusAndTextContrast() throws {
        for which in ZXBundledIdentity.allCases {
            for scheme in schemes {
                let v = try tokens(which, scheme)
                let fills = [("success", v.success), ("warning", v.warning), ("danger", v.danger),
                             ("info", v.info), ("neutral", v.neutral)]
                for (name, fill) in fills {
                    let ratio = v.statusOn.contrast(with: fill.composited(over: v.bg))
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(which) \(scheme) \(name) → \(ratio)")
                }
                XCTAssertGreaterThanOrEqual(v.textPrimary.contrast(with: v.bg), 4.5)
                // 次级文字压在纸与卡面上也要够正文的 4.5:1 (单色墨系浅色 muted 因此由 #757471 加深为 #6E6D6A)
                XCTAssertGreaterThanOrEqual(v.textSecondary.contrast(with: v.bg), 4.5,
                                            "\(which) \(scheme) textSecondary → \(v.textSecondary.contrast(with: v.bg))")
                XCTAssertGreaterThanOrEqual(v.textSecondary.contrast(with: v.surface), 4.5, "\(which) \(scheme)")
                XCTAssertGreaterThanOrEqual(v.textPrimary.contrast(with: v.surface), 4.5)
                XCTAssertGreaterThanOrEqual(v.textPrimary.contrast(with: v.surfaceElevated), 4.5)
            }
        }
    }

    /// 单色墨系: 强调就是墨, 反白是纸; 全篇唯一的朱只给印与 danger; 其余状态都是墨。
    func testMonochromeDerivation() throws {
        for scheme in schemes {
            let v = try tokens(.monochromeInk, scheme)
            XCTAssertEqual(v.accent, v.ink, "\(scheme)")
            XCTAssertEqual(v.accentOn, v.paper, "\(scheme)")
            XCTAssertEqual(v.textPrimary, v.ink)
            XCTAssertEqual(v.bg, v.paper)
            XCTAssertEqual(v.danger, v.seal)
            XCTAssertEqual(v.success, v.ink)
            XCTAssertEqual(v.statusOn, v.paper)
            XCTAssertEqual(v.secondary, v.muted)
            XCTAssertEqual(v.separator, v.rule)
            // warning / info 是墨压在纸上的不透明色: 没有色相 (R=G=B 左右), 且比纸更接近墨
            for status in [v.warning, v.info] {
                XCTAssertEqual(status.alpha, 1)
                XCTAssertEqual(status.red, status.green, accuracy: 0.01)
                XCTAssertLessThan(abs(status.relativeLuminance - v.ink.relativeLuminance),
                                  abs(status.relativeLuminance - v.paper.relativeLuminance))
            }
        }
    }

    func testPaperInkSealDerivation() throws {
        let light = try tokens(.paperInkSeal, .light)
        XCTAssertEqual(light.accent.description, "#963E31")
        XCTAssertEqual(light.accentOn, light.paper)
        XCTAssertEqual(light.secondary.description, "#49697B")
        XCTAssertEqual(light.success.description, "#5B6B48")
        XCTAssertEqual(light.warning.description, "#8A5E14")
        XCTAssertEqual(light.danger.description, "#A8321F")
        XCTAssertEqual(light.info.description, "#3D5566")
        let dark = try tokens(.paperInkSeal, .dark)
        XCTAssertEqual(dark.accent.description, "#E3A08B")
        // 深色下 accent 是浅色, 反白要用纸 (此时是深色)
        XCTAssertEqual(dark.accentOn, dark.paper)
        XCTAssertEqual(dark.danger.description, "#E88B78")
        // 备选强调色只换 accent
        let blue = try tokens(.paperInkSeal, .light, accent: "江月青")
        XCTAssertEqual(blue.accent.description, "#49697B")
        XCTAssertEqual(blue.seal, light.seal)
    }

    /// 浅色下抬起的层就是卡面 (靠影子分层); 深色下比卡面亮一档 (暗底上影子看不见)。
    func testSurfaceElevated() throws {
        for which in ZXBundledIdentity.allCases {
            let light = try tokens(which, .light)
            XCTAssertEqual(light.surfaceElevated, light.surface)
            let dark = try tokens(which, .dark)
            XCTAssertGreaterThan(dark.surfaceElevated.relativeLuminance, dark.surface.relativeLuminance)
            XCTAssertEqual(dark.surfaceElevated.alpha, 1, "减少透明度时玻璃的替身, 必须不透明")
            XCTAssertEqual(dark.shadow, dark.night)
            XCTAssertEqual(light.shadow, light.ink)
        }
    }

    /// 旧 JSON (没有五个新槽) 仍能解码, 并按表回落。
    func testMissingStatusSlotsFallBack() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "paper-ink-seal", withExtension: "json", subdirectory: "identities")
            ?? Bundle.module.url(forResource: "paper-ink-seal", withExtension: "json"))
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var palette = try XCTUnwrap(obj["palette"] as? [String: Any])
        for scheme in ["light", "dark"] {
            var swatch = try XCTUnwrap(palette[scheme] as? [String: Any])
            for key in ["secondary", "success", "warning", "danger", "info"] { swatch[key] = nil }
            palette[scheme] = swatch
        }
        obj["palette"] = palette
        let identity = try ZXIdentity.decode(from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(identity.palette.light.success)
        let v = ZXColorTokens(identity: identity, colorScheme: .light).values
        XCTAssertEqual(v.secondary, v.muted)
        XCTAssertEqual(v.success, v.ink)
        XCTAssertEqual(v.warning, v.ink)
        XCTAssertEqual(v.info, v.ink)
        XCTAssertEqual(v.danger, v.seal)
    }

    func testHexArithmetic() throws {
        let ink = try XCTUnwrap(ZXHex("#000000"))
        let paper = try XCTUnwrap(ZXHex("#FFFFFF"))
        XCTAssertEqual(ink.contrast(with: paper), 21, accuracy: 0.01)
        XCTAssertEqual(paper.contrast(with: paper), 1, accuracy: 0.0001)
        let half = ink.opacity(0.5).composited(over: paper)
        XCTAssertEqual(half.red, 0.5, accuracy: 0.001)
        XCTAssertEqual(half.alpha, 1)
        XCTAssertEqual(ink.mixed(with: paper, amount: 0.25).green, 0.25, accuracy: 0.001)
        XCTAssertEqual(ZXHex(red: 2, green: -1, blue: 0.5).description, "#FF0080")
    }
}

@MainActor
final class ThemeTokenTests: XCTestCase {
    /// 旧的平铺属性与 color 组同义。
    func testFlatPropertiesMirrorColorGroup() throws {
        for which in ZXBundledIdentity.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let theme = ZXTheme(try ZXIdentity.bundled(which), colorScheme: scheme)
                XCTAssertEqual(rgba(theme.surface), rgba(theme.color.surface))
                XCTAssertEqual(rgba(theme.muted), rgba(theme.color.muted))
                XCTAssertEqual(rgba(theme.border), rgba(theme.color.border))
                XCTAssertEqual(rgba(theme.track), rgba(theme.color.track))
                XCTAssertEqual(rgba(theme.accent), rgba(theme.color.accent))
                XCTAssertEqual(rgba(theme.seal), rgba(theme.color.seal))
                XCTAssertEqual(rgba(theme.rule), rgba(theme.color.rule))
                XCTAssertEqual(rgba(theme.night), rgba(theme.color.night))
                XCTAssertEqual(rgba(theme.ink()), rgba(theme.color.textPrimary))
                XCTAssertEqual(rgba(theme.paper()), rgba(theme.color.bg))
            }
        }
    }

    func testTypeTokensFollowIdentityFaces() throws {
        let mono = ZXTheme(try ZXIdentity.bundled(.monochromeInk), colorScheme: .light)
        XCTAssertEqual(mono.type.displayFace, .serifBold)
        // 有意与契约不同: 单色墨系的正文也是宋体
        XCTAssertEqual(mono.type.bodyFace, .serif)
        XCTAssertEqual(mono.type.face(for: .footnote), .serif, "单色墨系的 ui 字族也是宋")
        // 纸墨朱印: ui = system, 操作层小字 (footnote / caption) 走无衬线, 正文仍是宋
        let poet = ZXTheme(try ZXIdentity.bundled(.paperInkSeal), colorScheme: .light)
        XCTAssertEqual(poet.type.face(for: .footnote), .system)
        XCTAssertEqual(poet.type.face(for: .caption), .system)
        XCTAssertEqual(poet.type.face(for: .body), .serif)
        XCTAssertEqual(poet.type.face(for: .subhead), .serif)
        XCTAssertEqual(poet.type.face(for: .title2), .serifBold)
        XCTAssertEqual(ZXTypeRole.allCases.filter(\.usesUIFace), [.footnote, .caption])
        XCTAssertEqual(ZXTypeTokens(displayFace: .serifBold, bodyFace: .serif).face(for: .caption), .serif,
                       "不给 ui 字族时与正文同族")
        let bold = ZXTheme(try ZXIdentity.bundled(.monochromeInk), colorScheme: .light, legibilityWeight: .bold)
        XCTAssertEqual(bold.type.legibilityWeight, .bold)
    }

    func testTypeScale() {
        let sizes = ZXTypeRole.allCases.map(\.size)
        XCTAssertEqual(sizes, [34, 28, 22, 20, 17, 17, 16, 15, 13, 12])
        XCTAssertEqual(ZXTypeRole.allCases.filter(\.usesDisplayFace), [.display, .title1, .title2, .title3])
        XCTAssertEqual(ZXTypeRole.caption.size, ZXTypeRole.allCases.map(\.size).min())
        let type = ZXTypeTokens(displayFace: .serifBold, bodyFace: .serif)
        XCTAssertEqual(type.tracking(for: .body), 0)
        XCTAssertEqual(type.tracking(for: .display), 34 * 0.04, accuracy: 0.0001)
        XCTAssertGreaterThan(type.tracking(for: .caption), 0)
    }

    func testSpaceScale() {
        let s = ZXSpaceTokens.standard
        XCTAssertEqual([s.xxs, s.xs, s.sm, s.md, s.lg, s.xl, s.xxl, s.xxxl], [2, 4, 8, 12, 16, 24, 32, 48])
        XCTAssertEqual(s.margin, 20)
        let theme = ZXTheme(.fallback, colorScheme: .light)
        XCTAssertEqual(theme.space, .standard)
        XCTAssertEqual(theme.radius, .standard)
    }

    func testRadiusScaleAndNesting() {
        let r = ZXRadiusTokens.standard
        let scale = [r.xs, r.sm, r.md, r.lg, r.xl, r.pill]
        XCTAssertEqual(scale, scale.sorted(), "圆角阶要单调递增")
        XCTAssertEqual(r.xl, ZXMetric.panelRadius)
        XCTAssertEqual(ZXRadius.nested(in: 20, padding: 8), 12)
        XCTAssertEqual(ZXRadius.nested(in: 16, padding: 16), 0)
        XCTAssertEqual(ZXRadius.nested(in: 8, padding: 12), 0, "内边距大于外圆角时夹到 0, 不出负圆角")
        XCTAssertEqual(r.nested(in: r.xl, padding: 4), 16)
    }

    func testMotionAdaptedUnderReduceMotion() {
        let m = ZXMotionTokens.defaults
        for animation in [m.snappy, m.smooth, m.bouncy, m.standard, m.hero] {
            XCTAssertEqual(m.adapted(animation, reduceMotion: false), animation, "不减少动态时原样返回")
            XCTAssertEqual(m.adapted(animation, reduceMotion: true), m.reduced, "减少动态时换成短的无弹渐变")
        }
        XCTAssertNotEqual(m.reduced, m.bouncy)
        XCTAssertEqual(ZXTheme(.fallback, colorScheme: .dark).motion, m)
    }

    func testElevationShadowsGrowWithLevel() {
        let levels = ZXElevation.allCases
        XCTAssertEqual(levels, [.e0, .e1, .e2, .e3, .e4])
        XCTAssertEqual(ZXElevation.e0.shadow.opacity, 0)
        XCTAssertFalse(ZXElevation.e0.hairlineInDark)
        for (a, b) in zip(levels, levels.dropFirst()) {
            XCTAssertLessThan(a, b)
            XCTAssertLessThan(a.shadow.radius, b.shadow.radius)
            XCTAssertLessThan(a.shadow.opacity, b.shadow.opacity)
            XCTAssertTrue(b.hairlineInDark)
        }
    }

    private struct RGBA: Equatable { var r, g, b, a: Double }
    private func rgba(_ color: Color) -> RGBA {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func q(_ v: CGFloat) -> Double { (Double(v) * 1000).rounded() / 1000 }
        return RGBA(r: q(r), g: q(g), b: q(b), a: q(a))
    }
}
