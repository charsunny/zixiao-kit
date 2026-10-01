import SwiftUI
import XCTest
import ZixiaoDesign
@testable import ZixiaoPoet

/// 迁自 PoetKit ThemeFillContrastTests: 现在强调色与印色来自 ZXTheme (纸墨朱印 + 系列备选强调色),
/// 压在它们上面的字 (`onFill`) 在每种外观下仍须 ≥ 4.5:1。另验 shim 的动态色确实随外观换值。
@MainActor
final class ThemeShimTests: XCTestCase {
    private let appearances: [(String, UIUserInterfaceStyle, UIAccessibilityContrast)] = [
        ("light", .light, .normal), ("light-high", .light, .high),
        ("dark", .dark, .normal), ("dark-high", .dark, .high),
    ]

    func testAccentAndSealFillsChooseReadableForegroundInEveryAppearance() throws {
        let identity = try ZXIdentity.bundled(.paperInkSeal)
        let accentNames: [String?] = [nil] + (identity.palette.accents?.keys.sorted() ?? []).map(Optional.some)
        XCTAssertGreaterThanOrEqual(accentNames.count, 3)

        for name in accentNames {
            for scheme in [ColorScheme.light, .dark] {
                let theme = Theme(ZXTheme(identity, colorScheme: scheme, accentName: name))
                for (token, fill) in [("accent", theme.accent), ("seal", theme.seal)] {
                    for appearance in appearances {
                        let traits = UITraitCollection(traitsFrom: [
                            UITraitCollection(userInterfaceStyle: appearance.1),
                            UITraitCollection(accessibilityContrast: appearance.2),
                        ])
                        let ratio = contrastRatio(UIColor(fill.onFill).resolvedColor(with: traits),
                                                  UIColor(fill).resolvedColor(with: traits))
                        XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name ?? "default") \(token) \(appearance.0)")
                    }
                }
            }
        }
    }

    /// 同一份 shim 在局部强制深色 (夜读) 时给深色的值, 而不是注入时那一种外观的。
    func testShimColorsFollowTheLocalAppearance() throws {
        let identity = try ZXIdentity.bundled(.paperInkSeal)
        let lightTheme = ZXTheme(identity, colorScheme: .light)
        let darkTheme = ZXTheme(identity, colorScheme: .dark)
        let shim = Theme(lightTheme)

        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let light = UITraitCollection(userInterfaceStyle: .light)
        XCTAssertEqual(hex(UIColor(shim.paper).resolvedColor(with: light)), hexDigits(lightTheme.color.values.paper))
        XCTAssertEqual(hex(UIColor(shim.paper).resolvedColor(with: dark)), hexDigits(darkTheme.color.values.paper))
        XCTAssertEqual(hex(UIColor(shim.ink).resolvedColor(with: dark)), hexDigits(darkTheme.color.values.ink))
    }

    func testAlternateAccentIsCarriedIntoTheOtherAppearance() throws {
        let identity = try ZXIdentity.bundled(.paperInkSeal)
        let (name, pair) = try XCTUnwrap(identity.palette.accents?.sorted { $0.key < $1.key }.first)
        let shim = Theme(ZXTheme(identity, colorScheme: .light, accentName: name))
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertEqual(PoetThemeResolver.accentName(of: ZXTheme(identity, colorScheme: .dark, accentName: name)), name)
        XCTAssertEqual(hex(UIColor(shim.accent).resolvedColor(with: dark)), hexDigits(pair.dark))
    }

    private func hex(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        return [r, g, b].map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }

    private func hexDigits(_ value: ZXHex) -> String {
        String(value.description.dropFirst().prefix(6))
    }

    private func contrastRatio(_ first: UIColor, _ second: UIColor) -> CGFloat {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
