import Crypto
import Foundation
import Vapor

struct StripeCheckoutStatus: Content {
    var available: Bool
}

/// The subset of a Stripe webhook event payload this app cares about —
/// just enough to confirm a checkout.session.completed and recover the
/// SwagOrder id we stashed in the session's metadata.
struct StripeWebhookEvent: Decodable {
    struct DataObject: Decodable {
        let id: String
        let metadata: [String: String]?
    }
    struct EventData: Decodable {
        let object: DataObject
    }
    let type: String
    let data: EventData
}

enum StripeCheckoutError: Error {
    case requestFailed(String)
}

extension StripeCheckoutError: AbortError {
    var status: HTTPResponseStatus { .badGateway }

    var reason: String {
        switch self {
        case .requestFailed(let message): return "Checkout couldn't be started: \(message)"
        }
    }
}

/// Stripe-hosted Checkout: the server builds a one-time Checkout Session
/// with our line items and redirects the customer to Stripe's own payment
/// page, so this app never touches a raw card number. Entirely gated
/// behind STRIPE_SECRET_KEY — same "hidden until configured" pattern as AI
/// menu extraction / Apple / Facebook sign-in. Called directly via Stripe's
/// plain REST API rather than a third-party SDK dependency, mirroring how
/// GoogleOAuth/AppleOAuth already call their providers with req.client.
enum StripeCheckout {
    private struct SessionResponse: Decodable {
        let id: String
        let url: String?
    }

    private struct ErrorEnvelope: Decodable {
        struct ErrorBody: Decodable { let message: String? }
        let error: ErrorBody?
    }

    static func createSession(
        client: Client, secretKey: String, orderId: String, tableId: String,
        items: [SwagOrderItem], successURL: String, cancelURL: String
    ) async throws -> (id: String, url: String) {
        var form: [(String, String)] = [
            ("mode", "payment"),
            ("success_url", successURL),
            ("cancel_url", cancelURL),
            ("metadata[orderId]", orderId),
            ("metadata[tableId]", tableId),
        ]
        for (index, item) in items.enumerated() {
            let cents = Int((item.price * 100).rounded())
            form.append(("line_items[\(index)][price_data][currency]", "usd"))
            form.append(("line_items[\(index)][price_data][unit_amount]", String(cents)))
            form.append(("line_items[\(index)][price_data][product_data][name]", item.name))
            form.append(("line_items[\(index)][quantity]", String(item.quantity)))
        }
        let bodyString = form.map { "\(percentEncode($0.0))=\(percentEncode($0.1))" }.joined(separator: "&")

        let response = try await client.post(URI(string: "https://api.stripe.com/v1/checkout/sessions")) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: secretKey)
            req.headers.contentType = .urlEncodedForm
            req.body = ByteBuffer(string: bodyString)
        }.get()

        guard response.status == .ok else {
            let message = (try? response.content.decode(ErrorEnvelope.self))?.error?.message
                ?? "Stripe returned \(response.status.code)."
            throw StripeCheckoutError.requestFailed(message)
        }
        let decoded = try response.content.decode(SessionResponse.self)
        guard let url = decoded.url else {
            throw StripeCheckoutError.requestFailed("Stripe didn't return a checkout URL.")
        }
        return (decoded.id, url)
    }

    /// Verifies the `Stripe-Signature` header against the raw webhook body
    /// so a forged POST to the webhook endpoint can't fake a payment.
    /// Format: "t=<timestamp>,v1=<hex hmac>" — see Stripe's webhook docs.
    static func verifyWebhookSignature(
        payload: String, signatureHeader: String, secret: String, toleranceSeconds: Double = 300
    ) -> Bool {
        var timestamp: String?
        var signature: String?
        for part in signatureHeader.split(separator: ",") {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            if kv[0] == "t" { timestamp = String(kv[1]) }
            if kv[0] == "v1" { signature = String(kv[1]) }
        }
        guard let timestamp, let signature, let ts = Double(timestamp) else { return false }
        guard abs(Date().timeIntervalSince1970 - ts) < toleranceSeconds else { return false }

        let signedPayload = "\(timestamp).\(payload)"
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(signedPayload.utf8), using: key)
        let expected = mac.map { String(format: "%02x", $0) }.joined()
        return expected == signature
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
