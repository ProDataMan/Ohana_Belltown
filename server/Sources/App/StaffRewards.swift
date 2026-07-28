import Vapor

/// A staff member's running punch count toward a reward — same mechanic as
/// the customer loyalty card, but earned by keeping the site itself up to
/// date (photos, prices, specials, events) rather than by ordering food.
/// What the reward actually is (a free shift meal, schedule preference,
/// etc.) is a real-world decision an admin communicates and fulfills;
/// this just tracks the count and lets an admin redeem it once given.
struct StaffRewardCard: Codable, Content {
    var staffId: String
    var punches: Int
    var totalRedeemed: Int
    var createdAt: String
    var updatedAt: String
}

/// One earned (or manually granted) punch, kept as an activity log entry
/// so admins can see who earned what and when.
struct StaffRewardEvent: Codable, Content {
    var id: String
    var staffId: String
    /// "photo", "price", "special", "event" (auto-detected from editing
    /// actions) or "social"/"other" (always manual — there's no API to
    /// verify a social media post actually happened).
    var category: String
    var note: String?
    /// The admin's staff id who manually granted this, or nil if it was
    /// auto-awarded from the staff member's own edit.
    var awardedBy: String?
    var createdAt: String

    init(id: String = UUID().uuidString, staffId: String, category: String, note: String?, awardedBy: String?, createdAt: String) {
        self.id = id
        self.staffId = staffId
        self.category = category
        self.note = note
        self.awardedBy = awardedBy
        self.createdAt = createdAt
    }
}

struct StaffRewardsData: Codable {
    var cards: [StaffRewardCard]
    var events: [StaffRewardEvent]
}

struct StaffRewardStatus: Content {
    var staffId: String
    var punches: Int
    var punchesNeeded: Int
    var rewardReady: Bool
    var totalRedeemed: Int
}

enum StaffRewardError: Error, Equatable {
    case cardNotFound
    case noRewardAvailable
    case invalidCategory
}

extension StaffRewardError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .cardNotFound: return .notFound
        case .noRewardAvailable: return .badRequest
        case .invalidCategory: return .badRequest
        }
    }

    var reason: String {
        switch self {
        case .cardNotFound: return "No rewards card found for that staff member."
        case .noRewardAvailable: return "This staff member doesn't have enough punches for a reward yet."
        case .invalidCategory: return "Unknown reward category."
        }
    }
}

