import Foundation
import XCTest
@testable import ClockTowerCore

final class CityCatalogTests: XCTestCase {
    func testSearchFindsCitiesAcrossRegionsAndNormalizesSpellings() throws {
        let cases = [
            ("  ASTANA ", "Astana", "Asia/Almaty"),
            ("Nur-Sultan", "Astana", "Asia/Almaty"),
            ("NYC", "New York", "America/New_York"),
            ("sao paulo", "São Paulo", "America/Sao_Paulo"),
            ("Tokyo", "Tokyo", "Asia/Tokyo"),
            ("Nairobi", "Nairobi", "Africa/Nairobi"),
            ("Sydney", "Sydney", "Australia/Sydney"),
            ("Kathmandu", "Kathmandu", "Asia/Kathmandu"),
            ("Reykjavik", "Reykjavík", "Atlantic/Reykjavik"),
            ("Honolulu", "Honolulu", "Pacific/Honolulu")
        ]
        for (query, name, zone) in cases {
            let result = try XCTUnwrap(CityCatalog.search(query).first, query)
            XCTAssertEqual(result.name, name, query)
            XCTAssertEqual(result.timeZoneID, zone, query)
            XCTAssertNotNil(TimeZone(identifier: result.timeZoneID), query)
            XCTAssertFalse(result.isPinned, query)
        }
    }

    func testSearchUsesCountryAndRegionToDisambiguateNamesAndRanksExactCityFirst() throws {
        XCTAssertEqual(CityCatalog.search("York").first?.name, "York")
        let portland = try XCTUnwrap(CityCatalog.search("Portland Oregon").first)
        XCTAssertEqual(portland.name, "Portland")
        XCTAssertTrue(portland.fullName.contains("Oregon"))
        XCTAssertEqual(portland.timeZoneID, "America/Los_Angeles")
        XCTAssertEqual(CityCatalog.search("Portland ME").first?.timeZoneID, "America/New_York")
        XCTAssertEqual(CityCatalog.search("Paris France").first?.timeZoneID, "Europe/Paris")
        XCTAssertEqual(CityCatalog.search("Berlin DE").first?.name, "Berlin")
    }

    func testSearchLimitsAndNoMatchesArePredictable() {
        XCTAssertTrue(CityCatalog.search(" \n ").isEmpty)
        XCTAssertTrue(CityCatalog.search("impossiblecityname-927527").isEmpty)
        XCTAssertTrue(CityCatalog.search("London", limit: 0).isEmpty)
        XCTAssertTrue(CityCatalog.search("London", limit: -1).isEmpty)
        XCTAssertEqual(CityCatalog.search("san", limit: 3).count, 3)
        XCTAssertEqual(CityCatalog.search("san").count, 8)
    }
}
