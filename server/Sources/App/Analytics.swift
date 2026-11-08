import Vapor

struct DwellStat: Codable {
    var totalSeconds: Double
    var samples: Int
}

/// Aggregated per-day counts (not raw per-visit events).
struct DailyPageviews: Codable {
    var date: String
    var counts: [String: Int]
    var deviceCounts: [String: Int]
    var itemViewCounts: [String: Int]
    var dwell: [String: DwellStat]
    var osCounts: [String: Int]
    var browserCounts: [String: Int]
    var deviceModelCounts: [String: Int]
    var qrScanCounts: [String: Int]
    /// Which page a `/scan` hit actually redirected to — "menu" or
    /// "happy-hour" — so a busy host-stand QR vs. a table-flip "Happy Hour"
    /// QR can be told apart from the raw scan count alone.
    var qrScanDestinationCounts: [String: Int]
    /// Item detail-view opens, bucketed by the table id that was active when
    /// the tap happened (same ids as `qrScanCounts`) — the other half of
    /// "per-table engagement rate" (views ÷ scans for that table).
    var tableItemViewCounts: [String: Int]
    /// Seconds from a fresh `/scan` redirect landing to the first tap on any
    /// item card in that same session — how long it takes a guest to
    /// actually start engaging with the menu once they scan.
    var scanToFirstTapSeconds: DwellStat
    /// Seconds from a fresh `/scan` landing to the tab being hidden/closed,
    /// across however many pages were browsed in that session — a rough
    /// "how long did this scan hold someone's attention" figure.
    var scanSessionSeconds: DwellStat
    /// Free-text menu search queries, lowercased/trimmed — anonymous, same
    /// footing as the rest of this store; short/noise queries are filtered
    /// client- and server-side before they ever reach here.
    var searchQueryCounts: [String: Int]
    /// How far down a page someone actually scrolled, bucketed by
    /// `"<section>:<25|50|75|100>"` — one entry per threshold reached per
    /// page view (not continuous), so this counts visits-that-reached-X%,
    /// not scroll events.
    var scrollDepthCounts: [String: Int]

    enum CodingKeys: String, CodingKey {
        case date, counts, deviceCounts, itemViewCounts, dwell, osCounts, browserCounts, deviceModelCounts, qrScanCounts
        case qrScanDestinationCounts, tableItemViewCounts, scanToFirstTapSeconds, scanSessionSeconds
        case searchQueryCounts, scrollDepthCounts
    }

