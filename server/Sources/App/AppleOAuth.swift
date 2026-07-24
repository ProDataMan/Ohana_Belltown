import Vapor
import Crypto
import struct Foundation.Data
import class Foundation.JSONSerialization

enum AppleOAuth {
    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ string: some StringProtocol) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
    }

    private struct ClientSecretHeader: Encodable {
        let alg = "ES256"
        let kid: String
    }

    private struct ClientSecretPayload: Encodable {
        let iss: String
        let iat: Int
        let exp: Int
        let aud = "https://appleid.apple.com"
        let sub: String
    }

    /// Apple requires the OAuth "client_secret" to be a short-lived JWT signed
    /// with the developer's private key, not a static string like Google's.
    private static func makeClientSecret() throws -> String {
        guard let teamId = Environment.get("APPLE_OAUTH_TEAM_ID"), !teamId.isEmpty,
              let keyId = Environment.get("APPLE_OAUTH_KEY_ID"), !keyId.isEmpty,
              let clientId = Environment.get("APPLE_OAUTH_CLIENT_ID"), !clientId.isEmpty,
              let privateKeyPEM = Environment.get("APPLE_OAUTH_PRIVATE_KEY"), !privateKeyPEM.isEmpty else {
            throw OAuthConfigError.missingConfig(
                "APPLE_OAUTH_TEAM_ID / APPLE_OAUTH_KEY_ID / APPLE_OAUTH_CLIENT_ID / APPLE_OAUTH_PRIVATE_KEY are not set"
            )
        }

        let now = Int(Date().timeIntervalSince1970)
        let header = ClientSecretHeader(kid: keyId)
        let payload = ClientSecretPayload(iss: teamId, iat: now, exp: now + 300, sub: clientId)

        let encoder = JSONEncoder()
        let headerJSON = try encoder.encode(header)
        let payloadJSON = try encoder.encode(payload)
        let signingInput = base64URLEncode(headerJSON) + "." + base64URLEncode(payloadJSON)

        let key = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
        let signature = try key.signature(for: Data(signingInput.utf8))

        return signingInput + "." + base64URLEncode(signature.rawRepresentation)
    }

    static func authorizationURL(state: String, redirectURI: String) throws -> String {
        guard let clientId = Environment.get("APPLE_OAUTH_CLIENT_ID"), !clientId.isEmpty else {
            throw OAuthConfigError.missingConfig("APPLE_OAUTH_CLIENT_ID is not set")
        }
        var components = URLComponents(string: "https://appleid.apple.com/auth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "name email"),
            URLQueryItem(name: "response_mode", value: "form_post"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else {
            throw Abort(.internalServerError, reason: "Could not build Apple authorization URL.")
        }
        return url.absoluteString
    }

    private struct TokenResponse: Content {
        var id_token: String
    }

    private struct IDTokenClaims: Decodable {
        var sub: String
        var email: String?
    }

    /// The `user` field Apple POSTs back, only on the very first authorization.
    struct AppleUserField: Decodable {
        struct Name: Decodable {
            var firstName: String?
            var lastName: String?
        }
        var name: Name?
    }

    static func exchangeCodeAndFetchUser(code: String, redirectURI: String, userField: String?, client: Client) async throws -> OAuthUserInfo {
        guard let clientId = Environment.get("APPLE_OAUTH_CLIENT_ID"), !clientId.isEmpty else {
            throw OAuthConfigError.missingConfig("APPLE_OAUTH_CLIENT_ID is not set")
        }
        let clientSecret = try makeClientSecret()

        let tokenResponse = try await client.post(URI(string: "https://appleid.apple.com/auth/token")) { req in
            try req.content.encode(
                [
                    "code": code,
                    "client_id": clientId,
                    "client_secret": clientSecret,
                    "redirect_uri": redirectURI,
                    "grant_type": "authorization_code",
                ],
                as: .urlEncodedForm
            )
        }.get()
        guard tokenResponse.status == .ok else {
            throw Abort(.badGateway, reason: "Apple token exchange failed.")
        }
        let token = try tokenResponse.content.decode(TokenResponse.self)

        let parts = token.id_token.split(separator: ".")
        guard parts.count == 3, let payloadData = base64URLDecode(parts[1]) else {
            throw Abort(.badGateway, reason: "Could not read Apple's identity token.")
        }
        let claims = try JSONDecoder().decode(IDTokenClaims.self, from: payloadData)

        var displayName = claims.email ?? "Apple User"
        if let userField, let userData = userField.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(AppleUserField.self, from: userData),
           let name = parsed.name {
            displayName = [name.firstName, name.lastName].compactMap { $0 }.joined(separator: " ")
            if displayName.isEmpty { displayName = claims.email ?? "Apple User" }
        }

        guard let email = claims.email else {
            throw Abort(.forbidden, reason: "Apple didn't share an email for this account.")
        }

        return OAuthUserInfo(providerId: claims.sub, email: email, displayName: displayName)
    }
}
