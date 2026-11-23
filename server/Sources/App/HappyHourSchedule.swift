import Foundation

/// Published sitewide (happy-hour.html, specials.html) as Monday–Friday, 3–6pm Pacific.
enum HappyHourSchedule {
    static let pacific = TimeZone(identifier: "America/Los_Angeles")!
    /// Monday–Friday (1 = Sunday … 7 = Saturday).
    static let weekdays = 2...6
    static let startHour = 15
    static let endHour = 18

    static func isActive(at date: Date = Date(), timeZone: TimeZone = HappyHourSchedule.pacific) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday ... 7 = Saturday
        guard weekdays.contains(weekday) else { return false }
        let minutesSinceMidnight = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return minutesSinceMidnight >= startHour * 60 && minutesSinceMidnight < endHour * 60
    }

    /// Where a QR-code scan (or any other "just show me something relevant" entry point)
    /// should land right now.
    static func landingPath(at date: Date = Date(), timeZone: TimeZone = HappyHourSchedule.pacific) -> String {
        isActive(at: date, timeZone: timeZone) ? "/happy-hour" : "/menu"
    }
}
