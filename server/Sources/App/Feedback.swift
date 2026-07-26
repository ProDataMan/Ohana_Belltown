import Vapor

struct FeedbackEntry: Codable, Content {
    var id: String
    /// "website" | "food" | "service" | "other"
    var category: String
    /// Optional 1-5 star rating — feedback without one still counts, just
    /// doesn't factor into the average.
    var rating: Int?
    var message: String
    /// Which page the widget was open on when submitted, for context.
    var page: String?
    /// Optional — only if the guest wants a reply.
    var contactEmail: String?
    var acknowledged: Bool
    var createdAt: String
}

struct FeedbackData: Codable {
    var entries: [FeedbackEntry]
    /// Pacific-time "yyyy-MM-dd" of the last date the 9am digest was sent for
    /// — lets the background check be a dumb "has today happened yet"
    /// poll instead of needing precise, restart-proof timing.
    var lastDigestSentDate: String?

    init(entries: [FeedbackEntry] = [], lastDigestSentDate: String? = nil) {
        self.entries = entries
        self.lastDigestSentDate = lastDigestSentDate
    }
}

final class FeedbackStore: @unchecked Sendable {
    static let shared = FeedbackStore()
    static let retentionDays: Double = 180

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/feedback.json")
    private var data = FeedbackData()
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("feedback.json")
        loaded = false
    }

    private func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    static func dayKey(_ date: Date, timeZone: TimeZone = FeedbackStore.pacific) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    @discardableResult
    func submit(category: String, rating: Int?, message: String, page: String?, contactEmail: String?) throws -> FeedbackEntry {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let timestamp = now()
        let entry = FeedbackEntry(
            id: UUID().uuidString, category: category, rating: rating, message: message,
            page: page, contactEmail: contactEmail, acknowledged: false, createdAt: timestamp
        )
        data.entries.append(entry)
        try persist()
        return entry
    }

    /// Newest first, most recent `days` days.
    func recent(days: Int) throws -> [FeedbackEntry] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let formatter = ISO8601DateFormatter()
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        // ISO8601DateFormatter only has second-level resolution, so two
        // submissions in the same second tie on createdAt — reverse first so
        // a stable sort resolves ties to newest-inserted-first, not
        // oldest-inserted-first.
        return data.entries
            .reversed()
            .filter { entry in
                guard let created = formatter.date(from: entry.createdAt) else { return true }
                return created >= cutoff
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func unacknowledgedCount() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return data.entries.filter { !$0.acknowledged }.count
    }

    func acknowledgeAll() throws {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        for idx in data.entries.indices {
            data.entries[idx].acknowledged = true
        }
        try persist()
    }

    /// All feedback whose createdAt falls on the given Pacific-time calendar
    /// day (e.g. "yesterday", for the 9am digest).
    func entries(onDay dayKey: String) throws -> [FeedbackEntry] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let formatter = ISO8601DateFormatter()
        return data.entries
            .filter { entry in
                guard let created = formatter.date(from: entry.createdAt) else { return false }
                return Self.dayKey(created) == dayKey
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func hasSentDigest(for dayKey: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return data.lastDigestSentDate == dayKey
    }

    func markDigestSent(for dayKey: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        data.lastDigestSentDate = dayKey
        try persist()
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try Data(contentsOf: fileURL)
            data = try JSONDecoder().decode(FeedbackData.self, from: raw)
        } else {
            data = FeedbackData()
            try persist()
        }
        loaded = true
    }

    private func persist() throws {
        let formatter = ISO8601DateFormatter()
        let cutoff = Date().addingTimeInterval(-Self.retentionDays * 24 * 3600)
        data.entries = data.entries.filter { entry in
            guard let created = formatter.date(from: entry.createdAt) else { return true }
            return created > cutoff
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(data)
        try encoded.write(to: fileURL, options: .atomic)
    }
}
