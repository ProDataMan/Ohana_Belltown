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

    enum CodingKeys: String, CodingKey {
        case date, counts, deviceCounts, itemViewCounts, dwell, osCounts, browserCounts, deviceModelCounts
    }

    init(
        date: String, counts: [String: Int], deviceCounts: [String: Int] = [:],
        itemViewCounts: [String: Int] = [:], dwell: [String: DwellStat] = [:],
        osCounts: [String: Int] = [:], browserCounts: [String: Int] = [:], deviceModelCounts: [String: Int] = [:]
    ) {
        self.date = date
        self.counts = counts
        self.deviceCounts = deviceCounts
        self.itemViewCounts = itemViewCounts
        self.dwell = dwell
        self.osCounts = osCounts
        self.browserCounts = browserCounts
        self.deviceModelCounts = deviceModelCounts
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
        var osTotals: [String: Int] = [:]
        var browserTotals: [String: Int] = [:]
        var deviceModelTotals: [String: Int] = [:]
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

        return AnalyticsSummary(
            days: recent.sorted { $0.date < $1.date },
            totalViews: totals.values.reduce(0, +),
            topPages: Array(topPages),
            deviceBreakdown: deviceBreakdown,
            topItems: Array(topItems),
            pageDwell: Array(pageDwell),
            osBreakdown: osBreakdown,
            browserBreakdown: browserBreakdown,
            deviceModelBreakdown: Array(deviceModelBreakdown)
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
