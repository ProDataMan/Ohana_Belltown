import Foundation
import Vapor

struct SwagOrderItem: Codable, Content, Equatable {
    var productId: String
    var name: String
    var price: Double
    var quantity: Int
}

/// A table's swag purchase, paid for online via Stripe Checkout — unlike a
/// food TableOrderEntry (which just queues for staff and gets paid in
/// person), this actually collects a real card payment before staff bring
/// the item to the table. Lifecycle: pendingPayment (cart submitted, Stripe
/// session created) -> paid (Stripe webhook confirmed the charge) ->
/// delivered (staff brought it to the table).
struct SwagOrder: Codable, Content, Equatable {
    var id: String
    var tableId: String
    var customerId: String?
    var items: [SwagOrderItem]
    var totalAmount: Double
    var status: String
    var stripeSessionId: String?
    var createdAt: String
    var paidAt: String?
    var deliveredAt: String?
}

struct SwagCheckoutRequestItem: Content {
    var productId: String
    var quantity: Int
}

struct SwagCheckoutRequest: Content {
    var tableId: String
    var items: [SwagCheckoutRequestItem]
}

struct SwagCheckoutResponse: Content {
    var checkoutURL: String
}

final class SwagOrdersStore: @unchecked Sendable {
    static let shared = SwagOrdersStore()

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/swag-orders.json")
    private var orders: [SwagOrder] = []
    private var loaded = false

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("swag-orders.json")
        loaded = false
    }

    @discardableResult
    func createPendingOrder(tableId: String, customerId: String?, items: [SwagOrderItem]) throws -> SwagOrder {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let total = items.reduce(0.0) { $0 + $1.price * Double($1.quantity) }
        let order = SwagOrder(
            id: UUID().uuidString, tableId: tableId, customerId: customerId, items: items,
            totalAmount: total, status: "pendingPayment", stripeSessionId: nil,
            createdAt: Self.iso.string(from: Date()), paidAt: nil, deliveredAt: nil
        )
        orders.append(order)
        try persist()
        return order
    }

    @discardableResult
    func attachStripeSession(orderId: String, sessionId: String) throws -> SwagOrder {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let index = orders.firstIndex(where: { $0.id == orderId }) else { throw SwagError.orderNotFound }
        orders[index].stripeSessionId = sessionId
        try persist()
        return orders[index]
    }

    /// Idempotent — Stripe may redeliver the same webhook event more than
    /// once, and re-marking an already-paid order shouldn't stomp paidAt.
    @discardableResult
    func markPaid(orderId: String) throws -> SwagOrder {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let index = orders.firstIndex(where: { $0.id == orderId }) else { throw SwagError.orderNotFound }
        if orders[index].status == "pendingPayment" {
            orders[index].status = "paid"
            orders[index].paidAt = Self.iso.string(from: Date())
            try persist()
        }
        return orders[index]
    }

    @discardableResult
    func markDelivered(id: String) throws -> SwagOrder {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let index = orders.firstIndex(where: { $0.id == id }) else { throw SwagError.orderNotFound }
        orders[index].status = "delivered"
        orders[index].deliveredAt = Self.iso.string(from: Date())
        try persist()
        return orders[index]
    }

    func all() throws -> [SwagOrder] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return orders.sorted { $0.createdAt > $1.createdAt }
    }

    /// Paid but not yet brought to the table — the staff fulfillment queue.
    func awaitingDelivery() throws -> [SwagOrder] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return orders.filter { $0.status == "paid" }.sorted { $0.createdAt < $1.createdAt }
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try Data(contentsOf: fileURL)
            orders = try JSONDecoder().decode([SwagOrder].self, from: raw)
        } else {
            orders = []
            try persist()
        }
        loaded = true
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(orders)
        try encoded.write(to: fileURL, options: .atomic)
    }
}
