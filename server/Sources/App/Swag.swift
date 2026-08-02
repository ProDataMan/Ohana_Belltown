import Foundation
import Vapor

/// A physical item for sale (t-shirt, hat, bandana, etc.) — distinct from
/// MenuStore's food/drink items because two food-specific rules don't apply
/// to merch: prices there are hidden until a table's QR is scanned, and
/// sections feed PrepTimeEstimator/DiningTimeEstimator for kitchen timing.
/// Swag always shows its price and never gets a prep-time estimate.
struct SwagProduct: Codable, Content, Equatable {
    var id: String
    var name: String
    var price: Double
    var images: [String]
    var available: Bool

    init(
        id: String = UUID().uuidString, name: String, price: Double,
        images: [String] = [], available: Bool = true
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.images = images
        self.available = available
    }
}

enum SwagError: Error {
    case productNotFound
    case orderNotFound
    case emptyCart
    case checkoutNotConfigured
}

extension SwagError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .productNotFound, .orderNotFound: return .notFound
        case .emptyCart: return .badRequest
        case .checkoutNotConfigured: return .serviceUnavailable
        }
    }

    var reason: String {
        switch self {
        case .productNotFound: return "Swag product not found."
        case .orderNotFound: return "Swag order not found."
        case .emptyCart: return "Your cart is empty."
        case .checkoutNotConfigured: return "Online swag checkout isn't configured yet."
        }
    }
}

final class SwagStore: @unchecked Sendable {
    static let shared = SwagStore()

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/swag-products.json")
    private var products: [SwagProduct] = []
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("swag-products.json")
        loaded = false
    }

    func list() throws -> [SwagProduct] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return products
    }

    func find(id: String) throws -> SwagProduct {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let product = products.first(where: { $0.id == id }) else {
            throw SwagError.productNotFound
        }
        return product
    }

    @discardableResult
    func save(_ items: [SwagProduct]) throws -> [SwagProduct] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        products = items
        try persist()
        return products
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let raw = try Data(contentsOf: fileURL)
            products = try JSONDecoder().decode([SwagProduct].self, from: raw)
        } else {
            products = []
            try persist()
        }
        loaded = true
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(products)
        try encoded.write(to: fileURL, options: .atomic)
    }
}
