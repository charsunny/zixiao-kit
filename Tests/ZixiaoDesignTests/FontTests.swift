import UIKit
import XCTest
@testable import ZixiaoDesign

final class FontTests: XCTestCase {
    func testRegisterAllMakesFontsAvailable() {
        XCTAssertTrue(ZXFonts.registerAll())
        XCTAssertNotNil(UIFont(name: ZXFonts.serifRegularName, size: 17))
        XCTAssertNotNil(UIFont(name: ZXFonts.serifBoldName, size: 17))
        XCTAssertNotNil(UIFont(name: ZXFonts.kaiName, size: 17))
    }

    /// 幂等: 重复调用、并发调用都不出错, 结果一致。
    func testRegisterAllIsIdempotentAndThreadSafe() {
        XCTAssertTrue(ZXFonts.registerAll())
        XCTAssertTrue(ZXFonts.registerAll())
        let results = UnsafeResultBox(count: 16)
        DispatchQueue.concurrentPerform(iterations: 16) { i in
            results.set(i, ZXFonts.registerAll())
        }
        XCTAssertTrue(results.all)
    }

    /// 秋鸿楷是子集: 印文要先问覆盖。
    func testKaiSubsetCoverage() {
        XCTAssertTrue(ZXFonts.covers("玄", fontNamed: ZXFonts.kaiName))
        XCTAssertTrue(ZXFonts.covers("书 斋", fontNamed: ZXFonts.kaiName))
        XCTAssertFalse(ZXFonts.covers("晓", fontNamed: ZXFonts.kaiName))
        XCTAssertTrue(ZXFonts.covers("东坡居士", fontNamed: ZXFonts.serifRegularName))
        // 竖排标点的直排形在宋体里有字形
        XCTAssertTrue(ZXFonts.covers(String(ZXVerticalForms.map.values), fontNamed: ZXFonts.serifRegularName))
        XCTAssertFalse(ZXFonts.covers("字", fontNamed: "NoSuchFont-Regular"))
    }
}

/// 并发写入测试结果用; 每个下标只被一个线程写一次。
private final class UnsafeResultBox: @unchecked Sendable {
    private var values: [Bool]
    private let lock = NSLock()
    init(count: Int) { values = Array(repeating: false, count: count) }
    func set(_ i: Int, _ v: Bool) { lock.lock(); values[i] = v; lock.unlock() }
    var all: Bool { lock.lock(); defer { lock.unlock() }; return values.allSatisfy { $0 } }
}
