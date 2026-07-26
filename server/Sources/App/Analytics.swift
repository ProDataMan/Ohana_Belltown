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

    enum CodingKeys: String, CodingKey {
        case date, counts, deviceCounts, itemViewCounts, dwell
    }

    init(
        date: String, counts: [String: Int], deviceCounts: [String: Int] = [:],
        itemViewCounts: [String: Int] = [:], dwell: [String: DwellStat] = [:]
    ) {
        self.date = date
        self.counts = counts
        self.deviceCounts = deviceCounts
        self.itemViewCounts = itemViewCounts
        self.dwell = dwell
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        counts = try container.decode([String: Int].self, forKey: .counts)
        deviceCounts = try container.decodeIfPresent([String: Int].self, forKey: .deviceCounts) ?? [:]
        itemViewCounts = try container.decodeIfPresent([String: Int].self, forKey: .itemViewCounts) ?? [:]
        dwell = try container.decodeIfPresent([String: DwellStat].self, forKey: .dwell) ?? [:]
    }
}

struct AnalyticsSummary: Content {
    var days: [DailyPageviews]
    var totalViews: Int
    var topPages: [PageCount]
    var deviceBreakdown: [DeviceCount]
    var topItems: [ItemCount]
    var pageDwell: [PageDwell]
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

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/analytics.json")
    private var days: [DailyPageviews] = []
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("analytics.json")
        loaded = false
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
        try? persist()
    }

    func recordItemView(name: String) {
        lock.lock()
        defer { lock.unlock() }
        try? loadIfNeeded()
        let idx = todayIndex()
        days[idx].itemViewCounts[name, default: 0] += 1
        try? persist()
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
        try? persist()
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

        return AnalyticsSummary(
            days: recent.sorted { $0.date < $1.date },
            totalViews: totals.values.reduce(0, +),
            topPages: Array(topPages),
            deviceBreakdown: deviceBreakdown,
            topItems: Array(topItems),
            pageDwell: Array(pageDwell)
        )
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
