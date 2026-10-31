import Vapor

/// Tracks which competitor-restaurant menu photos still need a human (or a
/// future Claude session) to read prices/dishes off them. Deliberately a
/// separate store from `CompetitorPricingStore` — presence in this
/// dictionary means "this photo URL is a tracked competitor menu photo",
/// absence means "not tracked, ignore it entirely." Kept in sync by
/// `CompetitorPricingStore.saveRestaurants`, not by the generic
/// `POST /api/upload` route, since that route is shared site-wide and
/// must not tag unrelated uploads (menu items, loyalty photos, etc.).
///
/// `restaurantId` is nil for a photo that came in through the quick-upload
/// inbox (`recordInboxUpload`) — snapped on the spot at some other
/// restaurant's table with no "which restaurant is this" step at all, left
/// for whoever reviews it (a human or a future Claude session reading the
/// photo) to identify and either match to an existing `CompetitorRestaurant`
/// or create a new one.
struct CompetitorPhotoReviewEntry: Codable, Content {
    var restaurantId: String?
    var addedAt: String
    var reviewed: Bool
    var reviewedAt: String?
    var reviewedByName: String?
    var uploadedByName: String?
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
        // A missing file (first run, or a freshly `configure`d data
        // directory — as every test does) means "nothing tracked yet," not
        // "keep whatever's already in memory" — without this reset, this
        // singleton's leftover data from a previous `configure` call (e.g.
        // another test's temp directory) would silently bleed into whichever
        // run reads here next.
        guard let raw = try? Data(contentsOf: fileURL) else {
            data = [:]
            return
        }
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
        if var existing = data[url] {
            // An inbox upload (no restaurant chosen at upload time) just got
            // attached to one — fill that in rather than silently leaving it
            // stuck showing as unassigned forever. Leaves `reviewed` as-is
            // either way: attaching a photo to a restaurant isn't the same
            // as having actually read prices off it yet.
            guard existing.restaurantId == nil else { return }
            existing.restaurantId = restaurantId
            data[url] = existing
            persist()
            return
        }
        data[url] = CompetitorPhotoReviewEntry(
            restaurantId: restaurantId,
            addedAt: ISO8601DateFormatter().string(from: now),
            reviewed: false
        )
        persist()
    }

    /// The quick-upload path (`POST /api/competitor-pricing/photos/inbox`) —
    /// a photo snapped on the spot with no restaurant chosen at all.
    /// `uploadedByName` is who actually took it, separate from
    /// `reviewedByName` (who, likely a different staff member or a Claude
    /// session, later reads prices off it).
    func recordInboxUpload(url: String, uploadedByName: String?, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        guard data[url] == nil else { return }
        data[url] = CompetitorPhotoReviewEntry(
            restaurantId: nil,
            addedAt: ISO8601DateFormatter().string(from: now),
            reviewed: false,
            uploadedByName: uploadedByName
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

    /// Photos still waiting on the first step — nobody's identified which
    /// restaurant they're even from yet. Whoever reviews these (staff, or a
    /// Claude session asked to "go through the competitor photo inbox")
    /// needs to look at each image, figure out the restaurant, and add it
    /// (new or matched to an existing one) before prices can go anywhere.
    func unassignedEntries() -> [(url: String, entry: CompetitorPhotoReviewEntry)] {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return data
            .filter { !$0.value.reviewed && $0.value.restaurantId == nil }
            .map { ($0.key, $0.value) }
            .sorted { $0.entry.addedAt < $1.entry.addedAt }
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
