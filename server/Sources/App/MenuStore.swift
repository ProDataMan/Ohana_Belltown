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
        // Editors don't send this flag; keep it so a save never re-seeds
        // pitches staff have since changed or removed.
        updated.scanPitchesSeeded = updated.scanPitchesSeeded || menu.scanPitchesSeeded
        updated.appliedFixes = Array(Set(updated.appliedFixes).union(menu.appliedFixes)).sorted()
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
            Self.seedScanPitches(&menu)
            Self.applyOneTimeFixes(&menu)
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

    /// The dishes and drinks to push in the QR scan popup (chosen by the
    /// owner as the most profitable), keyed by menu section and exact item
    /// name. Applied once; after that, edit them per item in the item editor.
    static let initialScanPitches: [(section: String, name: String, pitch: String)] = [
        ("drinks", "Blue Hawaiian", "Aloha in a glass! Rum, pineapple and blue curaçao, as blue as the water off Waikīkī. It's the one everyone snaps a photo of before the first sip, and that sweet tropical finish puts you right on island time."),
        ("drinks", "Lychee Martini", "Shaka, this one's smooth! Sweet, floral lychee shaken ice-cold with vodka, light as a trade-wind breeze. Guests who try one usually order round two."),
        ("happy_hour", "Blue Hawaiian", "Happy Hour aloha in a glass! Rum, pineapple and blue curaçao, as blue as the water off Waikīkī, at our Happy Hour price. Everyone snaps a photo before the first sip."),
        ("happy_hour", "Lychee Martini", "Shaka, this one's smooth! Sweet, floral lychee shaken ice-cold with vodka, light as a trade-wind breeze, and even better at Happy Hour. One usually turns into two."),
        ("menu", "Chicken Katsu", "Broke da mouth crunchy! Tender chicken in a golden panko crust with our homemade katsu sauce. It's the plate-lunch classic our regulars order again and again, because it's crispy every single time."),
        ("menu", "Chicken Teriyaki", "Ono to the last bite! Chicken thighs marinated in our homemade teriyaki and caramelized on the grill: sweet, savory and juicy, just like a Honolulu plate lunch. A favorite for good reason."),
        ("menu", "Kalua Pork", "A lūʻau on a plate! Pork slow-roasted for hours until it's smoky, tender and falls apart, with cabbage and rice. It's the taste of a backyard Hawaiian party, and the dish people come back for."),
    ]

    /// Data changes the owner asked for that ship with a deploy instead of
    /// needing someone to sign in and make them, each applied once (tracked
    /// in `menu.appliedFixes`) so later edits in the editors aren't undone.
    static let oneTimeFixes: [(id: String, apply: (inout Menu) -> Void)] = [
        // The Lychee Martini's old photo was a plain martini with an olive.
        // Replaced (on Drinks and Happy Hour) with a free Pexels photo of a
        // pale martini on a plain background: "A Person Holding a Clear
        // Martini Glass" by cottonbro studio, pexels.com/photo/8956533
        // (Pexels License: free for commercial use, no attribution needed).
        ("lychee-martini-photo-2026-11", { menu in
            for c in menu.categories.indices where ["drinks", "happy_hour"].contains(menu.categories[c].section) {
                for i in menu.categories[c].items.indices where menu.categories[c].items[i].name == "Lychee Martini" {
                    menu.categories[c].items[i].images = ["/images/lychee-martini.jpg"]
                }
            }
        }),
    ]

    static func applyOneTimeFixes(_ menu: inout Menu) {
        for fix in oneTimeFixes where !menu.appliedFixes.contains(fix.id) {
            fix.apply(&menu)
            menu.appliedFixes.append(fix.id)
        }
    }

    /// Applies `initialScanPitches` the first time a menu without
    /// `scanPitchesSeeded` loads; an item that already has a pitch keeps it.
    static func seedScanPitches(_ menu: inout Menu) {
        guard !menu.scanPitchesSeeded else { return }
        for seed in initialScanPitches {
            for c in menu.categories.indices where menu.categories[c].section == seed.section {
                for i in menu.categories[c].items.indices
                where menu.categories[c].items[i].name == seed.name && menu.categories[c].items[i].scanPitch == nil {
                    menu.categories[c].items[i].scanPitch = seed.pitch
                }
            }
        }
        menu.scanPitchesSeeded = true
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(menu)
        try data.write(to: fileURL, options: .atomic)
    }
}
