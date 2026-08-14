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

struct CustomerBirthdayRequest: Content {
    var birthday: String?
}

struct CustomerLoyaltyPhoneRequest: Content {
    var phone: String?
}

struct CustomerLoyaltyView: Content {
    var linkedPhone: String?
    var status: LoyaltyStatus?
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
        let sender = EmailSenderFactory.make(client: req.client, logger: req.logger)
        try? await sender.send(
            to: customer.email,
            subject: "Verify your Ohana Belltown account",
            body: "Welcome to Ohana Belltown! Verify your email by visiting: \(PublicBaseURL.get())/verify-email?token=\(token)"
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
            let sender = EmailSenderFactory.make(client: req.client, logger: req.logger)
            try? await sender.send(
                to: body.email,
                subject: "Reset your Ohana Belltown password",
                body: "Reset your password: \(PublicBaseURL.get())/reset-password.html?token=\(token) (expires in 1 hour)"
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

    app.post("api", "customer", "birthday") { req throws -> CustomerUserPublic in
        let customer = try requireCustomerLogin(req)
        let body = try req.content.decode(CustomerBirthdayRequest.self)
        return try CustomerUserStore.shared.updateBirthday(id: customer.id, birthday: body.birthday)
    }

    // Links this account to a phone-based punch card, so a signed-in
    // customer can see their rewards status without re-entering their phone.
    app.post("api", "customer", "loyalty-phone") { req throws -> CustomerUserPublic in
        let customer = try requireCustomerLogin(req)
        let body = try req.content.decode(CustomerLoyaltyPhoneRequest.self)
        return try CustomerUserStore.shared.updateLoyaltyPhone(id: customer.id, phone: body.phone)
    }

    // A customer's own past table orders (only ones placed while signed in
    // have a customerId — ordering never requires being logged in).
    app.get("api", "customer", "order-history") { req throws -> [TableOrderEntry] in
        let customer = try requireCustomerLogin(req)
        return try TableOrdersStore.shared.ordersForCustomer(customerId: customer.id)
    }

    app.get("api", "customer", "loyalty") { req throws -> CustomerLoyaltyView in
        let customer = try requireCustomerLogin(req)
        guard let phone = customer.loyaltyPhone else {
            return CustomerLoyaltyView(linkedPhone: nil, status: nil)
        }
        return CustomerLoyaltyView(linkedPhone: phone, status: try? LoyaltyStore.shared.lookup(phone: phone))
    }

    // Staff-facing — who has a birthday coming up, so a server can treat them.
    app.get("api", "customer", "birthdays-upcoming") { req throws -> [CustomerUserPublic] in
        try requireLogin(req)
        let days = req.query[Int.self, at: "days"] ?? 7
        return try CustomerUserStore.shared.upcomingBirthdays(withinDays: days)
    }
}
