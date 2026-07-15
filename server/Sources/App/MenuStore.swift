import Vapor

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
