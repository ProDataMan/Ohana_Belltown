import Vapor

struct TableOrderEntry: Codable, Content {
    var id: String
    var tableId: String
    var itemName: String
    /// Menu item id, when known — keys the real-average prep-time lookup so
    /// a renamed item doesn't lose its history. Falls back to itemName.
    var itemId: String?
    /// MENU_SECTION the item was ordered from ("menu", "sushi", "drinks",
    /// "happy_hour") — used to pick a baseline prep-time estimate.
    var section: String?
    /// Signed-in customer who placed the order, if any — powers "my order
    /// history" on their account page. Most orders won't have one; ordering
    /// doesn't require being logged in.
    var customerId: String?
    /// "pending" (just placed) -> "entered" (staff checked with the table and
    /// entered it into the order system) -> "delivered".
    var status: String
    var createdAt: String
    var updatedAt: String
    var enteredAt: String?
    var deliveredAt: String?
    /// Set when marked "entered" — a heuristic estimate of when the dish
    /// should be ready, used to proactively notify staff. See PrepTimeEstimator.
    var estimatedReadyAt: String?

    enum CodingKeys: String, CodingKey {
        case id, tableId, itemName, itemId, section, customerId, status, createdAt, updatedAt
        case enteredAt, deliveredAt, estimatedReadyAt
    }

    init(
        id: String, tableId: String, itemName: String, itemId: String? = nil, section: String? = nil,
        customerId: String? = nil, status: String, createdAt: String, updatedAt: String,
        enteredAt: String? = nil, deliveredAt: String? = nil, estimatedReadyAt: String? = nil
    ) {
        self.id = id
        self.tableId = tableId
        self.itemName = itemName
        self.itemId = itemId
        self.section = section
        self.customerId = customerId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.enteredAt = enteredAt
        self.deliveredAt = deliveredAt
        self.estimatedReadyAt = estimatedReadyAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        tableId = try container.decode(String.self, forKey: .tableId)
        itemName = try container.decode(String.self, forKey: .itemName)
        itemId = try container.decodeIfPresent(String.self, forKey: .itemId)
        section = try container.decodeIfPresent(String.self, forKey: .section)
        customerId = try container.decodeIfPresent(String.self, forKey: .customerId)
        let decodedStatus = try container.decode(String.self, forKey: .status)
        // "acknowledged" was this feature's original status name, before the
        // entered/delivered lifecycle existed — treat it as "entered" so any
        // already-persisted entries don't end up in an unrecognized state.
        status = decodedStatus == "acknowledged" ? "entered" : decodedStatus
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        enteredAt = try container.decodeIfPresent(String.self, forKey: .enteredAt)
        deliveredAt = try container.decodeIfPresent(String.self, forKey: .deliveredAt)
        estimatedReadyAt = try container.decodeIfPresent(String.self, forKey: .estimatedReadyAt)
    }
}

struct ItemDeliveryStat: Content {
    var itemName: String
    var samples: Int
    var avgWaitMinutes: Double?
    var avgPrepMinutes: Double?
    var avgTotalMinutes: Double
}

struct DeliveryStatsSummary: Content {
    var items: [ItemDeliveryStat]
    var overallAvgWaitMinutes: Double?
    var overallAvgPrepMinutes: Double?
    var overallAvgTotalMinutes: Double?
    var completedOrders: Int
}

enum TableOrderError: Error, Equatable {
    case entryNotFound
}

extension TableOrderError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .entryNotFound: return .notFound
        }
    }

    var reason: String {
        switch self {
        case .entryNotFound: return "Order not found."
        }
    }
}

