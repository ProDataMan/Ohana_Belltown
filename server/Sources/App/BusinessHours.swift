import Vapor

/// One weekday's regular hours. Times are "HH:mm", 24-hour, restaurant time
/// (America/Los_Angeles). A close at or before the open time means after
/// midnight (open "16:30", close "01:00" runs into the next morning).
struct DayHours: Codable, Content, Equatable {
    /// 1 = Sunday … 7 = Saturday (Calendar's numbering).
    var weekday: Int
    var closed: Bool
    var open: String
    var close: String
    /// When the kitchen stops taking food orders; nil if it's open until close.
    var kitchenClose: String?
}

/// A one-off change for a specific date (a holiday, a private event).
struct HoursException: Codable, Content, Equatable {
    /// "yyyy-MM-dd", restaurant time.
    var date: String
    var closed: Bool
    var open: String?
    var close: String?
    var kitchenClose: String?
    /// e.g. "Thanksgiving" — shown to guests.
    var note: String?
}

/// What staff edit on /hours-admin.html, and the only place the site's hours
/// come from: the footer, the live "Open now" line, the home page banner,
/// the Contact page, the FAQ, and the hours Google reads all render this.
struct BusinessHoursData: Codable, Content, Equatable {
    /// e.g. "Fall hours"; shown above the week.
    var seasonLabel: String?
    var week: [DayHours]
    var exceptions: [HoursException]
    /// Shown under the hours, e.g. "Holiday hours may vary — call to confirm."
    var holidayNote: String?

    /// Fall 2026, as given by the owner: Mon–Thu 4:30pm–1am, Fri–Sun
    /// 1pm–1am; kitchen until 10pm Sun–Thu and 11pm Fri–Sat.
    static let initial = BusinessHoursData(
        seasonLabel: "Fall hours",
        week: [
            DayHours(weekday: 1, closed: false, open: "13:00", close: "01:00", kitchenClose: "22:00"),
            DayHours(weekday: 2, closed: false, open: "16:30", close: "01:00", kitchenClose: "22:00"),
            DayHours(weekday: 3, closed: false, open: "16:30", close: "01:00", kitchenClose: "22:00"),
            DayHours(weekday: 4, closed: false, open: "16:30", close: "01:00", kitchenClose: "22:00"),
            DayHours(weekday: 5, closed: false, open: "16:30", close: "01:00", kitchenClose: "22:00"),
            DayHours(weekday: 6, closed: false, open: "13:00", close: "01:00", kitchenClose: "23:00"),
            DayHours(weekday: 7, closed: false, open: "13:00", close: "01:00", kitchenClose: "23:00"),
        ],
        exceptions: [],
        holidayNote: "Holiday hours may vary, so give us a call to confirm."
    )
}

/// The hours as guests see them, worked out for right now. Returned by
/// GET /api/hours and rendered by the hours code in nav.js.
struct BusinessHoursPublic: Content {
    var seasonLabel: String?
    /// Days with the same hours grouped, Monday first: "Mon–Thu" / "4:30pm–1am".
    var week: [HoursLine]
    /// e.g. "Kitchen until 10pm Sun–Thu, 11pm Fri–Sat".
    var kitchenSummary: String?
    /// When Happy Hour can actually be had, given the opening hours:
    /// "Mon–Thu 4:30–6pm · Fri 3–6pm".
    var happyHourSummary: String?
    var holidayNote: String?
    /// Exceptions in the next 14 days.
    var upcoming: [HoursLine]
    var now: HoursStatus
    /// Items marked "Today's special" in the menu editor.
    var todaySpecials: [String]
    /// schema.org OpeningHoursSpecification objects for the home page's
    /// structured data, so search engines and assistants know the hours.
    var openingHoursSpecification: [OpeningHoursSpec]
    /// Today's day-of-week deal(s) (DailySpecialsStore), filled in by the
    /// /api/hours route.
    var todayDeals: [DailySpecial] = []
}

struct HoursLine: Content, Equatable {
    var label: String
    var hours: String
}

