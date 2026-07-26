import XCTest
@testable import App

final class PrepTimeEstimatorTests: XCTestCase {
    func testBaselineMinutesUsesSectionDefaults() {
        XCTAssertEqual(PrepTimeEstimator.baselineMinutes(section: "drinks"), 3)
        XCTAssertEqual(PrepTimeEstimator.baselineMinutes(section: "sushi"), 12)
        XCTAssertEqual(PrepTimeEstimator.baselineMinutes(section: "happy_hour"), 7)
        XCTAssertEqual(PrepTimeEstimator.baselineMinutes(section: "menu"), 12)
    }

    func testBaselineMinutesFallsBackForUnknownOrMissingSection() {
        XCTAssertEqual(PrepTimeEstimator.baselineMinutes(section: "not-a-real-section"), PrepTimeEstimator.fallbackBaselineMinutes)
        XCTAssertEqual(PrepTimeEstimator.baselineMinutes(section: nil), PrepTimeEstimator.fallbackBaselineMinutes)
    }

    func testLoadAdjustedMinutesUnchangedWhenStaffCoversTheLoad() {
        let adjusted = PrepTimeEstimator.loadAdjustedMinutes(baseline: 10, occupiedTables: 3, staffOnDuty: 5)
        XCTAssertEqual(adjusted, 10, "enough staff to cover current tables shouldn't add any penalty")
    }

    func testLoadAdjustedMinutesIncreasesWhenOverloaded() {
        // 3 tables over what staff can cover -> 3 * 15% = 45% slower.
        let adjusted = PrepTimeEstimator.loadAdjustedMinutes(baseline: 10, occupiedTables: 8, staffOnDuty: 5)
        XCTAssertEqual(adjusted, 14.5, accuracy: 0.01)
    }

    func testLoadAdjustedMinutesTreatsZeroStaffAsOne() {
        // Guards against dividing/overload math blowing up if staffing is misconfigured to 0.
        let adjusted = PrepTimeEstimator.loadAdjustedMinutes(baseline: 10, occupiedTables: 2, staffOnDuty: 0)
        XCTAssertEqual(adjusted, 11.5, accuracy: 0.01)
    }
}
