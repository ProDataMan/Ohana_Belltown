import Vapor

struct WaitlistEntry: Codable, Content {
    var id: String
    var name: String
    var phone: String
    var partySize: Int
    var note: String?
    var status: String
    var createdAt: String
    var updatedAt: String
}

enum WaitlistError: Error, Equatable {
    case entryNotFound
}

extension WaitlistError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .entryNotFound: return .notFound
        }
    }

    var reason: String {
        switch self {
        case .entryNotFound: return "Waitlist entry not found."
        }
    }
}

final class WaitlistStore: @unchecked Sendable {
    static let shared = WaitlistStore()
    /// How long a "waiting" entry stays on the live queue before it's
    /// treated as stale (customer presumably left or was seated without
    /// staff clearing it) — this is a same-day walk-in list, not a
    /// reservation book, so old entries shouldn't linger forever.
    static let staleAfterSeconds: TimeInterval = 4 * 60 * 60

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/waitlist.json")
    private var entries: [WaitlistEntry] = []
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("waitlist.json")
        loaded = false
    }

    private func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    @discardableResult
    func join(name: String, phone: String, partySize: Int, note: String?) throws -> WaitlistEntry {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let timestamp = now()
        let entry = WaitlistEntry(
            id: UUID().uuidString,
            name: name,
            phone: LoyaltyStore.normalizePhone(phone),
            partySize: partySize,
            note: note,
            status: "waiting",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        entries.append(entry)
        try persist()
        return entry
    }

    /// Active, non-stale entries currently waiting, oldest first.
    func active() throws -> [WaitlistEntry] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let cutoff = Date().addingTimeInterval(-Self.staleAfterSeconds)
        let formatter = ISO8601DateFormatter()
        return entries
            .filter { entry in
                guard entry.status == "waiting" || entry.status == "notified" else { return false }
                guard let created = formatter.date(from: entry.createdAt) else { return true }
                return created > cutoff
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    func markNotified(id: String) throws -> WaitlistEntry {
        try updateStatus(id: id, status: "notified")
    }

    @discardableResult
    func remove(id: String) throws -> WaitlistEntry {
        try updateStatus(id: id, status: "removed")
    }

    private func updateStatus(id: String, status: String) throws -> WaitlistEntry {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = entries.firstIndex(where: { $0.id == id }) else {
            throw WaitlistError.entryNotFound
        }
        entries[idx].status = status
        entries[idx].updatedAt = now()
        try persist()
        return entries[idx]
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([WaitlistEntry].self, from: raw)
        } else {
            entries = []
            try persist()
        }
        loaded = true
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(entries)
        try encoded.write(to: fileURL, options: .atomic)
    }
}
