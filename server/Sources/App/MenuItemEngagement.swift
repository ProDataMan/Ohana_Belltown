import Vapor

/// One tap on a menu item card — either its photo or the rest of the row
/// (which opens the detail modal). Separate from `AnalyticsStore.itemViewCounts`
/// (the older, anonymous, aggregate-only "most-viewed items" counter still
/// backing `/analytics.html`) on purpose: that counter is disclosed as having
/// no per-visitor identity at all, while this one is attributed to the same
/// per-browser `deviceId` order history already uses (and a `customerId` when
/// signed in) — a different privacy posture, so it gets its own store rather
/// than quietly changing what the existing one promises.
struct MenuItemEngagementEvent: Codable {
    var id: String
    var menuItemName: String
    var clickType: String
    var deviceId: String
    var customerId: String?
    var timestamp: String
}

struct MenuItemEngagementCount: Content {
    var menuItemName: String
    var clickType: String
    var totalClicks: Int
    var uniqueDevices: Int
}

/// Taps as a fraction of how often the card was actually shown, not a raw
/// count — an item near the top of a long category gets scrolled past by
/// everyone, one at the bottom doesn't, so raw taps alone favor position
/// over actual interest. `tapRate` is nil rather than 0 when there's no
/// impression data yet, so a dashboard can tell "never shown" apart from
/// "shown but never tapped."
struct MenuItemTapRate: Content {
    var menuItemName: String
    var impressions: Int
    var taps: Int
    var tapRate: Double?
}

final class MenuItemEngagementStore: @unchecked Sendable {
    static let shared = MenuItemEngagementStore()

    /// Raw events beyond this age are dropped whenever a new one is
    /// recorded — same retention window AnalyticsStore already uses for its
    /// day-bucketed pageview data.
    private static let retentionDays = 120

    enum ClickType: String {
        case photo
        case details
        /// The card scrolled into view — not a tap at all, but recorded
        /// through the same event shape so `summary` already aggregates it
        /// for free; `tapRateSummary` below is what actually uses it.
        case impression
    }

