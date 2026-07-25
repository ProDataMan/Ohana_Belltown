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
    var role: UserRole
    var mustChangePassword: Bool
    var active: Bool
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, username, displayName, passwordHash, email, googleId, appleId, role, mustChangePassword, active, createdAt, updatedAt
    }

    init(
        id: String, username: String, displayName: String, passwordHash: String,
        googleId: String?, appleId: String?, role: UserRole, mustChangePassword: Bool,
        active: Bool = true, createdAt: String, updatedAt: String, email: String? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.passwordHash = passwordHash
        self.email = email
        self.googleId = googleId
        self.appleId = appleId
        self.role = role
        self.mustChangePassword = mustChangePassword
        self.active = active
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
        role = try container.decode(UserRole.self, forKey: .role)
        mustChangePassword = try container.decode(Bool.self, forKey: .mustChangePassword)
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
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
    var active: Bool

    init(_ user: StaffUser) {
        id = user.id
        username = user.username
        displayName = user.displayName
        email = user.email
        role = user.role
        mustChangePassword = user.mustChangePassword
        googleLinked = user.googleId != nil
        appleLinked = user.appleId != nil
        active = user.active
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
}

extension UserError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .usernameTaken, .oauthAlreadyLinkedElsewhere, .emailTaken: return .conflict
        case .invalidCredentials, .wrongCurrentPassword, .accountDeactivated: return .unauthorized
        case .notFound, .oauthNotLinked: return .notFound
        case .alreadyBootstrapped, .cannotDeactivateSelf, .cannotDeactivateLastAdmin: return .forbidden
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
    func linkOAuth(id: String, provider: OAuthProvider, providerId: String) throws -> StaffUserPublic {
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
