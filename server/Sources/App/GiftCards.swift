import Foundation
import Vapor

/// Reasonable sanity bounds on a custom gift card amount — guards against a
/// fat-fingered $99999 or a $0 request, not a hard business rule.
let giftCardMinAmount: Double = 5
let giftCardMaxAmount: Double = 500

/// A gift card purchase paid for online via Square Checkout. Ohana already
/// sells physical gift cards in person — this doesn't create or activate a
/// Square gift card through the API, it just collects payment for one.
/// Unlike a SwagOrder, this deliberately isn't tied to a table: most gift
/// cards are bought as a gift, not while dining in, so staff instead follow
/// up with the buyer directly (activate a physical card and mail it, hold
/// it for pickup, etc.) using the contact info collected at checkout.
/// Lifecycle: pendingPayment -> paid (Square webhook confirmed the charge)
/// -> fulfilled (staff got the physical card to the buyer/recipient).
struct GiftCardOrder: Codable, Content, Equatable {
    var id: String
    var amount: Double
    var buyerName: String
    var buyerEmail: String
    var recipientName: String?
    var note: String?
    var customerId: String?
    var status: String
    var squareOrderId: String?
    var createdAt: String
    var paidAt: String?
    var fulfilledAt: String?
}

struct GiftCardCheckoutRequest: Content {
    var amount: Double
    var buyerName: String
    var buyerEmail: String
    var recipientName: String?
    var note: String?
}

struct GiftCardCheckoutResponse: Content {
    var checkoutURL: String
}

enum GiftCardError: Error {
    case orderNotFound
    case invalidAmount
}

extension GiftCardError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .orderNotFound: return .notFound
        case .invalidAmount: return .badRequest
        }
    }

    var reason: String {
        switch self {
        case .orderNotFound: return "Gift card order not found."
        case .invalidAmount: return "Enter an amount between $\(Int(giftCardMinAmount)) and $\(Int(giftCardMaxAmount))."
        }
    }
}

final class GiftCardOrdersStore: @unchecked Sendable {
    static let shared = GiftCardOrdersStore()

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/gift-card-orders.json")
    private var orders: [GiftCardOrder] = []
    private var loaded = false

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("gift-card-orders.json")
        loaded = false
    }

    @discardableResult
    func createPendingOrder(
        amount: Double, buyerName: String, buyerEmail: String, recipientName: String?, note: String?, customerId: String?
    ) throws -> GiftCardOrder {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let order = GiftCardOrder(
            id: UUID().uuidString, amount: amount, buyerName: buyerName, buyerEmail: buyerEmail,
            recipientName: recipientName, note: note, customerId: customerId, status: "pendingPayment",
            squareOrderId: nil, createdAt: Self.iso.string(from: Date()), paidAt: nil, fulfilledAt: nil
        )
        orders.append(order)
        try persist()
        return order
    }

    @discardableResult
    func attachSquareOrderId(orderId: String, squareOrderId: String) throws -> GiftCardOrder {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let index = orders.firstIndex(where: { $0.id == orderId }) else { throw GiftCardError.orderNotFound }
        orders[index].squareOrderId = squareOrderId
        try persist()
        return orders[index]
    }

    /// Returns nil (rather than throwing) when no gift card order matches —
    /// the shared Square webhook also checks SwagOrdersStore for the same
    /// squareOrderId, so "not found here" is an expected, non-error outcome.
    @discardableResult
    func markPaidIfPresent(squareOrderId: String) throws -> GiftCardOrder? {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let index = orders.firstIndex(where: { $0.squareOrderId == squareOrderId }) else { return nil }
        if orders[index].status == "pendingPayment" {
            orders[index].status = "paid"
            orders[index].paidAt = Self.iso.string(from: Date())
            try persist()
        }
        return orders[index]
    }

    @discardableResult
    func markFulfilled(id: String) throws -> GiftCardOrder {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let index = orders.firstIndex(where: { $0.id == id }) else { throw GiftCardError.orderNotFound }
        orders[index].status = "fulfilled"
        orders[index].fulfilledAt = Self.iso.string(from: Date())
        try persist()
        return orders[index]
    }

    func all() throws -> [GiftCardOrder] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return orders.sorted { $0.createdAt > $1.createdAt }
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try Data(contentsOf: fileURL)
            orders = try JSONDecoder().decode([GiftCardOrder].self, from: raw)
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