struct HoursStatus: Content, Equatable {
    var open: Bool
    /// "Open now · closes 1am" / "Closed · opens 4:30pm" / "Closed · opens 1pm Friday".
    var label: String
    /// "Open today 4:30pm–1am" / "Closed today" / "Open today 1pm–1am (Thanksgiving)".
    var today: String
    var kitchenOpen: Bool
    /// "Kitchen open until 10pm" / "Kitchen closed · bar open until 1am"; nil when closed.
    var kitchenLabel: String?
    var happyHourNow: Bool
    /// "Happy Hour until 6pm" while it's on.
    var happyHourLabel: String?
}

struct OpeningHoursSpec: Content, Equatable {
    var type = "OpeningHoursSpecification"
    var dayOfWeek: [String]
    var opens: String
    var closes: String

    enum CodingKeys: String, CodingKey {
        case type = "@type", dayOfWeek, opens, closes
    }
}

enum BusinessHoursCalculator {
    static let dayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let shortNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    /// Monday first, the way people read a week.
    static let displayOrder = [2, 3, 4, 5, 6, 7, 1]

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = HappyHourSchedule.pacific
        return calendar
    }

    static func isValidTime(_ value: String) -> Bool {
        minutes(value) != nil
    }

    /// "16:30" → 990.
    static func minutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    /// "16:30" → "4:30pm", "13:00" → "1pm", "00:00" → "midnight".
    static func display(_ value: String) -> String {
        guard let total = minutes(value) else { return value }
        if total == 0 { return "midnight" }
        if total == 12 * 60 { return "noon" }
        let h = total / 60, m = total % 60
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return "\(hour12)\(m == 0 ? "" : String(format: ":%02d", m))\(h < 12 ? "am" : "pm")"
    }

    /// The hours that apply on `day` (a date's start of day): its exception
    /// if there is one, else the weekly hours. Nil when closed.
    static func hours(on day: Date, data: BusinessHoursData) -> (open: String, close: String, kitchenClose: String?, note: String?)? {
        let key = dayKey(day)
        if let exception = data.exceptions.first(where: { $0.date == key }) {
            guard !exception.closed, let open = exception.open, let close = exception.close else { return nil }
            return (open, close, exception.kitchenClose, exception.note)
        }
        let weekday = calendar.component(.weekday, from: day)
        guard let regular = data.week.first(where: { $0.weekday == weekday }), !regular.closed else { return nil }
        return (regular.open, regular.close, regular.kitchenClose, nil)
    }

    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// `time` on `day`, rolled to the next day when it's at or before `open`
    /// (a close after midnight).
    static func moment(_ time: String, on day: Date, after open: String? = nil) -> Date? {
        guard let total = minutes(time) else { return nil }
        var date = calendar.date(byAdding: .minute, value: total, to: day) ?? day
        if let open, let openMinutes = minutes(open), total <= openMinutes {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }

    struct Span {
        var day: Date
        var open: Date
        var close: Date
        var kitchenClose: Date?
        var note: String?
    }

    static func span(on day: Date, data: BusinessHoursData) -> Span? {
        guard let h = hours(on: day, data: data),
              let open = moment(h.open, on: day),
              let close = moment(h.close, on: day, after: h.open) else { return nil }
        return Span(day: day, open: open, close: close, kitchenClose: h.kitchenClose.flatMap { moment($0, on: day, after: h.open) }, note: h.note)
    }

    /// Happy Hour on `span`'s day: HappyHourSchedule's weekday window cut to
    /// the hours the restaurant is actually open.
    static func happyHour(in span: Span) -> (start: Date, end: Date)? {
        let weekday = calendar.component(.weekday, from: span.day)
        guard HappyHourSchedule.weekdays.contains(weekday),
              let start = calendar.date(byAdding: .hour, value: HappyHourSchedule.startHour, to: span.day),
              let end = calendar.date(byAdding: .hour, value: HappyHourSchedule.endHour, to: span.day) else { return nil }
        let from = max(start, span.open), to = min(end, span.close)
        return from < to ? (from, to) : nil
    }

    static func clock(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return display(String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0))
    }

    static func build(data: BusinessHoursData, now: Date = Date(), specials: [String] = []) -> BusinessHoursPublic {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        // Right now: still inside last night's hours (after midnight), or today's.
        let current = [span(on: yesterday, data: data), span(on: today, data: data)]
            .compactMap { $0 }
            .first { now >= $0.open && now < $0.close }
        let todaySpan = span(on: today, data: data)

        var status = HoursStatus(open: false, label: "", today: "", kitchenOpen: false, kitchenLabel: nil, happyHourNow: false, happyHourLabel: nil)
        if let todaySpan, let h = hours(on: today, data: data) {
            status.today = "Open today \(display(h.open))–\(display(h.close))" + (h.note.map { " (\($0))" } ?? "")
        } else {
            let note = data.exceptions.first { $0.date == dayKey(today) }?.note
            status.today = "Closed today" + (note.map { " (\($0))" } ?? "")
        }
        if let current {
            status.open = true
            status.label = "Open now · closes \(clock(current.close))"
            if let kitchen = current.kitchenClose, now >= kitchen {
                status.kitchenLabel = "Kitchen closed · bar open until \(clock(current.close))"
            } else {
                status.kitchenOpen = true
                status.kitchenLabel = "Kitchen open until \(clock(current.kitchenClose ?? current.close))"
            }
            if let hh = happyHour(in: current), now >= hh.start, now < hh.end {
                status.happyHourNow = true
                status.happyHourLabel = "Happy Hour until \(clock(hh.end))"
            }
        } else {
            // The next opening in the coming week.
            for offset in 0...7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      let next = span(on: day, data: data), next.open > now else { continue }
                let when = offset == 0 ? "" : offset == 1 ? " tomorrow" : " \(dayNames[calendar.component(.weekday, from: day)])"
                status.label = "Closed · opens \(clock(next.open))\(when)"
                break
            }
            if status.label.isEmpty { status.label = "Closed" }
        }
        _ = todaySpan

        // The week, consecutive days with the same hours grouped.
        func rangeLabel(_ days: [Int]) -> String {
            days.count == 1 ? shortNames[days[0]] : "\(shortNames[days.first!])–\(shortNames[days.last!])"
        }
        var week: [HoursLine] = []
        var group: [Int] = []
        var groupText = ""
        for weekday in displayOrder {
            let day = data.week.first { $0.weekday == weekday }
            let text = (day == nil || day!.closed) ? "Closed" : "\(display(day!.open))–\(display(day!.close))"
            if !group.isEmpty && text == groupText {
                group.append(weekday)
            } else {
                if !group.isEmpty { week.append(HoursLine(label: rangeLabel(group), hours: groupText)) }
                group = [weekday]
                groupText = text
            }
        }
        if !group.isEmpty { week.append(HoursLine(label: rangeLabel(group), hours: groupText)) }

        // "Kitchen until 10pm Sun–Thu, 11pm Fri–Sat" — grouped by close time,
        // Sunday first so Sun–Thu reads as one run.
        var kitchenGroups: [(time: String, days: [Int])] = []
        for weekday in [1, 2, 3, 4, 5, 6, 7] {
            guard let day = data.week.first(where: { $0.weekday == weekday }), !day.closed, let kitchen = day.kitchenClose else { continue }
            if let last = kitchenGroups.last, last.time == kitchen, last.days.last == weekday - 1 {
                kitchenGroups[kitchenGroups.count - 1].days.append(weekday)
            } else {
                kitchenGroups.append((kitchen, [weekday]))
            }
        }
        let kitchenSummary = kitchenGroups.isEmpty ? nil
            : "Kitchen until " + kitchenGroups.map { "\(display($0.time)) \(rangeLabel($0.days))" }.joined(separator: ", ")

        // Happy Hour as it really works out against the hours, for the week
        // starting today's Monday.
        let weekStart = calendar.date(byAdding: .day, value: -((calendar.component(.weekday, from: today) + 5) % 7), to: today) ?? today
        var hhGroups: [(text: String, days: [Int])] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            // Weekly hours only; a holiday doesn't redefine Happy Hour's usual times.
            var regular = data
            regular.exceptions = []
            guard let s = span(on: day, data: regular), let hh = happyHour(in: s) else { continue }
            let text = "\(clock(hh.start).replacingOccurrences(of: "pm", with: ""))–\(clock(hh.end))"
            if let last = hhGroups.last, last.text == text, last.days.last == weekday - 1 {
                hhGroups[hhGroups.count - 1].days.append(weekday)
            } else {
                hhGroups.append((text, [weekday]))
            }
        }
        let happyHourSummary = hhGroups.isEmpty ? nil : hhGroups.map { "\(rangeLabel($0.days)) \($0.text)" }.joined(separator: " · ")

        // Exceptions in the next two weeks.
        let horizon = dayKey(calendar.date(byAdding: .day, value: 14, to: today) ?? today)
        let upcoming = data.exceptions
            .filter { $0.date >= dayKey(today) && $0.date <= horizon }
            .sorted { $0.date < $1.date }
            .map { e -> HoursLine in
                let date = calendar.date(from: DateComponents(
                    year: Int(e.date.prefix(4)), month: Int(e.date.dropFirst(5).prefix(2)), day: Int(e.date.suffix(2))
                )) ?? today
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = "EEE MMM d"
                let label = formatter.string(from: date) + (e.note.map { " (\($0))" } ?? "")
                let hours = e.closed ? "Closed" : "\(display(e.open ?? ""))–\(display(e.close ?? ""))"
                return HoursLine(label: label, hours: hours)
            }

        let schemaDays = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        var specs: [OpeningHoursSpec] = []
        for day in data.week.sorted(by: { displayOrder.firstIndex(of: $0.weekday)! < displayOrder.firstIndex(of: $1.weekday)! }) where !day.closed {
            if let i = specs.firstIndex(where: { $0.opens == day.open && $0.closes == day.close }) {
                specs[i].dayOfWeek.append(schemaDays[day.weekday])
            } else {
                specs.append(OpeningHoursSpec(dayOfWeek: [schemaDays[day.weekday]], opens: day.open, closes: day.close))
            }
        }

        return BusinessHoursPublic(
            seasonLabel: data.seasonLabel, week: week, kitchenSummary: kitchenSummary,
            happyHourSummary: happyHourSummary, holidayNote: data.holidayNote, upcoming: upcoming,
            now: status, todaySpecials: specials, openingHoursSpecification: specs
        )
    }
}

