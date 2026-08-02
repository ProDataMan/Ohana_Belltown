import Crypto
import Foundation
import Vapor

struct SquareCheckoutStatus: Content {
    var available: Bool
}

enum SquareCheckoutError: Error {
    case requestFailed(String)
}

extension SquareCheckoutError: AbortError {
    var status: HTTPResponseStatus { .badGateway }

    var reason: String {
        switch self {
        case .requestFailed(let message): return "Checkout couldn't be started: \(message)"
        }
    }
}

/// The subset of a Square `payment.updated` webhook event this app cares
/// about — just enough to confirm a COMPLETED payment and recover the
/// Square order id it belongs to (which we matched against our own
/// SwagOrder when the payment link was created).
struct SquareWebhookEvent: Decodable {
    struct PaymentObject: Decodable {
        let order_id: String?
        let status: String?
    }
    struct DataObject: Decodable {
        let payment: PaymentObject?
    }
    struct EventData: Decodable {
        let object: DataObject
    }
    let type: String
    let data: EventData
}

/// Square-hosted Checkout via the Payment Links API: the server creates a
/// payment link with our line items and redirects the customer to Square's
/// own payment page, so this app never touches a raw card number. Entirely
/// gated behind SQUARE_ACCESS_TOKEN/SQUARE_LOCATION_ID — same "hidden until
/// configured" pattern as AI menu extraction / Apple / Facebook sign-in.
/// Called directly via Square's plain REST API rather than a third-party
/// SDK dependency, mirroring how GoogleOAuth/AppleOAuth already call their
/// providers with req.client.
enum SquareCheckout {
    /// Square's documented, stable API version string — pinned rather than
    /// left to drift, since Square requires this header on every call.
    private static let apiVersion = "2026-07-15"

    private static func baseURL() -> String {
        Environment.get("SQUARE_ENVIRONMENT") == "sandbox"
            ? "https://connect.squareupsandbox.com"
            : "https://connect.squareup.com"
    }

    private struct PriceMoney: Encodable {
        let amount: Int
        let currency: String
    }

    private struct LineItem: Encodable {
        let name: String
        let quantity: String
        let base_price_money: PriceMoney
    }

    private struct OrderPayload: Encodable {
        let location_id: String
        let line_items: [LineItem]
        let metadata: [String: String]
    }

    private struct CheckoutOptions: Encodable {
        let redirect_url: String
    }

    private struct CreatePaymentLinkRequest: Encodable {
        let idempotency_key: String
        let order: OrderPayload
        let checkout_options: CheckoutOptions
    }

    private struct PaymentLink: Decodable {
        let id: String
        let order_id: String
        let url: String
    }

    private struct CreatePaymentLinkResponse: Decodable {
        let payment_link: PaymentLink?
    }

    private struct ErrorEnvelope: Decodable {
        struct SquareError: Decodable { let detail: String? }
        let errors: [SquareError]?
    }

    /// One line on a Square order — deliberately generic (not tied to
    /// SwagOrderItem) so both swag carts and single-item gift card
    /// purchases can share this one helper.
    struct LineItemInput {
        var name: String
        var quantity: Int
        var priceCents: Int
    }

    static func createPaymentLink(
        client: Client, accessToken: String, locationId: String, orderId: String,
        items: [LineItemInput], metadata: [String: String], redirectURL: String
    ) async throws -> (paymentLinkId: String, squareOrderId: String, url: String) {
        let lineItems = items.map { item in
            LineItem(
                name: item.name,
                quantity: String(item.quantity),
                base_price_money: PriceMoney(amount: item.priceCents, currency: "USD")
            )
        }
        let body = CreatePaymentLinkRequest(
            idempotency_key: UUID().uuidString,
            order: OrderPayload(
                location_id: locationId, line_items: lineItems,
                metadata: metadata.merging(["orderId": orderId]) { current, _ in current }
            ),
            checkout_options: CheckoutOptions(redirect_url: redirectURL)
        )

        let response = try await client.post(URI(string: "\(baseURL())/v2/online-checkout/payment-links")) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            req.headers.add(name: "Square-Version", value: apiVersion)
            try req.content.encode(body, as: .json)
        }.get()

        guard response.status == .ok else {
            let message = (try? response.content.decode(ErrorEnvelope.self))?.errors?.first?.detail
                ?? "Square returned \(response.status.code)."
            throw SquareCheckoutError.requestFailed(message)
        }
        let decoded = try response.content.decode(CreatePaymentLinkResponse.self)
        guard let link = decoded.payment_link else {
            throw SquareCheckoutError.requestFailed("Square didn't return a payment link.")
        }
        return (link.id, link.order_id, link.url)
    }

    /// Verifies the `x-square-hmacsha256-signature` header: base64(HMAC-SHA256(
    /// webhook signature key, notification URL + raw body)). The notification
    /// URL must exactly match what's configured for the webhook subscription
    /// in the Square Developer Dashboard.
    static func verifyWebhookSignature(payload: String, notificationURL: String, signatureHeader: String, signatureKey: String) -> Bool {
        let signedPayload = notificationURL + payload
        let key = SymmetricKey(data: Data(signatureKey.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(signedPayload.utf8), using: key)
        let expected = Data(mac).base64EncodedString()
        return expected == signatureHeader
    }
}
