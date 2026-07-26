import Vapor

/// A daily 9am (Pacific) email to admins summarizing the previous day's
/// customer feedback. Implemented as a periodic "has today's digest been
/// sent yet?" check rather than a precisely-timed cron job — simpler, and
/// safe across a redeploy: a missed 9am window just gets caught (and sent
/// late) on the next check rather than silently skipped or double-sent.
enum FeedbackDigest {
    static let checkIntervalMinutes: Int64 = 10
    static let sendAfterHour = 9

    static func schedule(_ app: Application) {
        app.eventLoopGroup.next().scheduleRepeatedTask(
            initialDelay: .seconds(30), delay: .minutes(checkIntervalMinutes)
        ) { _ in
            let promise = app.eventLoopGroup.next().makePromise(of: Void.self)
            promise.completeWithTask {
                await runIfDue(app)
            }
        }
    }

    /// Pure gating check — separated out so it's testable without needing to
    /// wait for a real clock or fake the store.
    static func isDigestDue(now: Date, timeZone: TimeZone, alreadySentToday: Bool) -> Bool {
        guard !alreadySentToday else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: now) >= sendAfterHour
    }

    static func renderDigestBody(entries: [FeedbackEntry], dayKey: String) -> String {
        guard !entries.isEmpty else {
            return "No feedback was submitted on \(dayKey)."
        }
        let ratings = entries.compactMap { $0.rating }
        var lines = ["\(entries.count) feedback submission(s) from \(dayKey):"]
        if !ratings.isEmpty {
            let avg = Double(ratings.reduce(0, +)) / Double(ratings.count)
            lines.append(String(format: "Average rating: %.1f / 5 (%d rated)", avg, ratings.count))
        }
        lines.append("")
        for entry in entries {
            var line = "- [\(entry.category)]"
            if let rating = entry.rating { line += " \(rating)/5" }
            line += " \(entry.message)"
            if let page = entry.page { line += " (from \(page))" }
            if let email = entry.contactEmail { line += " — reply to: \(email)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    static func runIfDue(_ app: Application) async {
        let now = Date()
        let today = FeedbackStore.dayKey(now)
        do {
            let alreadySent = try FeedbackStore.shared.hasSentDigest(for: today)
            guard isDigestDue(now: now, timeZone: FeedbackStore.pacific, alreadySentToday: alreadySent) else { return }

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = FeedbackStore.pacific
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return }
            let yesterdayKey = FeedbackStore.dayKey(yesterday)
            let entries = try FeedbackStore.shared.entries(onDay: yesterdayKey)

            let admins = try UserStore.shared.all().filter { $0.role == .admin && $0.active && $0.email != nil }
            guard !admins.isEmpty else {
                // No one to send to — still mark sent so this doesn't retry
                // every 10 minutes for the rest of the day.
                try FeedbackStore.shared.markDigestSent(for: today)
                return
            }

            let body = renderDigestBody(entries: entries, dayKey: yesterdayKey)
            let sender = EmailSenderFactory.make(logger: app.logger)
            for admin in admins {
                guard let email = admin.email else { continue }
                try? await sender.send(to: email, subject: "Ohana Belltown — Feedback from \(yesterdayKey)", body: body)
            }
            try FeedbackStore.shared.markDigestSent(for: today)
        } catch {
            app.logger.error("Feedback digest failed: \(error)")
        }
    }
}
