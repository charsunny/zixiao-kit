@testable import ZixiaoPoetCore
import CoreGraphics
import XCTest
@testable import ZixiaoPoet

final class StarLayoutTests: XCTestCase {
    private let requiredGap: CGFloat = 4
    private let centerFrame = CGRect(x: -27, y: -16, width: 54, height: 32)

    func testEmptyAndSingleNodeGeometry() {
        let empty = StarLayout([])
        XCTAssertTrue(empty.nodes.isEmpty)
        XCTAssertEqual(empty.minimumHitScale(), 0)
        XCTAssertEqual(empty.fitScale(in: CGSize(width: 20, height: 20)), 0.2)
        XCTAssertGreaterThan(empty.fitScale(in: CGSize(width: 100, height: 100)), 0.2)

        let single = StarLayout([associate("独坐")])
        XCTAssertEqual(single.nodes.count, 1)
        XCTAssertGreaterThan(single.minimumHitScale(), 0)
        assertHitFramesAreSeparated(single, scale: single.minimumHitScale())
    }

    func testDenseGraphKeepsFinalHitFramesSeparated() {
        let people = (0..<48).map { index in
            associate("人物\(String(format: "%02d", index))", weight: 100 - index)
        }
        let layout = StarLayout(people)
        let fit = layout.fitScale(in: CGSize(width: 320, height: 480))
        let displayedScale = max(fit, layout.minimumHitScale())

        XCTAssertEqual(layout.nodes.count, people.count)
        XCTAssertGreaterThanOrEqual(fit, 0.2)
        XCTAssertLessThanOrEqual(fit, 1)
        assertHitFramesAreSeparated(layout, scale: displayedScale)
    }

    func testLongNamesParticipateInFitAndCollisionGeometry() {
        let people = [
            associate("欧阳文忠公", weight: 9),
            associate("司马温国文正公", weight: 8),
            associate("黄庭坚鲁直", weight: 7),
            associate("米芾元章", weight: 6),
            associate("短名", weight: 5),
        ]
        let layout = StarLayout(people)
        let fit = layout.fitScale(in: CGSize(width: 280, height: 360))

        XCTAssertGreaterThan(StarLayout.labelWidth(people[1]), StarLayout.labelWidth(people[4]))
        XCTAssertEqual(layout.fitScale(in: CGSize(width: 2_000, height: 2_000)), 1)
        assertHitFramesAreSeparated(layout, scale: max(fit, layout.minimumHitScale()))
    }

    private func associate(_ name: String, weight: Int = 1) -> Associate {
        Associate(name: name, courtesyName: nil, groupKey: "test", weight: weight,
                  firstYear: nil, lastYear: nil)
    }

    private func assertHitFramesAreSeparated(
        _ layout: StarLayout,
        scale: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frames = layout.nodes.map { node in
            CGRect(x: node.offset.width * scale - StarLayout.labelWidth(node.associate) / 2,
                   y: node.offset.height * scale - 22,
                   width: StarLayout.labelWidth(node.associate), height: 44)
        }

        for (index, frame) in frames.enumerated() {
            XCTAssertTrue(isSeparated(frame, from: centerFrame, by: requiredGap),
                          "Node \(layout.nodes[index].id) overlaps the center at scale \(scale)",
                          file: file, line: line)
            for otherIndex in frames.indices where index < otherIndex {
                XCTAssertTrue(isSeparated(frame, from: frames[otherIndex], by: requiredGap),
                              "Nodes \(layout.nodes[index].id) and \(layout.nodes[otherIndex].id) overlap at scale \(scale)",
                              file: file, line: line)
            }
        }
    }

    private func isSeparated(_ first: CGRect, from second: CGRect, by gap: CGFloat) -> Bool {
        let horizontalGap = max(second.minX - first.maxX, first.minX - second.maxX)
        let verticalGap = max(second.minY - first.maxY, first.minY - second.maxY)
        return horizontalGap + 0.0001 >= gap || verticalGap + 0.0001 >= gap
    }
}
