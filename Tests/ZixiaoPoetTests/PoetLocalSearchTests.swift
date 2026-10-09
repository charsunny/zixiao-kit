@testable import ZixiaoPoetCore
import XCTest
@testable import ZixiaoPoet

final class PoetLocalSearchTests: XCTestCase {
    private let lifespan = (birth: 1000, death: 1060)

    private func station(_ sequence: Int, source: String, ancient: String?) -> Station {
        Station(id: UUID(), sequence: sequence, sourceName: source, latitude: 0, longitude: 0,
                year: 1010, yearLabel: nil, ageLabel: nil, emphasis: "none",
                places: ancient.map { Station.PlaceRef(name: $0, modern_name: source) })
    }

    func testMatchesAncientAndSourcePlaceNamesWithoutRepeatingStops() {
        let first = station(1, source: "旧城市", ancient: "古城")
        let returnVisit = station(2, source: "旧城市", ancient: "古城")
        let other = station(3, source: "山城", ancient: nil)
        for query in ["古城", " 旧城市\n"] {
            let result = SearchResults.local(query: query, stations: [first, returnVisit, other],
                                             associates: [], lifespan: lifespan)
            XCTAssertEqual(result.places.map(\.id), [first.id])
        }
    }

    func testMatchesCourtesyNamesWithoutNeedingAnOnlinePoemResponse() {
        let person = Associate(name: "友人甲", courtesyName: "子安", groupKey: nil,
                               weight: 3, firstYear: nil, lastYear: nil)
        let result = SearchResults.local(query: "子安", stations: [], associates: [person], lifespan: lifespan)
        XCTAssertEqual(result.people.map(\.name), [person.name])
        XCTAssertTrue(result.poems.isEmpty)
    }

    func testYearsIncludeLifeBoundariesAndRejectOutsideYears() {
        for year in [1000, 1030, 1060] {
            XCTAssertEqual(SearchResults.local(query: " \(year) ", stations: [], associates: [],
                                                lifespan: lifespan).year, year)
        }
        for query in ["999", "1061", "1030年", " \n"] {
            XCTAssertTrue(SearchResults.local(query: query, stations: [], associates: [],
                                               lifespan: lifespan).isEmpty)
        }
    }
}
