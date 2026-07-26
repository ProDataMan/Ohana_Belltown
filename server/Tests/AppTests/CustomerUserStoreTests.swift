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

    func testDeactivatedAccountCannotAuthenticate() throws {
        let (customer, _) = try CustomerUserStore.shared.register(
            email: "guest@example.com", displayName: "Guest", password: "guestpass1"
        )
        try CustomerUserStore.shared.deactivate(id: customer.id)

        XCTAssertThrowsError(try CustomerUserStore.shared.authenticate(email: "guest@example.com", password: "guestpass1")) { error in
            guard let customerError = error as? CustomerUserError else { return XCTFail("wrong error type") }
            XCTAssertEqual(customerError, .accountDeactivated)
        }
    }

    func testDeactivatedAccountSessionLookupFails() throws {
        let (customer, _) = try CustomerUserStore.shared.register(
            email: "guest@example.com", displayName: "Guest", password: "guestpass1"
        )
        XCTAssertNoThrow(try CustomerUserStore.shared.find(id: customer.id))
        try CustomerUserStore.shared.deactivate(id: customer.id)
        XCTAssertThrowsError(try CustomerUserStore.shared.find(id: customer.id))
    }

    func testDeactivatedAccountCannotSignInViaOAuth() throws {
        let customer = try CustomerUserStore.shared.findOrCreateFromOAuth(
            provider: .google, providerId: "google-1", email: "oauth@example.com", displayName: "OAuth User"
        )
        try CustomerUserStore.shared.deactivate(id: customer.id)

        XCTAssertThrowsError(
            try CustomerUserStore.shared.findOrCreateFromOAuth(
                provider: .google, providerId: "google-1", email: "oauth@example.com", displayName: "OAuth User"
            )
        ) { error in
            guard let customerError = error as? CustomerUserError else { return XCTFail("wrong error type") }
            XCTAssertEqual(customerError, .accountDeactivated)
        }
    }

    func testOAuthSignupCapturesProfilePhoto() throws {
        let customer = try CustomerUserStore.shared.findOrCreateFromOAuth(
            provider: .google, providerId: "google-1", email: "oauth@example.com", displayName: "OAuth User",
            pictureURL: "https://example.com/photo.png"
        )
        XCTAssertEqual(customer.photoURL, "https://example.com/photo.png")
    }

    func testOAuthLinkBackfillsPhotoOnExistingAccountByEmail() throws {
        try CustomerUserStore.shared.register(email: "guest@example.com", displayName: "Guest", password: "guestpass1")

        let linked = try CustomerUserStore.shared.findOrCreateFromOAuth(
            provider: .google, providerId: "google-1", email: "guest@example.com", displayName: "Guest via Google",
            pictureURL: "https://example.com/photo.png"
        )
        XCTAssertEqual(linked.photoURL, "https://example.com/photo.png")
    }

    func testOAuthBackfillsMissingPhotoOnSubsequentLogin() throws {
        // Simulates an account that linked Google before this field existed —
        // no picture on file yet, even though it's already linked by providerId.
        let first = try CustomerUserStore.shared.findOrCreateFromOAuth(
            provider: .google, providerId: "google-1", email: "oauth@example.com", displayName: "OAuth User"
        )
        XCTAssertNil(first.photoURL)

        let second = try CustomerUserStore.shared.findOrCreateFromOAuth(
            provider: .google, providerId: "google-1", email: "oauth@example.com", displayName: "OAuth User",
            pictureURL: "https://example.com/photo.png"
        )
        XCTAssertEqual(second.photoURL, "https://example.com/photo.png")
    }

    func testOAuthDoesNotOverwriteExistingPhoto() throws {
        _ = try CustomerUserStore.shared.findOrCreateFromOAuth(
            provider: .google, providerId: "google-1", email: "oauth@example.com", displayName: "OAuth User",
            pictureURL: "https://example.com/first.png"
        )
        let second = try CustomerUserStore.shared.findOrCreateFromOAuth(
            provider: .google, providerId: "google-1", email: "oauth@example.com", displayName: "OAuth User",
            pictureURL: "https://example.com/second.png"
        )
        XCTAssertEqual(second.photoURL, "https://example.com/first.png")
    }

    func testLoyaltyPhoneCanBeLinkedAndNormalized() throws {
        let (customer, _) = try CustomerUserStore.shared.register(email: "guest@example.com", displayName: "Guest", password: "guestpass1")
        let linked = try CustomerUserStore.shared.updateLoyaltyPhone(id: customer.id, phone: "(206) 555-0100")
        XCTAssertEqual(linked.loyaltyPhone, "2065550100")
    }

    func testLoyaltyPhoneCanBeUnlinked() throws {
        let (customer, _) = try CustomerUserStore.shared.register(email: "guest@example.com", displayName: "Guest", password: "guestpass1")
        try CustomerUserStore.shared.updateLoyaltyPhone(id: customer.id, phone: "2065550100")
        let unlinked = try CustomerUserStore.shared.updateLoyaltyPhone(id: customer.id, phone: nil)
        XCTAssertNil(unlinked.loyaltyPhone)
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

    private func monthDay(daysFromToday offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }

    func testBirthdayRejectsInvalidFormat() throws {
        let (customer, _) = try CustomerUserStore.shared.register(email: "guest@example.com", displayName: "Guest", password: "guestpass1")
        XCTAssertThrowsError(try CustomerUserStore.shared.updateBirthday(id: customer.id, birthday: "not-a-date")) { error in
            guard let customerError = error as? CustomerUserError else { return XCTFail("wrong error type") }
            XCTAssertEqual(customerError, .invalidBirthdayFormat)
        }
        XCTAssertThrowsError(try CustomerUserStore.shared.updateBirthday(id: customer.id, birthday: "13-40"))
    }

    func testBirthdayCanBeSetAndCleared() throws {
        let (customer, _) = try CustomerUserStore.shared.register(email: "guest@example.com", displayName: "Guest", password: "guestpass1")
        let set = try CustomerUserStore.shared.updateBirthday(id: customer.id, birthday: "07-26")
        XCTAssertEqual(set.birthday, "07-26")

        let cleared = try CustomerUserStore.shared.updateBirthday(id: customer.id, birthday: nil)
        XCTAssertNil(cleared.birthday)
    }

    func testUpcomingBirthdaysFindsCustomerWithinWindow() throws {
        let (customer, _) = try CustomerUserStore.shared.register(email: "guest@example.com", displayName: "Guest", password: "guestpass1")
        try CustomerUserStore.shared.updateBirthday(id: customer.id, birthday: monthDay(daysFromToday: 3))

        let upcoming = try CustomerUserStore.shared.upcomingBirthdays(withinDays: 7)
        XCTAssertTrue(upcoming.contains { $0.id == customer.id })
    }

    func testUpcomingBirthdaysIncludesToday() throws {
        let (customer, _) = try CustomerUserStore.shared.register(email: "guest@example.com", displayName: "Guest", password: "guestpass1")
        try CustomerUserStore.shared.updateBirthday(id: customer.id, birthday: monthDay(daysFromToday: 0))

        let upcoming = try CustomerUserStore.shared.upcomingBirthdays(withinDays: 0)
        XCTAssertTrue(upcoming.contains { $0.id == customer.id })
    }

    func testUpcomingBirthdaysExcludesOutsideWindow() throws {
        let (customer, _) = try CustomerUserStore.shared.register(email: "guest@example.com", displayName: "Guest", password: "guestpass1")
        try CustomerUserStore.shared.updateBirthday(id: customer.id, birthday: monthDay(daysFromToday: 20))

        let upcoming = try CustomerUserStore.shared.upcomingBirthdays(withinDays: 7)
        XCTAssertFalse(upcoming.contains { $0.id == customer.id })
    }

    func testUpcomingBirthdaysWrapsToNextYearForAPastDate() throws {
        // A birthday that already happened this year (yesterday) shouldn't
        // show up in a short window — its next real occurrence is ~364 days
        // away, not "already passed, ignore forever."
        let (customer, _) = try CustomerUserStore.shared.register(email: "guest@example.com", displayName: "Guest", password: "guestpass1")
        try CustomerUserStore.shared.updateBirthday(id: customer.id, birthday: monthDay(daysFromToday: -1))

        let upcoming = try CustomerUserStore.shared.upcomingBirthdays(withinDays: 7)
        XCTAssertFalse(upcoming.contains { $0.id == customer.id })
    }

    func testUpcomingBirthdaysExcludesInactiveCustomers() throws {
        let (customer, _) = try CustomerUserStore.shared.register(email: "guest@example.com", displayName: "Guest", password: "guestpass1")
        try CustomerUserStore.shared.updateBirthday(id: customer.id, birthday: monthDay(daysFromToday: 1))
        try CustomerUserStore.shared.deactivate(id: customer.id)

        let upcoming = try CustomerUserStore.shared.upcomingBirthdays(withinDays: 7)
        XCTAssertFalse(upcoming.contains { $0.id == customer.id })
    }
}
