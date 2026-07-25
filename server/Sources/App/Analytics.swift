import Vapor

/// Aggregated per-day, per-path view counts (not raw per-visit events).
struct DailyPageviews: Codable {
    var date: String
    var counts: [String: Int]
}

struct AnalyticsSummary: Content {
    var days: [DailyPageviews]
    var totalViews: Int
    var topPages: [PageCount]
}

struct PageCount: Content {
    var path: String
    var count: Int
}

/// Paths that shouldn't show up in "top pages" — staff/admin tools and
/// anything path-parameterized in a way that would fragment the counts.
private let excludedFromTopPages: Set<String> = [
    "/edit.html", "/loyalty-admin.html", "/events-admin.html", "/manage-users.html",
    "/create-account.html", "/account.html", "/change-password.html", "/login",
    "/analytics.html",
]

final class AnalyticsStore: @unchecked Sendable {
    static let shared = AnalyticsStore()

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

    func recordView(path: String) {
        lock.lock()
        defer { lock.unlock() }
        try? loadIfNeeded()
        let today = Self.today()
        if let idx = days.firstIndex(where: { $0.date == today }) {
            days[idx].counts[path, default: 0] += 1
        } else {
            days.append(DailyPageviews(date: today, counts: [path: 1]))
        }
        try? persist()
    }

    func summary(days dayCount: Int) throws -> AnalyticsSummary {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let recent = Array(days.sorted { $0.date > $1.date }.prefix(dayCount))

        var totals: [String: Int] = [:]
        for day in recent {
            for (path, count) in day.counts {
                totals[path, default: 0] += count
            }
        }
        let topPages = totals
            .filter { !excludedFromTopPages.contains($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map { PageCount(path: $0.key, count: $0.value) }

        return AnalyticsSummary(
            days: recent.sorted { $0.date < $1.date },
            totalViews: totals.values.reduce(0, +),
            topPages: Array(topPages)
        )
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
                AnalyticsStore.shared.recordView(path: path.isEmpty ? "/" : path)
            }
        }

        return response
    }
}
