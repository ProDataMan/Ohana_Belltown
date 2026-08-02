import Vapor

struct LoyaltyCustomer: Codable, Content {
    var phone: String
    var punches: Int
    /// Tenths of a punch accumulated from approved photo/social bonus claims
    /// (0-9) — rolls over into a real punch once it reaches 10.
    var bonusPoints: Int
    var totalRedeemed: Int
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case phone, punches, bonusPoints, totalRedeemed, createdAt, updatedAt
    }

    init(phone: String, punches: Int, bonusPoints: Int = 0, totalRedeemed: Int, createdAt: String, updatedAt: String) {
        self.phone = phone
        self.punches = punches
        self.bonusPoints = bonusPoints
        self.totalRedeemed = totalRedeemed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phone = try container.decode(String.self, forKey: .phone)
        punches = try container.decode(Int.self, forKey: .punches)
        bonusPoints = try container.decodeIfPresent(Int.self, forKey: .bonusPoints) ?? 0
        totalRedeemed = try container.decode(Int.self, forKey: .totalRedeemed)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }
}

struct BonusRequest: Codable, Content {
    var id: String
    var phone: String
    var type: String
    var content: String
    var note: String?
    var status: String
    var createdAt: String
    var reviewedAt: String?
    /// Tenths of a punch this specific claim actually earned (0 or 1) —
    /// 0 once the daily cap on rewarded claims has already been hit that day.
    var pointsAwarded: Int
    /// Which dish this is about — required for a "photo" claim (so the
    /// photo has somewhere to go once approved), optional for "social"
    /// (a social tag isn't always about one specific dish). `menuItemName`
    /// is denormalized purely for display in the staff review queue, since
    /// the item could be renamed or deleted before anyone reviews this.
    var menuItemId: String?
    var menuItemName: String?

    enum CodingKeys: String, CodingKey {
        case id, phone, type, content, note, status, createdAt, reviewedAt, pointsAwarded, menuItemId, menuItemName
    }

    init(
        id: String, phone: String, type: String, content: String, note: String?,
        status: String, createdAt: String, reviewedAt: String?, pointsAwarded: Int = 0,
        menuItemId: String? = nil, menuItemName: String? = nil
    ) {
        self.id = id
        self.phone = phone
        self.type = type
        self.content = content
        self.note = note
        self.status = status
        self.createdAt = createdAt
        self.reviewedAt = reviewedAt
        self.pointsAwarded = pointsAwarded
        self.menuItemId = menuItemId
        self.menuItemName = menuItemName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        phone = try container.decode(String.self, forKey: .phone)
        type = try container.decode(String.self, forKey: .type)
        content = try container.decode(String.self, forKey: .content)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        status = try container.decode(String.self, forKey: .status)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        reviewedAt = try container.decodeIfPresent(String.self, forKey: .reviewedAt)
        pointsAwarded = try container.decodeIfPresent(Int.self, forKey: .pointsAwarded) ?? 0
        menuItemId = try container.decodeIfPresent(String.self, forKey: .menuItemId)
        menuItemName = try container.decodeIfPresent(String.self, forKey: .menuItemName)
    }
}

struct LoyaltyData: Codable, Content {
    var customers: [LoyaltyCustomer]
    var bonusRequests: [BonusRequest]
}

struct LoyaltyStatus: Content {
    var phone: String
    var punches: Int
    var bonusPoints: Int
    var punchesNeeded: Int
    var rewardReady: Bool
    var totalRedeemed: Int
}

enum LoyaltyError: Error {
    case customerNotFound
    case bonusRequestNotFound
    case noRewardAvailable
}

extension LoyaltyError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .customerNotFound, .bonusRequestNotFound: return .notFound
        case .noRewardAvailable: return .badRequest
        }
    }

    var reason: String {
        switch self {
        case .customerNotFound: return "No punch card found for that phone number yet."
        case .bonusRequestNotFound: return "Bonus request not found."
        case .noRewardAvailable: return "This card doesn't have enough punches for a reward yet."
        }
    }
}

