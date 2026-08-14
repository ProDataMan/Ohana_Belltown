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

enum EmailSenderError: Error {
    case requestFailed(String)
}

extension EmailSenderError: AbortError {
    var status: HTTPResponseStatus { .badGateway }

    var reason: String {
        switch self {
        case .requestFailed(let message): return "Email couldn't be sent: \(message)"
        }
    }
}

/// Sends via Resend's plain REST API (`POST https://api.resend.com/emails`) —
/// no SDK dependency, mirroring how SquareCheckout/GoogleOAuth/AppleOAuth
/// already call their providers directly with `client`. Gated behind
/// RESEND_API_KEY, same "hidden/inactive until configured" pattern as
/// Square/Apple/Facebook/AI extraction. RESEND_FROM_ADDRESS defaults to
/// Resend's own onboarding@resend.dev, which works without verifying
/// ohanasushigrill.com's DNS (the "fast path" from the README) — set it to a
/// verified @ohanasushigrill.com address once that DNS work is done.
struct ResendEmailSender: EmailSender {
    let client: Client
    let apiKey: String
    let fromAddress: String
    let logger: Logger

    private struct SendRequest: Encodable {
        let from: String
        let to: [String]
        let subject: String
        let text: String
    }

    private struct ErrorEnvelope: Decodable {
        let message: String?
    }

    func send(to: String, subject: String, body: String) async throws {
        let request = SendRequest(from: fromAddress, to: [to], subject: subject, text: body)
        let response = try await client.post(URI(string: "https://api.resend.com/emails")) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: apiKey)
            try req.content.encode(request, as: .json)
        }.get()

        guard (200..<300).contains(Int(response.status.code)) else {
            let message = (try? response.content.decode(ErrorEnvelope.self))?.message
                ?? "Resend returned \(response.status.code)."
            logger.error("Resend send failed: \(message)")
            throw EmailSenderError.requestFailed(message)
        }
    }
}

enum EmailSenderFactory {
    static func make(client: Client, logger: Logger) -> EmailSender {
        if let apiKey = Environment.get("RESEND_API_KEY") {
            let from = Environment.get("RESEND_FROM_ADDRESS") ?? "onboarding@resend.dev"
            return ResendEmailSender(client: client, apiKey: apiKey, fromAddress: from, logger: logger)
        }
        return ConsoleEmailSender(logger: logger)
    }
}
