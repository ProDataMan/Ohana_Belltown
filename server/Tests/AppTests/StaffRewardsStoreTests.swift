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

    func testStatusCreatesZeroPunchCardForNewStaff() throws {
        let status = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(status.punches, 0)
        XCTAssertEqual(status.punchesNeeded, 10)
        XCTAssertFalse(status.rewardReady)
    }

    func testAwardAccumulatesPunches() throws {
        try StaffRewardsStore.shared.award(staffId: "staff-1", category: "photo", note: nil, awardedBy: nil)
        let status = try StaffRewardsStore.shared.award(staffId: "staff-1", category: "price", note: nil, awardedBy: "admin-1")
        XCTAssertEqual(status.punches, 2)
    }

    func testAwardRejectsUnknownCategory() throws {
        XCTAssertThrowsError(try StaffRewardsStore.shared.award(staffId: "staff-1", category: "bogus", note: nil, awardedBy: nil))
    }

    func testSelfReportAcceptsOnlyUnverifiableCategories() throws {
        let status = try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "social", note: "Instagram post")
        XCTAssertEqual(status.punches, 1)

        XCTAssertThrowsError(try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "photo", note: nil)) { error in
            guard let rewardError = error as? StaffRewardError else { return XCTFail("wrong error type") }
            XCTAssertEqual(rewardError, .invalidCategory)
        }
        XCTAssertThrowsError(try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "price", note: nil))
        XCTAssertThrowsError(try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "special", note: nil))
        XCTAssertThrowsError(try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "event", note: nil))
    }

    func testSelfReportedPunchesCountAgainstTheDailyAutoAwardCap() throws {
        for _ in 1...StaffRewardsStore.maxAutoAwardsPerDay {
            try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "other", note: nil)
        }
        let capped = try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "social", note: nil)
        XCTAssertEqual(capped.punches, StaffRewardsStore.maxAutoAwardsPerDay, "self-reports shouldn't bypass the daily cap the way admin grants do")
    }

    func testTenPunchesMakeRewardReady() throws {
        // Manual grants (awardedBy set) aren't subject to the daily auto-award cap.
        for _ in 1...10 {
            try StaffRewardsStore.shared.award(staffId: "staff-1", category: "other", note: nil, awardedBy: "admin-1")
        }
        let status = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertTrue(status.rewardReady)
        XCTAssertEqual(status.punches, 10)
    }

    func testAutoAwardsCapAtDailyLimitButManualGrantsDoNot() throws {
        for _ in 1...8 {
            try StaffRewardsStore.shared.award(staffId: "staff-1", category: "photo", note: nil, awardedBy: nil)
        }
        let status = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(status.punches, StaffRewardsStore.maxAutoAwardsPerDay, "auto-awards should stop at the daily cap")

        let afterManual = try StaffRewardsStore.shared.award(staffId: "staff-1", category: "social", note: "Instagram post", awardedBy: "admin-1")
        XCTAssertEqual(afterManual.punches, StaffRewardsStore.maxAutoAwardsPerDay + 1, "a manual grant should still land past the auto cap")
    }

    func testRedeemRequiresTenPunchesAndResetsCount() throws {
        for _ in 1...5 {
            try StaffRewardsStore.shared.award(staffId: "staff-1", category: "other", note: nil, awardedBy: "admin-1")
        }
        XCTAssertThrowsError(try StaffRewardsStore.shared.redeem(staffId: "staff-1", note: nil))

        for _ in 1...5 {
            try StaffRewardsStore.shared.award(staffId: "staff-1", category: "other", note: nil, awardedBy: "admin-1")
        }
        let redeemed = try StaffRewardsStore.shared.redeem(staffId: "staff-1", note: "Free shift meal")
        XCTAssertEqual(redeemed.punches, 0)
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
        XCTAssertEqual(status.punches, 3, "photo added, price set, and marked featured should each earn a punch")
    }

    func testAwardForMenuEditIgnoresUnchangedFields() throws {
        let before = MenuItem(name: "Poke Bowl", price: 16, images: ["/uploads/a.jpg"], featured: true)
        let after = before

        StaffRewardsStore.shared.awardForMenuEdit(staffId: "staff-1", before: before, after: after)

        let status = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(status.punches, 0)
    }

    func testAllCardsSortedByPunchesDescending() throws {
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
}
