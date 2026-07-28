import XCTest
@testable import App

final class DiningTimeEstimatorTests: XCTestCase {
    func testEatingBaselineUsesSectionDefaults() {
        XCTAssertEqual(DiningTimeEstimator.eatingBaseline(section: "drinks"), 18)
        XCTAssertEqual(DiningTimeEstimator.eatingBaseline(section: "happy_hour"), 18)
        XCTAssertEqual(DiningTimeEstimator.eatingBaseline(section: "sushi"), 22)
        XCTAssertEqual(DiningTimeEstimator.eatingBaseline(section: "menu"), 25)
    }

    func testEatingBaselineFallsBackForUnknownOrMissingSection() {
        XCTAssertEqual(DiningTimeEstimator.eatingBaseline(section: "not-a-real-section"), DiningTimeEstimator.fallbackEatingBaselineMinutes)
        XCTAssertEqual(DiningTimeEstimator.eatingBaseline(section: nil), DiningTimeEstimator.fallbackEatingBaselineMinutes)
    }

    func testEstimatedEatingMinutesUsesTheSingleSlowestDishWhenItDominates() {
        // menu (25) is the single longest dish and beats half the total (25+18)/2 = 21.5.
        let minutes = DiningTimeEstimator.estimatedEatingMinutes(dishSections: ["menu", "drinks"])
        XCTAssertEqual(minutes, 25, accuracy: 0.01)
    }

    func testEstimatedEatingMinutesUsesHalfTheTotalWhenSeveralDishesDominate() {
        // Three "menu" dishes: longest = 25, half of total (25*3)/2 = 37.5 -> half wins.
        let minutes = DiningTimeEstimator.estimatedEatingMinutes(dishSections: ["menu", "menu", "menu"])
        XCTAssertEqual(minutes, 37.5, accuracy: 0.01)
    }

    func testEstimatedEatingMinutesFallsBackForAnEmptyOrder() {
        XCTAssertEqual(DiningTimeEstimator.estimatedEatingMinutes(dishSections: []), DiningTimeEstimator.fallbackEatingBaselineMinutes)
    }

    func testEstimatedOccupancyMinutesCombinesArrivalWaitEatingAndSocialOverhead() {
        let minutes = DiningTimeEstimator.estimatedOccupancyMinutes(waitPlusPrepMinutes: 14, dishSections: ["menu"])
        let expected = DiningTimeEstimator.arrivalToOrderMinutes + 14 + 25 + DiningTimeEstimator.socialOverheadMinutes
        XCTAssertEqual(minutes, expected, accuracy: 0.01)
    }
}