    init(
        date: String, counts: [String: Int], deviceCounts: [String: Int] = [:],
        itemViewCounts: [String: Int] = [:], dwell: [String: DwellStat] = [:],
        osCounts: [String: Int] = [:], browserCounts: [String: Int] = [:], deviceModelCounts: [String: Int] = [:],
        qrScanCounts: [String: Int] = [:], qrScanDestinationCounts: [String: Int] = [:],
        tableItemViewCounts: [String: Int] = [:],
        scanToFirstTapSeconds: DwellStat = DwellStat(totalSeconds: 0, samples: 0),
        scanSessionSeconds: DwellStat = DwellStat(totalSeconds: 0, samples: 0),
        searchQueryCounts: [String: Int] = [:], scrollDepthCounts: [String: Int] = [:]
    ) {
        self.date = date
        self.counts = counts
        self.deviceCounts = deviceCounts
        self.itemViewCounts = itemViewCounts
        self.dwell = dwell
        self.osCounts = osCounts
        self.browserCounts = browserCounts
        self.deviceModelCounts = deviceModelCounts
        self.qrScanCounts = qrScanCounts
        self.qrScanDestinationCounts = qrScanDestinationCounts
        self.tableItemViewCounts = tableItemViewCounts
        self.scanToFirstTapSeconds = scanToFirstTapSeconds
        self.scanSessionSeconds = scanSessionSeconds
        self.searchQueryCounts = searchQueryCounts
        self.scrollDepthCounts = scrollDepthCounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        counts = try container.decode([String: Int].self, forKey: .counts)
        deviceCounts = try container.decodeIfPresent([String: Int].self, forKey: .deviceCounts) ?? [:]
        itemViewCounts = try container.decodeIfPresent([String: Int].self, forKey: .itemViewCounts) ?? [:]
        dwell = try container.decodeIfPresent([String: DwellStat].self, forKey: .dwell) ?? [:]
        osCounts = try container.decodeIfPresent([String: Int].self, forKey: .osCounts) ?? [:]
        browserCounts = try container.decodeIfPresent([String: Int].self, forKey: .browserCounts) ?? [:]
        deviceModelCounts = try container.decodeIfPresent([String: Int].self, forKey: .deviceModelCounts) ?? [:]
        qrScanCounts = try container.decodeIfPresent([String: Int].self, forKey: .qrScanCounts) ?? [:]
        qrScanDestinationCounts = try container.decodeIfPresent([String: Int].self, forKey: .qrScanDestinationCounts) ?? [:]
        tableItemViewCounts = try container.decodeIfPresent([String: Int].self, forKey: .tableItemViewCounts) ?? [:]
        scanToFirstTapSeconds = try container.decodeIfPresent(DwellStat.self, forKey: .scanToFirstTapSeconds)
            ?? DwellStat(totalSeconds: 0, samples: 0)
        scanSessionSeconds = try container.decodeIfPresent(DwellStat.self, forKey: .scanSessionSeconds)
            ?? DwellStat(totalSeconds: 0, samples: 0)
        searchQueryCounts = try container.decodeIfPresent([String: Int].self, forKey: .searchQueryCounts) ?? [:]
        scrollDepthCounts = try container.decodeIfPresent([String: Int].self, forKey: .scrollDepthCounts) ?? [:]
    }
}

struct AnalyticsSummary: Content {
    var days: [DailyPageviews]
    var totalViews: Int
    var topPages: [PageCount]
    var deviceBreakdown: [DeviceCount]
    var topItems: [ItemCount]
    var pageDwell: [PageDwell]
    var osBreakdown: [OSCount]
    var browserBreakdown: [BrowserCount]
    var deviceModelBreakdown: [DeviceModelCount]
    var qrScans: [QRScanCount]
    var scanDestinations: [ScanDestinationCount]
    var tableEngagement: [TableEngagementCount]
    var neverScannedTables: [String]
    var scanToFirstTapSeconds: Double?
    var scanToFirstTapSamples: Int
    var scanSessionSeconds: Double?
    var scanSessionSamples: Int
    var searchQueries: [SearchQueryCount]
    var scrollDepth: [ScrollDepthCount]
}

struct QRScanCount: Content {
    var table: String
    var count: Int
}

struct ScanDestinationCount: Content {
    var destination: String
    var count: Int
}

/// Per-table "views ÷ scans" — the already-tracked scan count for a table
/// cross-referenced against item detail-view opens recorded while that same
/// table id was active, giving a rough sense of which scans turn into actual
/// menu browsing vs. a scan that never goes anywhere.
struct TableEngagementCount: Content {
    var table: String
    var scans: Int
    var itemViews: Int
    var engagementRate: Double
}

struct SearchQueryCount: Content {
    var query: String
    var count: Int
}

struct ScrollDepthCount: Content {
    var section: String
    var bucket: Int
    var count: Int
}

struct PageCount: Content {
    var path: String
    var count: Int
}

struct DeviceCount: Content {
    var device: String
    var count: Int
}

struct ItemCount: Content {
    var name: String
    var count: Int
}

struct PageDwell: Content {
    var path: String
    var avgSeconds: Double
    var samples: Int
}

struct OSCount: Content {
    var os: String
    var count: Int
}

struct BrowserCount: Content {
    var browser: String
    var count: Int
}

struct DeviceModelCount: Content {
    var model: String
    var count: Int
}

