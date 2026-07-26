import Vapor

enum UserRole: String, Codable, CaseIterable {
    case admin
    case employee
}

struct StaffUser: Codable {
    var id: String
    var username: String
    var displayName: String
    var passwordHash: String
    var email: String?
    var googleId: String?
    var appleId: String?
    var facebookId: String?
    var role: UserRole
    var mustChangePassword: Bool
    var active: Bool
    /// Profile photo URL, extracted from Google on link/login — Apple never
    /// supplies one, and there's no manual-upload path.
    var photoURL: String?
    /// Month and day only, formatted "MM-DD" — never the birth year.
    var birthday: String?
    var phone: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, username, displayName, passwordHash, email, googleId, appleId, facebookId, role, mustChangePassword, active
        case photoURL, birthday, phone, createdAt, updatedAt
    }

    init(
        id: String, username: String, displayName: String, passwordHash: String,
        googleId: String?, appleId: String?, facebookId: String? = nil, role: UserRole, mustChangePassword: Bool,
        active: Bool = true, photoURL: String? = nil, birthday: String? = nil, phone: String? = nil,
        createdAt: String, updatedAt: String, email: String? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.passwordHash = passwordHash
        self.email = email
        self.googleId = googleId
        self.appleId = appleId
        self.facebookId = facebookId
        self.role = role
        self.mustChangePassword = mustChangePassword
        self.active = active
        self.photoURL = photoURL
        self.birthday = birthday
        self.phone = phone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decode(String.self, forKey: .displayName)
        passwordHash = try container.decode(String.self, forKey: .passwordHash)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        googleId = try container.decodeIfPresent(String.self, forKey: .googleId)
        appleId = try container.decodeIfPresent(String.self, forKey: .appleId)
        facebookId = try container.decodeIfPresent(String.self, forKey: .facebookId)
        role = try container.decode(UserRole.self, forKey: .role)
        mustChangePassword = try container.decode(Bool.self, forKey: .mustChangePassword)
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        photoURL = try container.decodeIfPresent(String.self, forKey: .photoURL)
        birthday = try container.decodeIfPresent(String.self, forKey: .birthday)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }
}

struct StaffUserPublic: Content {
    var id: String
    var username: String
    var displayName: String
    var email: String?
    var role: UserRole
    var mustChangePassword: Bool
    var googleLinked: Bool
    var appleLinked: Bool
    var facebookLinked: Bool
    var active: Bool
    var photoURL: String?
    var birthday: String?
    var phone: String?

    init(_ user: StaffUser) {
        id = user.id
        username = user.username
        displayName = user.displayName
        email = user.email
        role = user.role
        mustChangePassword = user.mustChangePassword
        googleLinked = user.googleId != nil
        appleLinked = user.appleId != nil
        facebookLinked = user.facebookId != nil
        active = user.active
        photoURL = user.photoURL
        birthday = user.birthday
        phone = user.phone
    }
}

enum UserError: Error, Equatable {
    case usernameTaken
    case invalidCredentials
    case accountDeactivated
    case notFound
    case alreadyBootstrapped
    case wrongCurrentPassword
    case oauthNotLinked
    case oauthAlreadyLinkedElsewhere
    case cannotDeactivateSelf
    case cannotDeactivateLastAdmin
    case emailTaken
    case invalidBirthdayFormat
}

extension UserError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .usernameTaken, .oauthAlreadyLinkedElsewhere, .emailTaken: return .conflict
        case .invalidCredentials, .wrongCurrentPassword, .accountDeactivated: return .unauthorized
        case .notFound, .oauthNotLinked: return .notFound
        case .alreadyBootstrapped, .cannotDeactivateSelf, .cannotDeactivateLastAdmin: return .forbidden
        case .invalidBirthdayFormat: return .badRequest
        }
    }

    var reason: String {
        switch self {
        case .usernameTaken: return "That username is already taken."
        case .invalidCredentials: return "Incorrect username or password."
        case .accountDeactivated: return "This account has been deactivated."
        case .notFound: return "User not found."
        case .alreadyBootstrapped: return "Setup has already been completed."
        case .wrongCurrentPassword: return "Current password is incorrect."
        case .oauthNotLinked: return "No staff account is linked to that account yet. Log in with your username and password first, then link it from My Account."
        case .oauthAlreadyLinkedElsewhere: return "That account is already linked to a different staff login."
        case .cannotDeactivateSelf: return "You can't deactivate your own account."
        case .cannotDeactivateLastAdmin: return "Can't deactivate the last active admin."
        case .emailTaken: return "That email is already in use by another account."
        case .invalidBirthdayFormat: return "Birthday must be in MM-DD format."
        }
    }
}

