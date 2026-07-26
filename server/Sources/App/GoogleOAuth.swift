import Vapor

enum GoogleOAuth {
    static func authorizationURL(state: String, redirectURI: String) throws -> String {
        guard let clientId = Environment.get("GOOGLE_OAUTH_CLIENT_ID"), !clientId.isEmpty else {
            throw OAuthConfigError.missingConfig("GOOGLE_OAUTH_CLIENT_ID is not set")
        }
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else {
            throw Abort(.internalServerError, reason: "Could not build Google authorization URL.")
        }
        return url.absoluteString
    }

    private struct TokenResponse: Content {
        var access_token: String
    }

    private struct UserInfoResponse: Content {
        var sub: String
        var email: String
        var email_verified: Bool?
        var name: String?
        var picture: String?
    }

    static func exchangeCodeAndFetchUser(code: String, redirectURI: String, client: Client) async throws -> OAuthUserInfo {
        guard let clientId = Environment.get("GOOGLE_OAUTH_CLIENT_ID"), !clientId.isEmpty,
              let clientSecret = Environment.get("GOOGLE_OAUTH_CLIENT_SECRET"), !clientSecret.isEmpty else {
            throw OAuthConfigError.missingConfig("GOOGLE_OAUTH_CLIENT_ID / GOOGLE_OAUTH_CLIENT_SECRET are not set")
        }

        let tokenResponse = try await client.post(URI(string: "https://oauth2.googleapis.com/token")) { req in
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
            throw Abort(.badGateway, reason: "Google token exchange failed.")
        }
        let token = try tokenResponse.content.decode(TokenResponse.self)

        let userResponse = try await client.get(URI(string: "https://www.googleapis.com/oauth2/v3/userinfo")) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: token.access_token)
        }.get()
        guard userResponse.status == .ok else {
            throw Abort(.badGateway, reason: "Google user info request failed.")
        }
        let info = try userResponse.content.decode(UserInfoResponse.self)
        guard info.email_verified ?? false else {
            throw Abort(.forbidden, reason: "Your Google email isn't verified.")
        }

        return OAuthUserInfo(providerId: info.sub, email: info.email, displayName: info.name ?? info.email, pictureURL: info.picture)
    }
}
