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
