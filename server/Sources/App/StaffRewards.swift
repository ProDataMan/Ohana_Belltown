import Vapor

/// A staff member's running point balance toward a reward — same mechanic
/// as the customer loyalty card, but earned by keeping the site itself up
/// to date (photos, prices, specials, events) rather than by ordering food.
/// 1 point = roughly $1 of reward value (see `StaffRewardsStore.pointValue`)
/// — 10 points redeems one free Classic Ohana Roll or Happy Hour appetizer,
/// which average ~$9.83 across both lists as of 2026-07-28.
struct StaffRewardCard: Codable, Content {
    var staffId: String
    var points: Int
    var totalRedeemed: Int
    var createdAt: String
    var updatedAt: String

    /// "punches" is the pre-2026-07-28 key name, back when every action was
    /// worth a flat 1 regardless of effort — decoding it straight into
    /// `points` is a reasonable reinterpretation since those flat values
    /// sat within the same 1-3 range the new per-category values use.
    enum CodingKeys: String, CodingKey {
        case staffId, points, punches, totalRedeemed, createdAt, updatedAt
    }

    init(staffId: String, points: Int, totalRedeemed: Int, createdAt: String, updatedAt: String) {
        self.staffId = staffId
        self.points = points
        self.totalRedeemed = totalRedeemed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        staffId = try container.decode(String.self, forKey: .staffId)
        if let points = try container.decodeIfPresent(Int.self, forKey: .points) {
            self.points = points
        } else {
            points = try container.decodeIfPresent(Int.self, forKey: .punches) ?? 0
        }
        totalRedeemed = try container.decode(Int.self, forKey: .totalRedeemed)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(staffId, forKey: .staffId)
        try container.encode(points, forKey: .points)
        try container.encode(totalRedeemed, forKey: .totalRedeemed)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

/// One earned (or manually granted) award, kept as an activity log entry
/// so admins can see who earned what, worth how many points, and when.
struct StaffRewardEvent: Codable, Content {
    var id: String
    var staffId: String
    /// "photo", "price", "special", "event" (auto-detected from editing
    /// actions) or "social"/"other" (always manual — there's no API to
    /// verify a social media post actually happened).
    var category: String
    var note: String?
    /// The admin's staff id who manually granted this, or nil if it was
    /// auto-awarded/self-reported.
    var awardedBy: String?
    /// Points this specific event was worth at the time — stored rather
    /// than recomputed from category, so the log stays accurate even if
    /// point values are retuned later.
    var points: Int
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, staffId, category, note, awardedBy, points, createdAt
    }

    init(id: String = UUID().uuidString, staffId: String, category: String, note: String?, awardedBy: String?, points: Int, createdAt: String) {
        self.id = id
        self.staffId = staffId
        self.category = category
        self.note = note
        self.awardedBy = awardedBy
        self.points = points
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        staffId = try container.decode(String.self, forKey: .staffId)
        category = try container.decode(String.self, forKey: .category)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        awardedBy = try container.decodeIfPresent(String.self, forKey: .awardedBy)
        // Pre-2026-07-28 events predate per-category point values and were
        // always worth a flat 1 punch.
        points = try container.decodeIfPresent(Int.self, forKey: .points) ?? 1
        createdAt = try container.decode(String.self, forKey: .createdAt)
    }
}

struct StaffRewardsData: Codable {
    var cards: [StaffRewardCard]
    var events: [StaffRewardEvent]
}

struct StaffRewardStatus: Content {
    var staffId: String
    var points: Int
    var pointsNeeded: Int
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
        case .noRewardAvailable: return "This staff member doesn't have enough points for a reward yet."
        case .invalidCategory: return "Unknown reward category."
        }
    }
}

