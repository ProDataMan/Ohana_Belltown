import Vapor

struct TableOrderEntry: Codable, Content {
    var id: String
    var tableId: String
    var itemName: String
    var status: String
    var createdAt: String
    var updatedAt: String
}

enum TableOrderError: Error, Equatable {
    case entryNotFound
}

extension TableOrderError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .entryNotFound: return .notFound
        }
    }

    var reason: String {
        switch self {
        case .entryNotFound: return "Order not found."
        }
    }
}

final class TableOrdersStore: @unchecked Sendable {
    static let shared = TableOrdersStore()
    /// A table-side "order" here just flags staff — it's not routed through
    /// ChowNow or any payment system. Same staleness window as the waitlist:
    /// this is a same-visit signal, not something that should linger for days.
    static let staleAfterSeconds: TimeInterval = 4 * 60 * 60

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/table-orders.json")
    private var entries: [TableOrderEntry] = []
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("table-orders.json")
        loaded = false
    }

    private func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    @discardableResult
    func place(tableId: String, itemName: String) throws -> TableOrderEntry {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let timestamp = now()
        let entry = TableOrderEntry(
            id: UUID().uuidString, tableId: tableId, itemName: itemName,
            status: "pending", createdAt: timestamp, updatedAt: timestamp
        )
        entries.append(entry)
        try persist()
        return entry
    }

    /// Pending, non-stale orders, oldest first.
    func pending() throws -> [TableOrderEntry] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let cutoff = Date().addingTimeInterval(-Self.staleAfterSeconds)
        let formatter = ISO8601DateFormatter()
        return entries
            .filter { entry in
                guard entry.status == "pending" else { return false }
                guard let created = formatter.date(from: entry.createdAt) else { return true }
                return created > cutoff
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    func acknowledge(id: String) throws -> TableOrderEntry {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = entries.firstIndex(where: { $0.id == id }) else {
            throw TableOrderError.entryNotFound
        }
        entries[idx].status = "acknowledged"
        entries[idx].updatedAt = now()
        try persist()
        return entries[idx]
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([TableOrderEntry].self, from: raw)
        } else {
            entries = []
            try persist()
        }
        loaded = true
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(entries)
        try encoded.write(to: fileURL, options: .atomic)
    }
}
