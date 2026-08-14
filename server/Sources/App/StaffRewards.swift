import Vapor

/// A staff member's running point balance toward a reward — same mechanic
/// as the customer loyalty card, but earned by keeping the site itself up
/// to date (photos, prices, specials, events) rather than by ordering food.
/// See `StaffRewardsStore.pointValues` — rescaled smaller in July 2026 (was
/// 100:1 points-to-dollar) now that most items already have a photo, so an
/// individual action reads as a smaller slice of the whole reward.
struct StaffRewardCard: Codable, Content {
    var staffId: String
    var points: Int
    var totalRedeemed: Int
    var createdAt: String
    var updatedAt: String

    /// "punches" is the pre-2026-07-28 key name, back when every action was
    /// worth a flat 1 regardless of effort — decoding it straight into
    /// `points` is a reasonable reinterpretation, even though it now reads
    /// as a tiny balance under the rescaled 100:1 system (an admin can
    /// manually top up anyone whose history got flattened this way).
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
    /// actions), "social"/"other" (always manual — there's no API to
    /// verify a social media post actually happened), or "redeemed".
    var category: String
    var note: String?
    /// The admin's staff id who manually granted this, or nil if it was
    /// auto-awarded/self-reported.
    var awardedBy: String?
    /// Points this specific event was worth at the time (negative for a
    /// redemption) — stored rather than recomputed from category/catalog,
    /// so the log stays accurate even if values are retuned later.
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

/// Something points can be redeemed for. `pointCost` is nil for a
/// placeholder item whose real-world cost hasn't been set yet (e.g. swag
/// waiting on a supplier quote) — it shows up in the catalog so staff can
/// see what's coming, but can't actually be redeemed until priced.
struct RewardCatalogItem: Codable, Content, Equatable {
    var id: String
    var name: String
    var pointCost: Int?

    init(id: String = UUID().uuidString, name: String, pointCost: Int?) {
        self.id = id
        self.name = name
        self.pointCost = pointCost
    }
}

/// A staff member's request for credit on a social media post — unlike
/// photo/price/special/event, there's no way to auto-verify a post
/// happened, so it needs a link and an admin's approval before the points
/// land, rather than being instant like `selfReport`'s "other" category.
struct StaffSocialRequest: Codable, Content {
    var id: String
    var staffId: String
    var link: String
    var note: String?
    var status: String
    var createdAt: String
    var reviewedAt: String?

    init(id: String = UUID().uuidString, staffId: String, link: String, note: String?, status: String, createdAt: String, reviewedAt: String? = nil) {
        self.id = id
        self.staffId = staffId
        self.link = link
        self.note = note
        self.status = status
        self.createdAt = createdAt
        self.reviewedAt = reviewedAt
    }
}

struct StaffRewardsData: Codable {
    var cards: [StaffRewardCard]
    var events: [StaffRewardEvent]
    var catalog: [RewardCatalogItem]?
    var socialRequests: [StaffSocialRequest]?
    /// Admin-editable override for `StaffRewardsStore.defaultPointValues` —
    /// nil until an admin has ever saved changes from `/staff-rewards-admin.html`.
    var pointValues: [String: Int]?

    init(
        cards: [StaffRewardCard], events: [StaffRewardEvent], catalog: [RewardCatalogItem]? = nil,
        socialRequests: [StaffSocialRequest]? = nil, pointValues: [String: Int]? = nil
    ) {
        self.cards = cards
        self.events = events
        self.catalog = catalog
        self.socialRequests = socialRequests
        self.pointValues = pointValues
    }
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
    case catalogItemNotFound
    case catalogItemNotPriced
    case linkRequired
    case socialRequestNotFound
    case socialRequestAlreadyReviewed
    case invalidPointValue
}

extension StaffRewardError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .cardNotFound: return .notFound
        case .noRewardAvailable: return .badRequest
        case .invalidCategory: return .badRequest
        case .catalogItemNotFound: return .notFound
        case .catalogItemNotPriced: return .badRequest
        case .linkRequired: return .badRequest
        case .socialRequestNotFound: return .notFound
        case .socialRequestAlreadyReviewed: return .badRequest
        case .invalidPointValue: return .badRequest
        }
    }

    var reason: String {
        switch self {
        case .cardNotFound: return "No rewards card found for that staff member."
        case .noRewardAvailable: return "This staff member doesn't have enough points for that yet."
        case .invalidCategory: return "Unknown reward category."
        case .catalogItemNotFound: return "That reward item doesn't exist."
        case .catalogItemNotPriced: return "That reward's point cost hasn't been set yet."
        case .linkRequired: return "A link to the post is required."
        case .socialRequestNotFound: return "That request doesn't exist."
        case .socialRequestAlreadyReviewed: return "That request has already been reviewed."
        case .invalidPointValue: return "Point values can't be negative."
        }
    }
}

