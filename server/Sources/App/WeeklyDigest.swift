import Vapor

/// A Monday 9am (Pacific) email to admins with the past week's numbers:
/// visits and where they came from, Order Online / call / directions taps,
/// QR use, what QR visitors looked at, searches that found nothing, table
/// cards that look missing, and the POS comparison once tickets are imported.
///
/// Same "check every 10 minutes whether it's due" approach as
/// FeedbackDigest, so a redeploy around 9am sends it late rather than
/// skipping or doubling it. Sends through EmailSenderFactory, which only
/// logs the email until RESEND_API_KEY is set.
enum WeeklyDigest {
    static let sendWeekday = 2 // Monday (1 = Sunday)
    static let sendAfterHour = 9

    static func schedule(_ app: Application) {
        app.eventLoopGroup.next().scheduleRepeatedTask(initialDelay: .minutes(1), delay: .minutes(FeedbackDigest.checkIntervalMinutes)) { _ in
            let promise = app.eventLoopGroup.next().makePromise(of: Void.self)
            promise.completeWithTask { await runIfDue(app) }
        }
    }

    /// Due from 9am Monday until it's been sent that Monday.
    static func isDue(now: Date, lastSentDay: String?) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = FeedbackStore.pacific
        guard calendar.component(.weekday, from: now) == sendWeekday,
              calendar.component(.hour, from: now) >= sendAfterHour else { return false }
        return lastSentDay != FeedbackStore.dayKey(now)
    }

    static func runIfDue(_ app: Application) async {
        let now = Date()
        let stateURL = URL(fileURLWithPath: Environment.get("DATA_DIR") ?? app.directory.workingDirectory + "Data")
            .appendingPathComponent("weekly-digest.json")
        let lastSent = (FileManager.default.contents(atPath: stateURL.path)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }?["lastSentDay"]
        guard isDue(now: now, lastSentDay: lastSent) else { return }
        do {
            let admins = try UserStore.shared.all().filter { $0.role == .admin && $0.active && $0.email != nil }
            if !admins.isEmpty {
                let body = try render(now: now)
                let sender = EmailSenderFactory.make(client: app.client, logger: app.logger)
                for admin in admins {
                    guard let email = admin.email else { continue }
                    try? await sender.send(to: email, subject: "Ohana Belltown — your week on the website", body: body)
                }
            }
            // Marked sent even with no admins to email, so it doesn't retry
            // every 10 minutes all Monday.
            try JSONEncoder().encode(["lastSentDay": FeedbackStore.dayKey(now)]).write(to: stateURL, options: .atomic)
        } catch {
            app.logger.error("Weekly digest failed: \(error)")
        }
    }

    /// The email body for the 7 days ending yesterday.
    static func render(now: Date) throws -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = FeedbackStore.pacific
        let to = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: -7, to: to) ?? to
        let site = try AnalyticsStore.shared.summary(days: 8)
        let visits = QRVisitStore.shared.visits(from: from, to: to)
        let insights = QRInsightsBuilder.build(
            visits: visits, from: from, to: to, menu: try? MenuStore.shared.get(),
            orders: PosOrderStore.shared.orders(from: from, to: to)
        )

        func list(_ items: [(String, Int)], limit: Int = 5) -> String {
            items.isEmpty ? "  (none yet)" : items.prefix(limit).map { "  • \($0.0): \($0.1)" }.joined(separator: "\n")
        }
        var lines = ["Your week on the website (\(FeedbackStore.dayKey(from)) to \(FeedbackStore.dayKey(to.addingTimeInterval(-1))))", ""]
        lines.append("Visits: \(site.visits) (\(site.totalViews) page views; staff and bots excluded)")
        lines.append("Where they came from:")
        lines.append(list(site.sources.map { ($0.label, $0.count) }))
        lines.append("")
        lines.append("Taps that lead to business:")
        lines.append(list(site.actions.map { ($0.label, $0.count) }))
        lines.append("")
        lines.append("QR menu: \(insights.totalVisits) visits at \(insights.tables.filter { $0.visits > 0 }.count) of \(insights.tables.count) tables")
        lines.append("Most-opened dishes:")
        lines.append(list(insights.items.map { ($0.itemName, $0.visits) }))
        let empty = insights.searches.filter { $0.emptyCount > 0 }
        if !empty.isEmpty {
            lines.append("Searches that found nothing:")
            lines.append(list(empty.map { ("\"\($0.query)\"", $0.emptyCount) }))
        }
        let quiet = QRInsightsBuilder.quietTables(lastWeek: visits)
        if !quiet.isEmpty {
            lines.append("Check these table cards (no scans all week): \(quiet.joined(separator: ", "))")
        }
        if let pos = insights.pos {
            lines.append("")
            lines.append("POS: \(pos.tableOrdersWithQRVisit) of \(pos.tableOrders) table tickets had a QR visit.")
            if let with = pos.avgNetSalesWithQR, let without = pos.avgNetSalesWithoutQR {
                lines.append(String(format: "Sales per guest: $%.2f with a QR visit vs $%.2f without.", with, without))
            }
        }
        lines.append("")
        lines.append("Full reports: https://www.ohanasushigrill.com/analytics.html and /qr-insights.html")
        return lines.joined(separator: "\n")
    }
}
