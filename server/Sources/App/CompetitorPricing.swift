import Vapor

/// A nearby restaurant staff are comparing prices against — not a live feed
/// (there's no reliable API for a competitor's actual menu prices), just a
/// staff-curated reference list they periodically check and re-enter from
/// the competitor's own published menu/site.
struct CompetitorRestaurant: Codable, Content, Equatable {
    var id: String
    var name: String
    var distanceMiles: Double?
    var address: String?
    var website: String?
    var notes: String?

    init(
        id: String = UUID().uuidString, name: String, distanceMiles: Double? = nil,
        address: String? = nil, website: String? = nil, notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.distanceMiles = distanceMiles
        self.address = address
        self.website = website
        self.notes = notes
    }
}

/// One comparable dish, e.g. "Ohana Burger" or a generic "Classic Cheeseburger"
/// — optionally linked to one of our own menu items so the report can pull
/// our current price automatically instead of needing it retyped and kept
/// in sync by hand.
struct MenuPriceComparisonGroup: Codable, Content, Equatable {
    var id: String
    var label: String
    var ourMenuItemId: String?
    var notes: String?

    init(id: String = UUID().uuidString, label: String, ourMenuItemId: String? = nil, notes: String? = nil) {
        self.id = id
        self.label = label
        self.ourMenuItemId = ourMenuItemId
        self.notes = notes
    }
}

/// One competitor's price for a comparison group, as staff found it
/// published (their own menu/site/delivery app) on `checkedAt`.
struct CompetitorPriceEntry: Codable, Content, Equatable {
    var id: String
    var groupId: String
    var restaurantId: String
    var price: Double
    var itemName: String?
    var sourceURL: String?
    var checkedAt: String

    init(
        id: String = UUID().uuidString, groupId: String, restaurantId: String, price: Double,
        itemName: String? = nil, sourceURL: String? = nil, checkedAt: String
    ) {
        self.id = id
        self.groupId = groupId
        self.restaurantId = restaurantId
        self.price = price
        self.itemName = itemName
        self.sourceURL = sourceURL
        self.checkedAt = checkedAt
    }
}

struct CompetitorPricingData: Codable {
    var restaurants: [CompetitorRestaurant]
    var groups: [MenuPriceComparisonGroup]
    var entries: [CompetitorPriceEntry]
}

struct CompetitorPriceReportEntry: Content {
    var restaurantId: String
    var restaurantName: String
    var distanceMiles: Double?
    var itemName: String?
    var price: Double
    var sourceURL: String?
    var checkedAt: String
}

struct CompetitorPriceReportRow: Content {
    var groupId: String
    var label: String
    var ourMenuItemId: String?
    var ourMenuItemName: String?
    var ourPrice: Double?
    var competitorCount: Int
    var competitorAverage: Double?
    var competitorMin: Double?
    var competitorMax: Double?
    /// Our price minus the competitor average — positive means we're pricier.
    var deltaVsAverage: Double?
    var deltaPercentVsAverage: Double?
    var entries: [CompetitorPriceReportEntry]
}

enum CompetitorPricingError: Error {
    case restaurantNotFound
    case groupNotFound
    case entryNotFound
}

extension CompetitorPricingError: AbortError {
    var status: HTTPResponseStatus {
        .notFound
    }

    var reason: String {
        switch self {
        case .restaurantNotFound: return "Competitor restaurant not found."
        case .groupNotFound: return "Comparison group not found."
        case .entryNotFound: return "Price entry not found."
        }
    }
}

final class CompetitorPricingStore: @unchecked Sendable {
    static let shared = CompetitorPricingStore()

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/competitor-pricing.json")
    private var data = CompetitorPricingData(restaurants: [], groups: [], entries: [])
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("competitor-pricing.json")
        loaded = false
    }

    func restaurants() throws -> [CompetitorRestaurant] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return data.restaurants.sorted { ($0.distanceMiles ?? .greatestFiniteMagnitude) < ($1.distanceMiles ?? .greatestFiniteMagnitude) }
    }

    @discardableResult
    func saveRestaurants(_ items: [CompetitorRestaurant]) throws -> [CompetitorRestaurant] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let keptIds = Set(items.map(\.id))
        data.restaurants = items
        data.entries.removeAll { !keptIds.contains($0.restaurantId) }
        try persist()
        return data.restaurants
    }

    func groups() throws -> [MenuPriceComparisonGroup] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return data.groups
    }

    @discardableResult
    func saveGroups(_ items: [MenuPriceComparisonGroup]) throws -> [MenuPriceComparisonGroup] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let keptIds = Set(items.map(\.id))
        data.groups = items
        data.entries.removeAll { !keptIds.contains($0.groupId) }
        try persist()
        return data.groups
    }

    func entries() throws -> [CompetitorPriceEntry] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return data.entries.sorted { $0.checkedAt > $1.checkedAt }
    }

    @discardableResult
    func saveEntries(_ items: [CompetitorPriceEntry]) throws -> [CompetitorPriceEntry] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        data.entries = items
        try persist()
        return data.entries
    }

    /// Builds the comparison report: for every group, our current price
    /// (looked up live from `MenuStore` when linked, so it can't go stale)
    /// alongside every competitor price on file for it, plus the average/
    /// min/max and how far our price sits from that average.
    func report() throws -> [CompetitorPriceReportRow] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()

        let restaurantsById = Dictionary(uniqueKeysWithValues: data.restaurants.map { ($0.id, $0) })

        return data.groups.map { group in
            var ourPrice: Double?
            var ourMenuItemName: String?
            if let itemId = group.ourMenuItemId, let location = try? MenuStore.shared.findItem(id: itemId) {
                ourPrice = location.item.price
                ourMenuItemName = location.item.name
            }

            let groupEntries = data.entries.filter { $0.groupId == group.id }
            let reportEntries: [CompetitorPriceReportEntry] = groupEntries.compactMap { entry in
                guard let restaurant = restaurantsById[entry.restaurantId] else { return nil }
                return CompetitorPriceReportEntry(
                    restaurantId: restaurant.id,
                    restaurantName: restaurant.name,
                    distanceMiles: restaurant.distanceMiles,
                    itemName: entry.itemName,
                    price: entry.price,
                    sourceURL: entry.sourceURL,
                    checkedAt: entry.checkedAt
                )
            }.sorted { $0.price < $1.price }

            let prices = reportEntries.map(\.price)
            let average = prices.isEmpty ? nil : prices.reduce(0, +) / Double(prices.count)
            let delta = (ourPrice != nil && average != nil) ? ourPrice! - average! : nil
            let deltaPercent = (delta != nil && average != nil && average! != 0) ? (delta! / average!) * 100 : nil

            return CompetitorPriceReportRow(
                groupId: group.id,
                label: group.label,
                ourMenuItemId: group.ourMenuItemId,
                ourMenuItemName: ourMenuItemName,
                ourPrice: ourPrice,
                competitorCount: prices.count,
                competitorAverage: average,
                competitorMin: prices.min(),
                competitorMax: prices.max(),
                deltaVsAverage: delta,
                deltaPercentVsAverage: deltaPercent,
                entries: reportEntries
            )
        }
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try Data(contentsOf: fileURL)
            data = try JSONDecoder().decode(CompetitorPricingData.self, from: raw)
        } else {
            data = CompetitorPricingData(restaurants: [], groups: [], entries: [])
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
