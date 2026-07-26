import Foundation

/// Published sitewide (happy-hour.html, specials.html) as Monday–Friday, 3–6pm Pacific.
enum HappyHourSchedule {
    static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    static func isActive(at date: Date = Date(), timeZone: TimeZone = HappyHourSchedule.pacific) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday ... 7 = Saturday
        guard (2...6).contains(weekday) else { return false }
        let minutesSinceMidnight = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return minutesSinceMidnight >= 15 * 60 && minutesSinceMidnight < 18 * 60
    }

    /// Where a QR-code scan (or any other "just show me something relevant" entry point)
    /// should land right now.
    static func landingPath(at date: Date = Date(), timeZone: TimeZone = HappyHourSchedule.pacific) -> String {
        isActive(at: date, timeZone: timeZone) ? "/happy-hour" : "/menu"
    }
}
