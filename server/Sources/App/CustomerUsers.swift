import Vapor

struct CustomerUser: Codable {
    var id: String
    var email: String
    var displayName: String
    var passwordHash: String
    var verified: Bool
    var verificationToken: String?
    var resetToken: String?
    var resetTokenExpiresAt: String?
    var createdAt: String
    var updatedAt: String
}

struct CustomerUserPublic: Content {
    var id: String
    var email: String
    var displayName: String
    var verified: Bool

    init(_ user: CustomerUser) {
        id = user.id
        email = user.email
        displayName = user.displayName
        verified = user.verified
    }
}

enum CustomerUserError: Error {
    case emailTaken
    case invalidCredentials
    case notFound
    case invalidOrExpiredToken
    case wrongCurrentPassword
}

extension CustomerUserError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .emailTaken: return .conflict
        case .invalidCredentials, .wrongCurrentPassword: return .unauthorized
        case .notFound: return .notFound
        case .invalidOrExpiredToken: return .badRequest
        }
    }

    var reason: String {
        switch self {
        case .emailTaken: return "An account with that email already exists."
        case .invalidCredentials: return "Incorrect email or password."
        case .notFound: return "Account not found."
        case .invalidOrExpiredToken: return "That link is invalid or has expired."
        case .wrongCurrentPassword: return "Current password is incorrect."
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
        guard let user = users.first(where: { $0.email == normalized }),
              try Bcrypt.verify(password, created: user.passwordHash) else {
            throw CustomerUserError.invalidCredentials
        }
        return user
    }

    func find(id: String) throws -> CustomerUser {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let user = users.first(where: { $0.id == id }) else {
            throw CustomerUserError.notFound
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
        guard try Bcrypt.verify(currentPassword, created: users[idx].passwordHash) else {
            throw CustomerUserError.wrongCurrentPassword
        }
        users[idx].passwordHash = try Bcrypt.hash(newPassword)
        users[idx].updatedAt = nowString()
        try persist()
        return CustomerUserPublic(users[idx])
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