    private let lock = NSLock()
    /// The pre-append-only file — a single JSON array rewritten on every
    /// event. Migrated into `log` on first load, then renamed aside.
    private var legacyFileURL = URL(fileURLWithPath: "Data/menu-item-engagement.json")
    private var log = JSONLinesLog<MenuItemEngagementEvent>(fileURL: URL(fileURLWithPath: "Data/menu-item-engagement.jsonl"))
    private var events: [MenuItemEngagementEvent] = []
    private var loaded = false
    private var lastCompaction = Date()

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        log.flush()
        let directory = URL(fileURLWithPath: dataDirectory)
        legacyFileURL = directory.appendingPathComponent("menu-item-engagement.json")
        log = JSONLinesLog(fileURL: directory.appendingPathComponent("menu-item-engagement.jsonl"))
        loaded = false
    }

    /// Waits for queued appends to reach disk — for tests.
    func flush() {
        lock.lock()
        defer { lock.unlock() }
        log.flush()
    }

    /// Loads (and, the first time, migrates) the event file ahead of the
    /// first request, so no guest's tap pays for parsing it.
    func warmUp() {
        lock.lock()
        defer { lock.unlock() }
        try? loadIfNeeded()
    }

    @discardableResult
    func record(menuItemName: String, clickType: ClickType, deviceId: String, customerId: String?) throws -> MenuItemEngagementEvent {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let event = MenuItemEngagementEvent(
            id: UUID().uuidString, menuItemName: menuItemName, clickType: clickType.rawValue,
            deviceId: deviceId, customerId: customerId, timestamp: ISO8601DateFormatter().string(from: Date())
        )
        events.append(event)
        log.append([event])
        compactIfDueLocked()
        return event
    }

    /// Same as `record`, for a whole batch at once under one lock/persist —
    /// impressions arrive in batches (the client queues everything that
    /// scrolled into view and flushes periodically) rather than one at a
    /// time, and a real menu can have 200+ items.
    @discardableResult
    func recordBatch(menuItemNames: [String], clickType: ClickType, deviceId: String, customerId: String?) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard !menuItemNames.isEmpty else { return 0 }
        try loadIfNeeded()
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let batch = menuItemNames.map { name in
            MenuItemEngagementEvent(
                id: UUID().uuidString, menuItemName: name, clickType: clickType.rawValue,
                deviceId: deviceId, customerId: customerId, timestamp: timestamp
            )
        }
        events.append(contentsOf: batch)
        log.append(batch)
        compactIfDueLocked()
        return menuItemNames.count
    }

    /// Aggregated over the trailing `days`: a raw click total per item +
    /// click type, plus how many distinct devices/customers that total came
    /// from — repeat taps from one visitor count once toward the latter, so
    /// staff can tell "widely engaging" apart from "one person tapping a lot."
    func summary(days: Int) throws -> [MenuItemEngagementCount] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let formatter = ISO8601DateFormatter()

        struct Key: Hashable { var menuItemName: String; var clickType: String }
        var totals: [Key: Int] = [:]
        var visitors: [Key: Set<String>] = [:]
        for event in events {
            guard let date = formatter.date(from: event.timestamp), date >= cutoff else { continue }
            let key = Key(menuItemName: event.menuItemName, clickType: event.clickType)
            totals[key, default: 0] += 1
            visitors[key, default: []].insert(event.customerId ?? event.deviceId)
        }
        return totals
            .map { key, total in
                MenuItemEngagementCount(
                    menuItemName: key.menuItemName, clickType: key.clickType,
                    totalClicks: total, uniqueDevices: visitors[key]?.count ?? 0
                )
            }
            .sorted { $0.totalClicks > $1.totalClicks }
    }

    /// Per item over the trailing `days`: impressions, taps (photo + details
    /// combined), and the resulting tap rate — see `MenuItemTapRate`'s doc
    /// comment for why this is the more honest "most engaging" signal than
    /// raw tap counts alone.
    func tapRateSummary(days: Int) throws -> [MenuItemTapRate] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let formatter = ISO8601DateFormatter()

        var impressions: [String: Int] = [:]
        var taps: [String: Int] = [:]
        for event in events {
            guard let date = formatter.date(from: event.timestamp), date >= cutoff else { continue }
            if event.clickType == ClickType.impression.rawValue {
                impressions[event.menuItemName, default: 0] += 1
            } else {
                taps[event.menuItemName, default: 0] += 1
            }
        }
        let itemNames = Set(impressions.keys).union(taps.keys)
        return itemNames
            .map { name -> MenuItemTapRate in
                let impressionCount = impressions[name] ?? 0
                let tapCount = taps[name] ?? 0
                let rate = impressionCount > 0 ? Double(tapCount) / Double(impressionCount) : nil
                return MenuItemTapRate(menuItemName: name, impressions: impressionCount, taps: tapCount, tapRate: rate)
            }
            .sorted { ($0.tapRate ?? -1) > ($1.tapRate ?? -1) }
    }

    /// Drops events past retention from memory and rewrites the file without
    /// them, at most once a day. Pruning on every event (as before) meant a
    /// full rewrite on every event; the file can carry a day's worth of
    /// expired lines in between at no cost. Must be called with `lock` held.
    private func compactIfDueLocked() {
        guard Date().timeIntervalSince(lastCompaction) > 24 * 60 * 60 else { return }
        lastCompaction = Date()
        let before = events.count
        pruneLocked()
        if events.count != before {
            log.rewrite(events)
        }
    }

    /// Must be called with `lock` already held.
    private func pruneLocked() {
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -Self.retentionDays, to: Date()) ?? .distantPast
        let formatter = ISO8601DateFormatter()
        events.removeAll { event in
            guard let date = formatter.date(from: event.timestamp) else { return true }
            return date < cutoff
        }
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: legacyFileURL.path) {
            // One-time migration. Anything already appended to the new log
            // (none in practice; the legacy file is migrated on first load)
            // is kept after the legacy events.
            let data = try Data(contentsOf: legacyFileURL)
            let legacy = (try? JSONDecoder().decode([MenuItemEngagementEvent].self, from: data)) ?? []
            events = legacy + log.readAll()
            pruneLocked()
            log.rewrite(events)
            log.flush()
            let backup = legacyFileURL.appendingPathExtension("migrated")
            try? fileManager.removeItem(at: backup)
            try fileManager.moveItem(at: legacyFileURL, to: backup)
        } else {
            events = log.readAll()
            pruneLocked()
        }
        lastCompaction = Date()
        loaded = true
    }
}
