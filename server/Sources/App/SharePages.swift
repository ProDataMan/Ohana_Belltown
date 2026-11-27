import Vapor

/// Shareable pages for social posts and texts: /dish/<id> and /deal/<id>.
/// Built on the server so the link preview (title, description, photo) is in
/// the HTML itself — Facebook, Instagram, iMessage and Slack read those tags
/// without running any script.
///
/// - /dish/<id>: a dish's preview; a person opening it is sent straight to
///   the dish, opened on its menu page (`?item=<id>`, see menu-section.js).
/// - /deal/<id>: a day-of-week deal's landing page (Musubi Monday…), with
///   its dishes and when it's next on.
enum SharePages {
    static let sectionPages = ["menu": "/menu", "sushi": "/sushi", "drinks": "/drinks", "happy_hour": "/happy-hour"]

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func absolute(_ path: String) -> String {
        path.hasPrefix("http") ? path : PublicBaseURL.get() + path
    }

    /// The <head> shared by both pages: title, description, canonical URL
    /// and the Open Graph / Twitter tags previews are built from.
    static func head(title: String, description: String, image: String?, path: String) -> String {
        let url = absolute(path)
        let imageTags = image.map {
            """
            <meta property="og:image" content="\(escape(absolute($0)))" />
                <meta name="twitter:image" content="\(escape(absolute($0)))" />
            """
        } ?? ""
        return """
        <meta charset="UTF-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1.0" />
            <title>\(escape(title))</title>
            <meta name="description" content="\(escape(description))" />
            <meta property="og:type" content="website" />
            <meta property="og:site_name" content="Ohana Belltown" />
            <meta property="og:title" content="\(escape(title))" />
            <meta property="og:description" content="\(escape(description))" />
            <meta property="og:url" content="\(escape(url))" />
            <meta name="twitter:card" content="summary_large_image" />
            \(imageTags)
            <link rel="canonical" href="\(escape(url))" />
            <link rel="stylesheet" href="/style.css" />
        """
    }

    static func page(head: String, body: String) -> Response {
        let html = """
        <!DOCTYPE html>
        <html lang="en">
          <head>
            \(head)
          </head>
          <body>
            <main class="page share-page">
              <p class="share-brand"><a href="/">Ohana Belltown</a></p>
              \(body)
            </main>
            <script src="/nav.js"></script>
          </body>
        </html>
        """
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/html; charset=utf-8")
        return Response(status: .ok, headers: headers, body: .init(string: html))
    }

    static func dish(_ location: MenuItemLocation, id: String, query: String?) -> Response {
        let item = location.item
        let description = item.description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "From the \(location.categoryName) menu at Ohana Belltown, Hawaiian food and sushi in Belltown, Seattle."
        // Carry the share link's tags (utm_source=share…) on to the menu page
        // so the visit is credited to the share.
        var menuURL = "\(sectionPages[location.section] ?? "/menu")?item=\(id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id)"
        if let query, !query.isEmpty { menuURL += "&" + query }
        let photo = item.images.first
        let body = """
        \(photo.map { "<img class=\"share-photo\" src=\"\(escape($0.hasPrefix("/uploads/") ? $0 + "?w=960" : $0))\" alt=\"\(escape(item.name))\" />" } ?? "")
        <p class="eyebrow">\(escape(location.categoryName))</p>
        <h1>\(escape(item.name))</h1>
        <p>\(escape(description))</p>
        <p><a class="cta-button" href="\(escape(menuURL))">See it on our menu &rarr;</a></p>
        <script>location.replace(\(jsonString(menuURL)));</script>
        """
        return page(
            head: head(title: "\(item.name) at Ohana Belltown", description: description, image: photo, path: "/dish/\(id)"),
            body: body
        )
    }

    static func deal(_ deal: DailySpecial, menu: Menu?, now: Date = Date()) -> Response {
        let calendar = BusinessHoursCalculator.calendar
        let dayName = BusinessHoursCalculator.dayNames[deal.weekday]
        let today = calendar.component(.weekday, from: now)
        let daysAhead = (deal.weekday - today + 7) % 7
        let next = calendar.date(byAdding: .day, value: daysAhead, to: now) ?? now
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE, MMMM d"
        let when = daysAhead == 0 ? "Today!" : "Next one: \(formatter.string(from: next))"

        var dishes: [(id: String, item: MenuItem)] = []
        for category in menu?.categories ?? [] {
            for item in category.items where deal.itemNames.contains(item.name) && !dishes.contains(where: { $0.item.name == item.name }) {
                dishes.append((item.id, item))
            }
        }
        let photo = dishes.compactMap { $0.item.images.first }.first
        let description = "\(deal.deal) every \(dayName) at Ohana Belltown." + (deal.details.map { " \($0)" } ?? "")
        let dishList = dishes.map { dish in
            """
            <li><a href="/dish/\(escape(dish.id))">\(dish.item.images.first.map { "<img src=\"\(escape($0.hasPrefix("/uploads/") ? $0 + "?w=480" : $0))\" alt=\"\" loading=\"lazy\" onerror=\"this.style.visibility='hidden'\" />" } ?? "")<span>\(escape(dish.item.name))</span></a></li>
            """
        }.joined()
        let body = """
        \(photo.map { "<img class=\"share-photo\" src=\"\(escape($0.hasPrefix("/uploads/") ? $0 + "?w=960" : $0))\" alt=\"\" />" } ?? "")
        <p class="eyebrow">Every \(escape(dayName))</p>
        <h1>\(escape(deal.title))</h1>
        <p class="share-deal">\(escape(deal.deal))</p>
        \(deal.details.map { "<p>\(escape($0))</p>" } ?? "")
        <p class="share-when">\(escape(when))</p>
        \(dishes.isEmpty ? "" : "<ul class=\"share-dishes\">\(dishList)</ul>")
        <p class="cta-row">
          <a class="cta-button" href="/menu">See the full menu &rarr;</a>
          <a class="cta-button secondary" href="/specials">All our deals</a>
        </p>
        <p><button type="button" class="cta-button secondary share-this-btn" data-title="\(escape(deal.title + " at Ohana Belltown"))">Share this deal</button></p>
        <script src="/share.js"></script>
        """
        return page(
            head: head(title: "\(deal.title) at Ohana Belltown: \(deal.deal)", description: description, image: photo, path: "/deal/\(deal.id)"),
            body: body
        )
    }