final class TableOrdersStore: @unchecked Sendable {
    static let shared = TableOrdersStore()
    /// A placed order not yet entered by staff drops off the "needs entry"
    /// view after this long — same-visit signal, not something that should
    /// linger for days.
    static let pendingStaleAfterSeconds: TimeInterval = 4 * 60 * 60
    /// An entered order not yet marked delivered drops off "awaiting
    /// delivery" after this long — longer than pending, since prep genuinely
    /// takes time, but still bounded.
    static let awaitingDeliveryStaleAfterSeconds: TimeInterval = 2 * 60 * 60
    /// Completed orders are kept much longer than either live view — they're
    /// the raw data behind the analytics delivery-time KPIs.
    static let retentionDays: Double = 90

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/table-orders.json")
    private var entries: [TableOrderEntry] = []
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("table-orders.json")
        loaded = false
    }

    private func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    @discardableResult
    func place(tableId: String, itemName: String, itemId: String?, section: String?, customerId: String?) throws -> TableOrderEntry {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let timestamp = now()
        let entry = TableOrderEntry(
            id: UUID().uuidString, tableId: tableId, itemName: itemName, itemId: itemId, section: section,
            customerId: customerId, status: "pending", createdAt: timestamp, updatedAt: timestamp
        )
        entries.append(entry)
        try persist()
        return entry
    }

    /// Placed, not-yet-entered orders, oldest first.
    func needsEntry() throws -> [TableOrderEntry] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let formatter = ISO8601DateFormatter()
        let cutoff = Date().addingTimeInterval(-Self.pendingStaleAfterSeconds)
        return entries
            .filter { entry in
                guard entry.status == "pending" else { return false }
                guard let created = formatter.date(from: entry.createdAt) else { return true }
                return created > cutoff
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Entered, not-yet-delivered orders, oldest first.
    func awaitingDelivery() throws -> [TableOrderEntry] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let formatter = ISO8601DateFormatter()
        let cutoff = Date().addingTimeInterval(-Self.awaitingDeliveryStaleAfterSeconds)
        return entries
            .filter { entry in
                guard entry.status == "entered" else { return false }
                guard let entered = entry.enteredAt, let enteredDate = formatter.date(from: entered) else { return true }
                return enteredDate > cutoff
            }
            .sorted { ($0.enteredAt ?? $0.createdAt) < ($1.enteredAt ?? $1.createdAt) }
    }

    /// How many awaiting-delivery orders are past their estimated ready
    /// time — the "should be ready now" staff notification signal.
    func readyForDeliveryCount() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let formatter = ISO8601DateFormatter()
        let now = Date()
        return entries.filter { entry in
            guard entry.status == "entered", let readyStr = entry.estimatedReadyAt,
                  let ready = formatter.date(from: readyStr) else { return false }
            return ready <= now
        }.count
    }

    /// Real historical average prep time (entered -> delivered) for this
    /// exact item, in minutes — nil until at least 3 completed samples
    /// exist, so one unusually fast/slow order can't skew the estimate.
    private func realAveragePrepMinutes(itemKey: String) -> Double? {
        let formatter = ISO8601DateFormatter()
        let samples = entries.compactMap { entry -> Double? in
            guard (entry.itemId ?? entry.itemName) == itemKey,
                  let enteredStr = entry.enteredAt, let deliveredStr = entry.deliveredAt,
                  let entered = formatter.date(from: enteredStr), let delivered = formatter.date(from: deliveredStr) else {
                return nil
            }
            return delivered.timeIntervalSince(entered) / 60
        }
        guard samples.count >= 3 else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    @discardableResult
    func markEntered(id: String, staffOnDuty: Int) throws -> TableOrderEntry {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = entries.firstIndex(where: { $0.id == id }) else {
            throw TableOrderError.entryNotFound
        }
        let timestamp = now()
        entries[idx].status = "entered"
        entries[idx].enteredAt = timestamp
        entries[idx].updatedAt = timestamp

        let itemKey = entries[idx].itemId ?? entries[idx].itemName
        let baseline = realAveragePrepMinutes(itemKey: itemKey) ?? PrepTimeEstimator.baselineMinutes(section: entries[idx].section)
        let occupiedTables = Set(entries.filter { $0.status == "pending" || $0.status == "entered" }.map { $0.tableId }).count
        let estimatedMinutes = PrepTimeEstimator.loadAdjustedMinutes(baseline: baseline, occupiedTables: occupiedTables, staffOnDuty: staffOnDuty)
        entries[idx].estimatedReadyAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(estimatedMinutes * 60))

        try persist()
        return entries[idx]
    }

    /// Anyone can confirm delivery — staff from the admin queue, or the
    /// customer themselves tapping "Mark Received" on the menu page.
    @discardableResult
    func markDelivered(id: String) throws -> TableOrderEntry {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = entries.firstIndex(where: { $0.id == id }) else {
            throw TableOrderError.entryNotFound
        }
        let timestamp = now()
        entries[idx].status = "delivered"
        entries[idx].deliveredAt = timestamp
        entries[idx].updatedAt = timestamp
        try persist()
        return entries[idx]
    }

    /// A signed-in customer's own past table orders, newest first.
    func ordersForCustomer(customerId: String) throws -> [TableOrderEntry] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return entries
            .filter { $0.customerId == customerId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func deliveryStats(days: Int) throws -> DeliveryStatsSummary {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let formatter = ISO8601DateFormatter()
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: Date()) ?? .distantPast

        struct Sample {
            var wait: Double?
            var prep: Double?
            var total: Double
        }
        var byItem: [String: [Sample]] = [:]

        for entry in entries {
            guard entry.status == "delivered",
                  let deliveredStr = entry.deliveredAt, let delivered = formatter.date(from: deliveredStr),
                  delivered >= cutoff,
                  let created = formatter.date(from: entry.createdAt) else { continue }

            var sample = Sample(wait: nil, prep: nil, total: delivered.timeIntervalSince(created) / 60)
            if let enteredStr = entry.enteredAt, let entered = formatter.date(from: enteredStr) {
                sample.wait = entered.timeIntervalSince(created) / 60
                sample.prep = delivered.timeIntervalSince(entered) / 60
            }
            byItem[entry.itemName, default: []].append(sample)
        }

        func average(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }

        let items = byItem
            .map { name, samples in
                ItemDeliveryStat(
                    itemName: name,
                    samples: samples.count,
                    avgWaitMinutes: average(samples.compactMap { $0.wait }),
                    avgPrepMinutes: average(samples.compactMap { $0.prep }),
                    avgTotalMinutes: average(samples.map { $0.total }) ?? 0
                )
            }
            .sorted { $0.avgTotalMinutes > $1.avgTotalMinutes }

        let allSamples = byItem.values.flatMap { $0 }
        return DeliveryStatsSummary(
            items: items,
            overallAvgWaitMinutes: average(allSamples.compactMap { $0.wait }),
            overallAvgPrepMinutes: average(allSamples.compactMap { $0.prep }),
            overallAvgTotalMinutes: average(allSamples.map { $0.total }),
            completedOrders: allSamples.count
        )
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([TableOrderEntry].self, from: raw)
        } else {
            entries = []
            try persist()
        }
        loaded = true
    }

    private func persist() throws {
        let formatter = ISO8601DateFormatter()
        let cutoff = Date().addingTimeInterval(-Self.retentionDays * 24 * 3600)
        entries = entries.filter { entry in
            guard let created = formatter.date(from: entry.createdAt) else { return true }
            return created > cutoff
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(entries)
        try encoded.write(to: fileURL, options: .atomic)
    }
}