final class UserStore: @unchecked Sendable {
    static let shared = UserStore()

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/users.json")
    private var users: [StaffUser] = []
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("users.json")
        loaded = false
    }

    private func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func normalizeIdentifier(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func bootstrapFirstAdmin(username: String, displayName: String, password: String) throws -> StaffUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard users.isEmpty else { throw UserError.alreadyBootstrapped }
        let timestamp = now()
        let user = StaffUser(
            id: UUID().uuidString,
            username: Self.normalizeIdentifier(username),
            displayName: displayName,
            passwordHash: try Bcrypt.hash(password),
            googleId: nil,
            appleId: nil,
            role: .admin,
            mustChangePassword: false,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        users.append(user)
        try persist()
        return StaffUserPublic(user)
    }

    @discardableResult
    func create(username: String, displayName: String, password: String, role: UserRole, mustChangePassword: Bool) throws -> StaffUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let normalized = Self.normalizeIdentifier(username)
        guard !users.contains(where: { $0.username == normalized }) else {
            throw UserError.usernameTaken
        }
        let timestamp = now()
        let user = StaffUser(
            id: UUID().uuidString,
            username: normalized,
            displayName: displayName,
            passwordHash: try Bcrypt.hash(password),
            googleId: nil,
            appleId: nil,
            role: role,
            mustChangePassword: mustChangePassword,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        users.append(user)
        try persist()
        return StaffUserPublic(user)
    }

    /// `username` may be either the account's username or its email —
    /// staff sign in with either.
    func authenticate(username: String, password: String) throws -> StaffUser {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let normalized = Self.normalizeIdentifier(username)
        guard let user = users.first(where: { $0.username == normalized || $0.email == normalized }),
              try Bcrypt.verify(password, created: user.passwordHash) else {
            throw UserError.invalidCredentials
        }
        guard user.active else {
            throw UserError.accountDeactivated
        }
        return user
    }

    /// Returns the user only if their account is still active — used to back
    /// session lookups, so a deactivation takes effect immediately even for an
    /// already-open session.
    func find(id: String) throws -> StaffUser {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let user = users.first(where: { $0.id == id }) else {
            throw UserError.notFound
        }
        guard user.active else {
            throw UserError.accountDeactivated
        }
        return user
    }

    func all() throws -> [StaffUserPublic] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return users.sorted { $0.username < $1.username }.map(StaffUserPublic.init)
    }

    @discardableResult
    func changePassword(id: String, currentPassword: String, newPassword: String) throws -> StaffUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.id == id }) else {
            throw UserError.notFound
        }
        guard try Bcrypt.verify(currentPassword, created: users[idx].passwordHash) else {
            throw UserError.wrongCurrentPassword
        }
        users[idx].passwordHash = try Bcrypt.hash(newPassword)
        users[idx].mustChangePassword = false
        users[idx].updatedAt = now()
        try persist()
        return StaffUserPublic(users[idx])
    }

    /// Self-service, optional — pass `nil` or an empty string to clear it.
    @discardableResult
    func updateEmail(id: String, email: String?) throws -> StaffUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.id == id }) else {
            throw UserError.notFound
        }
        let trimmed = email.map { Self.normalizeIdentifier($0) } ?? ""
        let normalized: String? = trimmed.isEmpty ? nil : trimmed
        if let normalized, users.contains(where: { $0.id != id && $0.email == normalized }) {
            throw UserError.emailTaken
        }
        users[idx].email = normalized
        users[idx].updatedAt = now()
        try persist()
        return StaffUserPublic(users[idx])
    }

    @discardableResult
    func adminResetPassword(id: String, newPassword: String) throws -> StaffUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.id == id }) else {
            throw UserError.notFound
        }
        users[idx].passwordHash = try Bcrypt.hash(newPassword)
        users[idx].mustChangePassword = true
        users[idx].updatedAt = now()
        try persist()
        return StaffUserPublic(users[idx])
    }

    func findByOAuth(provider: OAuthProvider, providerId: String) throws -> StaffUser {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let user = users.first(where: { provider.id(of: $0) == providerId }) else {
            throw UserError.oauthNotLinked
        }
        guard user.active else {
            throw UserError.accountDeactivated
        }
        return user
    }

    @discardableResult
    func linkOAuth(id: String, provider: OAuthProvider, providerId: String, pictureURL: String? = nil, email: String? = nil) throws -> StaffUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        if let existingIdx = users.firstIndex(where: { provider.id(of: $0) == providerId }), users[existingIdx].id != id {
            throw UserError.oauthAlreadyLinkedElsewhere
        }
        guard let idx = users.firstIndex(where: { $0.id == id }) else {
            throw UserError.notFound
        }
        provider.setId(providerId, on: &users[idx])
        if let pictureURL, users[idx].photoURL == nil {
            users[idx].photoURL = pictureURL
        }
        if let email, users[idx].email == nil {
            let normalized = Self.normalizeIdentifier(email)
            if !users.contains(where: { $0.id != id && $0.email == normalized }) {
                users[idx].email = normalized
            }
        }
        users[idx].updatedAt = now()
        try persist()
        return StaffUserPublic(users[idx])
    }

    /// Backfills a profile photo for an account that linked Google before
    /// this field existed — called on every OAuth sign-in, not just linking,
    /// but only ever fills a gap, never overwrites an existing photo.
    @discardableResult
    func setPhotoIfMissing(id: String, pictureURL: String) throws -> StaffUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.id == id }) else {
            throw UserError.notFound
        }
        if users[idx].photoURL == nil {
            users[idx].photoURL = pictureURL
            users[idx].updatedAt = now()
            try persist()
        }
        return StaffUserPublic(users[idx])
    }

    /// Same idea as setPhotoIfMissing, for the email Google supplies on every
    /// sign-in — an account that linked Google before this was captured (or
    /// whose account predates having any email at all) gets it filled in on
    /// their next login, never overwriting one that's already on file.
    @discardableResult
    func setEmailIfMissing(id: String, email: String) throws -> StaffUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.id == id }) else {
            throw UserError.notFound
        }
        if users[idx].email == nil {
            let normalized = Self.normalizeIdentifier(email)
            if !users.contains(where: { $0.id != id && $0.email == normalized }) {
                users[idx].email = normalized
                users[idx].updatedAt = now()
                try persist()
            }
        }
        return StaffUserPublic(users[idx])
    }

    /// `birthday` is "MM-DD" (e.g. "07-26"), or nil/empty to clear it.
    @discardableResult
    func updateBirthday(id: String, birthday: String?) throws -> StaffUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.id == id }) else {
            throw UserError.notFound
        }
        if let birthday, !birthday.isEmpty {
            guard Self.isValidMonthDay(birthday) else {
                throw UserError.invalidBirthdayFormat
            }
            users[idx].birthday = birthday
        } else {
            users[idx].birthday = nil
        }
        users[idx].updatedAt = now()
        try persist()
        return StaffUserPublic(users[idx])
    }

    private static func isValidMonthDay(_ value: String) -> Bool {
        let parts = value.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]) else { return false }
        return (1...12).contains(month) && (1...31).contains(day)
    }

    /// Self-service, optional — pass nil or an empty string to clear it.
    @discardableResult
    func updatePhone(id: String, phone: String?) throws -> StaffUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.id == id }) else {
            throw UserError.notFound
        }
        let trimmed = phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        users[idx].phone = trimmed.isEmpty ? nil : trimmed
        users[idx].updatedAt = now()
        try persist()
        return StaffUserPublic(users[idx])
    }

    @discardableResult
    func deactivate(id: String, requestedBy: String) throws -> StaffUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.id == id }) else {
            throw UserError.notFound
        }
        guard users[idx].id != requestedBy else {
            throw UserError.cannotDeactivateSelf
        }
        if users[idx].role == .admin {
            let activeAdminCount = users.filter { $0.role == .admin && $0.active }.count
            guard activeAdminCount > 1 else {
                throw UserError.cannotDeactivateLastAdmin
            }
        }
        users[idx].active = false
        users[idx].updatedAt = now()
        try persist()
        return StaffUserPublic(users[idx])
    }

    @discardableResult
    func reactivate(id: String) throws -> StaffUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.id == id }) else {
            throw UserError.notFound
        }
        users[idx].active = true
        users[idx].updatedAt = now()
        try persist()
        return StaffUserPublic(users[idx])
    }

    @discardableResult
    func updateRole(id: String, role: UserRole) throws -> StaffUserPublic {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = users.firstIndex(where: { $0.id == id }) else {
            throw UserError.notFound
        }
        users[idx].role = role
        users[idx].updatedAt = now()
        try persist()
        return StaffUserPublic(users[idx])
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            users = try JSONDecoder().decode([StaffUser].self, from: data)
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
