import Vapor

/// The three-stage rollout for table-side ordering: launch with just a menu
/// (no ordering UI at all, even though the table id still rides along on
/// every QR scan), then a plain "I'm ready to order" alert once staff are
/// used to guests scanning in, then finally the full item-by-item ordering
/// system that already exists in TableOrders.swift. Nothing about the
/// ordering feature itself is removed by any of this — it's gated behind
/// whichever phase is currently live, so flipping back is just as easy as
/// flipping forward.
enum OrderSystemPhase: String, Codable, CaseIterable {
    case menuOnly
    case readyToOrder
    case fullOrdering
}

struct OrderSystemConfig: Codable, Content {
    var phase: OrderSystemPhase
}

/// A single site-wide setting, same shape/pattern as StaffingStore — one
/// small file-backed value an admin can flip from /table-orders-admin.html
/// without needing a redeploy.
final class OrderSystemStore: @unchecked Sendable {
    static let shared = OrderSystemStore()
    static let defaultPhase: OrderSystemPhase = .menuOnly

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/order-system.json")
    private var config = OrderSystemConfig(phase: OrderSystemStore.defaultPhase)
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("order-system.json")
        loaded = false
    }

    func get() throws -> OrderSystemConfig {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return config
    }

    @discardableResult
    func setPhase(_ phase: OrderSystemPhase) throws -> OrderSystemConfig {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        config.phase = phase
        try persist()
        return config
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            config = try JSONDecoder().decode(OrderSystemConfig.self, from: data)
        } else {
            try persist()
        }
        loaded = true
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}
