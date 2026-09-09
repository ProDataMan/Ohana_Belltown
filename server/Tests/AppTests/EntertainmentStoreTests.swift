import XCTest
@testable import App

final class EntertainmentStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        EntertainmentStore.shared.configure(dataDirectory: tempDir.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func dateString(daysFromToday: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = calendar.date(byAdding: .day, value: daysFromToday, to: calendar.startOfDay(for: Date()))!
        return formatter.string(from: date)
    }

    func testCreatePersistsAllFields() throws {
        let request = EntertainmentBookingRequest(
            date: "2026-09-30", startTime: "21:00", performerName: "The Coconut Wireless", bio: "Island grooves.",
            photos: ["/uploads/a.jpg"], videoURL: "/uploads/clip.mp4"
        )
        let created = try EntertainmentStore.shared.create(request)
        XCTAssertEqual(created.date, "2026-09-30")
        XCTAssertEqual(created.startTime, "21:00")
        XCTAssertEqual(created.performerName, "The Coconut Wireless")
        XCTAssertEqual(created.bio, "Island grooves.")
        XCTAssertEqual(created.photos, ["/uploads/a.jpg"])
        XCTAssertEqual(created.videoURL, "/uploads/clip.mp4")
        XCTAssertFalse(created.id.isEmpty)
    }

    func testStartTimeIsOptional() throws {
        let request = EntertainmentBookingRequest(date: "2026-09-30", performerName: "No Time Set", photos: [])
        let created = try EntertainmentStore.shared.create(request)
        XCTAssertNil(created.startTime)
    }

    func testUpdateCanChangeStartTime() throws {
        let created = try EntertainmentStore.shared.create(
            EntertainmentBookingRequest(date: "2026-09-30", startTime: "21:00", performerName: "Name", photos: [])
        )
        let updated = try EntertainmentStore.shared.update(
            id: created.id,
            EntertainmentBookingRequest(date: "2026-09-30", startTime: "22:30", performerName: "Name", photos: [])
        )
        XCTAssertEqual(updated.startTime, "22:30")
    }

    func testUpdateChangesFields() throws {
        let created = try EntertainmentStore.shared.create(
            EntertainmentBookingRequest(date: "2026-09-30", performerName: "Original Name", bio: nil, photos: [], videoURL: nil)
        )
        let updated = try EntertainmentStore.shared.update(
            id: created.id,
            EntertainmentBookingRequest(date: "2026-10-07", performerName: "New Name", bio: "New bio", photos: ["/uploads/b.jpg"], videoURL: nil)
        )
        XCTAssertEqual(updated.date, "2026-10-07")
        XCTAssertEqual(updated.performerName, "New Name")
        XCTAssertEqual(updated.bio, "New bio")
        XCTAssertEqual(updated.photos, ["/uploads/b.jpg"])
    }

    func testUpdateUnknownIdThrowsNotFound() throws {
        XCTAssertThrowsError(
            try EntertainmentStore.shared.update(
                id: "does-not-exist",
                EntertainmentBookingRequest(date: "2026-09-30", performerName: "X", bio: nil, photos: nil, videoURL: nil)
            )
        ) { error in
            XCTAssertEqual(error as? EntertainmentError, .notFound)
        }
    }

    func testDeleteRemovesEntry() throws {
        let created = try EntertainmentStore.shared.create(
            EntertainmentBookingRequest(date: "2026-09-30", performerName: "Gone Soon", bio: nil, photos: [], videoURL: nil)
        )
        try EntertainmentStore.shared.delete(id: created.id)
        let all = try EntertainmentStore.shared.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testDeleteUnknownIdThrowsNotFound() throws {
        XCTAssertThrowsError(try EntertainmentStore.shared.delete(id: "does-not-exist")) { error in
            XCTAssertEqual(error as? EntertainmentError, .notFound)
        }
    }

    func testAllIsSortedByDate() throws {
        try EntertainmentStore.shared.create(EntertainmentBookingRequest(date: "2026-10-14", performerName: "Later", bio: nil, photos: [], videoURL: nil))
        try EntertainmentStore.shared.create(EntertainmentBookingRequest(date: "2026-09-30", performerName: "Earlier", bio: nil, photos: [], videoURL: nil))
        let all = try EntertainmentStore.shared.all()
        XCTAssertEqual(all.map(\.performerName), ["Earlier", "Later"])
    }

    func testUpcomingExcludesPastDates() throws {
        try EntertainmentStore.shared.create(EntertainmentBookingRequest(date: "2020-01-01", performerName: "Long Gone", bio: nil, photos: [], videoURL: nil))
        try EntertainmentStore.shared.create(EntertainmentBookingRequest(date: "2099-01-01", performerName: "Far Future", bio: nil, photos: [], videoURL: nil))
        let upcoming = try EntertainmentStore.shared.upcoming(from: "2026-09-08")
        XCTAssertEqual(upcoming.map(\.performerName), ["Far Future"])
    }

    // MARK: - entertainmentProvider booking-window math

    func testWindowAcceptsToday() {
        XCTAssertTrue(EntertainmentStore.isWithinEntertainmentProviderWindow(dateString(daysFromToday: 0)))
    }

    func testWindowAcceptsExactly60DaysOut() {
        XCTAssertTrue(EntertainmentStore.isWithinEntertainmentProviderWindow(dateString(daysFromToday: 60)))
    }

    func testWindowRejects61DaysOut() {
        XCTAssertFalse(EntertainmentStore.isWithinEntertainmentProviderWindow(dateString(daysFromToday: 61)))
    }

    func testWindowRejectsYesterday() {
        XCTAssertFalse(EntertainmentStore.isWithinEntertainmentProviderWindow(dateString(daysFromToday: -1)))
    }

    func testWindowRejectsGarbageDate() {
        XCTAssertFalse(EntertainmentStore.isWithinEntertainmentProviderWindow("not-a-date"))
    }

    // MARK: - weekday(of:) — which of the 7 nightly pages a date belongs on

    func testWeekdayOfKnownDates() {
        // 2026-09-09 is a real Wednesday; the rest of the week follows from there.
        XCTAssertEqual(EntertainmentStore.weekday(of: "2026-09-07"), "monday")
        XCTAssertEqual(EntertainmentStore.weekday(of: "2026-09-08"), "tuesday")
        XCTAssertEqual(EntertainmentStore.weekday(of: "2026-09-09"), "wednesday")
        XCTAssertEqual(EntertainmentStore.weekday(of: "2026-09-10"), "thursday")
        XCTAssertEqual(EntertainmentStore.weekday(of: "2026-09-11"), "friday")
        XCTAssertEqual(EntertainmentStore.weekday(of: "2026-09-12"), "saturday")
        XCTAssertEqual(EntertainmentStore.weekday(of: "2026-09-13"), "sunday")
    }

    func testWeekdayOfGarbageDateIsNil() {
        XCTAssertNil(EntertainmentStore.weekday(of: "not-a-date"))
    }

    func testUpcomingCanBeFilteredByWeekdayAtTheRouteLevel() throws {
        // weekday(of:) is a pure function used by the route handler to filter
        // /api/entertainment/upcoming?weekday=... — exercised end-to-end over
        // HTTP in RouteTests; this just locks down the underlying date math
        // it depends on for a full week, including both weekend days.
        let bookings = [
            ("2026-09-07", "monday"), ("2026-09-08", "tuesday"), ("2026-09-09", "wednesday"),
            ("2026-09-10", "thursday"), ("2026-09-11", "friday"), ("2026-09-12", "saturday"), ("2026-09-13", "sunday"),
        ]
        for (date, expectedWeekday) in bookings {
            try EntertainmentStore.shared.create(EntertainmentBookingRequest(date: date, performerName: expectedWeekday, photos: []))
        }
        let all = try EntertainmentStore.shared.all()
        for (date, expectedWeekday) in bookings {
            let matching = all.first { $0.date == date }
            XCTAssertEqual(matching.flatMap { EntertainmentStore.weekday(of: $0.date) }, expectedWeekday)
        }
    }
}