    /// What each night is called, for an event's preview and calendar entry
    /// (matches NIGHT_CONFIG in entertainment-night.js).
    static let nightTitles = [
        "wednesday": "Island Nights", "thursday": "DJ Night", "friday": "DJ Night",
        "saturday": "DJ Night", "sunday": "Karaoke",
    ]

    static func eventTitle(_ booking: EntertainmentBooking) -> String {
        let night = EntertainmentStore.weekday(of: booking.date).flatMap { nightTitles[$0] }
        return night.map { "\($0): \(booking.performerName)" } ?? booking.performerName
    }

    /// The booking's start in Pacific time; 9pm when no start time was set.
    static func eventStart(_ booking: EntertainmentBooking) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = booking.date.split(separator: "-").compactMap { Int($0) }
        let time = (booking.startTime ?? "21:00").split(separator: ":").compactMap { Int($0) }
        guard day.count == 3, time.count >= 2 else { return nil }
        return calendar.date(from: DateComponents(year: day[0], month: day[1], day: day[2], hour: time[0], minute: time[1]))
    }

    /// /event/<id>: a performer's night, previewed with their photo; a person
    /// opening it lands on that night's page.
    static func event(_ booking: EntertainmentBooking, query: String?) -> Response {
        let weekday = EntertainmentStore.weekday(of: booking.date) ?? "wednesday"
        var nightURL = "/entertainment/\(weekday)"
        if let query, !query.isEmpty { nightURL += "?" + query }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.dateFormat = "EEEE, MMMM d 'at' h:mma"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        let when = eventStart(booking).map { formatter.string(from: $0) } ?? booking.date
        let title = eventTitle(booking)
        let description = "\(when) at Ohana Belltown." + (booking.bio.map { " \($0)" } ?? " Free live entertainment in Belltown, Seattle.")
        let photo = booking.photos.first
        let body = """
        \(photo.map { "<img class=\"share-photo\" src=\"\(escape($0.hasPrefix("/uploads/") ? $0 + "?w=960" : $0))\" alt=\"\(escape(booking.performerName))\" />" } ?? "")
        <p class="eyebrow">\(escape(when))</p>
        <h1>\(escape(title))</h1>
        \(booking.bio.map { "<p>\(escape($0))</p>" } ?? "")
        <p class="cta-row">
          <a class="cta-button" href="\(escape(nightURL))">See the lineup &rarr;</a>
          <a class="cta-button secondary" href="/event/\(escape(booking.id))/calendar.ics">Add to calendar</a>
        </p>
        <script>location.replace(\(jsonString(nightURL)));</script>
        """
        return page(
            head: head(title: "\(title) at Ohana Belltown", description: description, image: photo, path: "/event/\(booking.id)"),
            body: body
        )
    }

    /// An .ics file for one booking — opens straight into Calendar on a phone.
    static func calendar(_ booking: EntertainmentBooking, now: Date = Date()) -> Response? {
        guard let start = eventStart(booking) else { return nil }
        let utc = DateFormatter()
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        func icsText(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: ";", with: "\\;")
                .replacingOccurrences(of: ",", with: "\\,")
                .replacingOccurrences(of: "\n", with: "\\n")
        }
        let lines = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Ohana Belltown//Entertainment//EN", "METHOD:PUBLISH",
            "BEGIN:VEVENT",
            "UID:\(booking.id)@ohanasushigrill.com",
            "DTSTAMP:\(utc.string(from: now))",
            "DTSTART:\(utc.string(from: start))",
            "DTEND:\(utc.string(from: start.addingTimeInterval(3 * 3600)))",
            "SUMMARY:\(icsText(eventTitle(booking) + " at Ohana Belltown"))",
            "DESCRIPTION:\(icsText((booking.bio ?? "Live entertainment at Ohana Belltown.") + " " + absolute("/event/\(booking.id)")))",
            "LOCATION:\(icsText("Ohana Belltown, 2207 1st Ave, Seattle, WA 98121"))",
            "URL:\(absolute("/event/\(booking.id)"))",
            "END:VEVENT", "END:VCALENDAR",
        ]
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/calendar; charset=utf-8")
        headers.add(name: .contentDisposition, value: "attachment; filename=\"ohana-\(booking.date).ics\"")
        return Response(status: .ok, headers: headers, body: .init(string: lines.joined(separator: "\r\n") + "\r\n"))
    }

    private static func jsonString(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("\"/menu\"".utf8)
        // A "</script>" inside the string would end the script tag.
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "</", with: "<\\/")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
