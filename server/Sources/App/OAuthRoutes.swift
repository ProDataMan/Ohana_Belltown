import Vapor

struct AppleCallbackBody: Content {
    var code: String?
    var state: String?
    var error: String?
    var user: String?
}

private func makeState(audience: String, mode: String) -> String {
    "\(UUID().uuidString):\(audience):\(mode)"
}

private func parseState(_ state: String) -> (csrf: String, audience: String, mode: String)? {
    let parts = state.split(separator: ":", maxSplits: 2).map(String.init)
    guard parts.count == 3 else { return nil }
    return (parts[0], parts[1], parts[2])
}

private func finishStaffOAuth(_ req: Request, info: OAuthUserInfo, provider: OAuthProvider, mode: String) throws -> Response {
    if mode == "link" {
        let currentStaff = try requireLogin(req)
        try UserStore.shared.linkOAuth(id: currentStaff.id, provider: provider, providerId: info.providerId)
        return req.redirect(to: "/account.html")
    }
    guard let staff = try? UserStore.shared.findByOAuth(provider: provider, providerId: info.providerId) else {
        return req.redirect(to: "/login?error=not_linked")
    }
    req.session.data["userId"] = staff.id
    return req.redirect(to: "/logged-in")
}

func registerOAuthRoutes(_ app: Application) throws {
    let base = PublicBaseURL.get()

    // Shared post-login destination — figures out whether the current
    // session is staff or a customer and sends them to the right place.
    // Also what OAuth sign-ins land on, so both flows end up here.
    app.get("logged-in") { req -> Response in
        if (try? currentUser(req)) != nil {
            return req.redirect(to: "/edit.html")
        }
        if (try? currentCustomer(req)) != nil {
            return req.redirect(to: "/my-account.html")
        }
        return req.redirect(to: "/login")
    }

    // MARK: Google — one shared callback URL for both customers and staff,
    // dispatched by the `audience` embedded in `state`. This means only a
    // single redirect URI needs to be registered in Google Cloud Console.

    app.get("auth", "google", "customer") { req -> Response in
        let state = makeState(audience: "customer", mode: "signin")
        req.session.data["oauthState"] = state
        let url = try GoogleOAuth.authorizationURL(state: state, redirectURI: "\(base)/auth/google/callback")
        return req.redirect(to: url)
    }

    app.get("auth", "google", "staff") { req throws -> Response in
        let mode = req.query[String.self, at: "mode"] ?? "signin"
        if mode == "link" {
            try requireLogin(req)
        }
        let state = makeState(audience: "staff", mode: mode)
        req.session.data["oauthState"] = state
        let url = try GoogleOAuth.authorizationURL(state: state, redirectURI: "\(base)/auth/google/callback")
        return req.redirect(to: url)
    }

    app.get("auth", "google", "callback") { req async throws -> Response in
        guard let code = req.query[String.self, at: "code"],
              let state = req.query[String.self, at: "state"],
              state == req.session.data["oauthState"],
              let parsed = parseState(state) else {
            return req.redirect(to: "/login?error=oauth_failed")
        }
        req.session.data["oauthState"] = nil
        let info = try await GoogleOAuth.exchangeCodeAndFetchUser(
            code: code, redirectURI: "\(base)/auth/google/callback", client: req.client
        )

        if parsed.audience == "customer" {
            let customer = try CustomerUserStore.shared.findOrCreateFromOAuth(
                provider: .google, providerId: info.providerId, email: info.email, displayName: info.displayName
            )
            req.session.data["customerId"] = customer.id
            return req.redirect(to: "/logged-in")
        }
        return try finishStaffOAuth(req, info: info, provider: .google, mode: parsed.mode)
    }

    // MARK: Customer — Apple (hidden in the UI for now, kept working underneath)

    app.get("auth", "apple", "customer") { req -> Response in
        let state = makeState(audience: "customer", mode: "signin")
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
        return req.redirect(to: "/logged-in")
    }

    // MARK: Staff — Apple (hidden in the UI for now, kept working underneath)

    app.get("auth", "apple", "staff") { req throws -> Response in
        let mode = req.query[String.self, at: "mode"] ?? "signin"
        if mode == "link" {
            try requireLogin(req)
        }
        let state = makeState(audience: "staff", mode: mode)
        req.session.data["oauthState"] = state
        let url = try AppleOAuth.authorizationURL(state: state, redirectURI: "\(base)/auth/apple/staff/callback")
        return req.redirect(to: url)
    }

    app.on(.POST, "auth", "apple", "staff", "callback") { req async throws -> Response in
        let body = try req.content.decode(AppleCallbackBody.self)
        guard let code = body.code, let state = body.state, state == req.session.data["oauthState"],
              let parsed = parseState(state) else {
            return req.redirect(to: "/login?error=oauth_failed")
        }
        req.session.data["oauthState"] = nil
        let info = try await AppleOAuth.exchangeCodeAndFetchUser(
            code: code, redirectURI: "\(base)/auth/apple/staff/callback", userField: body.user, client: req.client
        )
        return try finishStaffOAuth(req, info: info, provider: .apple, mode: parsed.mode)
    }
}
