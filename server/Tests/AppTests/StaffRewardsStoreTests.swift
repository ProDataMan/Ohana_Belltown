import XCTest
@testable import App

final class StaffRewardsStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        StaffRewardsStore.shared.configure(dataDirectory: tempDir.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testStatusCreatesZeroPointCardForNewStaff() throws {
        let status = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(status.points, 0)
        XCTAssertEqual(status.pointsNeeded, 10)
        XCTAssertFalse(status.rewardReady)
    }

    func testAwardAccumulatesPointsByCategoryValue() throws {
        // photo = 2 points, price = 1 point.
        try StaffRewardsStore.shared.award(staffId: "staff-1", category: "photo", note: nil, awardedBy: nil)
        let status = try StaffRewardsStore.shared.award(staffId: "staff-1", category: "price", note: nil, awardedBy: "admin-1")
        XCTAssertEqual(status.points, 3)
    }

    func testAwardRejectsUnknownCategory() throws {
        XCTAssertThrowsError(try StaffRewardsStore.shared.award(staffId: "staff-1", category: "bogus", note: nil, awardedBy: nil))
    }

    func testSelfReportAcceptsOnlyUnverifiableCategories() throws {
        // social = 3 points.
        let status = try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "social", note: "Instagram post")
        XCTAssertEqual(status.points, 3)

        XCTAssertThrowsError(try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "photo", note: nil)) { error in
            guard let rewardError = error as? StaffRewardError else { return XCTFail("wrong error type") }
            XCTAssertEqual(rewardError, .invalidCategory)
        }
        XCTAssertThrowsError(try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "price", note: nil))
        XCTAssertThrowsError(try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "special", note: nil))
        XCTAssertThrowsError(try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "event", note: nil))
    }

    func testSelfReportedPointsCountAgainstTheDailyAutoAwardCap() throws {
        // "other" = 2 points; 5 self-reports exactly reach the 10-point daily cap.
        for _ in 1...5 {
            try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "other", note: nil)
        }
        let atCap = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(atCap.points, StaffRewardsStore.maxAutoPointsPerDay)

        let stillCapped = try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "social", note: nil)
        XCTAssertEqual(stillCapped.points, StaffRewardsStore.maxAutoPointsPerDay, "self-reports shouldn't bypass the daily cap the way admin grants do")
    }

    func testTenPointsMakeRewardReady() throws {
        // Manual grants (awardedBy set) aren't subject to the daily auto-award cap.
        // "other" = 2 points, so 5 grants reach the 10-point threshold.
        for _ in 1...5 {
            try StaffRewardsStore.shared.award(staffId: "staff-1", category: "other", note: nil, awardedBy: "admin-1")
        }
        let status = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertTrue(status.rewardReady)
        XCTAssertEqual(status.points, 10)
    }

    func testAutoAwardsCapAtDailyLimitButManualGrantsDoNot() throws {
        // "photo" = 2 points each; the 10-point cap is hit after 5 of the 8 attempts.
        for _ in 1...8 {
            try StaffRewardsStore.shared.award(staffId: "staff-1", category: "photo", note: nil, awardedBy: nil)
        }
        let status = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(status.points, StaffRewardsStore.maxAutoPointsPerDay, "auto-awards should stop at the daily cap")

        let afterManual = try StaffRewardsStore.shared.award(staffId: "staff-1", category: "social", note: "Instagram post", awardedBy: "admin-1")
        XCTAssertEqual(afterManual.points, StaffRewardsStore.maxAutoPointsPerDay + 3, "a manual grant (social = 3 points) should still land past the auto cap")
    }

    func testRedeemRequiresTenPointsAndResetsCount() throws {
        // "price" = 1 point each, for simple exact-total math.
        for _ in 1...5 {
            try StaffRewardsStore.shared.award(staffId: "staff-1", category: "price", note: nil, awardedBy: "admin-1")
        }
        XCTAssertThrowsError(try StaffRewardsStore.shared.redeem(staffId: "staff-1", note: nil))

        for _ in 1...5 {
            try StaffRewardsStore.shared.award(staffId: "staff-1", category: "price", note: nil, awardedBy: "admin-1")
        }
        let redeemed = try StaffRewardsStore.shared.redeem(staffId: "staff-1", note: "Free roll")
        XCTAssertEqual(redeemed.points, 0)
        XCTAssertEqual(redeemed.totalRedeemed, 1)
    }

    func testAwardForMenuEditDetectsPhotoAndPriceAndSpecial() throws {
        let before = MenuItem(name: "Poke Bowl", price: nil, images: [])
        var after = before
        after.images = ["/uploads/a.jpg"]
        after.price = 16
        after.featured = true

        StaffRewardsStore.shared.awardForMenuEdit(staffId: "staff-1", before: before, after: after)

        let status = try StaffRewardsStore.shared.status(staffId: "staff-1")
        // photo (2) + price (1) + special (1) = 4.
        XCTAssertEqual(status.points, 4, "photo added, price set, and marked featured should each earn their category's points")
    }

    func testAwardForMenuEditIgnoresUnchangedFields() throws {
        let before = MenuItem(name: "Poke Bowl", price: 16, images: ["/uploads/a.jpg"], featured: true)
        let after = before

        StaffRewardsStore.shared.awardForMenuEdit(staffId: "staff-1", before: before, after: after)

        let status = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(status.points, 0)
    }

    func testAllCardsSortedByPointsDescending() throws {
        try StaffRewardsStore.shared.award(staffId: "low", category: "other", note: nil, awardedBy: "admin-1")
        for _ in 1...3 {
            try StaffRewardsStore.shared.award(staffId: "high", category: "other", note: nil, awardedBy: "admin-1")
        }
        let cards = try StaffRewardsStore.shared.allCards()
        XCTAssertEqual(cards.first?.staffId, "high")
    }

    func testRecentEventsReturnsNewestFirst() throws {
        try StaffRewardsStore.shared.award(staffId: "staff-1", category: "photo", note: nil, awardedBy: nil)
        try StaffRewardsStore.shared.award(staffId: "staff-1", category: "price", note: nil, awardedBy: nil)
        let events = try StaffRewardsStore.shared.recentEvents(limit: 10)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.category, "price")
    }

    func testEventsRecordThePointValueTheyWereWorth() throws {
        try StaffRewardsStore.shared.award(staffId: "staff-1", category: "social", note: nil, awardedBy: "admin-1")
        let events = try StaffRewardsStore.shared.recentEvents(limit: 10)
        XCTAssertEqual(events.first?.points, 3)
    }
}
