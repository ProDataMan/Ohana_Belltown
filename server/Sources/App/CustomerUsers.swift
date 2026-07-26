import Vapor

struct CustomerUser: Codable {
    var id: String
    var email: String
    var displayName: String
    var passwordHash: String?
    var googleId: String?
    var appleId: String?
    var facebookId: String?
    var verified: Bool
    var active: Bool
    /// Month and day only, formatted "MM-DD" — never the birth year, since
    /// nothing here needs age, just the day to mark for a birthday perk.
    var birthday: String?
    /// Profile photo URL, extracted from Google on signup/link. Apple never
    /// supplies one, and there's no manual-upload path — only ever set from OAuth.
    var photoURL: String?
    /// Phone number linking this account to a punch card in LoyaltyStore
    /// (which is phone-keyed and otherwise has no concept of a customer login).
    var loyaltyPhone: String?
    var verificationToken: String?
    var resetToken: String?
    var resetTokenExpiresAt: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, email, displayName, passwordHash, googleId, appleId, facebookId, verified, active, birthday, photoURL, loyaltyPhone
        case verificationToken, resetToken, resetTokenExpiresAt, createdAt, updatedAt
    }

    init(
        id: String, email: String, displayName: String, passwordHash: String?,
        googleId: String?, appleId: String?, facebookId: String? = nil, verified: Bool, active: Bool = true,
        birthday: String? = nil, photoURL: String? = nil, loyaltyPhone: String? = nil,
        verificationToken: String?, resetToken: String?, resetTokenExpiresAt: String?,
        createdAt: String, updatedAt: String
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.passwordHash = passwordHash
        self.googleId = googleId
        self.appleId = appleId
        self.facebookId = facebookId
        self.verified = verified
        self.active = active
        self.birthday = birthday
        self.photoURL = photoURL
        self.loyaltyPhone = loyaltyPhone
        self.verificationToken = verificationToken
        self.resetToken = resetToken
        self.resetTokenExpiresAt = resetTokenExpiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decode(String.self, forKey: .displayName)
        passwordHash = try container.decodeIfPresent(String.self, forKey: .passwordHash)
        googleId = try container.decodeIfPresent(String.self, forKey: .googleId)
        appleId = try container.decodeIfPresent(String.self, forKey: .appleId)
        facebookId = try container.decodeIfPresent(String.self, forKey: .facebookId)
        verified = try container.decode(Bool.self, forKey: .verified)
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        birthday = try container.decodeIfPresent(String.self, forKey: .birthday)
        photoURL = try container.decodeIfPresent(String.self, forKey: .photoURL)
        loyaltyPhone = try container.decodeIfPresent(String.self, forKey: .loyaltyPhone)
        verificationToken = try container.decodeIfPresent(String.self, forKey: .verificationToken)
        resetToken = try container.decodeIfPresent(String.self, forKey: .resetToken)
        resetTokenExpiresAt = try container.decodeIfPresent(String.self, forKey: .resetTokenExpiresAt)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }
}

struct CustomerUserPublic: Content {
    var id: String
    var email: String
    var displayName: String
    var verified: Bool
    var hasPassword: Bool
    var googleLinked: Bool
    var appleLinked: Bool
    var facebookLinked: Bool
    var birthday: String?
    var photoURL: String?
    var loyaltyPhone: String?

    init(_ user: CustomerUser) {
        id = user.id
        email = user.email
        displayName = user.displayName
        verified = user.verified
        hasPassword = user.passwordHash != nil
        googleLinked = user.googleId != nil
        appleLinked = user.appleId != nil
        facebookLinked = user.facebookId != nil
        birthday = user.birthday
        photoURL = user.photoURL
        loyaltyPhone = user.loyaltyPhone
    }
}

enum CustomerUserError: Error, Equatable {
    case emailTaken
    case invalidCredentials
    case noPasswordSet
    case accountDeactivated
    case notFound
    case invalidOrExpiredToken
    case wrongCurrentPassword
    case invalidBirthdayFormat
}

extension CustomerUserError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .emailTaken: return .conflict
        case .invalidCredentials, .wrongCurrentPassword, .noPasswordSet, .accountDeactivated: return .unauthorized
        case .notFound: return .notFound
        case .invalidOrExpiredToken, .invalidBirthdayFormat: return .badRequest
        }
    }

    var reason: String {
        switch self {
        case .emailTaken: return "An account with that email already exists."
        case .invalidCredentials: return "Incorrect email or password."
        case .noPasswordSet: return "This account signs in with Google or Apple — use that instead, or reset your password to set one."
        case .accountDeactivated: return "This account has been deactivated. Contact us if you'd like it restored."
        case .notFound: return "Account not found."
        case .invalidOrExpiredToken: return "That link is invalid or has expired."
        case .wrongCurrentPassword: return "Current password is incorrect."
        case .invalidBirthdayFormat: return "Birthday must be in MM-DD format."
        }
    }
}

