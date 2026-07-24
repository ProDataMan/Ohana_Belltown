import Vapor

protocol EmailSender: Sendable {
    func send(to: String, subject: String, body: String) async throws
}

/// Placeholder sender used until a real transactional email provider is configured.
/// Logs the email instead of delivering it, so the rest of the customer-account
/// flow (registration, verification, password reset) is fully testable today.
struct ConsoleEmailSender: EmailSender {
    let logger: Logger

    func send(to: String, subject: String, body: String) async throws {
        logger.notice("EMAIL (not sent — no provider configured) to=\(to) subject=\"\(subject)\"\n\(body)")
    }
}

enum EmailSenderFactory {
    static func make(logger: Logger) -> EmailSender {
        // No real provider is wired in yet. When one is chosen, branch on
        // Environment.get("EMAIL_PROVIDER") here and return a real sender
        // backed by EMAIL_API_KEY.
        ConsoleEmailSender(logger: logger)
    }
}
