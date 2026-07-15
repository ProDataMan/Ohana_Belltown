import Vapor

struct PhoneRequest: Content {
    var phone: String
}

struct BonusClaimRequest: Content {
    var phone: String
    var type: String
    var content: String
    var note: String?
}

struct BonusReviewRequest: Content {
    var approve: Bool
}

func requireStaffPin(_ req: Request) throws {
    guard let expected = Environment.get("STAFF_PIN"), !expected.isEmpty else {
        throw Abort(.internalServerError, reason: "Staff PIN is not configured on this server.")
    }
    guard let provided = req.headers.first(name: "X-Staff-Pin"), provided == expected else {
        throw Abort(.unauthorized, reason: "Staff PIN required.")
    }
}

func routes(_ app: Application) throws {
    app.get("healthz") { _ in "ok" }

    app.get("api", "menu") { _ throws -> Menu in
        try MenuStore.shared.get()
    }

    app.put("api", "menu") { req throws -> Menu in
        let incoming = try req.content.decode(Menu.self)
        return try MenuStore.shared.save(incoming)
    }

    app.on(.POST, "api", "upload", body: .collect(maxSize: "8mb")) { req throws -> UploadResponse in
        let upload = try req.content.decode(ImageUpload.self)
        let allowedExtensions = ["jpg", "jpeg", "png", "webp", "gif"]
        let ext = (upload.image.extension ?? "").lowercased()
        guard allowedExtensions.contains(ext) else {
            throw Abort(.unsupportedMediaType, reason: "Only jpg, png, webp, or gif images are allowed.")
        }
        guard let data = upload.image.data.getData(
            at: upload.image.data.readerIndex,
            length: upload.image.data.readableBytes
        ) else {
            throw Abort(.badRequest)
        }
        let filename = UUID().uuidString + "." + ext
        try data.write(to: URL(fileURLWithPath: Uploads.directory + filename))
        return UploadResponse(url: "/uploads/\(filename)")
    }

    app.get("uploads", ":filename") { req async throws -> Response in
        guard let filename = req.parameters.get("filename"), !filename.contains("..") else {
            throw Abort(.badRequest)
        }
        return try await req.fileio.asyncStreamFile(at: Uploads.directory + filename)
    }

    registerPlacesPhotoRoutes(app)

    app.get("api", "events") { _ throws -> EventsList in
        try EventsStore.shared.get()
    }

    app.put("api", "events") { req throws -> EventsList in
        try requireStaffPin(req)
        let incoming = try req.content.decode(EventsList.self)
        return try EventsStore.shared.save(incoming)
    }

    app.post("api", "loyalty", "lookup") { req throws -> LoyaltyStatus in
        let body = try req.content.decode(PhoneRequest.self)
        return try LoyaltyStore.shared.lookup(phone: body.phone)
    }

    app.post("api", "loyalty", "bonus-request") { req throws -> BonusRequest in
        let body = try req.content.decode(BonusClaimRequest.self)
        guard ["photo", "social"].contains(body.type) else {
            throw Abort(.badRequest, reason: "type must be 'photo' or 'social'")
        }
        return try LoyaltyStore.shared.submitBonusRequest(
            phone: body.phone, type: body.type, content: body.content, note: body.note
        )
    }

    app.post("api", "loyalty", "punch") { req throws -> LoyaltyStatus in
        try requireStaffPin(req)
        let body = try req.content.decode(PhoneRequest.self)
        return try LoyaltyStore.shared.addPunch(phone: body.phone)
    }

    app.post("api", "loyalty", "redeem") { req throws -> LoyaltyStatus in
        try requireStaffPin(req)
        let body = try req.content.decode(PhoneRequest.self)
        return try LoyaltyStore.shared.redeem(phone: body.phone)
    }

    app.get("api", "loyalty", "customers") { req throws -> [LoyaltyCustomer] in
        try requireStaffPin(req)
        return try LoyaltyStore.shared.allCustomers()
    }

    app.get("api", "loyalty", "bonus-requests") { req throws -> [BonusRequest] in
        try requireStaffPin(req)
        return try LoyaltyStore.shared.allBonusRequests()
    }

    app.post("api", "loyalty", "bonus-requests", ":id", "review") { req throws -> BonusRequest in
        try requireStaffPin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        let body = try req.content.decode(BonusReviewRequest.self)
        return try LoyaltyStore.shared.reviewBonusRequest(id: id, approve: body.approve)
    }

    func serveStatic(_ req: Request, file: String) async throws -> Response {
        let path = req.application.directory.publicDirectory + file
        return try await req.fileio.asyncStreamFile(at: path)
    }

    let cleanPages: [(String, String)] = [
        ("menu", "pages/menu.html"),
        ("sushi", "pages/sushi.html"),
        ("drinks", "pages/drinks.html"),
        ("happy-hour", "pages/happy-hour.html"),
        ("local", "pages/local.html"),
        ("about", "pages/about.html"),
        ("catering", "pages/catering.html"),
        ("contact", "pages/contact.html"),
        ("rewards", "pages/rewards.html"),
    ]
    for (route, file) in cleanPages {
        app.get(PathComponent(stringLiteral: route)) { req in
            try await serveStatic(req, file: file)
        }
    }

    let legacyRedirects: [(String, String)] = [
        ("menu.html", "/menu"),
        ("sushi.html", "/sushi"),
        ("drinks.html", "/drinks"),
        ("happy-hour.html", "/happy-hour"),
        ("local.html", "/local"),
        ("about-ohanas.html", "/about"),
        ("contact.html", "/contact"),
    ]
    for (legacyPath, target) in legacyRedirects {
        app.get(PathComponent(stringLiteral: legacyPath)) { req in
            req.redirect(to: target, redirectType: .permanent)
        }
    }
}
