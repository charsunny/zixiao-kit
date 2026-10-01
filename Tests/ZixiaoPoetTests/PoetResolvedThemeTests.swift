import SwiftUI
import XCTest
import ZixiaoDesign
@testable import ZixiaoPoet

/// 夜读 / 图版查看器按另一种外观重解析主题 (`ZXTheme.poetResolved(for:)`):
/// 同一身份、同一支备选强调色, 只换外观。(取代 M1 的 shim 测试; shim 已在 M2c 删除。)
@MainActor
final class PoetResolvedThemeTests: XCTestCase {
    func testAlternateAccentIsCarriedIntoTheOtherAppearance() throws {
        let identity = try ZXIdentity.bundled(.paperInkSeal)
        let (name, pair) = try XCTUnwrap(identity.palette.accents?.sorted { $0.key < $1.key }.first)
        let night = ZXTheme(identity, colorScheme: .light, accentName: name).poetResolved(for: .dark)
        XCTAssertTrue(night.isDark)
        XCTAssertEqual(night.color.values.accent, pair.dark)
        XCTAssertEqual(night.color.values.paper, ZXTheme(identity, colorScheme: .dark).color.values.paper)
    }

    func testSameAppearanceKeepsTheTheme() throws {
        let identity = try ZXIdentity.bundled(.paperInkSeal)
        let day = ZXTheme(identity, colorScheme: .light)
        XCTAssertEqual(day.poetResolved(for: .light).color.values.paper, day.color.values.paper)
        XCTAssertFalse(day.poetResolved(for: .light).isDark)
    }
}
