import XCTest
@testable import App

final class TableMapTests: XCTestCase {
    func testNoDuplicateTableIds() {
        let ids = TableMap.entries.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "every table id should be unique across all sections")
    }

    func testEveryEntryHasAValidSectionAndPosition() {
        for entry in TableMap.entries {
            XCTAssertTrue(TableMap.sections.contains(entry.section), "\(entry.id) has an unrecognized section \(entry.section)")
            XCTAssertTrue((0...100).contains(entry.x), "\(entry.id) x=\(entry.x) is outside the 0-100 canvas")
            XCTAssertTrue((0...100).contains(entry.y), "\(entry.id) y=\(entry.y) is outside the 0-100 canvas")
            XCTAssertTrue(["round", "square"].contains(entry.shape), "\(entry.id) has an unrecognized shape \(entry.shape)")
        }
    }

    func testEverySectionHasAtLeastOneTable() {
        for section in TableMap.sections {
            XCTAssertTrue(TableMap.entries.contains { $0.section == section }, "no tables found for section \(section)")
        }
    }
}
