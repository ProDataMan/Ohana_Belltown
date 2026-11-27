import Vapor

/// A day-of-week deal ("Musubi Monday: $5.50 musubis"). Shown in the QR scan
/// popup on its day, on the home page's "Today at Ohana" strip, as a badge on
/// the dishes it covers, and in the week's list on /specials. Edited on
/// /daily-specials-admin.html.
struct DailySpecial: Codable, Content, Equatable {
    var id: String
    /// 1 = Sunday … 7 = Saturday.
    var weekday: Int
    /// "Musubi Monday".
    var title: String
    /// "$5.50 musubis" — the headline price, free text.
    var deal: String
    /// Optional fine print, e.g. "Dine-in only."
    var details: String?
    /// Exact menu item names the deal covers; they get the badge and the
    /// popup's photo and "See" button.
    var itemNames: [String]
    var active: Bool
}

struct DailySpecialsData: Codable, Content, Equatable {
    var specials: [DailySpecial]

    /// As given by the owner, Nov 2026.
    static let initial = DailySpecialsData(specials: [
        DailySpecial(
            id: "musubi-monday", weekday: 2, title: "Musubi Monday", deal: "$5.50 musubis",
            details: "Every musubi, all day Monday (the Musubi Sampler isn't included).",
            itemNames: ["Spam Musubi", "Chicken Katsu Musubi", "Portuguese Sausage Musubi", "Veggie Tempura Musubi", "Buffalo Katsu Musubi", "Red Hot Dog Musubi"],
            active: true
        ),
        DailySpecial(
            id: "taco-tuesday", weekday: 3, title: "Taco Tuesday", deal: "$5.50 each",
            details: "Fish and kalua pork tacos, all day Tuesday.",
            itemNames: ["Fish Tacos", "Kalua Pork Tacos"],
            active: true
        ),
    ])
}

/// GET /api/daily-specials: the active deals, today's first.
struct DailySpecialsPublic: Content {
    /// Today's deal(s), restaurant time.
    var today: [DailySpecial]
    /// Every active deal, Monday first, for the week's list on /specials.
    var week: [DailySpecial]
    var todayWeekday: Int
}

final class DailySpecialsStore: @unchecked Sendable {
    static let shared = DailySpecialsStore()

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/daily-specials.json")
    private var data = DailySpecialsData.initial
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("daily-specials.json")
        loaded = false
    }

    func get() -> DailySpecialsData {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return data
    }

    func publicView(now: Date = Date()) -> DailySpecialsPublic {
        let weekday = BusinessHoursCalculator.calendar.component(.weekday, from: now)
        let active = get().specials.filter(\.active)
        let order = BusinessHoursCalculator.displayOrder
        return DailySpecialsPublic(
            today: active.filter { $0.weekday == weekday },
            week: active.sorted { (order.firstIndex(of: $0.weekday) ?? 0, $0.title) < (order.firstIndex(of: $1.weekday) ?? 0, $1.title) },
            todayWeekday: weekday
        )
    }

    @discardableResult
    func save(_ incoming: DailySpecialsData) throws -> DailySpecialsData {
        var cleaned: [DailySpecial] = []
        for var special in incoming.specials {
            special.title = special.title.trimmingCharacters(in: .whitespacesAndNewlines)
            special.deal = special.deal.trimmingCharacters(in: .whitespacesAndNewlines)
            special.details = special.details?.trimmingCharacters(in: .whitespacesAndNewlines)
            if special.details?.isEmpty == true { special.details = nil }
            special.itemNames = special.itemNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard (1...7).contains(special.weekday) else {
                throw Abort(.badRequest, reason: "Each special needs a day of the week.")
            }
            guard !special.title.isEmpty, !special.deal.isEmpty else {
                throw Abort(.badRequest, reason: "Each special needs a name (like \"Musubi Monday\") and a deal (like \"$5.50 musubis\").")
            }
            if special.id.isEmpty { special.id = UUID().uuidString }
            cleaned.append(special)
        }
        lock.lock()
        defer { lock.unlock() }
        data = DailySpecialsData(specials: cleaned)
        loaded = true
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(data).write(to: fileURL, options: .atomic)
        return data
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        if let raw = FileManager.default.contents(atPath: fileURL.path),
           let stored = try? JSONDecoder().decode(DailySpecialsData.self, from: raw) {
            data = stored
        } else {
            data = .initial
        }
        loaded = true
    }
}
