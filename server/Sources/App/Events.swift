import Vapor

struct EventItem: Codable, Content {
    var id: String
    var title: String
    var schedule: String
    var description: String?
    var active: Bool

    init(id: String = UUID().uuidString, title: String, schedule: String, description: String? = nil, active: Bool = true) {
        self.id = id
        self.title = title
        self.schedule = schedule
        self.description = description
        self.active = active
    }
}

struct EventsList: Codable, Content {
    var events: [EventItem]
}

final class EventsStore: @unchecked Sendable {
    static let shared = EventsStore()

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/events.json")
    private var events: [EventItem] = []
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("events.json")
    }

    func get() throws -> EventsList {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return EventsList(events: events)
    }

    func save(_ list: EventsList) throws -> EventsList {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        events = list.events
        try persist()
        return EventsList(events: events)
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            events = try JSONDecoder().decode(EventsList.self, from: data).events
        } else {
            events = [
                EventItem(title: "Karaoke Night", schedule: "Weekly — ask staff for the current night"),
                EventItem(title: "Live Hawaiian & Reggae Music", schedule: "Rotating schedule — ask staff for upcoming dates"),
            ]
            try persist()
        }
        loaded = true
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(EventsList(events: events))
        try data.write(to: fileURL, options: .atomic)
    }
}
