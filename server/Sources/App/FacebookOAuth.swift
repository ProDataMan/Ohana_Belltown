import Vapor
import NIOFoundationCompat
import struct Foundation.Data

/// Facebook Login — free to set up (a Meta for Developers app, no paid tier
/// required for basic sign-in), unlike X/Twitter's current API pricing.
/// Hidden in the UI (see `docs/oauth-setup.md`) until FACEBOOK_OAUTH_APP_ID /
/// FACEBOOK_OAUTH_APP_SECRET are actually configured, same as Apple.
enum FacebookOAuth {
    private static let graphVersion = "v19.0"

    static func authorizationURL(state: String, redirectURI: String) throws -> String {
        guard let appId = Environment.get("FACEBOOK_OAUTH_APP_ID"), !appId.isEmpty else {
            throw OAuthConfigError.missingConfig("FACEBOOK_OAUTH_APP_ID is not set")
        }
        var components = URLComponents(string: "https://www.facebook.com/\(graphVersion)/dialog/oauth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: appId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "email,public_profile,user_birthday"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else {
            throw Abort(.internalServerError, reason: "Could not build Facebook authorization URL.")
        }
        return url.absoluteString
    }

    private struct TokenResponse: Content {
        var access_token: String
    }

    private struct PictureData: Content {
        var url: String?
    }

    private struct Picture: Content {
        var data: PictureData?
    }

    private struct UserInfoResponse: Content {
        var id: String
        var name: String?
        var email: String?
        /// "MM/DD/YYYY", "MM/DD", or just "YYYY" depending on what the user
        /// has shared — Facebook's own format, not ISO 8601. See
        /// parseBirthday(_:) for how this becomes "MM-DD".
        var birthday: String?
    }

    static func exchangeCodeAndFetchUser(code: String, redirectURI: String, client: Client) async throws -> OAuthUserInfo {
        guard let appId = Environment.get("FACEBOOK_OAUTH_APP_ID"), !appId.isEmpty,
              let appSecret = Environment.get("FACEBOOK_OAUTH_APP_SECRET"), !appSecret.isEmpty else {
            throw OAuthConfigError.missingConfig("FACEBOOK_OAUTH_APP_ID / FACEBOOK_OAUTH_APP_SECRET are not set")
        }

        // Facebook's token exchange is a GET with query params, not a POST body.
        var tokenComponents = URLComponents(string: "https://graph.facebook.com/\(graphVersion)/oauth/access_token")!
        tokenComponents.queryItems = [
            URLQueryItem(name: "client_id", value: appId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "client_secret", value: appSecret),
            URLQueryItem(name: "code", value: code),
        ]
        guard let tokenURL = tokenComponents.url else {
            throw Abort(.internalServerError, reason: "Could not build Facebook token exchange URL.")
        }
        let tokenResponse = try await client.get(URI(string: tokenURL.absoluteString)).get()
        guard tokenResponse.status == .ok else {
            throw Abort(.badGateway, reason: "Facebook token exchange failed.")
        }
        let token = try decodeFacebookJSON(TokenResponse.self, from: tokenResponse)

        var userComponents = URLComponents(string: "https://graph.facebook.com/me")!
        userComponents.queryItems = [
            URLQueryItem(name: "fields", value: "id,name,email,birthday"),
            URLQueryItem(name: "access_token", value: token.access_token),
        ]
        guard let userURL = userComponents.url else {
            throw Abort(.internalServerError, reason: "Could not build Facebook user info URL.")
        }
        let userResponse = try await client.get(URI(string: userURL.absoluteString)).get()
        guard userResponse.status == .ok else {
            throw Abort(.badGateway, reason: "Facebook user info request failed.")
        }
        let info = try decodeFacebookJSON(UserInfoResponse.self, from: userResponse)
        guard let email = info.email else {
            throw Abort(.forbidden, reason: "Facebook didn't share an email for this account.")
        }

        // Fetched as its own call rather than a nested `picture.type(large)` field on
        // `/me`: on some Facebook Apps that nested form fails with "(#210) This call
        // requires a Page access token" even though a valid user token is in use. The
        // dedicated picture edge doesn't have that problem. Best-effort — a picture
        // fetch failure shouldn't block login.
        let pictureURL = try? await fetchPictureURL(userId: info.id, accessToken: token.access_token, client: client)

        return OAuthUserInfo(
            providerId: info.id, email: email, displayName: info.name ?? email, pictureURL: pictureURL,
            birthday: info.birthday.flatMap(Self.parseBirthday)
        )
    }

    /// Facebook returns the birthday in its own `MM/DD/YYYY` format (or just
    /// `MM/DD`, or bare `YYYY` if the user only shared the year) depending on
    /// what the user's chosen to share — never guaranteed to include a full
    /// date. The year is discarded either way, same privacy stance as the
    /// rest of the Birthday Club (see CustomerUser.birthday): only a
    /// `MM/DD`-shaped value can produce a result, zero-padded to match the
    /// "MM-DD" format the manual entry form already stores.
    static func parseBirthday(_ raw: String) -> String? {
        let parts = raw.split(separator: "/")
        guard parts.count >= 2, let month = Int(parts[0]), let day = Int(parts[1]),
              (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        func zeroPadded(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        return "\(zeroPadded(month))-\(zeroPadded(day))"
    }

    private static func fetchPictureURL(userId: String, accessToken: String, client: Client) async throws -> String? {
        var pictureComponents = URLComponents(string: "https://graph.facebook.com/\(userId)/picture")!
        pictureComponents.queryItems = [
            URLQueryItem(name: "type", value: "large"),
            URLQueryItem(name: "redirect", value: "false"),
            URLQueryItem(name: "access_token", value: accessToken),
        ]
        guard let pictureURL = pictureComponents.url else { return nil }
        let pictureResponse = try await client.get(URI(string: pictureURL.absoluteString)).get()
        guard pictureResponse.status == .ok else { return nil }
        return try decodeFacebookJSON(Picture.self, from: pictureResponse).data?.url
    }

    /// The Graph API's replies are JSON, but it frequently labels them
    /// `Content-Type: text/javascript; charset=UTF-8` — a long-standing
    /// Facebook quirk, not an error. `response.content.decode(_:)` picks its
    /// decoder from that header, and Vapor has nothing registered for
    /// `text/javascript`, so it throws a 415 even though the body decodes
    /// fine — which, uncaught, is what let a customer's browser download
    /// Vapor's raw error response as "callback.json" mid-login. Decoding
    /// directly with `JSONDecoder` sidesteps the header entirely.
    private static func decodeFacebookJSON<T: Decodable>(_: T.Type, from response: ClientResponse) throws -> T {
        guard let body = response.body else {
            throw Abort(.badGateway, reason: "Facebook returned an empty response.")
        }
        return try JSONDecoder().decode(T.self, from: Data(buffer: body))
    }
}
