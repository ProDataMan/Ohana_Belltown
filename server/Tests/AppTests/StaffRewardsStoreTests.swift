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
        // Default catalog's cheapest priced items ("roll-or-appetizer" and
        // "bandana") both cost 1000.
        XCTAssertEqual(status.pointsNeeded, 1000)
        XCTAssertFalse(status.rewardReady)
    }

    func testAwardAccumulatesPointsByCategoryValue() throws {
        // photo = 25 points, price = 10 points.
        try StaffRewardsStore.shared.award(staffId: "staff-1", category: "photo", note: nil, awardedBy: nil)
        let status = try StaffRewardsStore.shared.award(staffId: "staff-1", category: "price", note: nil, awardedBy: "admin-1")
        XCTAssertEqual(status.points, 35)
    }

    func testAwardRejectsUnknownCategory() throws {
        XCTAssertThrowsError(try StaffRewardsStore.shared.award(staffId: "staff-1", category: "bogus", note: nil, awardedBy: nil))
    }

    func testSelfReportOnlyAcceptsOther() throws {
        // "other" = 20 points, credited instantly.
        let status = try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "other", note: "Helped set up the patio")
        XCTAssertEqual(status.points, 20)

        // "social" now goes through submitSocialRequest instead — self-reporting it directly is rejected.
        XCTAssertThrowsError(try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "social", note: nil)) { error in
            guard let rewardError = error as? StaffRewardError else { return XCTFail("wrong error type") }
            XCTAssertEqual(rewardError, .invalidCategory)
        }
        XCTAssertThrowsError(try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "photo", note: nil))
        XCTAssertThrowsError(try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "price", note: nil))
        XCTAssertThrowsError(try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "special", note: nil))
        XCTAssertThrowsError(try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "event", note: nil))
    }

    func testSubmitSocialRequestRequiresANonEmptyLink() throws {
        XCTAssertThrowsError(try StaffRewardsStore.shared.submitSocialRequest(staffId: "staff-1", link: "   ", note: nil)) { error in
            guard let rewardError = error as? StaffRewardError else { return XCTFail("wrong error type") }
            XCTAssertEqual(rewardError, .linkRequired)
        }
    }

    func testSocialRequestGrantsNoPointsUntilApproved() throws {
        let request = try StaffRewardsStore.shared.submitSocialRequest(staffId: "staff-1", link: "https://instagram.com/p/abc", note: "New roll")
        XCTAssertEqual(request.status, "pending")

        let statusBeforeReview = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(statusBeforeReview.points, 0)

        let reviewed = try StaffRewardsStore.shared.reviewSocialRequest(id: request.id, approve: true, reviewerId: "admin-1")
        XCTAssertEqual(reviewed.status, "approved")

        let statusAfterReview = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(statusAfterReview.points, 30, "approving credits the social point value")
    }

    func testDeniedSocialRequestGrantsNoPoints() throws {
        let request = try StaffRewardsStore.shared.submitSocialRequest(staffId: "staff-1", link: "https://instagram.com/p/abc", note: nil)
        try StaffRewardsStore.shared.reviewSocialRequest(id: request.id, approve: false, reviewerId: "admin-1")
        let status = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(status.points, 0)
    }

    func testSocialRequestCannotBeReviewedTwice() throws {
        let request = try StaffRewardsStore.shared.submitSocialRequest(staffId: "staff-1", link: "https://instagram.com/p/abc", note: nil)
        try StaffRewardsStore.shared.reviewSocialRequest(id: request.id, approve: true, reviewerId: "admin-1")
        XCTAssertThrowsError(try StaffRewardsStore.shared.reviewSocialRequest(id: request.id, approve: true, reviewerId: "admin-1")) { error in
            guard let rewardError = error as? StaffRewardError else { return XCTFail("wrong error type") }
            XCTAssertEqual(rewardError, .socialRequestAlreadyReviewed)
        }
    }

    func testApprovedSocialRequestIsExemptFromTheDailyAutoAwardCap() throws {
        // Fill the daily cap with "other" self-reports first.
        for _ in 1...5 {
            try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "other", note: nil)
        }
        let atCap = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(atCap.points, StaffRewardsStore.maxAutoPointsPerDay)

        let request = try StaffRewardsStore.shared.submitSocialRequest(staffId: "staff-1", link: "https://instagram.com/p/abc", note: nil)
        try StaffRewardsStore.shared.reviewSocialRequest(id: request.id, approve: true, reviewerId: "admin-1")
        let afterApproval = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(afterApproval.points, StaffRewardsStore.maxAutoPointsPerDay + 30, "an admin-approved request isn't capped by the daily auto-award limit")
    }

    func testSelfReportedPointsCountAgainstTheDailyAutoAwardCap() throws {
        // "other" = 20 points; 5 self-reports exactly reach the 100-point daily cap.
        for _ in 1...5 {
            try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "other", note: nil)
        }
        let atCap = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(atCap.points, StaffRewardsStore.maxAutoPointsPerDay)

        let stillCapped = try StaffRewardsStore.shared.selfReport(staffId: "staff-1", category: "other", note: nil)
        XCTAssertEqual(stillCapped.points, StaffRewardsStore.maxAutoPointsPerDay, "self-reports shouldn't bypass the daily cap the way admin grants do")
    }

    func testEnoughPointsMakeRewardReady() throws {
        // Manual grants (awardedBy set) aren't subject to the daily auto-award cap.
        // "other" = 20 points, so 50 grants reach the 1000-point threshold.
        for _ in 1...50 {
            try StaffRewardsStore.shared.award(staffId: "staff-1", category: "other", note: nil, awardedBy: "admin-1")
        }
        let status = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertTrue(status.rewardReady)
        XCTAssertEqual(status.points, 1000)
    }

    func testAutoAwardsCapAtDailyLimitButManualGrantsDoNot() throws {
        // "photo" = 25 points each; the 100-point cap is hit after 4 of the 8 attempts.
        for _ in 1...8 {
            try StaffRewardsStore.shared.award(staffId: "staff-1", category: "photo", note: nil, awardedBy: nil)
        }
        let status = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(status.points, StaffRewardsStore.maxAutoPointsPerDay, "auto-awards should stop at the daily cap")

        let afterManual = try StaffRewardsStore.shared.award(staffId: "staff-1", category: "social", note: "Instagram post", awardedBy: "admin-1")
        XCTAssertEqual(afterManual.points, StaffRewardsStore.maxAutoPointsPerDay + 30, "a manual grant (social = 30 points) should still land past the auto cap")
    }

    func testRedeemRequiresEnoughPointsForTheChosenCatalogItem() throws {
        // "price" = 10 points each; the default "roll-or-appetizer" item costs 1000.
        for _ in 1...50 {
            try StaffRewardsStore.shared.award(staffId: "staff-1", category: "price", note: nil, awardedBy: "admin-1")
        }
        XCTAssertThrowsError(try StaffRewardsStore.shared.redeem(staffId: "staff-1", catalogItemId: "roll-or-appetizer", note: nil))

        for _ in 1...50 {
            try StaffRewardsStore.shared.award(staffId: "staff-1", category: "price", note: nil, awardedBy: "admin-1")
        }
        let redeemed = try StaffRewardsStore.shared.redeem(staffId: "staff-1", catalogItemId: "roll-or-appetizer", note: "Free roll")
        XCTAssertEqual(redeemed.points, 0)
        XCTAssertEqual(redeemed.totalRedeemed, 1)
    }

    func testRedeemRejectsUnknownCatalogItem() throws {
        try StaffRewardsStore.shared.award(staffId: "staff-1", category: "other", note: nil, awardedBy: "admin-1")
        XCTAssertThrowsError(try StaffRewardsStore.shared.redeem(staffId: "staff-1", catalogItemId: "bogus-item", note: nil)) { error in
            guard let rewardError = error as? StaffRewardError else { return XCTFail("wrong error type") }
            XCTAssertEqual(rewardError, .catalogItemNotFound)
        }
    }

    func testRedeemRejectsAnUnpricedCatalogItem() throws {
        // Plenty of points, but "sticker" is saved as a placeholder with no price yet.
        try StaffRewardsStore.shared.saveCatalog([
            RewardCatalogItem(id: "sticker", name: "Ohana Sticker", pointCost: nil),
        ])
        for _ in 1...50 {
            try StaffRewardsStore.shared.award(staffId: "staff-1", category: "social", note: nil, awardedBy: "admin-1")
        }
        XCTAssertThrowsError(try StaffRewardsStore.shared.redeem(staffId: "staff-1", catalogItemId: "sticker", note: nil)) { error in
            guard let rewardError = error as? StaffRewardError else { return XCTFail("wrong error type") }
            XCTAssertEqual(rewardError, .catalogItemNotPriced)
        }
    }

    func testDefaultCatalogSeedsFoodRewardAndSwagAllPriced() throws {
        let items = try StaffRewardsStore.shared.catalog()
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        XCTAssertEqual(byId["roll-or-appetizer"]?.pointCost, 1000)
        XCTAssertEqual(byId["bandana"]?.name, "Bandana")
        XCTAssertEqual(byId["bandana"]?.pointCost, 1000)
        XCTAssertEqual(byId["tshirt"]?.name, "26th Anniversary T-Shirt")
        XCTAssertEqual(byId["tshirt"]?.pointCost, 2500)
        XCTAssertEqual(byId["hat"]?.name, "Straw Hat")
        XCTAssertEqual(byId["hat"]?.pointCost, 5000)
    }

    func testSaveCatalogReplacesItemsAndAffectsPointsNeeded() throws {
        try StaffRewardsStore.shared.saveCatalog([
            RewardCatalogItem(id: "sticker", name: "Ohana Sticker", pointCost: 50),
            RewardCatalogItem(id: "hat", name: "Ohana Hat", pointCost: 800),
        ])
        let items = try StaffRewardsStore.shared.catalog()
        XCTAssertEqual(items.count, 2)

        // pointsNeeded should now reflect the cheapest priced item (50), not the old default (1000).
        let status = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(status.pointsNeeded, 50)
    }

    func testPointValuesReturnsDefaultsUntilAnAdminSavesAnOverride() throws {
        let values = try StaffRewardsStore.shared.pointValues()
        XCTAssertEqual(values, StaffRewardsStore.defaultPointValues)
    }

    func testSavePointValuesOverridesAndAffectsFutureAwards() throws {
        var values = StaffRewardsStore.defaultPointValues
        values["photo"] = 99
        try StaffRewardsStore.shared.savePointValues(values)

        let saved = try StaffRewardsStore.shared.pointValues()
        XCTAssertEqual(saved["photo"], 99)

        let status = try StaffRewardsStore.shared.award(staffId: "staff-1", category: "photo", note: nil, awardedBy: nil)
        XCTAssertEqual(status.points, 99, "an edited point value should actually apply to new awards")
    }

    func testSavePointValuesFillsInCategoriesMissingFromAPartialOverride() throws {
        // Simulates an override saved before a category like "photo_bounty"
        // existed — it should still resolve via the current defaults.
        try StaffRewardsStore.shared.savePointValues(["photo": 99])

        let values = try StaffRewardsStore.shared.pointValues()
        XCTAssertEqual(values["photo"], 99)
        XCTAssertEqual(values["photo_bounty"], StaffRewardsStore.defaultPointValues["photo_bounty"])
        XCTAssertEqual(values["social"], StaffRewardsStore.defaultPointValues["social"])
    }

    func testSavePointValuesRejectsNegativeValues() throws {
        XCTAssertThrowsError(try StaffRewardsStore.shared.savePointValues(["photo": -5])) { error in
            guard let rewardError = error as? StaffRewardError else { return XCTFail("wrong error type") }
            XCTAssertEqual(rewardError, .invalidPointValue)
        }
    }

    func testAwardForMenuEditDetectsPhotoBountyPriceAndSpecial() throws {
        let before = MenuItem(name: "Poke Bowl", price: nil, images: [])
        var after = before
        after.images = ["/uploads/a.jpg"]
        after.price = 16
        after.featured = true

        StaffRewardsStore.shared.awardForMenuEdit(staffId: "staff-1", before: before, after: after)

        let status = try StaffRewardsStore.shared.status(staffId: "staff-1")
        // This item had zero photos before, so it's the bounty rate (50), not
        // the regular photo rate (25) — plus price (10) + special (10) = 70.
        XCTAssertEqual(status.points, 70, "a first-ever photo should earn the bounty rate, not the regular photo rate")

        let events = try StaffRewardsStore.shared.recentEvents(limit: 10)
        XCTAssertTrue(events.contains { $0.category == "photo_bounty" && $0.points == 50 })
    }

    func testAwardForMenuEditUsesRegularPhotoRateWhenTheItemAlreadyHadOne() throws {
        let before = MenuItem(name: "Poke Bowl", price: 16, images: ["/uploads/a.jpg"])
        var after = before
        after.images = ["/uploads/a.jpg", "/uploads/b.jpg"]

        StaffRewardsStore.shared.awardForMenuEdit(staffId: "staff-1", before: before, after: after)

        let status = try StaffRewardsStore.shared.status(staffId: "staff-1")
        XCTAssertEqual(status.points, 25, "an item that already had a photo should earn the regular rate, not the bounty")

        let events = try StaffRewardsStore.shared.recentEvents(limit: 10)
        XCTAssertTrue(events.contains { $0.category == "photo" && $0.points == 25 })
        XCTAssertFalse(events.contains { $0.category == "photo_bounty" })
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
        XCTAssertEqual(events.first?.points, 30)
    }
}
