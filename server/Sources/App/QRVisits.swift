import Vapor

/// One thing a guest did during a QR-originated visit: landing from the scan
/// itself (`start`), opening a page, opening an item's detail view, tapping
/// an item's photo, searching, or adding an item to a table order.
///
/// A visit begins when someone scans a table card (or the front-door / Happy
/// Hour QR) and lasts for that browser tab until two hours pass without
/// activity (see the visit tracker in nav.js). Every event carries the
/// visit's table, so "what did table 12 look at between 7 and 8pm" is a
/// filter over this log, and the same table + time window is what lines a
/// visit up against an order in the POS.
///
/// Unlike AnalyticsStore's anonymous daily counts, these are attributed to
/// the per-browser `deviceId` (and the signed-in customer, if any), the same
/// footing as MenuItemEngagementStore, disclosed on /privacy.
struct QRVisitEvent: Codable, Equatable {
    var visitId: String
    var deviceId: String
    var customerId: String?
    var table: String?
    /// Only on `start`: "table", "front-door", or "happy-hour".
    var source: String?
    /// Only on `start`: coarse device label from the User-Agent, e.g.
    /// "iPhone · Safari". The raw User-Agent is never stored.
    var device: String?
    var type: String
    var page: String?
    var itemName: String?
    var query: String?
    /// Server time (ISO 8601), never the phone's clock.
    var at: String
}

struct QRVisitItemCount: Content {
    var itemName: String
    var count: Int
}

struct QRVisitTimelineEntry: Content {
    var type: String
    var at: String
    var page: String?
    var itemName: String?
    var query: String?
}

struct QRVisitSummary: Content {
    var visitId: String
    var table: String?
    var source: String?
    var device: String?
    var deviceId: String
    var customerId: String?
    var customerName: String?
    var startedAt: String
    var lastSeenAt: String
    var durationSeconds: Double
    var pageViews: Int
    var pages: [String]
    var detailViews: [QRVisitItemCount]
    var photoTaps: [QRVisitItemCount]
    var searches: [String]
    var addedToOrder: [String]
    /// Earlier QR visits from this same browser, so a regular can be told
    /// apart from a first-timer.
    var previousVisits: Int
    var timeline: [QRVisitTimelineEntry]
}

final class QRVisitStore: @unchecked Sendable {
    static let shared = QRVisitStore()

    static let retentionDays = 120
    /// A cap per visit so one runaway (or hostile) tab can't fill the log:
    /// this is a public, unauthenticated endpoint.
    static let maxEventsPerVisit = 1000

    enum EventType: String, CaseIterable {
        case start
        case page
        case details
        case photo
        case search
        case addToOrder = "add-to-order"
    }

    static let sources: Set<String> = ["table", "front-door", "happy-hour"]

