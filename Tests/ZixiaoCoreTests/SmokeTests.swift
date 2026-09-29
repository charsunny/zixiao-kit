import XCTest
@testable import ZixiaoCore

final class ZixiaoCoreSmokeTests: XCTestCase {
    func testModuleName() { XCTAssertEqual(ZixiaoCoreModule.name, "ZixiaoCore") }
}
