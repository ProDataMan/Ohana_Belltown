import Vapor
import Crypto
import struct Foundation.Data

/// Facebook's "Data Deletion Request" callback — set as the Data Deletion
/// Request URL under Facebook Login → Settings. When a user asks Facebook to
/// have an app delete their data (e.g. via their own Facebook settings, not
/// anything on our site), Facebook POSTs here instead of hitting any button
/// of ours. https://developers.facebook.com/docs/facebook-login/guides/data-deletion
enum FacebookDataDeletion {
    private static func base64URLDecode(_ string: some StringProtocol) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
    }

    private struct SignedRequestPayload: Decodable {
        var user_id: String
    }

    /// Verifies the `signed_request` Facebook POSTs (an HMAC-SHA256 of the
    /// payload, keyed with the app secret — the same shared secret used for
    /// the OAuth token exchange) and returns the Facebook user id inside it.
    /// Rejects anything that isn't actually from Facebook.
    static func parseUserId(signedRequest: String) throws -> String {
        guard let appSecret = Environment.get("FACEBOOK_OAUTH_APP_SECRET"), !appSecret.isEmpty else {
            throw OAuthConfigError.missingConfig("FACEBOOK_OAUTH_APP_SECRET is not set")
        }
        let parts = signedRequest.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let signatureData = base64URLDecode(parts[0]),
              let payloadData = base64URLDecode(parts[1]) else {
            throw Abort(.badRequest, reason: "Malformed signed_request.")
        }
        let key = SymmetricKey(data: Data(appSecret.utf8))
        guard HMAC<SHA256>.isValidAuthenticationCode(signatureData, authenticating: Data(parts[1].utf8), using: key) else {
            throw Abort(.badRequest, reason: "signed_request failed signature verification.")
        }
        return try JSONDecoder().decode(SignedRequestPayload.self, from: payloadData).user_id
    }
}
