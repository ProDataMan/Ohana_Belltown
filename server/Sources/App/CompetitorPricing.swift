import Foundation
import Vapor

/// A nearby restaurant staff are comparing prices against. The restaurant
/// itself is sourced from Google Maps (`nearbyRestaurants`, below) rather
/// than typed in by hand — there's just no reliable API for a competitor's
/// actual menu *prices*, so those still need a staff member to check the
/// competitor's own published menu/site and enter what they find.
struct CompetitorRestaurant: Codable, Content, Equatable {
    var id: String
    var name: String
    var distanceMiles: Double?
    var address: String?
    var website: String?
    var notes: String?
    /// Google's place_id, when this restaurant was added from the Nearby
    /// Search picker — lets the admin UI recognize "already added" and skip
    /// offering a duplicate. Absent for anything added before this existed.
    var placeId: String?
    /// Photos of this competitor's actual menu (uploaded via the shared
    /// /api/upload endpoint, same as menu item photos) — a reference for
    /// whoever's entering prices, since a competitor's site often doesn't
    /// list them at all.
    var menuPhotoUrls: [String]?

    init(
        id: String = UUID().uuidString, name: String, distanceMiles: Double? = nil,
        address: String? = nil, website: String? = nil, notes: String? = nil, placeId: String? = nil,
        menuPhotoUrls: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.distanceMiles = distanceMiles
        self.address = address
        self.website = website
        self.notes = notes
        self.placeId = placeId
        self.menuPhotoUrls = menuPhotoUrls
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

/// One result from Google's Nearby Search, before it's been picked and added
/// to `CompetitorRestaurant` — a candidate, not yet part of the saved list.
struct NearbyRestaurantCandidate: Content {
    var placeId: String
    var name: String
    var address: String?
    var distanceMiles: Double
    var rating: Double?
}

private struct GoogleNearbySearchResult: Codable {
    let place_id: String
    let name: String
    let vicinity: String?
    let rating: Double?
    let geometry: GoogleGeometry?
    let business_status: String?
}

private struct GoogleNearbySearchResponse: Codable {
    let results: [GoogleNearbySearchResult]
    let status: String
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

    // Nearby-search results aren't persisted (they're just Google's answer to
    // "what's around here right now," re-fetched on demand) — a short
    // in-memory cache avoids re-billing/re-hitting the API on every reload of
    // the admin page.
    private var nearbyCache: [NearbyRestaurantCandidate]?
    private var nearbyCacheFetchedAt: Date?
    private let nearbyCacheTTL: TimeInterval = 6 * 3600

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("competitor-pricing.json")
        loaded = false
    }

    /// Restaurants near Ohana Belltown from Google's Nearby Search — lets
    /// staff pick a competitor from a real, current list instead of typing a
    /// name/address by hand. This only sources *who's nearby*; Google has no
    /// API for a competitor's actual menu prices, so those still need a
    /// person to look at the competitor's own site/menu.
    func nearbyRestaurants(client: Client, apiKey: String, placeId: String, radiusMiles: Double) async throws -> [NearbyRestaurantCandidate] {
        lock.lock()
        let isFresh = nearbyCacheFetchedAt.map { Date().timeIntervalSince($0) < nearbyCacheTTL } ?? false
        if isFresh, let cached = nearbyCache {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let ourDetails = try await PlacesPhotoCache.shared.getDetails(client: client, apiKey: apiKey, placeId: placeId)
        guard let ourLocation = ourDetails.geometry?.location else {
            return []
        }

        let radiusMeters = Int(radiusMiles * 1609.34)
        let uri = URI(string: "https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=\(ourLocation.lat),\(ourLocation.lng)&radius=\(radiusMeters)&type=restaurant&key=\(apiKey)")
        let response = try await client.get(uri).get()
        let decoded = try response.content.decode(GoogleNearbySearchResponse.self)

        let candidates = decoded.results
            .compactMap { result -> NearbyRestaurantCandidate? in
                guard result.place_id != placeId else { return nil }
                guard result.business_status == nil || result.business_status == "OPERATIONAL" else { return nil }
                guard let location = result.geometry?.location else { return nil }
                let distance = Self.haversineMiles(lat1: ourLocation.lat, lng1: ourLocation.lng, lat2: location.lat, lng2: location.lng)
                guard distance <= radiusMiles else { return nil }
                return NearbyRestaurantCandidate(
                    placeId: result.place_id,
                    name: result.name,
                    address: result.vicinity,
                    distanceMiles: (distance * 10).rounded() / 10,
                    rating: result.rating
                )
            }
            .sorted { $0.distanceMiles < $1.distanceMiles }

        lock.lock()
        nearbyCache = candidates
        nearbyCacheFetchedAt = Date()
        lock.unlock()

        return candidates
    }

    private static func haversineMiles(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
        let earthRadiusMiles = 3958.8
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMiles * c
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
        let oldPhotosByRestaurant = Dictionary(
            uniqueKeysWithValues: data.restaurants.map { ($0.id, Set($0.menuPhotoUrls ?? [])) }
        )
        let keptIds = Set(items.map(\.id))
        data.restaurants = items
        data.entries.removeAll { !keptIds.contains($0.restaurantId) }
        try persist()

        // Every photo URL genuinely new to a restaurant starts tracked as
        // unreviewed; anything no longer referenced by any restaurant (a
        // removed photo, or a whole deleted restaurant) stops counting.
        for restaurant in items {
            let oldUrls = oldPhotosByRestaurant[restaurant.id] ?? []
            for url in restaurant.menuPhotoUrls ?? [] where !oldUrls.contains(url) {
                CompetitorPhotoReviewStore.shared.recordUnreviewed(url: url, restaurantId: restaurant.id)
            }
        }
        let allCurrentPhotoUrls = Set(items.flatMap { $0.menuPhotoUrls ?? [] })
        CompetitorPhotoReviewStore.shared.removeEntries(notIn: allCurrentPhotoUrls)

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
