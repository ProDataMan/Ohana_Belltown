import Vapor

/// Tracks which competitor-restaurant menu photos still need a human (or a
/// future Claude session) to read prices/dishes off them. Deliberately a
/// separate store from `CompetitorPricingStore` — presence in this
/// dictionary means "this photo URL is a tracked competitor menu photo",
/// absence means "not tracked, ignore it entirely." Kept in sync by
/// `CompetitorPricingStore.saveRestaurants`, not by the generic
/// `POST /api/upload` route, since that route is shared site-wide and
/// must not tag unrelated uploads (menu items, loyalty photos, etc.).
struct CompetitorPhotoReviewEntry: Codable, Content {
    var restaurantId: String
    var addedAt: String
    var reviewed: Bool
    var reviewedAt: String?
    var reviewedByName: String?
}

final class CompetitorPhotoReviewStore: @unchecked Sendable {
    static let shared = CompetitorPhotoReviewStore()

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/competitor-photo-review.json")
    private var data: [String: CompetitorPhotoReviewEntry] = [:]
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("competitor-photo-review.json")
        loaded = false
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let raw = try? Data(contentsOf: fileURL) else { return }
        data = (try? JSONDecoder().decode([String: CompetitorPhotoReviewEntry].self, from: raw)) ?? [:]
    }

    private func persist() {
        guard let raw = try? JSONEncoder().encode(data) else { return }
        try? raw.write(to: fileURL)
    }

    func recordUnreviewed(url: String, restaurantId: String, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        guard data[url] == nil else { return }
        data[url] = CompetitorPhotoReviewEntry(
            restaurantId: restaurantId,
            addedAt: ISO8601DateFormatter().string(from: now),
            reviewed: false
        )
        persist()
    }

    func markReviewed(url: String, reviewedByName: String?, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        guard var entry = data[url] else { return }
        entry.reviewed = true
        entry.reviewedAt = ISO8601DateFormatter().string(from: now)
        entry.reviewedByName = reviewedByName
        data[url] = entry
        persist()
    }

    func unreviewedCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return data.values.filter { !$0.reviewed }.count
    }

    func unreviewedURLs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return data.filter { !$0.value.reviewed }.map(\.key).sorted()
    }

    /// Drops any tracked photo whose URL is no longer referenced by any
    /// restaurant — called after every restaurant-list save so a removed
    /// photo (or a whole deleted restaurant) stops counting.
    func removeEntries(notIn keptUrls: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        let before = data.count
        data = data.filter { keptUrls.contains($0.key) }
        if data.count != before {
            persist()
        }
    }
}
