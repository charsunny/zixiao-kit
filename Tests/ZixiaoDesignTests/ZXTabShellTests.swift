import SwiftUI
import XCTest
@testable import ZixiaoDesign

/// `ZXTab.isSearch` → 系统 `Tab` 的 role 的映射 (T23)。视图本身交给截图验证。
final class ZXTabShellTests: XCTestCase {
    func testTabIsNotSearchByDefault() {
        let tab = ZXTab(id: "today", title: "今日", systemImage: "sun.max")
        XCTAssertFalse(tab.isSearch)
        if #available(iOS 18.0, *) {
            XCTAssertNil(tab.tabRole)
        }
    }

    func testSearchTabMapsToSearchRole() throws {
        let tab = ZXTab(id: "search", title: "搜索", systemImage: "magnifyingglass", isSearch: true)
        XCTAssertTrue(tab.isSearch)
        guard #available(iOS 18.0, *) else { throw XCTSkip("Tab role 从 iOS 18 起才有") }
        XCTAssertEqual(tab.tabRole, .search)
    }

    func testSearchFlagTakesPartInEquality() {
        let plain = ZXTab(id: "search", title: "搜索", systemImage: "magnifyingglass")
        let search = ZXTab(id: "search", title: "搜索", systemImage: "magnifyingglass", isSearch: true)
        XCTAssertNotEqual(plain, search)
    }
}