final class CustomerUserStore: @unchecked Sendable {
    static let shared = CustomerUserStore()

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/customers.json")
    private var users: [CustomerUser] = []
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("customers.json")
        loaded = false
    }

    private func now() -> Date { Date() }
    private func nowString() -> String { ISO8601DateFormatter().string(from: Date()) }

    private static func normalizeEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    @discardableResult
    func register(email: String, displayName: String, password: String) throws -> (CustomerUserPublic, String) {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let normalized = Self.normalizeEmail(email)
        guard !users.contains(where: { $0.email == normalized }) else {
            throw CustomerUserError.emailTaken
        }
        let timestamp = nowString()
        let token = UUID().uuidString
        let user = CustomerUser(
            id: UUID().uuidString,
            email: normalized,
            displayName: displayName,
            passwordHash: try Bcrypt.hash(password),
            googleId: nil,
            appleId: nil,
            verified: false,
            verificationToken: token,
            resetToken: nil,
            resetTokenExpiresAt: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        users.append(user)
        try persist()
        return (CustomerUserPublic(user), token)
    }

    @discardableResult
    func verify(token: String) throws -> CustomerUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.verificationToken == token }) else {
            throw CustomerUserError.invalidOrExpiredToken
        }
        users[idx].verified = true
        users[idx].verificationToken = nil
        users[idx].updatedAt = nowString()
        try persist()
        return CustomerUserPublic(users[idx])
    }

    func authenticate(email: String, password: String) throws -> CustomerUser {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let normalized = Self.normalizeEmail(email)
        guard let user = users.first(where: { $0.email == normalized }) else {
            throw CustomerUserError.invalidCredentials
        }
        guard let hash = user.passwordHash else {
            throw CustomerUserError.noPasswordSet
        }
        guard try Bcrypt.verify(password, created: hash) else {
            throw CustomerUserError.invalidCredentials
        }
        guard user.active else {
            throw CustomerUserError.accountDeactivated
        }
        return user
    }

    /// Deactivates the caller's own account (self-service only — there's no
    /// staff-facing customer management UI). Takes effect immediately since
    /// find(id:) backs session lookups and also rejects inactive accounts.
    @discardableResult
    func deactivate(id: String) throws -> CustomerUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.id == id }) else {
            throw CustomerUserError.notFound
        }
        users[idx].active = false
        users[idx].updatedAt = nowString()
        try persist()
        return CustomerUserPublic(users[idx])
    }

    /// Finds the account linked to this OAuth identity, links it to an existing
    /// account with a matching verified email, or creates a new account.
    /// Whenever the provider supplies a profile photo and the account doesn't
    /// have one on file yet, it's backfilled — covers both a brand-new signup
    /// and an account that linked Google before this field existed.
    @discardableResult
    func findOrCreateFromOAuth(provider: OAuthProvider, providerId: String, email: String, displayName: String, pictureURL: String? = nil) throws -> CustomerUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let normalized = Self.normalizeEmail(email)
        let timestamp = nowString()

        if let idx = users.firstIndex(where: { provider.id(of: $0) == providerId }) {
            guard users[idx].active else {
                throw CustomerUserError.accountDeactivated
            }
            if let pictureURL, users[idx].photoURL == nil {
                users[idx].photoURL = pictureURL
                users[idx].updatedAt = timestamp
                try persist()
            }
            return CustomerUserPublic(users[idx])
        }

        if let idx = users.firstIndex(where: { $0.email == normalized }) {
            guard users[idx].active else {
                throw CustomerUserError.accountDeactivated
            }
            provider.setId(providerId, on: &users[idx])
            users[idx].verified = true
            if let pictureURL, users[idx].photoURL == nil {
                users[idx].photoURL = pictureURL
            }
            users[idx].updatedAt = timestamp
            try persist()
            return CustomerUserPublic(users[idx])
        }

        var user = CustomerUser(
            id: UUID().uuidString,
            email: normalized,
            displayName: displayName,
            passwordHash: nil,
            googleId: nil,
            appleId: nil,
            verified: true,
            photoURL: pictureURL,
            verificationToken: nil,
            resetToken: nil,
            resetTokenExpiresAt: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        provider.setId(providerId, on: &user)
        users.append(user)
        try persist()
        return CustomerUserPublic(user)
    }

    /// Returns the user only if their account is still active — backs session
    /// lookups, so a self-deactivation ends the current session immediately.
    func find(id: String) throws -> CustomerUser {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let user = users.first(where: { $0.id == id }) else {
            throw CustomerUserError.notFound
        }
        guard user.active else {
            throw CustomerUserError.accountDeactivated
        }
        return user
    }

    /// Always succeeds (even for an unknown email) to avoid leaking which emails are registered.
    /// Returns a token only when the email is actually on file, so the caller can decide whether to email it.
    func requestPasswordReset(email: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let normalized = Self.normalizeEmail(email)
        guard let idx = users.firstIndex(where: { $0.email == normalized }) else {
            return nil
        }
        let token = UUID().uuidString
        users[idx].resetToken = token
        users[idx].resetTokenExpiresAt = ISO8601DateFormatter().string(from: now().addingTimeInterval(3600))
        users[idx].updatedAt = nowString()
        try persist()
        return token
    }

    @discardableResult
    func resetPassword(token: String, newPassword: String) throws -> CustomerUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.resetToken == token }),
              let expiresAtString = users[idx].resetTokenExpiresAt,
              let expiresAt = ISO8601DateFormatter().date(from: expiresAtString),
              expiresAt > now() else {
            throw CustomerUserError.invalidOrExpiredToken
        }
        users[idx].passwordHash = try Bcrypt.hash(newPassword)
        users[idx].resetToken = nil
        users[idx].resetTokenExpiresAt = nil
        users[idx].updatedAt = nowString()
        try persist()
        return CustomerUserPublic(users[idx])
    }

    @discardableResult
    func changePassword(id: String, currentPassword: String, newPassword: String) throws -> CustomerUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.id == id }) else {
            throw CustomerUserError.notFound
        }
        if let hash = users[idx].passwordHash {
            guard try Bcrypt.verify(currentPassword, created: hash) else {
                throw CustomerUserError.wrongCurrentPassword
            }
        }
        users[idx].passwordHash = try Bcrypt.hash(newPassword)
        users[idx].updatedAt = nowString()
        try persist()
        return CustomerUserPublic(users[idx])
    }

    /// `birthday` is "MM-DD" (e.g. "07-26"), or nil/empty to clear it — never
    /// a full date, so no birth year is ever stored.
    @discardableResult
    func updateBirthday(id: String, birthday: String?) throws -> CustomerUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.id == id }) else {
            throw CustomerUserError.notFound
        }
        if let birthday, !birthday.isEmpty {
            guard Self.isValidMonthDay(birthday) else {
                throw CustomerUserError.invalidBirthdayFormat
            }
            users[idx].birthday = birthday
        } else {
            users[idx].birthday = nil
        }
        users[idx].updatedAt = nowString()
        try persist()
        return CustomerUserPublic(users[idx])
    }

    /// Links this account to a phone-based punch card in LoyaltyStore, so a
    /// signed-in customer can see their rewards status without re-entering
    /// their phone every time. `phone` is normalized the same way LoyaltyStore
    /// normalizes it (digits only) — pass nil/empty to unlink.
    @discardableResult
    func updateLoyaltyPhone(id: String, phone: String?) throws -> CustomerUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.id == id }) else {
            throw CustomerUserError.notFound
        }
        if let phone, !phone.isEmpty {
            users[idx].loyaltyPhone = LoyaltyStore.normalizePhone(phone)
        } else {
            users[idx].loyaltyPhone = nil
        }
        users[idx].updatedAt = nowString()
        try persist()
        return CustomerUserPublic(users[idx])
    }

    private static func isValidMonthDay(_ value: String) -> Bool {
        let parts = value.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]) else { return false }
        return (1...12).contains(month) && (1...31).contains(day)
    }

    /// Active customers with a birthday in the next `withinDays` days
    /// (inclusive of today), wrapping correctly across a year boundary —
    /// staff-facing, so a server can proactively treat a regular on their
    /// birthday rather than relying on an automated discount.
    func upcomingBirthdays(withinDays: Int) throws -> [CustomerUserPublic] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())

        func daysUntilNextOccurrence(ofMonthDay value: String) -> Int? {
            let parts = value.split(separator: "-")
            guard parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]) else { return nil }
            let currentYear = calendar.component(.year, from: today)
            for yearOffset in 0...1 {
                var components = DateComponents()
                components.year = currentYear + yearOffset
                components.month = month
                components.day = day
                guard let candidate = calendar.date(from: components) else { continue }
                let diff = calendar.dateComponents([.day], from: today, to: candidate).day ?? -1
                if diff >= 0 { return diff }
            }
            return nil
        }

        return users
            .filter { $0.active }
            .compactMap { user -> (CustomerUserPublic, Int)? in
                guard let birthday = user.birthday, let daysAway = daysUntilNextOccurrence(ofMonthDay: birthday) else { return nil }
                guard daysAway <= withinDays else { return nil }
                return (CustomerUserPublic(user), daysAway)
            }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            users = try JSONDecoder().decode([CustomerUser].self, from: data)
        } else {
            users = []
            try persist()
        }
        loaded = true
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(users)
        try data.write(to: fileURL, options: .atomic)
    }
}
