import XCTest
@testable import App

final class BusinessHoursTests: XCTestCase {
    private let iso = ISO8601DateFormatter()

    /// November 2026 is PST (UTC−8).
    private func pacific(_ local: String) -> Date {
        iso.date(from: local + "-08:00")!
    }

    private func status(_ local: String, data: BusinessHoursData = .initial) -> HoursStatus {
        BusinessHoursCalculator.build(data: data, now: pacific(local)).now
    }

    func testWeekdayEveningIsOpenWithKitchenAndHappyHour() {
        let s = status("2026-11-24T17:00:00") // Tuesday 5pm
        XCTAssertTrue(s.open)
        XCTAssertEqual(s.label, "Open now · closes 1am")
        XCTAssertEqual(s.kitchenLabel, "Kitchen open until 10pm")
        XCTAssertTrue(s.happyHourNow)
        XCTAssertEqual(s.happyHourLabel, "Happy Hour until 6pm")
        XCTAssertEqual(s.today, "Open today 4:30pm–1am")
    }

    func testAfterMidnightStillCountsAsTheNightBefore() {
        let s = status("2026-11-25T00:30:00") // Wednesday 12:30am, Tuesday's late night
        XCTAssertTrue(s.open)
        XCTAssertEqual(s.label, "Open now · closes 1am")
        XCTAssertFalse(s.kitchenOpen)
        XCTAssertEqual(s.kitchenLabel, "Kitchen closed · bar open until 1am")
        XCTAssertFalse(s.happyHourNow)
    }

    func testClosedTimesSayWhenWeOpenNext() {
        XCTAssertEqual(status("2026-11-24T14:00:00").label, "Closed · opens 4:30pm") // Tuesday 2pm
        XCTAssertEqual(status("2026-11-25T01:30:00").label, "Closed · opens 4:30pm") // Wednesday 1:30am
        XCTAssertFalse(status("2026-11-24T14:00:00").happyHourNow, "Happy Hour can't run while closed")
    }

    func testFridayAndSaturdayHours() {
        let friday = status("2026-11-27T15:30:00")
        XCTAssertTrue(friday.open)
        XCTAssertTrue(friday.happyHourNow)
        XCTAssertEqual(friday.today, "Open today 1pm–1am")
        XCTAssertEqual(status("2026-11-28T22:30:00").kitchenLabel, "Kitchen open until 11pm") // Saturday
        XCTAssertFalse(status("2026-11-28T15:30:00").happyHourNow, "no Happy Hour on Saturday")
    }

    func testWeekKitchenAndHappyHourSummaries() {
        let hours = BusinessHoursCalculator.build(data: .initial, now: pacific("2026-11-24T12:00:00"))
        XCTAssertEqual(hours.week, [
            HoursLine(label: "Mon–Thu", hours: "4:30pm–1am"),
            HoursLine(label: "Fri–Sun", hours: "1pm–1am"),
        ])
        XCTAssertEqual(hours.kitchenSummary, "Kitchen until 10pm Sun–Thu, 11pm Fri–Sat")
        XCTAssertEqual(hours.happyHourSummary, "Mon–Thu 4:30–6pm · Fri 3–6pm")
        XCTAssertEqual(hours.openingHoursSpecification.map(\.dayOfWeek), [
            ["Monday", "Tuesday", "Wednesday", "Thursday"],
            ["Friday", "Saturday", "Sunday"],
        ])
        XCTAssertEqual(hours.openingHoursSpecification.first?.opens, "16:30")
    }

    func testHolidayClosure() {
        var data = BusinessHoursData.initial
        data.exceptions = [HoursException(date: "2026-11-26", closed: true, note: "Thanksgiving")]
        let thanksgiving = BusinessHoursCalculator.build(data: data, now: pacific("2026-11-26T18:00:00"))
        XCTAssertFalse(thanksgiving.now.open)
        XCTAssertEqual(thanksgiving.now.today, "Closed today (Thanksgiving)")
        XCTAssertEqual(thanksgiving.now.label, "Closed · opens 1pm tomorrow")
        let before = BusinessHoursCalculator.build(data: data, now: pacific("2026-11-24T12:00:00"))
        XCTAssertEqual(before.upcoming, [HoursLine(label: "Thu Nov 26 (Thanksgiving)", hours: "Closed")])
        XCTAssertEqual(before.happyHourSummary, "Mon–Thu 4:30–6pm · Fri 3–6pm", "a holiday doesn't change the usual Happy Hour line")
    }

    func testTimeDisplay() {
        XCTAssertEqual(BusinessHoursCalculator.display("16:30"), "4:30pm")
        XCTAssertEqual(BusinessHoursCalculator.display("13:00"), "1pm")
        XCTAssertEqual(BusinessHoursCalculator.display("01:00"), "1am")
        XCTAssertEqual(BusinessHoursCalculator.display("00:00"), "midnight")
        XCTAssertEqual(BusinessHoursCalculator.display("12:00"), "noon")
    }

    func testSaveRejectsBadTimesAndMissingDays() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        BusinessHoursStore.shared.configure(dataDirectory: dir.path)

        var bad = BusinessHoursData.initial
        bad.week[0].open = "4:30pm"
        XCTAssertThrowsError(try BusinessHoursStore.shared.save(bad))
        var missing = BusinessHoursData.initial
        missing.week.removeLast()
        XCTAssertThrowsError(try BusinessHoursStore.shared.save(missing))

        var good = BusinessHoursData.initial
        good.seasonLabel = "Winter hours"
        try BusinessHoursStore.shared.save(good)
        BusinessHoursStore.shared.configure(dataDirectory: dir.path)
        XCTAssertEqual(BusinessHoursStore.shared.get().seasonLabel, "Winter hours")
    }
}

final class DailySpecialsTests: XCTestCase {
    private let iso = ISO8601DateFormatter()

    func testTodaysDealFollowsTheWeekdayAndSkipsOffDeals() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        DailySpecialsStore.shared.configure(dataDirectory: dir.path)

        let monday = iso.date(from: "2026-11-30T12:00:00-08:00")!
        let tuesday = iso.date(from: "2026-12-01T12:00:00-08:00")!
        let wednesday = iso.date(from: "2026-12-02T12:00:00-08:00")!
        XCTAssertEqual(DailySpecialsStore.shared.publicView(now: monday).today.map(\.title), ["Musubi Monday"])
        XCTAssertEqual(DailySpecialsStore.shared.publicView(now: tuesday).today.first?.itemNames, ["Fish Tacos", "Kalua Pork Tacos"])
        XCTAssertTrue(DailySpecialsStore.shared.publicView(now: wednesday).today.isEmpty)

        var data = DailySpecialsStore.shared.get()
        data.specials[0].active = false
        try DailySpecialsStore.shared.save(data)
        DailySpecialsStore.shared.configure(dataDirectory: dir.path)
        XCTAssertTrue(DailySpecialsStore.shared.publicView(now: monday).today.isEmpty, "a deal switched off doesn't show")
        XCTAssertEqual(DailySpecialsStore.shared.publicView(now: monday).week.map(\.title), ["Taco Tuesday"])
    }
}
