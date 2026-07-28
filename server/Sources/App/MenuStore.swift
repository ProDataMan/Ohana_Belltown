import Vapor

enum MenuItemError: Error, Equatable {
    case itemNotFound
}

extension MenuItemError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .itemNotFound: return .notFound
        }
    }

    var reason: String {
        switch self {
        case .itemNotFound: return "Menu item not found."
        }
    }
}

struct MenuItemLocation: Content {
    var item: MenuItem
    var categoryName: String
    var section: String
}

struct SeedAdditionsResult: Content {
    var catalogAdded: Int
    var itemsUpdated: [String]
}

final class MenuStore: @unchecked Sendable {
    static let shared = MenuStore()

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/menu.json")
    private var seedURL = URL(fileURLWithPath: "Resources/seed-menu.json")
    private var menu = Menu(restaurant: "Ohana Belltown", lastUpdated: "", categories: [])
    private var loaded = false

    func configure(dataDirectory: String, resourcesDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: dataDirectory) {
            try? fileManager.createDirectory(atPath: dataDirectory, withIntermediateDirectories: true)
        }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("menu.json")
        seedURL = URL(fileURLWithPath: resourcesDirectory).appendingPathComponent("seed-menu.json")
        loaded = false
    }

    func get() throws -> Menu {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return menu
    }

    func save(_ newMenu: Menu) throws -> Menu {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        var updated = newMenu
        updated.lastUpdated = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        menu = updated
        try persist()
        return menu
    }

    func findItem(id: String) throws -> MenuItemLocation {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        for category in menu.categories {
            if let item = category.items.first(where: { $0.id == id }) {
                return MenuItemLocation(item: item, categoryName: category.name, section: category.section)
            }
        }
        throw MenuItemError.itemNotFound
    }

    @discardableResult
    func updateItem(id: String, _ apply: (inout MenuItem) -> Void) throws -> MenuItem {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        for catIdx in menu.categories.indices {
            if let itemIdx = menu.categories[catIdx].items.firstIndex(where: { $0.id == id }) {
                apply(&menu.categories[catIdx].items[itemIdx])
                menu.lastUpdated = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
                try persist()
                return menu.categories[catIdx].items[itemIdx]
            }
        }
        throw MenuItemError.itemNotFound
    }

    func additionsCatalog() throws -> [AdditionCatalogItem] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return menu.additionsCatalog
    }

    @discardableResult
    func saveAdditionsCatalog(_ items: [AdditionCatalogItem]) throws -> [AdditionCatalogItem] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        menu.additionsCatalog = items
        try persist()
        return items
    }

    // Curated from a full sweep of every item's description on 2026-07-28,
    // looking for real upcharge text ("Add Katsu +$6", "YOSH size: $53.20",
    // etc). One consistent price per addition across every item that offers
    // it, except Yosh Size, which is priced per item below since it
    // genuinely varies by dish.
    private static let commonAdditionsCatalog: [(name: String, priceDelta: Double)] = [
        ("Add Bacon", 5.50),
        ("Add Fried Egg", 3.50),
        ("Add Spam", 6),
        ("Add Salmon", 6),
        ("Add Shrimp", 5),
        ("Add Katsu", 6),
        ("Add Chicken", 6),
        ("Sub Fried Rice", 6),
        ("Sub Kalua Pork", 0),
        ("Sub Noodles", 3),
        ("Extra Tofu", 3),
        ("Add Strawberry", 1.50),
        ("Add Mango", 1.50),
        ("Add Banana", 1.50),
        ("Yosh Size", 25.20),
    ]

    private static let commonItemModifiers: [(itemName: String, additions: [(name: String, priceOverride: Double?)])] = [
        ("Spicy Fried Rice", [("Add Fried Egg", nil), ("Add Spam", nil), ("Add Bacon", nil)]),
        ("Veggie Spring Rolls", [("Add Salmon", 5), ("Add Shrimp", nil)]),
        ("Loco Moco", [("Sub Fried Rice", nil), ("Sub Kalua Pork", nil), ("Add Bacon", nil), ("Add Katsu", nil), ("Add Spam", nil), ("Yosh Size", 25.20)]),
        ("Kalua Pork", [("Yosh Size", 24.30)]),
        ("Curry Rice", [("Add Katsu", nil), ("Yosh Size", 23.40)]),
        ("Adobo", [("Yosh Size", 25.20)]),
        ("Yakisoba", [("Extra Tofu", nil), ("Add Chicken", 4), ("Yosh Size", 20.70)]),
        ("Chicken Katsu", [("Yosh Size", 25.20)]),
        ("Ginger Chicken Broccoli", [("Sub Noodles", nil), ("Yosh Size", 25.20)]),
        ("Big Kahuna Fish & Chips", [("Yosh Size", 26.10)]),
        ("Ohana Cheese Burger", [("Add Bacon", nil)]),
        ("Island Style Baby Back Ribs", [("Yosh Size", 28.80)]),
        ("Ohana Salad", [("Add Chicken", nil), ("Add Salmon", nil), ("Yosh Size", 11.70)]),
        ("Chicken Teriyaki / Spicy Chicken Teriyaki", [("Yosh Size", 25.20)]),
        ("Salmon Teriyaki", [("Yosh Size", 27.90)]),
        ("Beef Teriyaki / Spicy Beef Teriyaki", [("Yosh Size", 27.90)]),
        ("Virgin Pina Colada", [("Add Strawberry", nil), ("Add Mango", nil), ("Add Banana", nil)]),
    ]

    /// One-click, idempotent: seeds the shared catalog and applies matching
    /// modifiers to whichever of the known items are still missing them.
    /// Safe to run repeatedly — already-present catalog entries/modifiers
    /// (matched case-insensitively by name) are left untouched.
    @discardableResult
    func seedCommonAdditions() throws -> SeedAdditionsResult {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()

        let existingCatalogNames = Set(menu.additionsCatalog.map { $0.name.lowercased() })
        var catalogAdded = 0
        for entry in Self.commonAdditionsCatalog where !existingCatalogNames.contains(entry.name.lowercased()) {
            menu.additionsCatalog.append(AdditionCatalogItem(name: entry.name, priceDelta: entry.priceDelta))
            catalogAdded += 1
        }
        let catalogPrices = Dictionary(uniqueKeysWithValues: Self.commonAdditionsCatalog.map { ($0.name, $0.priceDelta) })

        var itemsUpdated: [String] = []
        for (itemName, additions) in Self.commonItemModifiers {
            let normalizedName = itemName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            outer: for catIdx in menu.categories.indices {
                for itemIdx in menu.categories[catIdx].items.indices {
                    guard menu.categories[catIdx].items[itemIdx].name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName else { continue }

                    let existingModNames = Set(menu.categories[catIdx].items[itemIdx].modifiers.map { $0.name.lowercased() })
                    var added = 0
                    for addition in additions where !existingModNames.contains(addition.name.lowercased()) {
                        let price = addition.priceOverride ?? catalogPrices[addition.name] ?? 0
                        menu.categories[catIdx].items[itemIdx].modifiers.append(MenuItemModifier(name: addition.name, priceDelta: price))
                        added += 1
                    }
                    if added > 0 {
                        itemsUpdated.append(itemName)
                    }
                    break outer
                }
            }
        }

        if catalogAdded > 0 || !itemsUpdated.isEmpty {
            menu.lastUpdated = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
            try persist()
        }

        return SeedAdditionsResult(catalogAdded: catalogAdded, itemsUpdated: itemsUpdated)
    }

    func deleteItem(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        for catIdx in menu.categories.indices {
            if let itemIdx = menu.categories[catIdx].items.firstIndex(where: { $0.id == id }) {
                menu.categories[catIdx].items.remove(at: itemIdx)
                menu.lastUpdated = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
                try persist()
                return
            }
        }
        throw MenuItemError.itemNotFound
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            menu = try JSONDecoder().decode(Menu.self, from: data)
            // Re-persist immediately so any fields defaulted during decode
            // (e.g. a stable id generated for a pre-existing item) become
            // durable rather than regenerating on every restart.
            try persist()
        } else if fileManager.fileExists(atPath: seedURL.path) {
            let data = try Data(contentsOf: seedURL)
            menu = try JSONDecoder().decode(Menu.self, from: data)
            try persist()
        } else {
            try persist()
        }
        loaded = true
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(menu)
        try data.write(to: fileURL, options: .atomic)
    }
}
