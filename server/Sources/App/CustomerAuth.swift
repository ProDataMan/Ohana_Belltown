import Vapor

struct CustomerRegisterRequest: Content {
    var email: String
    var displayName: String
    var password: String
}

struct CustomerLoginRequest: Content {
    var email: String
    var password: String
}

struct CustomerForgotPasswordRequest: Content {
    var email: String
}

struct CustomerResetPasswordRequest: Content {
    var token: String
    var newPassword: String
}

struct CustomerChangePasswordRequest: Content {
    var currentPassword: String
    var newPassword: String
}

struct GenericOK: Content {
    var ok: Bool = true
}

func currentCustomer(_ req: Request) throws -> CustomerUser? {
    guard let id = req.session.data["customerId"] else { return nil }
    return try? CustomerUserStore.shared.find(id: id)
}

@discardableResult
func requireCustomerLogin(_ req: Request) throws -> CustomerUser {
    guard let customer = try currentCustomer(req) else {
        throw Abort(.unauthorized, reason: "Please log in.")
    }
    return customer
}

func serveCustomerPage(_ req: Request, file: String, requireLogin: Bool = false) async throws -> Response {
    if requireLogin, try currentCustomer(req) == nil {
        return req.redirect(to: "/account-login?next=\(req.url.path)")
    }
    let path = req.application.directory.publicDirectory + file
    return try await req.fileio.asyncStreamFile(at: path)
}

func registerCustomerAuthRoutes(_ app: Application) throws {
    app.get("signup") { req async throws -> Response in
        try await serveCustomerPage(req, file: "customer/signup.html")
    }
    app.get("account-login") { req async throws -> Response in
        try await serveCustomerPage(req, file: "customer/account-login.html")
    }
    app.get("my-account.html") { req async throws -> Response in
        try await serveCustomerPage(req, file: "customer/my-account.html", requireLogin: true)
    }
    app.get("forgot-password.html") { req async throws -> Response in
        try await serveCustomerPage(req, file: "customer/forgot-password.html")
    }
    app.get("reset-password.html") { req async throws -> Response in
        try await serveCustomerPage(req, file: "customer/reset-password.html")
    }

    app.get("verify-email") { req async throws -> Response in
        guard let token = req.query[String.self, at: "token"] else {
            return req.redirect(to: "/my-account.html")
        }
        _ = try? CustomerUserStore.shared.verify(token: token)
        return req.redirect(to: "/my-account.html?verified=1")
    }

    app.post("api", "customer", "register") { req async throws -> CustomerUserPublic in
        let body = try req.content.decode(CustomerRegisterRequest.self)
        let (customer, token) = try CustomerUserStore.shared.register(
            email: body.email, displayName: body.displayName, password: body.password
        )
        let sender = EmailSenderFactory.make(logger: req.logger)
        try? await sender.send(
            to: customer.email,
            subject: "Verify your Ohana Belltown account",
            body: "Welcome to Ohana Belltown! Verify your email by visiting: /verify-email?token=\(token)"
        )
        req.session.data["customerId"] = customer.id
        return customer
    }

    app.post("api", "customer", "login") { req throws -> CustomerUserPublic in
        let body = try req.content.decode(CustomerLoginRequest.self)
        let customer = try CustomerUserStore.shared.authenticate(email: body.email, password: body.password)
        req.session.data["customerId"] = customer.id
        return CustomerUserPublic(customer)
    }

    app.post("api", "customer", "logout") { req -> HTTPStatus in
        req.session.data["customerId"] = nil
        return .ok
    }

    app.get("api", "customer", "me") { req throws -> CustomerUserPublic in
        guard let customer = try currentCustomer(req) else {
            throw Abort(.unauthorized)
        }
        return CustomerUserPublic(customer)
    }

    app.post("api", "customer", "forgot-password") { req async throws -> GenericOK in
        let body = try req.content.decode(CustomerForgotPasswordRequest.self)
        if let token = try CustomerUserStore.shared.requestPasswordReset(email: body.email) {
            let sender = EmailSenderFactory.make(logger: req.logger)
            try? await sender.send(
                to: body.email,
                subject: "Reset your Ohana Belltown password",
                body: "Reset your password: /reset-password.html?token=\(token) (expires in 1 hour)"
            )
        }
        return GenericOK()
    }

    app.post("api", "customer", "reset-password") { req throws -> CustomerUserPublic in
        let body = try req.content.decode(CustomerResetPasswordRequest.self)
        return try CustomerUserStore.shared.resetPassword(token: body.token, newPassword: body.newPassword)
    }

    app.post("api", "customer", "change-password") { req throws -> CustomerUserPublic in
        let customer = try requireCustomerLogin(req)
        let body = try req.content.decode(CustomerChangePasswordRequest.self)
        return try CustomerUserStore.shared.changePassword(
            id: customer.id, currentPassword: body.currentPassword, newPassword: body.newPassword
        )
    }

    app.post("api", "customer", "deactivate") { req throws -> CustomerUserPublic in
        let customer = try requireCustomerLogin(req)
        let result = try CustomerUserStore.shared.deactivate(id: customer.id)
        req.session.data["customerId"] = nil
        return result
    }
}
