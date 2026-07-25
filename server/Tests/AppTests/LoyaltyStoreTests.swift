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

    func testApprovedBonusRequestAddsPunch() throws {
        let request = try LoyaltyStore.shared.submitBonusRequest(
            phone: "2065551234", type: "photo", content: "/uploads/test.jpg", note: nil
        )
        XCTAssertEqual(request.status, "pending")

        let reviewed = try LoyaltyStore.shared.reviewBonusRequest(id: request.id, approve: true)
        XCTAssertEqual(reviewed.status, "approved")

        let status = try LoyaltyStore.shared.lookup(phone: "2065551234")
        XCTAssertEqual(status.punches, 1)
    }

    func testDeniedBonusRequestDoesNotAddPunch() throws {
        let request = try LoyaltyStore.shared.submitBonusRequest(
            phone: "2065559999", type: "social", content: "@someone", note: nil
        )
        let reviewed = try LoyaltyStore.shared.reviewBonusRequest(id: request.id, approve: false)
        XCTAssertEqual(reviewed.status, "denied")
        XCTAssertThrowsError(try LoyaltyStore.shared.lookup(phone: "2065559999"))
    }

    func testDataPersistsAcrossReconfigure() throws {
        try LoyaltyStore.shared.addPunch(phone: "2065551234", count: 3)
        // Re-point at the same directory to force a fresh reload from disk.
        LoyaltyStore.shared.configure(dataDirectory: tempDir.path)
        let status = try LoyaltyStore.shared.lookup(phone: "2065551234")
        XCTAssertEqual(status.punches, 3)
    }
}
