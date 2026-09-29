import XCTest
@testable import ZixiaoLibrary

final class ZixiaoLibrarySmokeTests: XCTestCase {
    func testModuleName() { XCTAssertEqual(ZixiaoLibraryModule.name, "ZixiaoLibrary") }
}
