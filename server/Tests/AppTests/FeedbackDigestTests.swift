import XCTest
@testable import App

final class FeedbackDigestTests: XCTestCase {
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    private func date(hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        let components = DateComponents(year: 2026, month: 7, day: 26, hour: hour, minute: minute)
        return calendar.date(from: components)!
    }

    func testNotDueBeforeNineAM() {
        XCTAssertFalse(FeedbackDigest.isDigestDue(now: date(hour: 8, minute: 59), timeZone: pacific, alreadySentToday: false))
    }

    func testDueAtOrAfterNineAM() {
        XCTAssertTrue(FeedbackDigest.isDigestDue(now: date(hour: 9, minute: 0), timeZone: pacific, alreadySentToday: false))
        XCTAssertTrue(FeedbackDigest.isDigestDue(now: date(hour: 14, minute: 30), timeZone: pacific, alreadySentToday: false))
    }

    func testNotDueIfAlreadySentToday() {
        XCTAssertFalse(FeedbackDigest.isDigestDue(now: date(hour: 10), timeZone: pacific, alreadySentToday: true))
    }

    func testRenderDigestBodyHandlesNoFeedback() {
        let body = FeedbackDigest.renderDigestBody(entries: [], dayKey: "2026-07-25")
        XCTAssertEqual(body, "No feedback was submitted on 2026-07-25.")
    }

    func testRenderDigestBodyIncludesAverageRatingAndEntries() {
        let entries = [
            FeedbackEntry(id: "1", category: "food", rating: 5, message: "Loved it", page: "/menu", contactEmail: nil, acknowledged: false, createdAt: "2026-07-25T12:00:00Z"),
            FeedbackEntry(id: "2", category: "service", rating: 3, message: "Slow service", page: nil, contactEmail: "guest@example.com", acknowledged: false, createdAt: "2026-07-25T18:00:00Z"),
        ]
        let body = FeedbackDigest.renderDigestBody(entries: entries, dayKey: "2026-07-25")
        XCTAssertTrue(body.contains("2 feedback submission(s)"))
        XCTAssertTrue(body.contains("Average rating: 4.0 / 5"))
        XCTAssertTrue(body.contains("Loved it"))
        XCTAssertTrue(body.contains("Slow service"))
        XCTAssertTrue(body.contains("guest@example.com"))
    }
}
