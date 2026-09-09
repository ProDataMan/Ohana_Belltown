import Vapor

struct LoginRequest: Content {
    var username: String
    var password: String
}

struct BootstrapRequest: Content {
    var username: String
    var displayName: String
    var password: String
}

struct CreateUserRequest: Content {
    var username: String
    var displayName: String
    var password: String
    var role: UserRole
}

struct ChangePasswordRequest: Content {
    var currentPassword: String
    var newPassword: String
}

struct ResetPasswordRequest: Content {
    var newPassword: String
}

struct UpdateEmailRequest: Content {
    var email: String?
}

struct UpdateStaffBirthdayRequest: Content {
    var birthday: String?
}

struct UpdateStaffPhoneRequest: Content {
    var phone: String?
}

struct UpdateRoleRequest: Content {
    var role: UserRole
}

struct UpdateDisplayNameRequest: Content {
    var displayName: String
}

func currentUser(_ req: Request) throws -> StaffUser? {
    guard let userId = req.session.data["userId"] else { return nil }
    return try? UserStore.shared.find(id: userId)
}

@discardableResult
func requireLogin(_ req: Request) throws -> StaffUser {
    guard let user = try currentUser(req) else {
        throw Abort(.unauthorized, reason: "Please log in.")
    }
    return user
}

@discardableResult
func requireAdmin(_ req: Request) throws -> StaffUser {
    let user = try requireLogin(req)
    guard user.role == .admin else {
        throw Abort(.forbidden, reason: "Admin access required.")
    }
    return user
}

/// Like requireLogin, but excludes .entertainmentProvider — use this (not
/// requireLogin) for every staff route that isn't specifically entertainment
/// booking management, its photo/video upload, or a staff member's own
/// account fields. entertainmentProvider is a deliberately narrow role for
/// outside performers/promoters; requireLogin alone would let it reach
/// everything a regular employee can.
@discardableResult
func requireStaffAccess(_ req: Request) throws -> StaffUser {
    let user = try requireLogin(req)
    guard user.role != .entertainmentProvider else {
        throw Abort(.forbidden, reason: "This account can only manage entertainment bookings.")
    }
    return user
}

/// Pages an entertainmentProvider account may still view even though
/// they're blocked from every other adminOnly:false staff page — their own
/// tool plus basic self-service (account/password/help).
private let entertainmentProviderAllowedPages: Set<String> = [
    "entertainment-admin.html", "account.html", "change-password.html", "help.html",
]

func serveStaffPage(_ req: Request, file: String, adminOnly: Bool = false) async throws -> Response {
    guard let user = try currentUser(req) else {
        return req.redirect(to: "/login?next=\(req.url.path)")
    }
    if adminOnly && user.role != .admin {
        throw Abort(.forbidden, reason: "Admin access required.")
    }
    let pageBasename = file.split(separator: "/").last.map(String.init) ?? file
    if user.role == .entertainmentProvider, !entertainmentProviderAllowedPages.contains(pageBasename) {
        throw Abort(.forbidden, reason: "This account can only manage entertainment bookings.")
    }
    let path = req.application.directory.publicDirectory + file
    return try await req.fileio.asyncStreamFile(at: path)
}

struct SetupStatus: Content {
    var needsSetup: Bool
}

func registerAuthRoutes(_ app: Application) throws {
    app.get("login") { req async throws -> Response in
        let path = req.application.directory.publicDirectory + "staff/login.html"
        return try await req.fileio.asyncStreamFile(at: path)
    }

    app.get("api", "auth", "setup-needed") { _ throws -> SetupStatus in
        SetupStatus(needsSetup: try UserStore.shared.all().isEmpty)
    }

    app.post("api", "auth", "bootstrap") { req throws -> StaffUserPublic in
        let body = try req.content.decode(BootstrapRequest.self)
        let user = try UserStore.shared.bootstrapFirstAdmin(
            username: body.username, displayName: body.displayName, password: body.password
        )
        req.session.data["userId"] = user.id
        return user
    }

    app.post("api", "auth", "login") { req throws -> StaffUserPublic in
        let body = try req.content.decode(LoginRequest.self)
        let user = try UserStore.shared.authenticate(username: body.username, password: body.password)
        req.session.data["userId"] = user.id
        return StaffUserPublic(user)
    }

    app.post("api", "auth", "logout") { req -> HTTPStatus in
        req.session.destroy()
        return .ok
    }

    app.get("api", "auth", "me") { req throws -> StaffUserPublic in
        guard let user = try currentUser(req) else {
            throw Abort(.unauthorized)
        }
        return StaffUserPublic(user)
    }

    app.post("api", "account", "change-password") { req throws -> StaffUserPublic in
        let user = try requireLogin(req)
        let body = try req.content.decode(ChangePasswordRequest.self)
        return try UserStore.shared.changePassword(
            id: user.id, currentPassword: body.currentPassword, newPassword: body.newPassword
        )
    }

    app.post("api", "account", "email") { req throws -> StaffUserPublic in
        let user = try requireLogin(req)
        let body = try req.content.decode(UpdateEmailRequest.self)
        return try UserStore.shared.updateEmail(id: user.id, email: body.email)
    }

    app.post("api", "account", "birthday") { req throws -> StaffUserPublic in
        let user = try requireLogin(req)
        let body = try req.content.decode(UpdateStaffBirthdayRequest.self)
        return try UserStore.shared.updateBirthday(id: user.id, birthday: body.birthday)
    }

    app.post("api", "account", "phone") { req throws -> StaffUserPublic in
        let user = try requireLogin(req)
        let body = try req.content.decode(UpdateStaffPhoneRequest.self)
        return try UserStore.shared.updatePhone(id: user.id, phone: body.phone)
    }

    app.get("api", "users") { req throws -> [StaffUserPublic] in
        try requireAdmin(req)
        return try UserStore.shared.all()
    }

    app.post("api", "users") { req throws -> StaffUserPublic in
        try requireAdmin(req)
        let body = try req.content.decode(CreateUserRequest.self)
        return try UserStore.shared.create(
            username: body.username, displayName: body.displayName,
            password: body.password, role: body.role, mustChangePassword: true
        )
    }

    app.post("api", "users", ":id", "reset-password") { req throws -> StaffUserPublic in
        try requireAdmin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        let body = try req.content.decode(ResetPasswordRequest.self)
        return try UserStore.shared.adminResetPassword(id: id, newPassword: body.newPassword)
    }

    app.post("api", "users", ":id", "role") { req throws -> StaffUserPublic in
        try requireAdmin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        let body = try req.content.decode(UpdateRoleRequest.self)
        return try UserStore.shared.updateRole(id: id, role: body.role)
    }

    app.post("api", "users", ":id", "display-name") { req throws -> StaffUserPublic in
        try requireAdmin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        let body = try req.content.decode(UpdateDisplayNameRequest.self)
        return try UserStore.shared.updateDisplayName(id: id, displayName: body.displayName)
    }

    app.post("api", "users", ":id", "deactivate") { req throws -> StaffUserPublic in
        let admin = try requireAdmin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        return try UserStore.shared.deactivate(id: id, requestedBy: admin.id)
    }

    app.post("api", "users", ":id", "reactivate") { req throws -> StaffUserPublic in
        try requireAdmin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        return try UserStore.shared.reactivate(id: id)
    }
}