final class StaffRewardsStore: @unchecked Sendable {
    static let shared = StaffRewardsStore()
    /// Fallback target for the progress bar if the catalog is ever empty or
    /// entirely unpriced — otherwise `statusFor` uses the cheapest priced
    /// catalog item instead, so the target always reflects something
    /// actually redeemable.
    static let pointsNeeded = 100
    /// Points awarded per category, scaled to real effort and business
    /// value rather than a flat amount per action. Rescaled down (roughly
    /// 1/10, though not a strict formula) in July 2026 — the original
    /// values assumed most items still needed a photo; now that most do,
    /// a single photo/price/special edit should read as a smaller slice of
    /// the whole reward, not the same big jump it used to be:
    ///   - marking a special / updating a price: trivial data-entry effort
    ///   - adding a photo / adding an event: real content-creation effort
    ///   - a social media post: the most effort (shoot, write, post) and
    ///     the most marketing value, so it's worth the most
    /// "photo_bounty" is a separate, higher-value category (not directly
    /// in the effort scale above) — see `awardForMenuEdit`: it's what
    /// actually gets awarded instead of "photo" when an item goes from zero
    /// photos to one, since a menu with photo gaps still remaining should
    /// pay a real bounty to close them, not the same flat rate as touching
    /// up an item that already had one.
    ///
    /// These are just the seed/fallback values — an admin can edit them from
    /// `/staff-rewards-admin.html` (`GET`/`PUT /api/staff-rewards/point-values`),
    /// which persists an override in `StaffRewardsData.pointValues`. Always
    /// go through `effectivePointValues()` / `currentPointValue(for:)`
    /// rather than this directly, so an edited value actually takes effect.
    static let defaultPointValues: [String: Int] = [
        "special": 10,
        "price": 10,
        "photo": 25,
        "photo_bounty": 50,
        "event": 35,
        "other": 20,
        "social": 30,
    ]
    static var categories: [String] { Array(defaultPointValues.keys) }
    /// Categories a staff member can log for themselves and have credited
    /// instantly, without an admin. "social" is deliberately excluded —
    /// unlike "other", it goes through `submitSocialRequest` instead, since
    /// it needs a link and an admin's approval before the points land.
    /// "photo_bounty" is excluded too — it's only ever system-detected from
    /// a real menu edit, never something to self-report.
    static let selfReportableCategories = ["other"]
    /// Only auto-awarded/self-reported points (not a manual admin grant)
    /// count against this — caps how many points a day repeatedly editing
    /// the same item (or repeatedly self-reporting) can earn, without
    /// limiting genuine deliberate recognition from an admin.
    static let maxAutoPointsPerDay = 100

