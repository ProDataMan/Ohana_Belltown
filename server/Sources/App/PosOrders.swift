import Vapor

/// One ticket from the in-restaurant POS (Heartland), imported by the daily
/// API sync (HeartlandSync) or a CSV upload (PosCSVImport), so QR visits can
/// be compared with what each table actually ordered.
///
/// Only what that comparison needs is kept: table, times, guest count, and
/// items. Heartland's order records also carry guest names, phone numbers
/// and card details; those are dropped at import and never stored.
struct PosOrder: Codable, Equatable {
    /// "heartland:<ticket id>" or "csv:<business date>:<ticket>".
    var id: String
    /// "heartland-api" or "csv".
    var source: String
    var ticketNumber: String?
    /// The table's name in the POS, normalized with `PosMatching.tableKey`
    /// so it lines up with the floor map / QR card ids ("30", "B1", "R2").
    var table: String?
    var room: String?
    var openedAt: String
    var closedAt: String?
    var guestCount: Int?
    var items: [PosOrderItem]
    var netSales: Double?
}

struct PosOrderItem: Codable, Equatable {
    var name: String
    var quantity: Double
    var netSales: Double?
}

struct PosSyncStatus: Codable, Content {
    var at: String
    var source: String
    var from: String?
    var to: String?
    var ordersImported: Int
    var error: String?
}

private struct PosOrderFile: Codable {
    var orders: [PosOrder]
    var lastSync: PosSyncStatus?
}

final class PosOrderStore: @unchecked Sendable {
    static let shared = PosOrderStore()
    static let retentionDays = 120

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/pos-orders.json")
    private var file = PosOrderFile(orders: [], lastSync: nil)
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("pos-orders.json")
        loaded = false
    }

    /// Adds new orders and replaces ones already imported (same id), so a
    /// re-sync or re-upload of the same days never double counts. Written
    /// once per import, never per request.
    @discardableResult
    func upsert(_ orders: [PosOrder], status: PosSyncStatus) throws -> (added: Int, updated: Int) {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        var index = Dictionary(uniqueKeysWithValues: file.orders.enumerated().map { ($1.id, $0) })
        var added = 0
        var updated = 0
        for order in orders {
            if let i = index[order.id] {
                if file.orders[i] != order { updated += 1 }
                file.orders[i] = order
            } else {
                index[order.id] = file.orders.count
                file.orders.append(order)
                added += 1
            }
        }
        prune()
        file.lastSync = status
        try persist()
        return (added, updated)
    }

    func recordFailure(_ status: PosSyncStatus) {
        lock.lock()
        defer { lock.unlock() }
        try? loadIfNeeded()
        file.lastSync = status
        try? persist()
    }

    func lastSync() -> PosSyncStatus? {
        lock.lock()
        defer { lock.unlock() }
        try? loadIfNeeded()
        return file.lastSync
    }

    /// Orders opened in `[from, to)`, oldest first.
    func orders(from: Date, to: Date) -> [PosOrder] {
        lock.lock()
        defer { lock.unlock() }
        try? loadIfNeeded()
        return file.orders
            .filter { order in
                guard let opened = PosMatching.date(order.openedAt) else { return false }
                return opened >= from && opened < to
            }
            .sorted { $0.openedAt < $1.openedAt }
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        file.orders.removeAll { (PosMatching.date($0.openedAt) ?? .distantPast) < cutoff }
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        if let data = FileManager.default.contents(atPath: fileURL.path), !data.isEmpty {
            file = try JSONDecoder().decode(PosOrderFile.self, from: data)
        } else {
            file = PosOrderFile(orders: [], lastSync: nil)
        }
        loaded = true
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(file).write(to: fileURL, options: .atomic)
    }
}

/// Lining QR visits up with POS tickets.
enum PosMatching {
    /// A ticket counts as that visit's order when the two overlap in time at
    /// the same table: the visit (from 15 minutes before the scan, for a
    /// ticket the server opened as the party sat down, to 90 minutes after
    /// the last tap, for ordering after browsing) against the ticket's open
    /// to close.
    static let leadTime: TimeInterval = 15 * 60
    static let trailTime: TimeInterval = 90 * 60
    /// A ticket with no close time is treated as open this long.
    static let assumedTicketLength: TimeInterval = 3 * 60 * 60

    static func date(_ string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: string) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }

    /// "Table 30" → "30", "b1" → "B1", "07" → "7".
    static func tableKey(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value.lowercased() != "null" else {
            return nil
        }
        for prefix in ["table #", "table#", "table", "tbl", "#"] where value.lowercased().hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        value = value.uppercased().replacingOccurrences(of: " ", with: "")
        if let number = Int(value) { return String(number) }
        return value.isEmpty ? nil : value
    }

    /// Lowercased letters and digits only, with any "(16oz)"-style
    /// parenthetical dropped, so "Spam Musubi (2pc)" and "SPAM MUSUBI" match.
    static func itemKey(_ name: String) -> String {
        var text = name.lowercased()
        while let open = text.firstIndex(of: "("), let close = text[open...].firstIndex(of: ")") {
            text.removeSubrange(open...close)
        }
        return text.filter { $0.isLetter || $0.isNumber }
    }

    /// Whether a POS item name and a website menu item name are the same dish:
    /// identical keys, or one contained in the other when both are specific
    /// enough (5+ characters) for that not to be a coincidence.
    static func sameItem(_ posName: String, _ menuName: String) -> Bool {
        let a = itemKey(posName)
        let b = itemKey(menuName)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        guard min(a.count, b.count) >= 5 else { return false }
        return a.contains(b) || b.contains(a)
    }

    static func orders(for visit: QRVisitSummary, in orders: [PosOrder]) -> [PosOrder] {
        guard let table = tableKey(visit.table),
              let start = date(visit.startedAt), let end = date(visit.lastSeenAt) else { return [] }
        let windowStart = start.addingTimeInterval(-leadTime)
        let windowEnd = end.addingTimeInterval(trailTime)
        return orders.filter { order in
            guard order.table == table, let opened = date(order.openedAt) else { return false }
            let closed = order.closedAt.flatMap(date) ?? opened.addingTimeInterval(assumedTicketLength)
            return opened <= windowEnd && closed >= windowStart
        }
    }
}

/// A matched ticket, as shown on a QR visit.
struct PosOrderBrief: Content {
    var ticketNumber: String?
    var openedAt: String
    var closedAt: String?
    var guestCount: Int?
    var items: [QRVisitItemCount]
    var netSales: Double?

    init(_ order: PosOrder) {
        ticketNumber = order.ticketNumber
        openedAt = order.openedAt
        closedAt = order.closedAt
        guestCount = order.guestCount
        var counts: [String: Double] = [:]
        var names: [String] = []
        for item in order.items {
            if counts[item.name] == nil { names.append(item.name) }
            counts[item.name, default: 0] += item.quantity
        }
        items = names.map { QRVisitItemCount(itemName: $0, count: Int((counts[$0] ?? 1).rounded())) }
        netSales = order.netSales
    }
}