    private let lock = NSLock()
    private var log = JSONLinesLog<QRVisitEvent>(fileURL: URL(fileURLWithPath: "Data/qr-visit-events.jsonl"))
    private var events: [QRVisitEvent] = []
    private var eventsPerVisit: [String: Int] = [:]
    private var loaded = false
    private var lastCompaction = Date()

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        log.flush()
        log = JSONLinesLog(fileURL: URL(fileURLWithPath: dataDirectory).appendingPathComponent("qr-visit-events.jsonl"))
        loaded = false
    }

    func flush() {
        lock.lock()
        defer { lock.unlock() }
        log.flush()
    }

    func warmUp() {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
    }

    /// Ids come from the browser (crypto.randomUUID), so anything that isn't
    /// a short run of letters, digits and dashes is junk or abuse.
    static func isValidId(_ value: String) -> Bool {
        (8...64).contains(value.count) && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    static func clean(_ value: String?, maxLength: Int) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }

    /// Returns false (and records nothing) when the event is malformed or
    /// the visit has hit its cap.
    @discardableResult
    func record(_ event: QRVisitEvent) -> Bool {
        guard Self.isValidId(event.visitId), Self.isValidId(event.deviceId),
              EventType(rawValue: event.type) != nil else { return false }
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        guard eventsPerVisit[event.visitId, default: 0] < Self.maxEventsPerVisit else { return false }
        eventsPerVisit[event.visitId, default: 0] += 1
        events.append(event)
        log.append([event])
        compactIfDueLocked()
        return true
    }

    /// Visits that started in `[from, to)`, newest first, optionally only
    /// one table's.
    func visits(from: Date, to: Date, table: String? = nil) -> [QRVisitSummary] {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        let formatter = ISO8601DateFormatter()

        var byVisit: [String: [QRVisitEvent]] = [:]
        for event in events {
            byVisit[event.visitId, default: []].append(event)
        }
        // Start times per device, for "previous visits from this browser".
        var visitStartsByDevice: [String: [Date]] = [:]
        var built: [(start: Date, summary: QRVisitSummary)] = []
        for (visitId, visitEvents) in byVisit {
            let sorted = visitEvents.sorted { $0.at < $1.at }
            guard let first = sorted.first, let last = sorted.last,
                  let startDate = formatter.date(from: first.at),
                  let endDate = formatter.date(from: last.at) else { continue }
            visitStartsByDevice[first.deviceId, default: []].append(startDate)
            let start = sorted.first { $0.type == EventType.start.rawValue }
            let visitTable = start?.table ?? sorted.compactMap(\.table).first
            if let table, visitTable != table { continue }
            guard startDate >= from, startDate < to else { continue }

            func counts(_ type: EventType) -> [QRVisitItemCount] {
                var tally: [String: Int] = [:]
                var order: [String] = []
                for event in sorted where event.type == type.rawValue {
                    guard let name = event.itemName else { continue }
                    if tally[name] == nil { order.append(name) }
                    tally[name, default: 0] += 1
                }
                return order.map { QRVisitItemCount(itemName: $0, count: tally[$0] ?? 0) }
            }
            let pageEvents = sorted.filter { $0.type == EventType.page.rawValue }
            var pages: [String] = []
            for page in pageEvents.compactMap(\.page) where pages.last != page {
                pages.append(page)
            }
            let customerId = sorted.compactMap(\.customerId).first
            built.append((startDate, QRVisitSummary(
                visitId: visitId,
                table: visitTable,
                source: start?.source,
                device: start?.device,
                deviceId: first.deviceId,
                customerId: customerId,
                customerName: customerId.flatMap { (try? CustomerUserStore.shared.find(id: $0))?.displayName },
                startedAt: first.at,
                lastSeenAt: last.at,
                durationSeconds: endDate.timeIntervalSince(startDate),
                pageViews: pageEvents.count,
                pages: pages,
                detailViews: counts(.details),
                photoTaps: counts(.photo),
                searches: sorted.filter { $0.type == EventType.search.rawValue }.compactMap(\.query),
                addedToOrder: sorted.filter { $0.type == EventType.addToOrder.rawValue }.compactMap(\.itemName),
                previousVisits: 0,
                timeline: sorted.map { QRVisitTimelineEntry(type: $0.type, at: $0.at, page: $0.page, itemName: $0.itemName, query: $0.query) }
            )))
        }
        return built
            .map { entry -> QRVisitSummary in
                var summary = entry.summary
                summary.previousVisits = visitStartsByDevice[summary.deviceId]?.filter { $0 < entry.start }.count ?? 0
                return summary
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// Raw events in `[from, to)`, oldest first — backs the CSV export.
    func events(from: Date, to: Date, table: String? = nil) -> [QRVisitEvent] {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        let formatter = ISO8601DateFormatter()
        var tableByVisit: [String: String] = [:]
        for event in events {
            if let eventTable = event.table, tableByVisit[event.visitId] == nil {
                tableByVisit[event.visitId] = eventTable
            }
        }
        return events
            .filter { event in
                guard let date = formatter.date(from: event.at), date >= from, date < to else { return false }
                if let table { return (event.table ?? tableByVisit[event.visitId]) == table }
                return true
            }
            .sorted { $0.at < $1.at }
    }

    /// Must be called with `lock` held.
    private func compactIfDueLocked() {
        guard Date().timeIntervalSince(lastCompaction) > 24 * 60 * 60 else { return }
        lastCompaction = Date()
        let before = events.count
        pruneLocked()
        if events.count != before {
            log.rewrite(events)
        }
    }

    /// Must be called with `lock` held.
    private func pruneLocked() {
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -Self.retentionDays, to: Date()) ?? .distantPast
        let formatter = ISO8601DateFormatter()
        events.removeAll { event in
            guard let date = formatter.date(from: event.at) else { return true }
            return date < cutoff
        }
        eventsPerVisit = events.reduce(into: [:]) { $0[$1.visitId, default: 0] += 1 }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        events = log.readAll()
        pruneLocked()
        lastCompaction = Date()
        loaded = true
    }
}
