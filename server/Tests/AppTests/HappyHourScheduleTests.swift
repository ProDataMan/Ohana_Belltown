import XCTest
@testable import App

final class HappyHourScheduleTests: XCTestCase {
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    private func date(year: Int = 2026, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: components)!
    }

    func testActiveDuringWeekdayWindow() {
        // Wednesday 2026-07-22, 4:30pm Pacific — inside the 3-6pm window.
        let wednesdayAfternoon = date(month: 7, day: 22, hour: 16, minute: 30)
        XCTAssertTrue(HappyHourSchedule.isActive(at: wednesdayAfternoon, timeZone: pacific))
    }

    func testInactiveBeforeWindowStarts() {
        let wednesdayNoon = date(month: 7, day: 22, hour: 14, minute: 59)
        XCTAssertFalse(HappyHourSchedule.isActive(at: wednesdayNoon, timeZone: pacific))
    }

    func testInactiveAtWindowEnd() {
        // The window is [3pm, 6pm) — 6:00pm exactly is no longer happy hour.
        let wednesdaySixPM = date(month: 7, day: 22, hour: 18, minute: 0)
        XCTAssertFalse(HappyHourSchedule.isActive(at: wednesdaySixPM, timeZone: pacific))
    }

    func testInactiveOnWeekend() {
        // Saturday 2026-07-25, 4:30pm Pacific — otherwise within the time window, but weekend.
        let saturdayAfternoon = date(month: 7, day: 25, hour: 16, minute: 30)
        XCTAssertFalse(HappyHourSchedule.isActive(at: saturdayAfternoon, timeZone: pacific))
    }

    func testLandingPathDuringHappyHour() {
        let wednesdayAfternoon = date(month: 7, day: 22, hour: 16, minute: 30)
        XCTAssertEqual(HappyHourSchedule.landingPath(at: wednesdayAfternoon, timeZone: pacific), "/happy-hour")
    }

    func testLandingPathOutsideHappyHour() {
        let saturdayAfternoon = date(month: 7, day: 25, hour: 16, minute: 30)
        XCTAssertEqual(HappyHourSchedule.landingPath(at: saturdayAfternoon, timeZone: pacific), "/menu")
    }
}