final class StaffRewardsStore: @unchecked Sendable {
    static let shared = StaffRewardsStore()
    static let punchesNeeded = 10
    static let categories = ["photo", "price", "special", "event", "social", "other"]
    /// Categories a staff member can log for themselves, without an admin —
    /// only the ones that can't be auto-detected from a real edit. Letting
    /// someone self-report "photo"/"price"/"special"/"event" would let them
    /// claim credit without actually doing the edit that's supposed to earn it.
    static let selfReportableCategories = ["social", "other"]
    /// Only auto-awarded punches (from a staff member's own edits, not a
    /// manual admin grant) count against this — caps how many times a day
    /// repeatedly editing the same item can earn a punch, without limiting
    /// genuine deliberate recognition from an admin.
    static let maxAutoAwardsPerDay = 5

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/staff-rewards.json")
    private var data = StaffRewardsData(cards: [], events: [])
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("staff-rewards.json")
        loaded = false
    }

    private func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func dayKey(fromISO8601 iso: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        return formatter.string(from: date)
    }

    private func statusFor(_ card: StaffRewardCard) -> StaffRewardStatus {
        StaffRewardStatus(
            staffId: card.staffId,
            punches: card.punches,
            punchesNeeded: Self.punchesNeeded,
            rewardReady: card.punches >= Self.punchesNeeded,
            totalRedeemed: card.totalRedeemed
        )
    }

    /// Finds a staff member's card, creating a fresh zero-punch one if this
    /// is their first ever award — unlike customer loyalty cards, every
    /// staff member should be able to see a "0/10" status right away rather
    /// than a 404. Assumes the lock is already held.
    private func findOrCreateCardIndex(staffId: String) -> Int {
        if let idx = data.cards.firstIndex(where: { $0.staffId == staffId }) {
            return idx
        }
        let timestamp = now()
        let card = StaffRewardCard(staffId: staffId, punches: 0, totalRedeemed: 0, createdAt: timestamp, updatedAt: timestamp)
        data.cards.append(card)
        return data.cards.count - 1
    }

    func status(staffId: String) throws -> StaffRewardStatus {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let idx = findOrCreateCardIndex(staffId: staffId)
        try persist()
        return statusFor(data.cards[idx])
    }

    func allCards() throws -> [StaffRewardCard] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return data.cards.sorted { $0.punches > $1.punches }
    }

    func recentEvents(limit: Int) throws -> [StaffRewardEvent] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return data.events.reversed().sorted { $0.createdAt > $1.createdAt }.prefix(limit).map { $0 }
    }

    /// Awards one punch. `awardedBy` nil means the system auto-detected the
    /// action from the staff member's own edit; a non-nil admin id means a
    /// manual grant (e.g. for a social media post, which can't be verified
    /// automatically). Auto-awards silently no-op once the daily cap for
    /// that staff member is hit, rather than erroring — this always gets
    /// called alongside a real edit that should succeed regardless.
    @discardableResult
    func award(staffId: String, category: String, note: String?, awardedBy: String?) throws -> StaffRewardStatus {
        try awardBatch(staffId: staffId, categories: [category], note: note, awardedBy: awardedBy)
    }

    /// Same as `award`, but applies one or more categories under a single
    /// lock/persist — a menu edit that adds a photo, sets a price, *and*
    /// marks a special all at once still only touches disk once, not three
    /// times, since this always runs inline inside another route's request.
    @discardableResult
    func awardBatch(staffId: String, categories: [String], note: String?, awardedBy: String?) throws -> StaffRewardStatus {
        for category in categories {
            guard Self.categories.contains(category) else { throw StaffRewardError.invalidCategory }
        }
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let idx = findOrCreateCardIndex(staffId: staffId)
        guard !categories.isEmpty else { return statusFor(data.cards[idx]) }

        let today = Self.dayKey(fromISO8601: now())
        var autoAwardsToday = awardedBy == nil
            ? data.events.filter { $0.staffId == staffId && $0.awardedBy == nil && Self.dayKey(fromISO8601: $0.createdAt) == today }.count
            : 0

        var awardedAny = false
        for category in categories {
            if awardedBy == nil {
                guard autoAwardsToday < Self.maxAutoAwardsPerDay else { continue }
                autoAwardsToday += 1
            }
            let timestamp = now()
            data.events.append(StaffRewardEvent(staffId: staffId, category: category, note: note, awardedBy: awardedBy, createdAt: timestamp))
            data.cards[idx].punches += 1
            data.cards[idx].updatedAt = timestamp
            awardedAny = true
        }
        if awardedAny {
            try persist()
        }
        return statusFor(data.cards[idx])
    }

    /// Convenience for the menu-item PATCH route — diffs a before/after
    /// item and awards whichever of photo/price/special actually changed,
    /// all in one batched write. Never throws; a rewards-system hiccup
    /// should never block a real menu edit from succeeding.
    func awardForMenuEdit(staffId: String, before: MenuItem?, after: MenuItem) {
        guard let before else { return }
        var categories: [String] = []
        if after.images.count > before.images.count {
            categories.append("photo")
        }
        if let newPrice = after.price, newPrice != before.price {
            categories.append("price")
        }
        if after.featured && !before.featured {
            categories.append("special")
        }
        guard !categories.isEmpty else { return }
        try? awardBatch(staffId: staffId, categories: categories, note: nil, awardedBy: nil)
    }

    /// A staff member logging their own activity (e.g. "posted on
    /// Instagram") rather than an admin granting it. Still subject to the
    /// shared daily auto-award cap, same as system-detected punches — it's
    /// unverified, so it shouldn't be able to farm unlimited punches.
    @discardableResult
    func selfReport(staffId: String, category: String, note: String?) throws -> StaffRewardStatus {
        guard Self.selfReportableCategories.contains(category) else { throw StaffRewardError.invalidCategory }
        return try award(staffId: staffId, category: category, note: note, awardedBy: nil)
    }

    @discardableResult
    func redeem(staffId: String, note: String?) throws -> StaffRewardStatus {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = data.cards.firstIndex(where: { $0.staffId == staffId }) else {
            throw StaffRewardError.cardNotFound
        }
        guard data.cards[idx].punches >= Self.punchesNeeded else {
            throw StaffRewardError.noRewardAvailable
        }
        data.cards[idx].punches -= Self.punchesNeeded
        data.cards[idx].totalRedeemed += 1
        data.cards[idx].updatedAt = now()
        data.events.append(StaffRewardEvent(staffId: staffId, category: "redeemed", note: note, awardedBy: nil, createdAt: now()))
        try persist()
        return statusFor(data.cards[idx])
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try Data(contentsOf: fileURL)
            data = try JSONDecoder().decode(StaffRewardsData.self, from: raw)
        } else {
            data = StaffRewardsData(cards: [], events: [])
            try persist()
        }
        loaded = true
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(data)
        try encoded.write(to: fileURL, options: .atomic)
    }
}
