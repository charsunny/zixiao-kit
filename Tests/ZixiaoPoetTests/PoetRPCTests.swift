import Foundation
import XCTest
@testable import ZixiaoPoet

final class PoetRPCTests: XCTestCase {
    func testEventYearCountsParamsEncodeAsLowercasedPoetId() throws {
        let id = try XCTUnwrap(UUID(uuidString: "6F0B3C2A-1D4E-4B8A-9C55-0123456789AB"))
        let data = try JSONEncoder().encode(PoetRPC.EventYearCountsParams(poetId: id))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object, ["p_poet_id": "6f0b3c2a-1d4e-4b8a-9c55-0123456789ab"])
        XCTAssertEqual(PoetRPC.eventYearCounts, "poet_event_year_counts")
    }

    func testYearCountRowsBecomeADictionary() throws {
        let rows = try JSONDecoder().decode([PoetRPC.YearCount].self,
                                            from: Data(#"[{"year":1079,"n":12},{"year":1082,"n":40}]"#.utf8))
        XCTAssertEqual(PoetRPC.yearCounts(rows), [1079: 12, 1082: 40])
        XCTAssertEqual(PoetRPC.yearCounts(rows + [PoetRPC.YearCount(year: 1079, n: 1)])[1079], 13)
    }
}
