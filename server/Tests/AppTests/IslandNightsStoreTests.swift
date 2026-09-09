import XCTest
@testable import App

final class IslandNightsStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        IslandNightsStore.shared.configure(dataDirectory: tempDir.path)
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
        let request = IslandNightPerformerRequest(
            date: "2026-09-30", startTime: "21:00", performerName: "The Coconut Wireless", bio: "Island grooves.",
            photos: ["/uploads/a.jpg"], videoURL: "/uploads/clip.mp4"
        )
        let created = try IslandNightsStore.shared.create(request)
        XCTAssertEqual(created.date, "2026-09-30")
        XCTAssertEqual(created.startTime, "21:00")
        XCTAssertEqual(created.performerName, "The Coconut Wireless")
        XCTAssertEqual(created.bio, "Island grooves.")
        XCTAssertEqual(created.photos, ["/uploads/a.jpg"])
        XCTAssertEqual(created.videoURL, "/uploads/clip.mp4")
        XCTAssertFalse(created.id.isEmpty)
    }

    func testStartTimeIsOptional() throws {
        let request = IslandNightPerformerRequest(date: "2026-09-30", performerName: "No Time Set", photos: [])
        let created = try IslandNightsStore.shared.create(request)
        XCTAssertNil(created.startTime)
    }

    func testUpdateCanChangeStartTime() throws {
        let created = try IslandNightsStore.shared.create(
            IslandNightPerformerRequest(date: "2026-09-30", startTime: "21:00", performerName: "Name", photos: [])
        )
        let updated = try IslandNightsStore.shared.update(
            id: created.id,
            IslandNightPerformerRequest(date: "2026-09-30", startTime: "22:30", performerName: "Name", photos: [])
        )
        XCTAssertEqual(updated.startTime, "22:30")
    }

    func testUpdateChangesFields() throws {
        let created = try IslandNightsStore.shared.create(
            IslandNightPerformerRequest(date: "2026-09-30", performerName: "Original Name", bio: nil, photos: [], videoURL: nil)
        )
        let updated = try IslandNightsStore.shared.update(
            id: created.id,
            IslandNightPerformerRequest(date: "2026-10-07", performerName: "New Name", bio: "New bio", photos: ["/uploads/b.jpg"], videoURL: nil)
        )
        XCTAssertEqual(updated.date, "2026-10-07")
        XCTAssertEqual(updated.performerName, "New Name")
        XCTAssertEqual(updated.bio, "New bio")
        XCTAssertEqual(updated.photos, ["/uploads/b.jpg"])
    }

    func testUpdateUnknownIdThrowsNotFound() throws {
        XCTAssertThrowsError(
            try IslandNightsStore.shared.update(
                id: "does-not-exist",
                IslandNightPerformerRequest(date: "2026-09-30", performerName: "X", bio: nil, photos: nil, videoURL: nil)
            )
        ) { error in
            XCTAssertEqual(error as? IslandNightsError, .notFound)
        }
    }

    func testDeleteRemovesEntry() throws {
        let created = try IslandNightsStore.shared.create(
            IslandNightPerformerRequest(date: "2026-09-30", performerName: "Gone Soon", bio: nil, photos: [], videoURL: nil)
        )
        try IslandNightsStore.shared.delete(id: created.id)
        let all = try IslandNightsStore.shared.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testDeleteUnknownIdThrowsNotFound() throws {
        XCTAssertThrowsError(try IslandNightsStore.shared.delete(id: "does-not-exist")) { error in
            XCTAssertEqual(error as? IslandNightsError, .notFound)
        }
    }

    func testAllIsSortedByDate() throws {
        try IslandNightsStore.shared.create(IslandNightPerformerRequest(date: "2026-10-14", performerName: "Later", bio: nil, photos: [], videoURL: nil))
        try IslandNightsStore.shared.create(IslandNightPerformerRequest(date: "2026-09-30", performerName: "Earlier", bio: nil, photos: [], videoURL: nil))
        let all = try IslandNightsStore.shared.all()
        XCTAssertEqual(all.map(\.performerName), ["Earlier", "Later"])
    }

    func testUpcomingExcludesPastDates() throws {
        try IslandNightsStore.shared.create(IslandNightPerformerRequest(date: "2020-01-01", performerName: "Long Gone", bio: nil, photos: [], videoURL: nil))
        try IslandNightsStore.shared.create(IslandNightPerformerRequest(date: "2099-01-01", performerName: "Far Future", bio: nil, photos: [], videoURL: nil))
        let upcoming = try IslandNightsStore.shared.upcoming(from: "2026-09-08")
        XCTAssertEqual(upcoming.map(\.performerName), ["Far Future"])
    }

    // MARK: - entertainmentProvider booking-window math

    func testWindowAcceptsToday() {
        XCTAssertTrue(IslandNightsStore.isWithinEntertainmentProviderWindow(dateString(daysFromToday: 0)))
    }

    func testWindowAcceptsExactly60DaysOut() {
        XCTAssertTrue(IslandNightsStore.isWithinEntertainmentProviderWindow(dateString(daysFromToday: 60)))
    }

    func testWindowRejects61DaysOut() {
        XCTAssertFalse(IslandNightsStore.isWithinEntertainmentProviderWindow(dateString(daysFromToday: 61)))
    }

    func testWindowRejectsYesterday() {
        XCTAssertFalse(IslandNightsStore.isWithinEntertainmentProviderWindow(dateString(daysFromToday: -1)))
    }

    func testWindowRejectsGarbageDate() {
        XCTAssertFalse(IslandNightsStore.isWithinEntertainmentProviderWindow("not-a-date"))
    }
}