final class StaffRewardsStore: @unchecked Sendable {
    static let shared = StaffRewardsStore()
    /// 10 points ≈ $9.83, the average cost across the Classic Ohana Rolls
    /// ($8.90 avg) and Happy Hour appetizers ($11.00 avg) that make up the
    /// reward — a deliberate ~$1/point anchor, not an arbitrary count.
    static let pointsNeeded = 10
    /// Points awarded per category, scaled to real effort and business
    /// value rather than a flat amount per action:
    ///   - marking a special / updating a price: trivial data-entry effort
    ///   - adding a photo / adding an event: real content-creation effort
    ///   - a social media post: the most effort (shoot, write, post) and
    ///     the most marketing value, so it's worth the most
    static let pointValues: [String: Int] = [
        "special": 1,
        "price": 1,
        "photo": 2,
        "event": 2,
        "other": 2,
        "social": 3,
    ]
    static var categories: [String] { Array(pointValues.keys) }
    /// Categories a staff member can log for themselves, without an admin —
    /// only the ones that can't be auto-detected from a real edit. Letting
    /// someone self-report "photo"/"price"/"special"/"event" would let them
    /// claim credit without actually doing the edit that's supposed to earn it.
    static let selfReportableCategories = ["social", "other"]
    /// Only auto-awarded/self-reported points (not a manual admin grant)
    /// count against this — caps how many points a day repeatedly editing
    /// the same item (or repeatedly self-reporting) can earn, without
    /// limiting genuine deliberate recognition from an admin.
    static let maxAutoPointsPerDay = 10

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
            points: card.points,
            pointsNeeded: Self.pointsNeeded,
            rewardReady: card.points >= Self.pointsNeeded,
            totalRedeemed: card.totalRedeemed
        )
    }

    /// Finds a staff member's card, creating a fresh zero-point one if this
    /// is their first ever award — unlike customer loyalty cards, every
    /// staff member should be able to see a "0/10" status right away rather
    /// than a 404. Assumes the lock is already held.
    private func findOrCreateCardIndex(staffId: String) -> Int {
        if let idx = data.cards.firstIndex(where: { $0.staffId == staffId }) {
            return idx
        }
        let timestamp = now()
        let card = StaffRewardCard(staffId: staffId, points: 0, totalRedeemed: 0, createdAt: timestamp, updatedAt: timestamp)
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
        return data.cards.sorted { $0.points > $1.points }
    }

    func recentEvents(limit: Int) throws -> [StaffRewardEvent] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return data.events.reversed().sorted { $0.createdAt > $1.createdAt }.prefix(limit).map { $0 }
    }

    /// Awards points for one category. `awardedBy` nil means the system
    /// auto-detected the action from the staff member's own edit (or they
    /// self-reported it); a non-nil admin id means a manual grant. Auto/
    /// self-reported points silently no-op once the daily cap is hit,
    /// rather than erroring — this always gets called alongside a real
    /// edit that should succeed regardless.
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
            guard let pointValue = Self.pointValues[category], pointValue > 0 else {
                throw StaffRewardError.invalidCategory
            }
        }
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let idx = findOrCreateCardIndex(staffId: staffId)
        guard !categories.isEmpty else { return statusFor(data.cards[idx]) }

        let today = Self.dayKey(fromISO8601: now())
        // "redeemed" events are excluded — spending points isn't an earning
        // event, and their negative point value would otherwise loosen the
        // cap for the rest of the day.
        var autoPointsToday = awardedBy == nil
            ? data.events
                .filter { $0.staffId == staffId && $0.awardedBy == nil && $0.category != "redeemed" && Self.dayKey(fromISO8601: $0.createdAt) == today }
                .reduce(0) { $0 + $1.points }
            : 0

        var awardedAny = false
        for category in categories {
            let pointValue = Self.pointValues[category] ?? 1
            if awardedBy == nil {
                guard autoPointsToday < Self.maxAutoPointsPerDay else { continue }
                autoPointsToday += pointValue
            }
            let timestamp = now()
            data.events.append(StaffRewardEvent(staffId: staffId, category: category, note: note, awardedBy: awardedBy, points: pointValue, createdAt: timestamp))
            data.cards[idx].points += pointValue
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
    /// shared daily auto-award cap, same as system-detected points — it's
    /// unverified, so it shouldn't be able to farm unlimited points.
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
        guard data.cards[idx].points >= Self.pointsNeeded else {
            throw StaffRewardError.noRewardAvailable
        }
        data.cards[idx].points -= Self.pointsNeeded
        data.cards[idx].totalRedeemed += 1
        data.cards[idx].updatedAt = now()
        data.events.append(StaffRewardEvent(staffId: staffId, category: "redeemed", note: note, awardedBy: nil, points: -Self.pointsNeeded, createdAt: now()))
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
