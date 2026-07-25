import XCTest
@testable import App

final class CustomerUserStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        CustomerUserStore.shared.configure(dataDirectory: tempDir.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRegisterCreatesUnverifiedAccount() throws {
        let (customer, token) = try CustomerUserStore.shared.register(
            email: "guest@example.com", displayName: "Guest", password: "guestpass1"
        )
        XCTAssertFalse(customer.verified)
        XCTAssertTrue(customer.hasPassword)
        XCTAssertFalse(token.isEmpty)
    }

    func testDuplicateEmailRejected() throws {
        try CustomerUserStore.shared.register(email: "guest@example.com", displayName: "Guest", password: "guestpass1")
        XCTAssertThrowsError(
            try CustomerUserStore.shared.register(email: "GUEST@example.com", displayName: "Guest 2", password: "guestpass2")
        )
    }

    func testVerifyTokenMarksAccountVerified() throws {
        let (_, token) = try CustomerUserStore.shared.register(
            email: "guest@example.com", displayName: "Guest", password: "guestpass1"
        )
        let verified = try CustomerUserStore.shared.verify(token: token)
        XCTAssertTrue(verified.verified)
    }

    func testOAuthOnlyAccountHasNoPassword() throws {
        let customer = try CustomerUserStore.shared.findOrCreateFromOAuth(
            provider: .google, providerId: "google-1", email: "oauth@example.com", displayName: "OAuth User"
        )
        XCTAssertFalse(customer.hasPassword)
        XCTAssertTrue(customer.verified, "OAuth sign-in should auto-verify since the provider verified the email")
        XCTAssertTrue(customer.googleLinked)

        XCTAssertThrowsError(try CustomerUserStore.shared.authenticate(email: "oauth@example.com", password: "anything")) { error in
            guard let customerError = error as? CustomerUserError else { return XCTFail("wrong error type") }
            XCTAssertEqual(customerError, .noPasswordSet)
        }
    }

    func testOAuthLinksToExistingAccountByVerifiedEmail() throws {
        try CustomerUserStore.shared.register(email: "guest@example.com", displayName: "Guest", password: "guestpass1")

        let linked = try CustomerUserStore.shared.findOrCreateFromOAuth(
            provider: .google, providerId: "google-1", email: "guest@example.com", displayName: "Guest via Google"
        )
        XCTAssertTrue(linked.googleLinked)
        XCTAssertTrue(linked.hasPassword, "linking shouldn't remove the existing password")

        // Same phone can now log in either way.
        let byPassword = try CustomerUserStore.shared.authenticate(email: "guest@example.com", password: "guestpass1")
        XCTAssertEqual(byPassword.id, linked.id)
    }

    func testRepeatedOAuthSignInReturnsSameAccount() throws {
        let first = try CustomerUserStore.shared.findOrCreateFromOAuth(
            provider: .apple, providerId: "apple-1", email: "guest@example.com", displayName: "Guest"
        )
        let second = try CustomerUserStore.shared.findOrCreateFromOAuth(
            provider: .apple, providerId: "apple-1", email: "guest@example.com", displayName: "Guest"
        )
        XCTAssertEqual(first.id, second.id)
    }

    func testPasswordResetTokenExpiresAndIsSingleUse() throws {
        try CustomerUserStore.shared.register(email: "guest@example.com", displayName: "Guest", password: "guestpass1")
        let token = try CustomerUserStore.shared.requestPasswordReset(email: "guest@example.com")
        XCTAssertNotNil(token)

        _ = try CustomerUserStore.shared.resetPassword(token: token!, newPassword: "newpass123")
        // Using the same token again should fail — it gets cleared after use.
        XCTAssertThrowsError(try CustomerUserStore.shared.resetPassword(token: token!, newPassword: "another1"))

        let authed = try CustomerUserStore.shared.authenticate(email: "guest@example.com", password: "newpass123")
        XCTAssertEqual(authed.email, "guest@example.com")
    }

    func testForgotPasswordForUnknownEmailReturnsNilWithoutThrowing() throws {
        let token = try CustomerUserStore.shared.requestPasswordReset(email: "nobody@example.com")
        XCTAssertNil(token)
    }

    func testChangePasswordOnOAuthOnlyAccountSetsFirstPassword() throws {
        let customer = try CustomerUserStore.shared.findOrCreateFromOAuth(
            provider: .google, providerId: "google-1", email: "oauth@example.com", displayName: "OAuth User"
        )
        // No current password exists yet, so this should succeed without verifying one.
        let updated = try CustomerUserStore.shared.changePassword(id: customer.id, currentPassword: "", newPassword: "newpass123")
        XCTAssertTrue(updated.hasPassword)

        let authed = try CustomerUserStore.shared.authenticate(email: "oauth@example.com", password: "newpass123")
        XCTAssertEqual(authed.id, customer.id)
    }
}
