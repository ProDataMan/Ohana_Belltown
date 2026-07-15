import Vapor

struct LoyaltyCustomer: Codable, Content {
    var phone: String
    var punches: Int
    var totalRedeemed: Int
    var createdAt: String
    var updatedAt: String
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
}

struct LoyaltyData: Codable, Content {
    var customers: [LoyaltyCustomer]
    var bonusRequests: [BonusRequest]
}

struct LoyaltyStatus: Content {
    var phone: String
    var punches: Int
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

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/loyalty.json")
    private var data = LoyaltyData(customers: [], bonusRequests: [])
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("loyalty.json")
    }

    static func normalizePhone(_ raw: String) -> String {
        raw.filter { $0.isNumber }
    }

    private func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func statusFor(_ customer: LoyaltyCustomer) -> LoyaltyStatus {
        LoyaltyStatus(
            phone: customer.phone,
            punches: customer.punches,
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
    func submitBonusRequest(phone rawPhone: String, type: String, content: String, note: String?) throws -> BonusRequest {
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
            reviewedAt: nil
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
        let phone = data.bonusRequests[idx].phone
        try persist()

        if approve {
            lock.unlock()
            try addPunch(phone: phone, count: 1)
            lock.lock()
        }
        return data.bonusRequests[idx]
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
