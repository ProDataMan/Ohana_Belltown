import XCTest
@testable import App

final class FeedbackStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        FeedbackStore.shared.configure(dataDirectory: tempDir.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSubmitAddsUnacknowledgedEntry() throws {
        let entry = try FeedbackStore.shared.submit(category: "food", rating: 5, message: "Great food!", page: "/menu", contactEmail: nil)
        XCTAssertFalse(entry.acknowledged)

        let recent = try FeedbackStore.shared.recent(days: 30)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(try FeedbackStore.shared.unacknowledgedCount(), 1)
    }

    func testRecentIsNewestFirst() throws {
        try FeedbackStore.shared.submit(category: "food", rating: nil, message: "First", page: nil, contactEmail: nil)
        try FeedbackStore.shared.submit(category: "service", rating: nil, message: "Second", page: nil, contactEmail: nil)

        let recent = try FeedbackStore.shared.recent(days: 30)
        XCTAssertEqual(recent.map { $0.message }, ["Second", "First"])
    }

    func testAcknowledgeAllClearsUnacknowledgedCount() throws {
        try FeedbackStore.shared.submit(category: "website", rating: 2, message: "Slow page", page: "/", contactEmail: nil)
        try FeedbackStore.shared.acknowledgeAll()
        XCTAssertEqual(try FeedbackStore.shared.unacknowledgedCount(), 0)
    }

    func testEntriesOnDayFiltersToThatCalendarDay() throws {
        try FeedbackStore.shared.submit(category: "food", rating: 4, message: "Today's feedback", page: nil, contactEmail: nil)
        let today = FeedbackStore.dayKey(Date())
        let entries = try FeedbackStore.shared.entries(onDay: today)
        XCTAssertEqual(entries.map { $0.message }, ["Today's feedback"])

        let yesterday = FeedbackStore.dayKey(Date().addingTimeInterval(-24 * 3600))
        XCTAssertTrue(try FeedbackStore.shared.entries(onDay: yesterday).isEmpty)
    }

    func testDigestSentTrackingIsPerDay() throws {
        let today = FeedbackStore.dayKey(Date())
        XCTAssertFalse(try FeedbackStore.shared.hasSentDigest(for: today))
        try FeedbackStore.shared.markDigestSent(for: today)
        XCTAssertTrue(try FeedbackStore.shared.hasSentDigest(for: today))

        let yesterday = FeedbackStore.dayKey(Date().addingTimeInterval(-24 * 3600))
        XCTAssertFalse(try FeedbackStore.shared.hasSentDigest(for: yesterday), "marking today sent shouldn't affect other days")
    }
}
