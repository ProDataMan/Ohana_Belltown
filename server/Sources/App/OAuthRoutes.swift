import Vapor

struct AppleCallbackBody: Content {
    var code: String?
    var state: String?
    var error: String?
    var user: String?
}

private func makeState(mode: String) -> String {
    "\(UUID().uuidString):\(mode)"
}

private func parseState(_ state: String) -> (csrf: String, mode: String)? {
    let parts = state.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return nil }
    return (parts[0], parts[1])
}

func registerOAuthRoutes(_ app: Application) throws {
    let base = PublicBaseURL.get()

    // MARK: Customer — Google

    app.get("auth", "google", "customer") { req -> Response in
        let state = makeState(mode: "signin")
        req.session.data["oauthState"] = state
        let url = try GoogleOAuth.authorizationURL(state: state, redirectURI: "\(base)/auth/google/customer/callback")
        return req.redirect(to: url)
    }

    app.get("auth", "google", "customer", "callback") { req async throws -> Response in
        guard let code = req.query[String.self, at: "code"],
              let state = req.query[String.self, at: "state"],
              state == req.session.data["oauthState"] else {
            return req.redirect(to: "/account-login?error=oauth_failed")
        }
        req.session.data["oauthState"] = nil
        let info = try await GoogleOAuth.exchangeCodeAndFetchUser(
            code: code, redirectURI: "\(base)/auth/google/customer/callback", client: req.client
        )
        let customer = try CustomerUserStore.shared.findOrCreateFromOAuth(
            provider: .google, providerId: info.providerId, email: info.email, displayName: info.displayName
        )
        req.session.data["customerId"] = customer.id
        return req.redirect(to: "/my-account.html")
    }

    // MARK: Customer — Apple

    app.get("auth", "apple", "customer") { req -> Response in
        let state = makeState(mode: "signin")
        req.session.data["oauthState"] = state
        let url = try AppleOAuth.authorizationURL(state: state, redirectURI: "\(base)/auth/apple/customer/callback")
        return req.redirect(to: url)
    }

    app.on(.POST, "auth", "apple", "customer", "callback") { req async throws -> Response in
        let body = try req.content.decode(AppleCallbackBody.self)
        guard let code = body.code, let state = body.state, state == req.session.data["oauthState"] else {
            return req.redirect(to: "/account-login?error=oauth_failed")
        }
        req.session.data["oauthState"] = nil
        let info = try await AppleOAuth.exchangeCodeAndFetchUser(
            code: code, redirectURI: "\(base)/auth/apple/customer/callback", userField: body.user, client: req.client
        )
        let customer = try CustomerUserStore.shared.findOrCreateFromOAuth(
            provider: .apple, providerId: info.providerId, email: info.email, displayName: info.displayName
        )
        req.session.data["customerId"] = customer.id
        return req.redirect(to: "/my-account.html")
    }

    // MARK: Staff — Google

    app.get("auth", "google", "staff") { req throws -> Response in
        let mode = req.query[String.self, at: "mode"] ?? "signin"
        if mode == "link" {
            try requireLogin(req)
        }
        let state = makeState(mode: mode)
        req.session.data["oauthState"] = state
        let url = try GoogleOAuth.authorizationURL(state: state, redirectURI: "\(base)/auth/google/staff/callback")
        return req.redirect(to: url)
    }

    app.get("auth", "google", "staff", "callback") { req async throws -> Response in
        try await handleStaffOAuthCallback(
            req, code: req.query[String.self, at: "code"], state: req.query[String.self, at: "state"],
            provider: .google, redirectURI: "\(base)/auth/google/staff/callback", userField: nil
        )
    }

    // MARK: Staff — Apple

    app.get("auth", "apple", "staff") { req throws -> Response in
        let mode = req.query[String.self, at: "mode"] ?? "signin"
        if mode == "link" {
            try requireLogin(req)
        }
        let state = makeState(mode: mode)
        req.session.data["oauthState"] = state
        let url = try AppleOAuth.authorizationURL(state: state, redirectURI: "\(base)/auth/apple/staff/callback")
        return req.redirect(to: url)
    }

    app.on(.POST, "auth", "apple", "staff", "callback") { req async throws -> Response in
        let body = try req.content.decode(AppleCallbackBody.self)
        return try await handleStaffOAuthCallback(
            req, code: body.code, state: body.state,
            provider: .apple, redirectURI: "\(base)/auth/apple/staff/callback", userField: body.user
        )
    }
}

private func handleStaffOAuthCallback(
    _ req: Request, code: String?, state: String?, provider: OAuthProvider, redirectURI: String, userField: String?
) async throws -> Response {
    guard let code, let state, state == req.session.data["oauthState"],
          let parsed = parseState(state) else {
        return req.redirect(to: "/login?error=oauth_failed")
    }
    req.session.data["oauthState"] = nil

    let info: OAuthUserInfo
    switch provider {
    case .google:
        info = try await GoogleOAuth.exchangeCodeAndFetchUser(code: code, redirectURI: redirectURI, client: req.client)
    case .apple:
        info = try await AppleOAuth.exchangeCodeAndFetchUser(code: code, redirectURI: redirectURI, userField: userField, client: req.client)
    }

    if parsed.mode == "link" {
        let currentStaff = try requireLogin(req)
        try UserStore.shared.linkOAuth(id: currentStaff.id, provider: provider, providerId: info.providerId)
        return req.redirect(to: "/account.html")
    } else {
        guard let staff = try? UserStore.shared.findByOAuth(provider: provider, providerId: info.providerId) else {
            return req.redirect(to: "/login?error=not_linked")
        }
        req.session.data["userId"] = staff.id
        return req.redirect(to: "/edit.html")
    }
}
