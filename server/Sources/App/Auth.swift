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

struct UpdateRoleRequest: Content {
    var role: UserRole
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

func serveStaffPage(_ req: Request, file: String, adminOnly: Bool = false) async throws -> Response {
    guard let user = try currentUser(req) else {
        return req.redirect(to: "/login?next=\(req.url.path)")
    }
    if adminOnly && user.role != .admin {
        throw Abort(.forbidden, reason: "Admin access required.")
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
}