final class BusinessHoursStore: @unchecked Sendable {
    static let shared = BusinessHoursStore()

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/hours.json")
    private var data = BusinessHoursData.initial
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("hours.json")
        loaded = false
    }

    func get() -> BusinessHoursData {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return data
    }

    /// Validates and saves. Past exceptions are dropped on save.
    @discardableResult
    func save(_ incoming: BusinessHoursData) throws -> BusinessHoursData {
        guard Set(incoming.week.map(\.weekday)) == Set(1...7), incoming.week.count == 7 else {
            throw Abort(.badRequest, reason: "Hours need exactly one entry for each day of the week.")
        }
        for day in incoming.week where !day.closed {
            guard BusinessHoursCalculator.isValidTime(day.open), BusinessHoursCalculator.isValidTime(day.close),
                  day.kitchenClose.map(BusinessHoursCalculator.isValidTime) ?? true else {
                throw Abort(.badRequest, reason: "\(BusinessHoursCalculator.dayNames[day.weekday]): times must be like 16:30.")
            }
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        for e in incoming.exceptions {
            guard dateFormatter.date(from: e.date) != nil else {
                throw Abort(.badRequest, reason: "Exception dates must be like 2026-11-26.")
            }
            if !e.closed {
                guard let open = e.open, let close = e.close,
                      BusinessHoursCalculator.isValidTime(open), BusinessHoursCalculator.isValidTime(close) else {
                    throw Abort(.badRequest, reason: "\(e.date): give opening and closing times, or mark it closed.")
                }
            }
        }
        var cleaned = incoming
        cleaned.seasonLabel = incoming.seasonLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        cleaned.holidayNote = incoming.holidayNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let today = BusinessHoursCalculator.dayKey(Date())
        cleaned.exceptions = incoming.exceptions.filter { $0.date >= today }.sorted { $0.date < $1.date }
        lock.lock()
        defer { lock.unlock() }
        data = cleaned
        loaded = true
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(data).write(to: fileURL, options: .atomic)
        return data
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        if let raw = FileManager.default.contents(atPath: fileURL.path),
           let stored = try? JSONDecoder().decode(BusinessHoursData.self, from: raw) {
            data = stored
        } else {
            data = .initial
        }
        loaded = true
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
