import XCTest
@testable import App

final class LoyaltyStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        LoyaltyStore.shared.configure(dataDirectory: tempDir.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testPunchAccumulatesAndCreatesCustomer() throws {
        let status = try LoyaltyStore.shared.addPunch(phone: "206-555-1234")
        XCTAssertEqual(status.punches, 1)
        XCTAssertEqual(status.punchesNeeded, 10)
        XCTAssertFalse(status.rewardReady)
    }

    func testPhoneNumbersNormalizeAcrossFormats() throws {
        try LoyaltyStore.shared.addPunch(phone: "(206) 555-1234")
        let status = try LoyaltyStore.shared.lookup(phone: "2065551234")
        XCTAssertEqual(status.punches, 1)
    }

    func testTenPunchesMakeRewardReady() throws {
        for _ in 1...10 {
            try LoyaltyStore.shared.addPunch(phone: "2065551234")
        }
        let status = try LoyaltyStore.shared.lookup(phone: "2065551234")
        XCTAssertTrue(status.rewardReady)
        XCTAssertEqual(status.punches, 10)
    }

    func testRedeemRequiresTenPunches() throws {
        try LoyaltyStore.shared.addPunch(phone: "2065551234", count: 5)
        XCTAssertThrowsError(try LoyaltyStore.shared.redeem(phone: "2065551234")) { error in
            XCTAssertTrue(error is LoyaltyError)
        }
    }

    func testRedeemResetsPunchesAndIncrementsTotal() throws {
        try LoyaltyStore.shared.addPunch(phone: "2065551234", count: 10)
        let status = try LoyaltyStore.shared.redeem(phone: "2065551234")
        XCTAssertEqual(status.punches, 0)
        XCTAssertEqual(status.totalRedeemed, 1)
        XCTAssertFalse(status.rewardReady)
    }

    func testLookupUnknownPhoneThrows() throws {
        XCTAssertThrowsError(try LoyaltyStore.shared.lookup(phone: "2065559999"))
    }

    func testApprovedBonusRequestAddsOnlyATenthOfAPunch() throws {
        let request = try LoyaltyStore.shared.submitBonusRequest(
            phone: "2065551234", type: "photo", content: "/uploads/test.jpg", note: nil
        )
        XCTAssertEqual(request.status, "pending")

        let reviewed = try LoyaltyStore.shared.reviewBonusRequest(id: request.id, approve: true)
        XCTAssertEqual(reviewed.status, "approved")
        XCTAssertEqual(reviewed.pointsAwarded, 1)

        let status = try LoyaltyStore.shared.lookup(phone: "2065551234")
        XCTAssertEqual(status.punches, 0)
        XCTAssertEqual(status.bonusPoints, 1)
    }

    func testTenBonusPointsRollOverIntoAPunch() throws {
        // Seed a customer already sitting at 9/10 bonus points (as if earned
        // across several earlier visits), then approve one more claim today —
        // it should roll over into a real punch instead of just reading 10.
        let phone = "2065551234"
        let seeded = LoyaltyData(
            customers: [LoyaltyCustomer(
                phone: phone, punches: 0, bonusPoints: 9, totalRedeemed: 0,
                createdAt: "2020-01-01T00:00:00Z", updatedAt: "2020-01-01T00:00:00Z"
            )],
            bonusRequests: []
        )
        try JSONEncoder().encode(seeded).write(to: tempDir.appendingPathComponent("loyalty.json"))
        LoyaltyStore.shared.configure(dataDirectory: tempDir.path)

        let request = try LoyaltyStore.shared.submitBonusRequest(phone: phone, type: "photo", content: "x", note: nil)
        let reviewed = try LoyaltyStore.shared.reviewBonusRequest(id: request.id, approve: true)
        XCTAssertEqual(reviewed.pointsAwarded, 1)

        let status = try LoyaltyStore.shared.lookup(phone: phone)
        XCTAssertEqual(status.punches, 1, "9 + 1 bonus points should roll over into a real punch")
        XCTAssertEqual(status.bonusPoints, 0)
    }

    func testOnlyTwoBonusRequestsPerDayEarnPoints() throws {
        let phone = "2065551234"
        var lastReviewed: BonusRequest!
        for _ in 1...3 {
            let req = try LoyaltyStore.shared.submitBonusRequest(phone: phone, type: "photo", content: "x", note: nil)
            lastReviewed = try LoyaltyStore.shared.reviewBonusRequest(id: req.id, approve: true)
        }
        XCTAssertEqual(lastReviewed.status, "approved")
        XCTAssertEqual(lastReviewed.pointsAwarded, 0, "the 3rd claim in one day shouldn't earn points")

        let status = try LoyaltyStore.shared.lookup(phone: phone)
        XCTAssertEqual(status.bonusPoints, 2, "only the first 2 claims that day should have counted")
    }

    func testDeniedBonusRequestDoesNotAddPunch() throws {
        let request = try LoyaltyStore.shared.submitBonusRequest(
            phone: "2065559999", type: "social", content: "@someone", note: nil
        )
        let reviewed = try LoyaltyStore.shared.reviewBonusRequest(id: request.id, approve: false)
        XCTAssertEqual(reviewed.status, "denied")
        XCTAssertEqual(reviewed.pointsAwarded, 0)
        XCTAssertThrowsError(try LoyaltyStore.shared.lookup(phone: "2065559999"))
    }

    func testDataPersistsAcrossReconfigure() throws {
        try LoyaltyStore.shared.addPunch(phone: "2065551234", count: 3)
        // Re-point at the same directory to force a fresh reload from disk.
        LoyaltyStore.shared.configure(dataDirectory: tempDir.path)
        let status = try LoyaltyStore.shared.lookup(phone: "2065551234")
        XCTAssertEqual(status.punches, 3)
    }

    func testApprovingAPhotoBonusRequestPublishesToTheLinkedMenuItemsGallery() throws {
        let menuTempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: menuTempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: menuTempDir) }
        MenuStore.shared.configure(dataDirectory: menuTempDir.path, resourcesDirectory: menuTempDir.path)
        let saved = try MenuStore.shared.save(Menu(
            restaurant: "Ohana Belltown", lastUpdated: "",
            categories: [MenuCategory(section: "menu", name: "Rolls", note: nil, items: [MenuItem(name: "Volcano Roll", price: 15)])]
        ))
        let itemId = saved.categories[0].items[0].id

        let request = try LoyaltyStore.shared.submitBonusRequest(
            phone: "2065550000", type: "photo", content: "/uploads/dish.jpg", note: nil,
            menuItemId: itemId, menuItemName: "Volcano Roll"
        )
        _ = try LoyaltyStore.shared.reviewBonusRequest(id: request.id, approve: true)

        let location = try MenuStore.shared.findItem(id: itemId)
        XCTAssertTrue(location.item.images.contains("/uploads/dish.jpg"), "approving should publish the photo into the linked item's gallery")
    }

    func testDenyingAPhotoBonusRequestDoesNotPublishToTheMenuItem() throws {
        let menuTempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: menuTempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: menuTempDir) }
        MenuStore.shared.configure(dataDirectory: menuTempDir.path, resourcesDirectory: menuTempDir.path)
        let saved = try MenuStore.shared.save(Menu(
            restaurant: "Ohana Belltown", lastUpdated: "",
            categories: [MenuCategory(section: "menu", name: "Rolls", note: nil, items: [MenuItem(name: "Volcano Roll", price: 15)])]
        ))
        let itemId = saved.categories[0].items[0].id

        let request = try LoyaltyStore.shared.submitBonusRequest(
            phone: "2065550001", type: "photo", content: "/uploads/dish2.jpg", note: nil,
            menuItemId: itemId, menuItemName: "Volcano Roll"
        )
        _ = try LoyaltyStore.shared.reviewBonusRequest(id: request.id, approve: false)

        let location = try MenuStore.shared.findItem(id: itemId)
        XCTAssertFalse(location.item.images.contains("/uploads/dish2.jpg"), "denying shouldn't publish anything to the menu item")
    }
}
