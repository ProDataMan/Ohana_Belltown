import XCTest
@testable import App

final class UserStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        UserStore.shared.configure(dataDirectory: tempDir.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @discardableResult
    private func bootstrapAdmin() throws -> StaffUserPublic {
        try UserStore.shared.bootstrapFirstAdmin(username: "admin1", displayName: "Admin One", password: "adminpass")
    }

    func testBootstrapCreatesFirstAdmin() throws {
        let admin = try bootstrapAdmin()
        XCTAssertEqual(admin.role, .admin)
        XCTAssertFalse(admin.mustChangePassword)
    }

    func testBootstrapFailsIfAlreadyBootstrapped() throws {
        try bootstrapAdmin()
        XCTAssertThrowsError(
            try UserStore.shared.bootstrapFirstAdmin(username: "someone", displayName: "Someone", password: "x12345")
        ) { error in
            guard let userError = error as? UserError else { return XCTFail("wrong error type") }
            XCTAssertEqual(userError, .alreadyBootstrapped)
        }
    }

    func testAuthenticateWithWrongPasswordFails() throws {
        try bootstrapAdmin()
        XCTAssertThrowsError(try UserStore.shared.authenticate(username: "admin1", password: "wrong"))
    }

    func testUsernameIsCaseInsensitiveAndTrimmed() throws {
        try bootstrapAdmin()
        let user = try UserStore.shared.authenticate(username: "  ADMIN1  ", password: "adminpass")
        XCTAssertEqual(user.username, "admin1")
    }

    func testCreatingDuplicateUsernameFails() throws {
        let admin = try bootstrapAdmin()
        XCTAssertThrowsError(
            try UserStore.shared.create(username: "admin1", displayName: "Dup", password: "x12345", role: .employee, mustChangePassword: true)
        )
        _ = admin
    }

    func testNewAccountMustChangePasswordUntilTheyDo() throws {
        try bootstrapAdmin()
        let employee = try UserStore.shared.create(
            username: "tim", displayName: "Tim", password: "12345", role: .employee, mustChangePassword: true
        )
        XCTAssertTrue(employee.mustChangePassword)

        let changed = try UserStore.shared.changePassword(id: employee.id, currentPassword: "12345", newPassword: "newpass1")
        XCTAssertFalse(changed.mustChangePassword)
    }

    func testDeactivatedAccountCannotAuthenticate() throws {
        let admin = try bootstrapAdmin()
        let tim = try UserStore.shared.create(
            username: "tim", displayName: "Tim", password: "12345", role: .employee, mustChangePassword: false
        )
        try UserStore.shared.deactivate(id: tim.id, requestedBy: admin.id)

        XCTAssertThrowsError(try UserStore.shared.authenticate(username: "tim", password: "12345")) { error in
            guard let userError = error as? UserError else { return XCTFail("wrong error type") }
            XCTAssertEqual(userError, .accountDeactivated)
        }
    }

    func testDeactivatedAccountSessionLookupFails() throws {
        let admin = try bootstrapAdmin()
        let tim = try UserStore.shared.create(
            username: "tim", displayName: "Tim", password: "12345", role: .employee, mustChangePassword: false
        )
        // find(id:) backs session lookups — this simulates an already-open session
        // getting cut off immediately when an admin deactivates the account.
        XCTAssertNoThrow(try UserStore.shared.find(id: tim.id))
        try UserStore.shared.deactivate(id: tim.id, requestedBy: admin.id)
        XCTAssertThrowsError(try UserStore.shared.find(id: tim.id))
    }

    func testReactivateRestoresAccess() throws {
        let admin = try bootstrapAdmin()
        let tim = try UserStore.shared.create(
            username: "tim", displayName: "Tim", password: "12345", role: .employee, mustChangePassword: false
        )
        try UserStore.shared.deactivate(id: tim.id, requestedBy: admin.id)
        try UserStore.shared.reactivate(id: tim.id)
        let user = try UserStore.shared.authenticate(username: "tim", password: "12345")
        XCTAssertTrue(user.active)
    }

    func testCannotDeactivateSelf() throws {
        let admin = try bootstrapAdmin()
        XCTAssertThrowsError(try UserStore.shared.deactivate(id: admin.id, requestedBy: admin.id)) { error in
            guard let userError = error as? UserError else { return XCTFail("wrong error type") }
            XCTAssertEqual(userError, .cannotDeactivateSelf)
        }
    }

    func testLinkOAuthPreventsDoubleLinking() throws {
        let admin = try bootstrapAdmin()
        let tim = try UserStore.shared.create(
            username: "tim", displayName: "Tim", password: "12345", role: .employee, mustChangePassword: false
        )
        try UserStore.shared.linkOAuth(id: tim.id, provider: .google, providerId: "google-123")

        XCTAssertThrowsError(
            try UserStore.shared.linkOAuth(id: admin.id, provider: .google, providerId: "google-123")
        ) { error in
            guard let userError = error as? UserError else { return XCTFail("wrong error type") }
            XCTAssertEqual(userError, .oauthAlreadyLinkedElsewhere)
        }
    }

    func testFindByOAuthRequiresLinking() throws {
        try bootstrapAdmin()
        XCTAssertThrowsError(try UserStore.shared.findByOAuth(provider: .google, providerId: "unlinked")) { error in
            guard let userError = error as? UserError else { return XCTFail("wrong error type") }
            XCTAssertEqual(userError, .oauthNotLinked)
        }
    }

    func testLinkFacebookOAuthIsIndependentFromGoogle() throws {
        let admin = try bootstrapAdmin()
        try UserStore.shared.linkOAuth(id: admin.id, provider: .google, providerId: "google-1")
        let linked = try UserStore.shared.linkOAuth(id: admin.id, provider: .facebook, providerId: "facebook-1")

        XCTAssertEqual(try UserStore.shared.findByOAuth(provider: .google, providerId: "google-1").id, admin.id)
        XCTAssertEqual(try UserStore.shared.findByOAuth(provider: .facebook, providerId: "facebook-1").id, admin.id)
        XCTAssertEqual(linked.id, admin.id)
    }

    func testCanAuthenticateWithEmailAfterSettingIt() throws {
        let admin = try bootstrapAdmin()
        try UserStore.shared.updateEmail(id: admin.id, email: "  Admin1@Example.com  ")

        let user = try UserStore.shared.authenticate(username: "admin1@example.com", password: "adminpass")
        XCTAssertEqual(user.id, admin.id)
    }

    func testUsernameStillWorksAfterEmailIsSet() throws {
        let admin = try bootstrapAdmin()
        try UserStore.shared.updateEmail(id: admin.id, email: "admin1@example.com")

        let user = try UserStore.shared.authenticate(username: "admin1", password: "adminpass")
        XCTAssertEqual(user.id, admin.id)
    }

    func testEmailIsOptionalAndCanBeCleared() throws {
        let admin = try bootstrapAdmin()
        try UserStore.shared.updateEmail(id: admin.id, email: "admin1@example.com")
        let cleared = try UserStore.shared.updateEmail(id: admin.id, email: "")
        XCTAssertNil(cleared.email)
    }

    func testDuplicateEmailAcrossAccountsFails() throws {
        let admin = try bootstrapAdmin()
        let tim = try UserStore.shared.create(
            username: "tim", displayName: "Tim", password: "12345", role: .employee, mustChangePassword: false
        )
        try UserStore.shared.updateEmail(id: admin.id, email: "shared@example.com")

        XCTAssertThrowsError(try UserStore.shared.updateEmail(id: tim.id, email: "shared@example.com")) { error in
            guard let userError = error as? UserError else { return XCTFail("wrong error type") }
            XCTAssertEqual(userError, .emailTaken)
        }
    }

    func testBirthdayCanBeSetAndCleared() throws {
        let admin = try bootstrapAdmin()
        let set = try UserStore.shared.updateBirthday(id: admin.id, birthday: "07-26")
        XCTAssertEqual(set.birthday, "07-26")

        let cleared = try UserStore.shared.updateBirthday(id: admin.id, birthday: nil)
        XCTAssertNil(cleared.birthday)
    }

    func testBirthdayRejectsInvalidFormat() throws {
        let admin = try bootstrapAdmin()
        XCTAssertThrowsError(try UserStore.shared.updateBirthday(id: admin.id, birthday: "not-a-date")) { error in
            guard let userError = error as? UserError else { return XCTFail("wrong error type") }
            XCTAssertEqual(userError, .invalidBirthdayFormat)
        }
    }

    func testPhoneCanBeSetAndCleared() throws {
        let admin = try bootstrapAdmin()
        let set = try UserStore.shared.updatePhone(id: admin.id, phone: "206-555-0100")
        XCTAssertEqual(set.phone, "206-555-0100")

        let cleared = try UserStore.shared.updatePhone(id: admin.id, phone: "")
        XCTAssertNil(cleared.phone)
    }

    func testLinkOAuthCapturesProfilePhoto() throws {
        let admin = try bootstrapAdmin()
        let linked = try UserStore.shared.linkOAuth(id: admin.id, provider: .google, providerId: "google-1", pictureURL: "https://example.com/photo.png")
        XCTAssertEqual(linked.photoURL, "https://example.com/photo.png")
    }

    func testSetPhotoIfMissingBackfillsButDoesNotOverwrite() throws {
        let admin = try bootstrapAdmin()
        try UserStore.shared.linkOAuth(id: admin.id, provider: .google, providerId: "google-1")

        let backfilled = try UserStore.shared.setPhotoIfMissing(id: admin.id, pictureURL: "https://example.com/first.png")
        XCTAssertEqual(backfilled.photoURL, "https://example.com/first.png")

        let unchanged = try UserStore.shared.setPhotoIfMissing(id: admin.id, pictureURL: "https://example.com/second.png")
        XCTAssertEqual(unchanged.photoURL, "https://example.com/first.png")
    }

    func testLinkOAuthCapturesEmail() throws {
        let admin = try bootstrapAdmin()
        let linked = try UserStore.shared.linkOAuth(id: admin.id, provider: .google, providerId: "google-1", email: "admin1@example.com")
        XCTAssertEqual(linked.email, "admin1@example.com")
    }

    func testSetEmailIfMissingBackfillsButDoesNotOverwrite() throws {
        let admin = try bootstrapAdmin()
        try UserStore.shared.linkOAuth(id: admin.id, provider: .google, providerId: "google-1")

        let backfilled = try UserStore.shared.setEmailIfMissing(id: admin.id, email: "first@example.com")
        XCTAssertEqual(backfilled.email, "first@example.com")

        let unchanged = try UserStore.shared.setEmailIfMissing(id: admin.id, email: "second@example.com")
        XCTAssertEqual(unchanged.email, "first@example.com")
    }

    func testSetEmailIfMissingSkipsSilentlyWhenAlreadyTakenByAnotherAccount() throws {
        let admin = try bootstrapAdmin()
        let tim = try UserStore.shared.create(
            username: "tim", displayName: "Tim", password: "12345", role: .employee, mustChangePassword: false
        )
        try UserStore.shared.updateEmail(id: tim.id, email: "shared@example.com")

        // Shouldn't throw, and shouldn't steal the email — just leaves admin's blank.
        let result = try UserStore.shared.setEmailIfMissing(id: admin.id, email: "shared@example.com")
        XCTAssertNil(result.email)
    }
}
