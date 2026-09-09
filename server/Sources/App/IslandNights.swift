import Vapor

/// A single Wednesday's Island Nights performer — the promoter (see
/// island-nights-admin.html) lines these up a few weeks ahead. Public-facing
/// (GET) so /entertainment can show who's playing next; writes require staff
/// login, same trust model as every other admin-editable content on the site.
struct IslandNightPerformer: Codable, Content {
    var id: String
    /// "yyyy-MM-dd" — the specific Wednesday this performer is booked for.
    var date: String
    var performerName: String
    var bio: String?
    var photos: [String]
    /// A single video clip (with sound) of the performer, if provided —
    /// stored the same way as photos (/uploads/<filename>), just via the
    /// separate /api/upload-video route since videos need a much larger
    /// size ceiling than the image upload path allows.
    var videoURL: String?
    var createdAt: String
    var updatedAt: String

    init(
        id: String = UUID().uuidString, date: String, performerName: String, bio: String? = nil,
        photos: [String] = [], videoURL: String? = nil, createdAt: String, updatedAt: String
    ) {
        self.id = id
        self.date = date
        self.performerName = performerName
        self.bio = bio
        self.photos = photos
        self.videoURL = videoURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct IslandNightsList: Codable, Content {
    var performers: [IslandNightPerformer]
}

struct IslandNightPerformerRequest: Content {
    var date: String
    var performerName: String
    var bio: String?
    var photos: [String]?
    var videoURL: String?
}

enum IslandNightsError: Error, Equatable {
    case notFound
    case outsideBookingWindow
}

extension IslandNightsError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .notFound: return .notFound
        case .outsideBookingWindow: return .forbidden
        }
    }
    var reason: String {
        switch self {
        case .notFound: return "Performer entry not found."
        case .outsideBookingWindow: return "This account can only manage dates within the next \(IslandNightsStore.entertainmentProviderWindowDays) days."
        }
    }
}

/// entertainmentProvider accounts (outside DJs/promoters) may only touch
/// entries within a rolling booking window from today — enforced here so
/// every write route (create/update/delete) applies the same rule, rather
/// than each route reimplementing the date math.
func requireWithinEntertainmentProviderWindow(user: StaffUser, dateStr: String) throws {
    guard user.role == .entertainmentProvider else { return }
    guard IslandNightsStore.isWithinEntertainmentProviderWindow(dateStr) else {
        throw IslandNightsError.outsideBookingWindow
    }
}

final class IslandNightsStore: @unchecked Sendable {
    static let shared = IslandNightsStore()
    static let entertainmentProviderWindowDays = 60

    static func isWithinEntertainmentProviderWindow(_ dateStr: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        guard let date = formatter.date(from: dateStr) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let today = calendar.startOfDay(for: Date())
        let targetDay = calendar.startOfDay(for: date)
        guard let days = calendar.dateComponents([.day], from: today, to: targetDay).day else { return false }
        return days >= 0 && days <= entertainmentProviderWindowDays
    }

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/island-nights.json")
    private var performers: [IslandNightPerformer] = []
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("island-nights.json")
        loaded = false
    }

    private func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    /// Sorted by date so both the admin list and the public "coming up"
    /// view can just take the list as-is.
    func all() throws -> [IslandNightPerformer] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return performers.sorted { $0.date < $1.date }
    }

    /// Only today-or-later entries — what /entertainment should actually show
    /// a guest, since a past Wednesday's performer isn't useful to surface.
    func upcoming(from today: String) throws -> [IslandNightPerformer] {
        try all().filter { $0.date >= today }
    }

    @discardableResult
    func create(_ body: IslandNightPerformerRequest) throws -> IslandNightPerformer {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let timestamp = now()
        let performer = IslandNightPerformer(
            date: body.date, performerName: body.performerName, bio: body.bio,
            photos: body.photos ?? [], videoURL: body.videoURL,
            createdAt: timestamp, updatedAt: timestamp
        )
        performers.append(performer)
        try persist()
        return performer
    }

    @discardableResult
    func update(id: String, _ body: IslandNightPerformerRequest) throws -> IslandNightPerformer {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = performers.firstIndex(where: { $0.id == id }) else {
            throw IslandNightsError.notFound
        }
        performers[idx].date = body.date
        performers[idx].performerName = body.performerName
        performers[idx].bio = body.bio
        if let photos = body.photos { performers[idx].photos = photos }
        performers[idx].videoURL = body.videoURL
        performers[idx].updatedAt = now()
        try persist()
        return performers[idx]
    }

    func delete(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = performers.firstIndex(where: { $0.id == id }) else {
            throw IslandNightsError.notFound
        }
        performers.remove(at: idx)
        try persist()
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            performers = try JSONDecoder().decode(IslandNightsList.self, from: data).performers
        } else {
            performers = []
            try persist()
        }
        loaded = true
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(IslandNightsList(performers: performers))
        try data.write(to: fileURL, options: .atomic)
    }
}
