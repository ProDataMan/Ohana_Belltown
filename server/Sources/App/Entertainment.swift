import Vapor

/// A single booking on any night's entertainment page — which night it
/// belongs to is derived from `date` (see `weekday(of:)`) rather than stored
/// separately, so it can never disagree with the date itself. Public-facing
/// (GET) so each /entertainment/<day> page can show who's playing; writes
/// require staff login, same trust model as every other admin-editable
/// content on the site.
struct EntertainmentBooking: Codable, Content {
    var id: String
    /// "yyyy-MM-dd" — the specific date this booking is for. Which of the
    /// 7 per-night pages it shows on is computed from this, not stored.
    var date: String
    /// "HH:mm" 24-hour, optional — each night has its own default start
    /// time shown as a placeholder client-side, but a performer/promoter
    /// can set a different one for their own date if it varies.
    var startTime: String?
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
        id: String = UUID().uuidString, date: String, startTime: String? = nil, performerName: String, bio: String? = nil,
        photos: [String] = [], videoURL: String? = nil, createdAt: String, updatedAt: String
    ) {
        self.id = id
        self.date = date
        self.startTime = startTime
        self.performerName = performerName
        self.bio = bio
        self.photos = photos
        self.videoURL = videoURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct EntertainmentBookingsList: Codable, Content {
    var bookings: [EntertainmentBooking]
}

struct EntertainmentBookingRequest: Content {
    var date: String
    var startTime: String? = nil
    var performerName: String
    var bio: String? = nil
    var photos: [String]? = nil
    var videoURL: String? = nil
}

enum EntertainmentError: Error, Equatable {
    case notFound
    case outsideBookingWindow
}

extension EntertainmentError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .notFound: return .notFound
        case .outsideBookingWindow: return .forbidden
        }
    }
    var reason: String {
        switch self {
        case .notFound: return "Booking not found."
        case .outsideBookingWindow: return "This account can only manage dates within the next \(EntertainmentStore.entertainmentProviderWindowDays) days."
        }
    }
}

/// entertainmentProvider accounts (outside DJs/promoters) may only touch
/// entries within a rolling booking window from today — enforced here so
/// every write route (create/update/delete) applies the same rule, rather
/// than each route reimplementing the date math.
func requireWithinEntertainmentProviderWindow(user: StaffUser, dateStr: String) throws {
    guard user.role == .entertainmentProvider else { return }
    guard EntertainmentStore.isWithinEntertainmentProviderWindow(dateStr) else {
        throw EntertainmentError.outsideBookingWindow
    }
}

final class EntertainmentStore: @unchecked Sendable {
    static let shared = EntertainmentStore()
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

    /// Lowercase English weekday name ("monday"..."sunday") for a "yyyy-MM-dd"
    /// date string, or nil if it doesn't parse — used to route a booking onto
    /// the right /entertainment/<day> page.
    static func weekday(of dateStr: String) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        guard let date = formatter.date(from: dateStr) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = calendar
        weekdayFormatter.dateFormat = "EEEE"
        weekdayFormatter.timeZone = calendar.timeZone
        return weekdayFormatter.string(from: date).lowercased()
    }

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/entertainment.json")
    private var bookings: [EntertainmentBooking] = []
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("entertainment.json")
        loaded = false
    }

    private func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    /// Sorted by date so both the admin list and each night's "coming up"
    /// view can just take the list as-is.
    func all() throws -> [EntertainmentBooking] {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return bookings.sorted { $0.date < $1.date }
    }

    /// Only today-or-later entries — what a night's page should actually
    /// show a guest, since a past date's booking isn't useful to surface.
    func upcoming(from today: String) throws -> [EntertainmentBooking] {
        try all().filter { $0.date >= today }
    }

    @discardableResult
    func create(_ body: EntertainmentBookingRequest) throws -> EntertainmentBooking {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        let timestamp = now()
        let booking = EntertainmentBooking(
            date: body.date, startTime: body.startTime, performerName: body.performerName, bio: body.bio,
            photos: body.photos ?? [], videoURL: body.videoURL,
            createdAt: timestamp, updatedAt: timestamp
        )
        bookings.append(booking)
        try persist()
        return booking
    }

    @discardableResult
    func update(id: String, _ body: EntertainmentBookingRequest) throws -> EntertainmentBooking {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = bookings.firstIndex(where: { $0.id == id }) else {
            throw EntertainmentError.notFound
        }
        bookings[idx].date = body.date
        bookings[idx].startTime = body.startTime
        bookings[idx].performerName = body.performerName
        bookings[idx].bio = body.bio
        if let photos = body.photos { bookings[idx].photos = photos }
        bookings[idx].videoURL = body.videoURL
        bookings[idx].updatedAt = now()
        try persist()
        return bookings[idx]
    }

    func delete(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        guard let idx = bookings.firstIndex(where: { $0.id == id }) else {
            throw EntertainmentError.notFound
        }
        bookings.remove(at: idx)
        try persist()
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            bookings = try JSONDecoder().decode(EntertainmentBookingsList.self, from: data).bookings
        } else {
            bookings = []
            try persist()
        }
        loaded = true
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(EntertainmentBookingsList(bookings: bookings))
        try data.write(to: fileURL, options: .atomic)
    }
}
