import XCTest
@testable import App

final class CompetitorPhotoReviewStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        CompetitorPhotoReviewStore.shared.configure(dataDirectory: tempDir.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testInboxUploadStartsUnassignedAndUnreviewed() {
        CompetitorPhotoReviewStore.shared.recordInboxUpload(url: "/uploads/a.jpg", uploadedByName: "Yosh")

        let unassigned = CompetitorPhotoReviewStore.shared.unassignedEntries()
        XCTAssertEqual(unassigned.count, 1)
        XCTAssertEqual(unassigned[0].url, "/uploads/a.jpg")
        XCTAssertEqual(unassigned[0].entry.uploadedByName, "Yosh")
        XCTAssertNil(unassigned[0].entry.restaurantId)
        XCTAssertEqual(CompetitorPhotoReviewStore.shared.unreviewedCount(), 1)
    }

    /// Regression test: `recordUnreviewed` used to silently no-op when an
    /// entry already existed for a URL, which meant attaching an inbox photo
    /// to a real restaurant (via `CompetitorPricingStore.saveRestaurants`,
    /// which calls `recordUnreviewed`) never actually updated its
    /// `restaurantId` — the photo would stay attached to the restaurant AND
    /// stuck showing up in `unassignedEntries()` forever, since that list
    /// filters on `restaurantId == nil`.
    func testAttachingAnInboxPhotoToARestaurantClearsItFromUnassigned() {
        CompetitorPhotoReviewStore.shared.recordInboxUpload(url: "/uploads/a.jpg", uploadedByName: "Yosh")
        CompetitorPhotoReviewStore.shared.recordUnreviewed(url: "/uploads/a.jpg", restaurantId: "r1")

        XCTAssertTrue(CompetitorPhotoReviewStore.shared.unassignedEntries().isEmpty, "now attached to a restaurant, so no longer 'unassigned'")
        // Not yet reviewed, though — attaching to a restaurant isn't the
        // same as having actually read prices off it.
        XCTAssertEqual(CompetitorPhotoReviewStore.shared.unreviewedCount(), 1)
        XCTAssertEqual(CompetitorPhotoReviewStore.shared.unreviewedURLs(), ["/uploads/a.jpg"])
    }

    /// `recordUnreviewed` is also how a photo uploaded straight to a known
    /// restaurant (the original, non-inbox flow) gets tracked in the first
    /// place — distinct from the inbox path, and shouldn't regress.
    func testRecordUnreviewedForAKnownRestaurantSkipsTheInboxEntirely() {
        CompetitorPhotoReviewStore.shared.recordUnreviewed(url: "/uploads/b.jpg", restaurantId: "r1")

        XCTAssertTrue(CompetitorPhotoReviewStore.shared.unassignedEntries().isEmpty)
        XCTAssertEqual(CompetitorPhotoReviewStore.shared.unreviewedCount(), 1)
    }

    func testMarkReviewedRemovesFromUnassignedAndUnreviewed() {
        CompetitorPhotoReviewStore.shared.recordInboxUpload(url: "/uploads/a.jpg", uploadedByName: "Yosh")
        CompetitorPhotoReviewStore.shared.markReviewed(url: "/uploads/a.jpg", reviewedByName: "Claude")

        XCTAssertTrue(CompetitorPhotoReviewStore.shared.unassignedEntries().isEmpty)
        XCTAssertEqual(CompetitorPhotoReviewStore.shared.unreviewedCount(), 0)
    }

    func testPruningPreservesInboxButRemovesDetachedRestaurantPhotos() {
        CompetitorPhotoReviewStore.shared.recordInboxUpload(url: "/uploads/a.jpg", uploadedByName: "Yosh")
        CompetitorPhotoReviewStore.shared.recordUnreviewed(url: "/uploads/removed.jpg", restaurantId: "r1")
        CompetitorPhotoReviewStore.shared.removeEntries(notIn: [])

        XCTAssertEqual(CompetitorPhotoReviewStore.shared.unassignedEntries().map(\.url), ["/uploads/a.jpg"])
        XCTAssertEqual(CompetitorPhotoReviewStore.shared.unreviewedCount(), 1)
    }
}