final class LoyaltyStore: @unchecked Sendable {
    static let shared = LoyaltyStore()
    static let punchesNeeded = 10
    /// Approved photo/social bonus claims are worth a tenth of a punch each —
    /// 10 approved claims add up to 1 real punch, rather than each claim
    /// granting a full punch outright.
    static let bonusPointsPerPunch = 10
    /// Only the first N approved bonus claims per calendar day (Pacific time,
    /// keyed off when the claim was submitted) actually earn points — extra
    /// claims that day can still be submitted and approved, they just award
    /// zero points, so posting many photos of one meal doesn't multiply the
    /// reward.
    static let maxAwardedBonusClaimsPerDay = 2

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/loyalty.json")
    private var data = LoyaltyData(customers: [], bonusRequests: [])
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("loyalty.json")
        loaded = false
    }

    static func normalizePhone(_ raw: String) -> String {
        raw.filter { $0.isNumber }
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

    private func statusFor(_ customer: LoyaltyCustomer) -> LoyaltyStatus {
        LoyaltyStatus(
            phone: customer.phone,
            punches: customer.punches,
            bonusPoints: customer.bonusPoints,
            punchesNeeded: Self.punchesNeeded,
            rewardReady: customer.punches >= Self.punchesNeeded,
            totalRedeemed: customer.totalRedeemed
        )
    }

    func lookup(phone rawPhone: String) throws -> LoyaltyStatus {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let phone = Self.normalizePhone(rawPhone)
        guard let customer = data.customers.first(where: { $0.phone == phone }) else {
            throw LoyaltyError.customerNotFound
        }
        return statusFor(customer)
    }

    @discardableResult
    func addPunch(phone rawPhone: String, count: Int = 1) throws -> LoyaltyStatus {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let phone = Self.normalizePhone(rawPhone)
        let timestamp = now()
        if let idx = data.customers.firstIndex(where: { $0.phone == phone }) {
            data.customers[idx].punches += count
            data.customers[idx].updatedAt = timestamp
            try persist()
            return statusFor(data.customers[idx])
        } else {
            let customer = LoyaltyCustomer(phone: phone, punches: count, totalRedeemed: 0, createdAt: timestamp, updatedAt: timestamp)
            data.customers.append(customer)
            try persist()
            return statusFor(customer)
        }
    }

    @discardableResult
    func redeem(phone rawPhone: String) throws -> LoyaltyStatus {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let phone = Self.normalizePhone(rawPhone)
        guard let idx = data.customers.firstIndex(where: { $0.phone == phone }) else {
            throw LoyaltyError.customerNotFound
        }
        guard data.customers[idx].punches >= Self.punchesNeeded else {
            throw LoyaltyError.noRewardAvailable
        }
        data.customers[idx].punches -= Self.punchesNeeded
        data.customers[idx].totalRedeemed += 1
        data.customers[idx].updatedAt = now()
        try persist()
        return statusFor(data.customers[idx])
    }

    func allCustomers() throws -> [LoyaltyCustomer] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return data.customers.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func submitBonusRequest(
        phone rawPhone: String, type: String, content: String, note: String?,
        menuItemId: String? = nil, menuItemName: String? = nil
    ) throws -> BonusRequest {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let request = BonusRequest(
            id: UUID().uuidString,
            phone: Self.normalizePhone(rawPhone),
            type: type,
            content: content,
            note: note,
            status: "pending",
            createdAt: now(),
            reviewedAt: nil,
            menuItemId: menuItemId,
            menuItemName: menuItemName
        )
        data.bonusRequests.append(request)
        try persist()
        return request
    }

    func allBonusRequests() throws -> [BonusRequest] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return data.bonusRequests.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func reviewBonusRequest(id: String, approve: Bool) throws -> BonusRequest {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = data.bonusRequests.firstIndex(where: { $0.id == id }) else {
            throw LoyaltyError.bonusRequestNotFound
        }
        data.bonusRequests[idx].status = approve ? "approved" : "denied"
        data.bonusRequests[idx].reviewedAt = now()

        if approve {
            let phone = data.bonusRequests[idx].phone
            let visitDay = Self.dayKey(fromISO8601: data.bonusRequests[idx].createdAt)
            let alreadyAwardedToday = data.bonusRequests.filter { other in
                other.id != id && other.phone == phone && other.pointsAwarded > 0
                    && Self.dayKey(fromISO8601: other.createdAt) == visitDay
            }.count

            if alreadyAwardedToday < Self.maxAwardedBonusClaimsPerDay {
                data.bonusRequests[idx].pointsAwarded = 1
                let customerIdx = findOrCreateCustomerIndex(phone: phone)
                data.customers[customerIdx].bonusPoints += 1
                if data.customers[customerIdx].bonusPoints >= Self.bonusPointsPerPunch {
                    data.customers[customerIdx].punches += data.customers[customerIdx].bonusPoints / Self.bonusPointsPerPunch
                    data.customers[customerIdx].bonusPoints %= Self.bonusPointsPerPunch
                }
                data.customers[customerIdx].updatedAt = now()
            } else {
                data.bonusRequests[idx].pointsAwarded = 0
            }

            // Publish the photo into the dish's own gallery, if the customer
            // linked one — best-effort: the item could have been renamed or
            // deleted since submission, and that should never block the
            // punch-awarding logic above.
            if data.bonusRequests[idx].type == "photo", let menuItemId = data.bonusRequests[idx].menuItemId {
                let photoURL = data.bonusRequests[idx].content
                try? MenuStore.shared.updateItem(id: menuItemId) { item in
                    if !item.images.contains(photoURL) {
                        item.images.append(photoURL)
                    }
                }
            }
        }
        try persist()
        return data.bonusRequests[idx]
    }

    /// Finds the customer's index, creating a fresh zero-punch card if this
    /// phone number hasn't punched in before — so an approved bonus claim
    /// still has somewhere to land. Assumes the lock is already held.
    private func findOrCreateCustomerIndex(phone rawPhone: String) -> Int {
        let phone = Self.normalizePhone(rawPhone)
        if let idx = data.customers.firstIndex(where: { $0.phone == phone }) {
            return idx
        }
        let timestamp = now()
        let customer = LoyaltyCustomer(phone: phone, punches: 0, bonusPoints: 0, totalRedeemed: 0, createdAt: timestamp, updatedAt: timestamp)
        data.customers.append(customer)
        return data.customers.count - 1
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try Data(contentsOf: fileURL)
            data = try JSONDecoder().decode(LoyaltyData.self, from: raw)
        } else {
            data = LoyaltyData(customers: [], bonusRequests: [])
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
