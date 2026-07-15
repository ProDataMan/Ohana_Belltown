import Vapor

final class MenuStore: @unchecked Sendable {
    static let shared = MenuStore()

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/menu.json")
    private var menu = MenuStore.seedMenu()
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: dataDirectory) {
            try? fileManager.createDirectory(atPath: dataDirectory, withIntermediateDirectories: true)
        }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("menu.json")
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

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            menu = try JSONDecoder().decode(Menu.self, from: data)
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

    private static func seedMenu() -> Menu {
        Menu(
            restaurant: "Ohana Belltown",
            lastUpdated: "2026-07-12",
            categories: [
                MenuCategory(name: "Appetizers", items: [
                    MenuItem(name: "Edamame", description: "Steamed soybeans with sea salt.", price: 6.5),
                    MenuItem(name: "Spicy Tuna Tartare", description: "Tuna, avocado, cucumber, chili crisp.", price: 16.0),
                ]),
                MenuCategory(name: "Sushi Rolls", items: [
                    MenuItem(name: "California Roll", description: "Crab, cucumber, avocado.", price: 12.0),
                    MenuItem(name: "Spicy Tuna Roll", description: "Tuna, cucumber, spicy sauce.", price: 14.5),
                ]),
                MenuCategory(name: "Entrees", items: [
                    MenuItem(name: "Teriyaki Chicken", description: "Grilled chicken with house sauce and rice.", price: 18.0),
                    MenuItem(name: "Salmon Bowl", description: "Seared salmon, rice, cucumber, scallions.", price: 20.0),
                ]),
            ]
        )
    }
}
