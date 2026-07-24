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
    var role: UserRole
    var mustChangePassword: Bool
    var createdAt: String
    var updatedAt: String
}

struct StaffUserPublic: Content {
    var id: String
    var username: String
    var displayName: String
    var role: UserRole
    var mustChangePassword: Bool

    init(_ user: StaffUser) {
        id = user.id
        username = user.username
        displayName = user.displayName
        role = user.role
        mustChangePassword = user.mustChangePassword
    }
}

enum UserError: Error {
    case usernameTaken
    case invalidCredentials
    case notFound
    case alreadyBootstrapped
    case wrongCurrentPassword
}

extension UserError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .usernameTaken: return .conflict
        case .invalidCredentials, .wrongCurrentPassword: return .unauthorized
        case .notFound: return .notFound
        case .alreadyBootstrapped: return .forbidden
        }
    }

    var reason: String {
        switch self {
        case .usernameTaken: return "That username is already taken."
        case .invalidCredentials: return "Incorrect username or password."
        case .notFound: return "User not found."
        case .alreadyBootstrapped: return "Setup has already been completed."
        case .wrongCurrentPassword: return "Current password is incorrect."
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
    }

    private func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func normalizeUsername(_ raw: String) -> String {
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
            username: Self.normalizeUsername(username),
            displayName: displayName,
            passwordHash: try Bcrypt.hash(password),
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
        let normalized = Self.normalizeUsername(username)
        guard !users.contains(where: { $0.username == normalized }) else {
            throw UserError.usernameTaken
        }
        let timestamp = now()
        let user = StaffUser(
            id: UUID().uuidString,
            username: normalized,
            displayName: displayName,
            passwordHash: try Bcrypt.hash(password),
            role: role,
            mustChangePassword: mustChangePassword,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        users.append(user)
        try persist()
        return StaffUserPublic(user)
    }

    func authenticate(username: String, password: String) throws -> StaffUser {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let normalized = Self.normalizeUsername(username)
        guard let user = users.first(where: { $0.username == normalized }),
              try Bcrypt.verify(password, created: user.passwordHash) else {
            throw UserError.invalidCredentials
        }
        return user
    }

    func find(id: String) throws -> StaffUser {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let user = users.first(where: { $0.id == id }) else {
            throw UserError.notFound
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