    /// Seeded the first time the catalog is loaded — the base food reward
    /// (priced against real Happy Hour menu costs, rescaled to 1000 points
    /// alongside the July 2026 point-value rescale, see `defaultPointValues`)
    /// plus swag, priced at that same ~100 points per $1, against actual
    /// shop prices from `/api/swag/products` (Bandana $10, 26th Anniversary
    /// T-Shirt $25, Straw Hat $50 as of 2026-08-02).
    static let defaultCatalog: [RewardCatalogItem] = [
        RewardCatalogItem(id: "roll-or-appetizer", name: "Classic Ohana Roll or Happy Hour Appetizer", pointCost: 1000),
        RewardCatalogItem(id: "bandana", name: "Bandana", pointCost: 1000),
        RewardCatalogItem(id: "tshirt", name: "26th Anniversary T-Shirt", pointCost: 2500),
        RewardCatalogItem(id: "hat", name: "Straw Hat", pointCost: 5000),
    ]

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
        let cheapestCost = (data.catalog ?? []).compactMap(\.pointCost).filter { $0 > 0 }.min() ?? Self.pointsNeeded
        return StaffRewardStatus(
            staffId: card.staffId,
            points: card.points,
            pointsNeeded: cheapestCost,
            rewardReady: card.points >= cheapestCost,
            totalRedeemed: card.totalRedeemed
        )
    }

    /// Finds a staff member's card, creating a fresh zero-point one if this
    /// is their first ever award — unlike customer loyalty cards, every
    /// staff member should be able to see a "0/1000" status right away
    /// rather than a 404. Assumes the lock is already held.
    private func findOrCreateCardIndex(staffId: String) -> Int {
        if let idx = data.cards.firstIndex(where: { $0.staffId == staffId }) {
            return idx
        }
        let timestamp = now()
        let card = StaffRewardCard(staffId: staffId, points: 0, totalRedeemed: 0, createdAt: timestamp, updatedAt: timestamp)
        data.cards.append(card)
        return data.cards.count - 1
    }

    /// Adds points and logs the event — the shared core of every
    /// point-granting path (auto-award, self-report, and approving a social
    /// request). Assumes the lock is already held; callers that also need
    /// to persist/return a status do so themselves, since NSLock isn't
    /// reentrant and this may run from inside another locked method.
    @discardableResult
    private func creditPoints(staffId: String, category: String, note: String?, awardedBy: String?, pointValue: Int) -> Int {
        let idx = findOrCreateCardIndex(staffId: staffId)
        let timestamp = now()
        data.events.append(StaffRewardEvent(staffId: staffId, category: category, note: note, awardedBy: awardedBy, points: pointValue, createdAt: timestamp))
        data.cards[idx].points += pointValue
        data.cards[idx].updatedAt = timestamp
        return idx
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

    func catalog() throws -> [RewardCatalogItem] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return data.catalog ?? []
    }

    @discardableResult
    func saveCatalog(_ items: [RewardCatalogItem]) throws -> [RewardCatalogItem] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        data.catalog = items
        try persist()
        return items
    }

    /// Lock-free — assumes the caller already holds `lock` and has already
    /// called `loadIfNeeded()`. `Self.defaultPointValues` fills in any
    /// category missing from a possibly-stale persisted override (e.g. one
    /// saved before "photo_bounty" existed), so a value is always available.
    private func currentPointValues() -> [String: Int] {
        guard let override = data.pointValues else { return Self.defaultPointValues }
        return Self.defaultPointValues.merging(override) { _, overridden in overridden }
    }

    func pointValues() throws -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return currentPointValues()
    }

    @discardableResult
    func savePointValues(_ values: [String: Int]) throws -> [String: Int] {
        guard values.values.allSatisfy({ $0 >= 0 }) else {
            throw StaffRewardError.invalidPointValue
        }
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        data.pointValues = values
        try persist()
        return currentPointValues()
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
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let pointValues = currentPointValues()
        for category in categories {
            guard pointValues[category] != nil else {
                throw StaffRewardError.invalidCategory
            }
        }
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
            let pointValue = pointValues[category] ?? 1
            if awardedBy == nil {
                guard autoPointsToday < Self.maxAutoPointsPerDay else { continue }
                autoPointsToday += pointValue
            }
            creditPoints(staffId: staffId, category: category, note: note, awardedBy: awardedBy, pointValue: pointValue)
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
        if before.images.isEmpty && !after.images.isEmpty {
            // Bounty rate — this item had zero photos before, so closing
            // that specific gap is worth double the normal photo rate.
            categories.append("photo_bounty")
        } else if after.images.count > before.images.count {
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

    /// A staff member requesting credit for a social media post — always
    /// needs a link, and never grants points directly; an admin has to
    /// approve it first via `reviewSocialRequest`.
    @discardableResult
    func submitSocialRequest(staffId: String, link: String, note: String?) throws -> StaffSocialRequest {
        let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLink.isEmpty else { throw StaffRewardError.linkRequired }
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let request = StaffSocialRequest(staffId: staffId, link: trimmedLink, note: note, status: "pending", createdAt: now())
        data.socialRequests = (data.socialRequests ?? []) + [request]
        try persist()
        return request
    }

    func allSocialRequests() throws -> [StaffSocialRequest] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return (data.socialRequests ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    /// Approving credits the "social" point value to the requester,
    /// attributed to the reviewing admin — exempt from the daily
    /// auto-award cap, same as any other manual grant, since a human has
    /// now verified it actually happened.
    @discardableResult
    func reviewSocialRequest(id: String, approve: Bool, reviewerId: String) throws -> StaffSocialRequest {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard var requests = data.socialRequests, let idx = requests.firstIndex(where: { $0.id == id }) else {
            throw StaffRewardError.socialRequestNotFound
        }
        guard requests[idx].status == "pending" else {
            throw StaffRewardError.socialRequestAlreadyReviewed
        }
        requests[idx].status = approve ? "approved" : "denied"
        requests[idx].reviewedAt = now()
        if approve {
            let pointValue = currentPointValues()["social"] ?? 30
            creditPoints(staffId: requests[idx].staffId, category: "social", note: requests[idx].link, awardedBy: reviewerId, pointValue: pointValue)
        }
        data.socialRequests = requests
        try persist()
        return requests[idx]
    }

    /// Redeems one catalog item for a staff member — an admin action, since
    /// it means physically handing over food or swag. Fails if the item
    /// doesn't exist, hasn't been priced yet, or the staff member doesn't
    /// have enough points.
    @discardableResult
    func redeem(staffId: String, catalogItemId: String, note: String?) throws -> StaffRewardStatus {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let item = (data.catalog ?? []).first(where: { $0.id == catalogItemId }) else {
            throw StaffRewardError.catalogItemNotFound
        }
        guard let cost = item.pointCost, cost > 0 else {
            throw StaffRewardError.catalogItemNotPriced
        }
        guard let idx = data.cards.firstIndex(where: { $0.staffId == staffId }) else {
            throw StaffRewardError.cardNotFound
        }
        guard data.cards[idx].points >= cost else {
            throw StaffRewardError.noRewardAvailable
        }
        data.cards[idx].points -= cost
        data.cards[idx].totalRedeemed += 1
        data.cards[idx].updatedAt = now()
        let combinedNote = [item.name, note].compactMap { $0 }.joined(separator: " — ")
        data.events.append(StaffRewardEvent(staffId: staffId, category: "redeemed", note: combinedNote, awardedBy: nil, points: -cost, createdAt: now()))
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
        }
        if data.catalog == nil {
            data.catalog = Self.defaultCatalog
        }
        try persist()
        loaded = true
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(data)
        try encoded.write(to: fileURL, options: .atomic)
    }
}