/// Paths that shouldn't show up in "top pages" — staff/admin tools and
/// anything path-parameterized in a way that would fragment the counts.
private let excludedFromTopPages: Set<String> = [
    "/edit.html", "/loyalty-admin.html", "/waitlist-admin.html", "/events-admin.html", "/manage-users.html",
    "/create-account.html", "/account.html", "/change-password.html", "/login",
    "/analytics.html",
]

final class AnalyticsStore: @unchecked Sendable {
    static let shared = AnalyticsStore()

    /// Dwell samples outside this range are dropped — too short to mean
    /// anything, or absurdly long (a tab left open overnight), either way
    /// not representative of someone actually reading the page.
    static let minDwellSeconds: Double = 1
    static let maxDwellSeconds: Double = 1800

    /// The bucket a `/scan` hit with no `table` id falls into — the
    /// front-door "While You Wait" QR by the host stand, or any other scan
    /// that isn't tied to a specific table.
    static let genericScanLabel = "Front Door / No Table"

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/analytics.json")
    private var days: [DailyPageviews] = []
    private var loaded = false

    /// Counts are saved at most once per `persistDelay` on a background
    /// queue instead of on every recorded event. Every page view hits this
    /// store (see AnalyticsMiddleware), and rewriting the whole file on each
    /// one, on an event-loop thread over the Azure Files mount, slowed down
    /// every other request. A crash loses at most a few seconds of counts.
    static let persistDelay: TimeInterval = 5
    private let writeQueue = DispatchQueue(label: "analytics.persist")
    private var persistScheduled = false
    /// Bumped by `configure`, so a save scheduled before a reconfigure never
    /// writes the old data into the newly configured file.
    private var generation = 0

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        if persistScheduled, loaded {
            try? persist()
        }
        persistScheduled = false
        generation += 1
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("analytics.json")
        loaded = false
    }

    /// Writes any pending counts now — for tests.
    func flush() {
        lock.lock()
        defer { lock.unlock() }
        if persistScheduled, loaded {
            try? persist()
        }
        persistScheduled = false
    }

    /// Must be called with `lock` held.
    private func schedulePersistLocked() {
        guard !persistScheduled else { return }
        persistScheduled = true
        let scheduledGeneration = generation
        writeQueue.asyncAfter(deadline: .now() + Self.persistDelay) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard self.persistScheduled, self.generation == scheduledGeneration else { return }
            self.persistScheduled = false
            try? self.persist()
        }
    }

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return formatter.string(from: Date())
    }

    /// Coarse, heuristic bucketing from the User-Agent string — no raw UA is
    /// ever stored, just which of these three buckets it fell into.
    static func deviceType(from userAgent: String?) -> String {
        guard let ua = userAgent else { return "unknown" }
        if ua.contains("iPad") || (ua.contains("Tablet") && !ua.contains("Mobile")) {
            return "tablet"
        }
        if ua.contains("Mobile") || ua.contains("iPhone") || ua.contains("Android") {
            return "mobile"
        }
        return "desktop"
    }

    /// Coarse OS/platform, heuristically read from the User-Agent — no raw UA
    /// is ever stored, just which bucket it fell into.
    static func operatingSystem(from userAgent: String?) -> String {
        guard let ua = userAgent else { return "Unknown" }
        if ua.contains("iPhone") { return "iPhone" }
        if ua.contains("iPad") { return "iPad" }
        if ua.contains("Android") { return "Android" }
        if ua.contains("Macintosh") || ua.contains("Mac OS X") { return "macOS" }
        if ua.contains("Windows") { return "Windows" }
        if ua.contains("Linux") { return "Linux" }
        return "Other"
    }

    /// Browser family from the User-Agent. Order matters: Chrome-based
    /// browsers (Edge, Samsung Internet, Opera) all include "Chrome" in
    /// their UA string, and Chrome itself includes "Safari" — so the more
    /// specific tokens have to be checked first.
    static func browserName(from userAgent: String?) -> String {
        guard let ua = userAgent else { return "Unknown" }
        if ua.contains("EdgiOS") || ua.contains("EdgA") || ua.contains("Edg/") || ua.contains("Edge/") { return "Edge" }
        if ua.contains("SamsungBrowser") { return "Samsung Internet" }
        if ua.contains("OPR/") || ua.contains("Opera") { return "Opera" }
        if ua.contains("FxiOS") || ua.contains("Firefox") { return "Firefox" }
        if ua.contains("CriOS") || ua.contains("Chrome") { return "Chrome" }
        if ua.contains("Safari") { return "Safari" }
        return "Other"
    }

    /// Best-effort Android hardware model (e.g. "Pixel 8", "SM-G991B"), parsed
    /// from the `Android <version>; <model>` segment many Android browsers
    /// include in their UA. Returns nil when it can't be confidently parsed
    /// (including on every iOS device — Apple's UA never exposes a specific
    /// hardware model, only "iPhone"/"iPad") rather than storing a guess.
    static func androidModel(from userAgent: String?) -> String? {
        guard let ua = userAgent, let androidRange = ua.range(of: "Android ") else { return nil }
        let afterAndroid = ua[androidRange.upperBound...]
        guard let semicolon = afterAndroid.firstIndex(of: ";") else { return nil }
        let afterVersion = afterAndroid[afterAndroid.index(after: semicolon)...]
        guard let terminatorIndex = afterVersion.firstIndex(where: { $0 == ")" || $0 == ";" }) else { return nil }
        var model = String(afterVersion[..<terminatorIndex]).trimmingCharacters(in: .whitespaces)
        if let buildRange = model.range(of: " Build/") {
            model = String(model[..<buildRange.lowerBound])
        }
        return model.isEmpty ? nil : model
    }

    private func todayIndex() -> Int {
        let today = Self.today()
        if let idx = days.firstIndex(where: { $0.date == today }) {
            return idx
        }
        days.append(DailyPageviews(date: today, counts: [:]))
        return days.count - 1
    }

    func recordView(path: String, userAgent: String?) {
        lock.lock()
        defer { lock.unlock() }
        try? loadIfNeeded()
        let idx = todayIndex()
        days[idx].counts[path, default: 0] += 1
        days[idx].deviceCounts[Self.deviceType(from: userAgent), default: 0] += 1
        days[idx].osCounts[Self.operatingSystem(from: userAgent), default: 0] += 1
        days[idx].browserCounts[Self.browserName(from: userAgent), default: 0] += 1
        if let model = Self.androidModel(from: userAgent) {
            days[idx].deviceModelCounts[model, default: 0] += 1
        }
        schedulePersistLocked()
    }

    /// `table`, when present, is the table id active when the item's detail
    /// view was opened — threaded through so per-table engagement rate can
    /// be computed without a separate, session-keyed event log.
    func recordItemView(name: String, table: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        try? loadIfNeeded()
        let idx = todayIndex()
        days[idx].itemViewCounts[name, default: 0] += 1
        if let table, !table.isEmpty {
            days[idx].tableItemViewCounts[table, default: 0] += 1
        }
        schedulePersistLocked()
    }

    /// A `/scan` hit — `table` is the raw table/seat id off the physical QR
    /// (e.g. "5", "B2", "R1"), matching what's printed on the card itself, or
    /// `Self.genericScanLabel` for the front-door QR (no table). Recorded
    /// server-side in the `/scan` redirect itself, independent of whatever
    /// the guest does next (browse only, or actually place an order) — the
    /// only way to see "which tables are using the QR menu" at all, since an
    /// order-based report misses everyone who scanned and just browsed.
    /// `destination` is which page the scan actually redirected to ("menu"
    /// or "happy-hour").
    func recordQRScan(table: String, destination: String) {
        lock.lock()
        defer { lock.unlock() }
        try? loadIfNeeded()
        let idx = todayIndex()
        days[idx].qrScanCounts[table, default: 0] += 1
        days[idx].qrScanDestinationCounts[destination, default: 0] += 1
        schedulePersistLocked()
    }

    func recordScanToFirstTap(seconds: Double) {
        guard seconds >= 0, seconds <= Self.maxDwellSeconds else { return }
        lock.lock()
        defer { lock.unlock() }
        try? loadIfNeeded()
        let idx = todayIndex()
        days[idx].scanToFirstTapSeconds.totalSeconds += seconds
        days[idx].scanToFirstTapSeconds.samples += 1
        schedulePersistLocked()
    }

    func recordScanSession(seconds: Double) {
        guard seconds >= 0, seconds <= Self.maxDwellSeconds else { return }
        lock.lock()
        defer { lock.unlock() }
        try? loadIfNeeded()
        let idx = todayIndex()
        days[idx].scanSessionSeconds.totalSeconds += seconds
        days[idx].scanSessionSeconds.samples += 1
        schedulePersistLocked()
    }

    /// Lowercased/trimmed search text only — queries under 2 characters are
    /// dropped before they ever get here (both client- and server-side) since
    /// a single keystroke mid-typing isn't a meaningful search term.
    func recordSearchQuery(_ query: String) {
        lock.lock()
        defer { lock.unlock() }
        try? loadIfNeeded()
        let idx = todayIndex()
        days[idx].searchQueryCounts[query, default: 0] += 1
        schedulePersistLocked()
    }

    func recordScrollDepth(section: String, bucket: Int) {
        lock.lock()
        defer { lock.unlock() }
        try? loadIfNeeded()
        let idx = todayIndex()
        days[idx].scrollDepthCounts["\(section):\(bucket)", default: 0] += 1
        schedulePersistLocked()
    }

    /// Every table on the floor map that hasn't had a single `/scan` hit in
    /// any stored day — not just the summary's windowed range, since a table
    /// that was scanned once three months ago shouldn't show up as "never
    /// scanned" just because the report window is 30 days.
    func neverScannedTables() throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        var scanned = Set<String>()
        for day in days {
            scanned.formUnion(day.qrScanCounts.keys)
        }
        return TableMap.allIds.subtracting(scanned).sorted()
    }

    func recordDwell(path: String, seconds: Double) {
        guard seconds >= Self.minDwellSeconds, seconds <= Self.maxDwellSeconds else { return }
        lock.lock()
        defer { lock.unlock() }
        try? loadIfNeeded()
        let idx = todayIndex()
        var stat = days[idx].dwell[path] ?? DwellStat(totalSeconds: 0, samples: 0)
        stat.totalSeconds += seconds
        stat.samples += 1
        days[idx].dwell[path] = stat
        schedulePersistLocked()
    }

    func summary(days dayCount: Int) throws -> AnalyticsSummary {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let recent = Array(days.sorted { $0.date > $1.date }.prefix(dayCount))

        var totals: [String: Int] = [:]
        var deviceTotals: [String: Int] = [:]
        var itemTotals: [String: Int] = [:]
        var dwellTotals: [String: DwellStat] = [:]
        var osTotals: [String: Int] = [:]
        var browserTotals: [String: Int] = [:]
        var deviceModelTotals: [String: Int] = [:]
        var qrScanTotals: [String: Int] = [:]
        var qrScanDestinationTotals: [String: Int] = [:]
        var tableItemViewTotals: [String: Int] = [:]
        var scanToFirstTapTotal = DwellStat(totalSeconds: 0, samples: 0)
        var scanSessionTotal = DwellStat(totalSeconds: 0, samples: 0)
        var searchQueryTotals: [String: Int] = [:]
        var scrollDepthTotals: [String: Int] = [:]
        for day in recent {
            for (path, count) in day.counts {
                totals[path, default: 0] += count
            }
            for (device, count) in day.deviceCounts {
                deviceTotals[device, default: 0] += count
            }
            for (name, count) in day.itemViewCounts {
                itemTotals[name, default: 0] += count
            }
            for (path, stat) in day.dwell {
                var combined = dwellTotals[path] ?? DwellStat(totalSeconds: 0, samples: 0)
                combined.totalSeconds += stat.totalSeconds
                combined.samples += stat.samples
                dwellTotals[path] = combined
            }
            for (os, count) in day.osCounts {
                osTotals[os, default: 0] += count
            }
            for (browser, count) in day.browserCounts {
                browserTotals[browser, default: 0] += count
            }
            for (model, count) in day.deviceModelCounts {
                deviceModelTotals[model, default: 0] += count
            }
            for (table, count) in day.qrScanCounts {
                qrScanTotals[table, default: 0] += count
            }
            for (destination, count) in day.qrScanDestinationCounts {
                qrScanDestinationTotals[destination, default: 0] += count
            }
            for (table, count) in day.tableItemViewCounts {
                tableItemViewTotals[table, default: 0] += count
            }
            scanToFirstTapTotal.totalSeconds += day.scanToFirstTapSeconds.totalSeconds
            scanToFirstTapTotal.samples += day.scanToFirstTapSeconds.samples
            scanSessionTotal.totalSeconds += day.scanSessionSeconds.totalSeconds
            scanSessionTotal.samples += day.scanSessionSeconds.samples
            for (query, count) in day.searchQueryCounts {
                searchQueryTotals[query, default: 0] += count
            }
            for (key, count) in day.scrollDepthCounts {
                scrollDepthTotals[key, default: 0] += count
            }
        }

        let topPages = totals
            .filter { !excludedFromTopPages.contains($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map { PageCount(path: $0.key, count: $0.value) }

        let deviceBreakdown = deviceTotals
            .sorted { $0.value > $1.value }
            .map { DeviceCount(device: $0.key, count: $0.value) }

        let topItems = itemTotals
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map { ItemCount(name: $0.key, count: $0.value) }

        let pageDwell = dwellTotals
            .filter { $0.value.samples >= 3 }
            .map { PageDwell(path: $0.key, avgSeconds: $0.value.totalSeconds / Double($0.value.samples), samples: $0.value.samples) }
            .sorted { $0.avgSeconds > $1.avgSeconds }
            .prefix(15)

        let osBreakdown = osTotals
            .sorted { $0.value > $1.value }
            .map { OSCount(os: $0.key, count: $0.value) }

        let browserBreakdown = browserTotals
            .sorted { $0.value > $1.value }
            .map { BrowserCount(browser: $0.key, count: $0.value) }

        let deviceModelBreakdown = deviceModelTotals
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map { DeviceModelCount(model: $0.key, count: $0.value) }

        // Most-scanned table first; the front-door/generic bucket always
        // last regardless of its count — it isn't a table, so it shouldn't
        // compete in a "which table gets scanned most" ranking.
        let qrScans = qrScanTotals
            .sorted { lhs, rhs in
                if lhs.key == Self.genericScanLabel { return false }
                if rhs.key == Self.genericScanLabel { return true }
                return lhs.value > rhs.value
            }
            .map { QRScanCount(table: $0.key, count: $0.value) }

        let scanDestinations = qrScanDestinationTotals
            .sorted { $0.value > $1.value }
            .map { ScanDestinationCount(destination: $0.key, count: $0.value) }

        // Every table that showed up as a scan or an attributed item view in
        // this window, most-scanned first (generic/no-table last, same as
        // qrScans — it isn't a table, so it shouldn't win "most engaged").
        let engagedTableIds = Set(qrScanTotals.keys).union(tableItemViewTotals.keys)
        let tableEngagement = engagedTableIds
            .map { table -> TableEngagementCount in
                let scans = qrScanTotals[table] ?? 0
                let views = tableItemViewTotals[table] ?? 0
                let rate = scans > 0 ? Double(views) / Double(scans) : 0
                return TableEngagementCount(table: table, scans: scans, itemViews: views, engagementRate: rate)
            }
            .sorted { lhs, rhs in
                if lhs.table == Self.genericScanLabel { return false }
                if rhs.table == Self.genericScanLabel { return true }
                return lhs.scans > rhs.scans
            }

        let searchQueries = searchQueryTotals
            .sorted { $0.value > $1.value }
            .prefix(30)
            .map { SearchQueryCount(query: $0.key, count: $0.value) }

        let scrollDepth = scrollDepthTotals
            .compactMap { key, count -> ScrollDepthCount? in
                let parts = key.split(separator: ":")
                guard parts.count == 2, let bucket = Int(parts[1]) else { return nil }
                return ScrollDepthCount(section: String(parts[0]), bucket: bucket, count: count)
            }
            .sorted { lhs, rhs in
                lhs.section == rhs.section ? lhs.bucket < rhs.bucket : lhs.section < rhs.section
            }

        return AnalyticsSummary(
            days: recent.sorted { $0.date < $1.date },
            totalViews: totals.values.reduce(0, +),
            topPages: Array(topPages),
            deviceBreakdown: deviceBreakdown,
            topItems: Array(topItems),
            pageDwell: Array(pageDwell),
            osBreakdown: osBreakdown,
            browserBreakdown: browserBreakdown,
            deviceModelBreakdown: Array(deviceModelBreakdown),
            qrScans: qrScans,
            scanDestinations: scanDestinations,
            tableEngagement: tableEngagement,
            neverScannedTables: try neverScannedTablesLocked(),
            scanToFirstTapSeconds: scanToFirstTapTotal.samples > 0 ? scanToFirstTapTotal.totalSeconds / Double(scanToFirstTapTotal.samples) : nil,
            scanToFirstTapSamples: scanToFirstTapTotal.samples,
            scanSessionSeconds: scanSessionTotal.samples > 0 ? scanSessionTotal.totalSeconds / Double(scanSessionTotal.samples) : nil,
            scanSessionSamples: scanSessionTotal.samples,
            searchQueries: Array(searchQueries),
            scrollDepth: scrollDepth
        )
    }

    /// Same logic as `neverScannedTables()`, but callable from inside
    /// `summary(days:)` while the lock is already held — `neverScannedTables()`
    /// itself takes the lock, so calling it directly from here would deadlock.
    private func neverScannedTablesLocked() throws -> [String] {
        var scanned = Set<String>()
        for day in days {
            scanned.formUnion(day.qrScanCounts.keys)
        }
        return TableMap.allIds.subtracting(scanned).sorted()
    }

    /// Most-viewed menu items over the given window, for auto-featuring.
    /// Returns names only — the caller decides what "most viewed" should do.
    func topItemNames(days dayCount: Int, limit: Int) throws -> [String] {
        try summary(days: dayCount).topItems.prefix(limit).map { $0.name }
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            days = try JSONDecoder().decode([DailyPageviews].self, from: data)
        } else {
            days = []
            try persist()
        }
        loaded = true
    }

    private func persist() throws {
        // Keep at most 120 days of history so the file doesn't grow forever.
        if days.count > 120 {
            days = Array(days.sorted { $0.date > $1.date }.prefix(120))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(days)
        try data.write(to: fileURL, options: .atomic)
    }
}

struct AnalyticsMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)

        if request.method == .GET,
           response.status == .ok,
           response.headers.contentType?.type == "text",
           response.headers.contentType?.subType == "html" {
            let path = request.url.path
            if !path.hasPrefix("/api/") && path != "/healthz" {
                AnalyticsStore.shared.recordView(path: path.isEmpty ? "/" : path, userAgent: request.headers[.userAgent].first)
            }
        }

        return response
    }
}
