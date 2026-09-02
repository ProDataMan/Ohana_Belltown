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
    /// Names of any selected add-ons/upgrades (e.g. "Add Katsu", "Yosh Size")
    /// — just names for staff to read, not priced here; this isn't a payment
    /// system, so the extra charge still gets rung up wherever the order
    /// actually gets paid for.
    var modifiers: [String]

    enum CodingKeys: String, CodingKey {
        case id, tableId, itemName, itemId, section, customerId, status, createdAt, updatedAt
        case enteredAt, deliveredAt, estimatedReadyAt, modifiers
    }

    init(
        id: String, tableId: String, itemName: String, itemId: String? = nil, section: String? = nil,
        customerId: String? = nil, status: String, createdAt: String, updatedAt: String,
        enteredAt: String? = nil, deliveredAt: String? = nil, estimatedReadyAt: String? = nil,
        modifiers: [String] = []
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
        self.modifiers = modifiers
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
        modifiers = try container.decodeIfPresent([String].self, forKey: .modifiers) ?? []
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

/// See DiningTimeEstimator for how this is computed and why. `isBaselineOnly`
/// is true when there aren't any completed dining sessions yet in the
/// requested window — the numbers are still a real (if generic) estimate,
/// just not informed by any of this restaurant's own completed orders yet.
struct TableOccupancyStatsSummary: Content {
    var sessions: Int
    var averageEstimatedOccupancyMinutes: Double
    /// The real average when `isBaselineOnly` is false; the same generic
    /// baseline used to compute `averageEstimatedOccupancyMinutes` otherwise
    /// — never nil, so callers never have to separately reconstruct what
    /// baseline number was actually used.
    var averageWaitPlusPrepMinutes: Double
    var averageEstimatedEatingMinutes: Double
    var arrivalToOrderMinutes: Double
    var socialOverheadMinutes: Double
    var isBaselineOnly: Bool
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
    func place(tableId: String, itemName: String, itemId: String?, section: String?, customerId: String?, modifiers: [String] = []) throws -> TableOrderEntry {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let timestamp = now()
        let entry = TableOrderEntry(
            id: UUID().uuidString, tableId: tableId, itemName: itemName, itemId: itemId, section: section,
            customerId: customerId, status: "pending", createdAt: timestamp, updatedAt: timestamp,
            modifiers: modifiers
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

    /// Same "past estimated ready time" filter as readyForDeliveryCount(),
    /// but the actual entries rather than just a count — used by the
    /// station-light poll to know which prep station/table to flash for.
    func readyForDelivery() throws -> [TableOrderEntry] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let formatter = ISO8601DateFormatter()
        let now = Date()
        return entries
            .filter { entry in
                guard entry.status == "entered", let readyStr = entry.estimatedReadyAt,
                      let ready = formatter.date(from: readyStr) else { return false }
                return ready <= now
            }
            .sorted { ($0.estimatedReadyAt ?? "") < ($1.estimatedReadyAt ?? "") }
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

    /// Estimated table turnover time — see DiningTimeEstimator for the model.
    /// Orders at the same table are grouped into "dining sessions" (a big
    /// gap between orders means a new party sat down), and only sessions
    /// where every order actually completed give a real measured wait+prep
    /// time to combine with the eating/social-overhead estimate.
    func tableOccupancyStats(days: Int) throws -> TableOccupancyStatsSummary {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let formatter = ISO8601DateFormatter()
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: Date()) ?? .distantPast

        let byTable = Dictionary(grouping: entries, by: { $0.tableId })
        var sessions: [[TableOrderEntry]] = []
        for (_, orders) in byTable {
            let sorted = orders.sorted { $0.createdAt < $1.createdAt }
            var current: [TableOrderEntry] = []
            var lastCreated: Date?
            for order in sorted {
                guard let created = formatter.date(from: order.createdAt) else { continue }
                if let last = lastCreated, created.timeIntervalSince(last) > DiningTimeEstimator.sameSessionGapSeconds {
                    if !current.isEmpty { sessions.append(current) }
                    current = []
                }
                current.append(order)
                lastCreated = created
            }
            if !current.isEmpty { sessions.append(current) }
        }

        struct Estimate {
            var occupancyMinutes: Double
            var waitPlusPrepMinutes: Double
            var eatingMinutes: Double
        }
        var estimates: [Estimate] = []
        for session in sessions {
            guard session.allSatisfy({ $0.status == "delivered" }) else { continue }
            let createdDates = session.compactMap { formatter.date(from: $0.createdAt) }
            let deliveredDates = session.compactMap { $0.deliveredAt.flatMap { formatter.date(from: $0) } }
            guard let earliestCreated = createdDates.min(), let latestDelivered = deliveredDates.max(),
                  latestDelivered >= cutoff else { continue }

            let waitPlusPrep = latestDelivered.timeIntervalSince(earliestCreated) / 60
            let dishSections = session.map { $0.section }
            let eating = DiningTimeEstimator.estimatedEatingMinutes(dishSections: dishSections)
            let occupancy = DiningTimeEstimator.estimatedOccupancyMinutes(waitPlusPrepMinutes: waitPlusPrep, dishSections: dishSections)
            estimates.append(Estimate(occupancyMinutes: occupancy, waitPlusPrepMinutes: waitPlusPrep, eatingMinutes: eating))
        }

        func average(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }

        guard !estimates.isEmpty else {
            // No completed dining sessions yet — show a clearly-labeled
            // example (a single food-section dish) instead of an empty stat.
            let exampleWaitPlusPrep = PrepTimeEstimator.baselineMinutes(section: "menu")
            return TableOccupancyStatsSummary(
                sessions: 0,
                averageEstimatedOccupancyMinutes: DiningTimeEstimator.estimatedOccupancyMinutes(waitPlusPrepMinutes: exampleWaitPlusPrep, dishSections: ["menu"]),
                averageWaitPlusPrepMinutes: exampleWaitPlusPrep,
                averageEstimatedEatingMinutes: DiningTimeEstimator.estimatedEatingMinutes(dishSections: ["menu"]),
                arrivalToOrderMinutes: DiningTimeEstimator.arrivalToOrderMinutes,
                socialOverheadMinutes: DiningTimeEstimator.socialOverheadMinutes,
                isBaselineOnly: true
            )
        }

        return TableOccupancyStatsSummary(
            sessions: estimates.count,
            averageEstimatedOccupancyMinutes: average(estimates.map { $0.occupancyMinutes }) ?? 0,
            averageWaitPlusPrepMinutes: average(estimates.map { $0.waitPlusPrepMinutes }) ?? 0,
            averageEstimatedEatingMinutes: average(estimates.map { $0.eatingMinutes }) ?? 0,
            arrivalToOrderMinutes: DiningTimeEstimator.arrivalToOrderMinutes,
            socialOverheadMinutes: DiningTimeEstimator.socialOverheadMinutes,
            isBaselineOnly: false
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
