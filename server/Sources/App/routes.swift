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

struct WaitlistJoinRequest: Content {
    var name: String
    var phone: String
    var partySize: Int
    var note: String?
}

struct ItemViewRequest: Content {
    var name: String
}

struct DwellRequest: Content {
    var path: String
    var seconds: Double
}

struct MenuItemUpdateRequest: Content {
    var name: String
    var description: String?
    var price: Double?
    var images: [String]
    var tags: [String]
    var featured: Bool
    var available: Bool
    var happyHour: Bool
}

func routes(_ app: Application) throws {
    try registerAuthRoutes(app)
    try registerCustomerAuthRoutes(app)
    try registerOAuthRoutes(app)

    app.get("healthz") { _ in "ok" }

    app.get("api", "menu") { _ throws -> Menu in
        try MenuStore.shared.get()
    }

    app.put("api", "menu") { req throws -> Menu in
        try requireLogin(req)
        let incoming = try req.content.decode(Menu.self)
        return try MenuStore.shared.save(incoming)
    }

    app.get("api", "menu", "items", ":id") { req throws -> MenuItemLocation in
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        return try MenuStore.shared.findItem(id: id)
    }

    app.on(.PATCH, "api", "menu", "items", ":id") { req throws -> MenuItem in
        try requireLogin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        let body = try req.content.decode(MenuItemUpdateRequest.self)
        return try MenuStore.shared.updateItem(id: id) { item in
            item.name = body.name
            item.description = body.description
            item.price = body.price
            item.images = body.images
            item.tags = body.tags
            item.featured = body.featured
            item.available = body.available
            item.happyHour = body.happyHour
        }
    }

    app.on(.DELETE, "api", "menu", "items", ":id") { req throws -> HTTPStatus in
        try requireLogin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        try MenuStore.shared.deleteItem(id: id)
        return .noContent
    }

    app.on(.POST, "api", "upload", body: .collect(maxSize: "8mb")) { req async throws -> UploadResponse in
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
        let path = Uploads.directory + filename
        try data.write(to: URL(fileURLWithPath: path))
        if ImageOptimizer.optimizableExtensions.contains(ext) {
            try await ImageOptimizer.optimize(at: path, on: req.application)
        }
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
        try requireAdmin(req)
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
        try requireLogin(req)
        let body = try req.content.decode(PhoneRequest.self)
        return try LoyaltyStore.shared.addPunch(phone: body.phone)
    }

    app.post("api", "loyalty", "redeem") { req throws -> LoyaltyStatus in
        try requireLogin(req)
        let body = try req.content.decode(PhoneRequest.self)
        return try LoyaltyStore.shared.redeem(phone: body.phone)
    }

    app.get("api", "loyalty", "customers") { req throws -> [LoyaltyCustomer] in
        try requireLogin(req)
        return try LoyaltyStore.shared.allCustomers()
    }

    app.get("api", "loyalty", "bonus-requests") { req throws -> [BonusRequest] in
        try requireLogin(req)
        return try LoyaltyStore.shared.allBonusRequests()
    }

    app.post("api", "loyalty", "bonus-requests", ":id", "review") { req throws -> BonusRequest in
        try requireLogin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        let body = try req.content.decode(BonusReviewRequest.self)
        return try LoyaltyStore.shared.reviewBonusRequest(id: id, approve: body.approve)
    }

    app.post("api", "waitlist", "join") { req throws -> WaitlistEntry in
        let body = try req.content.decode(WaitlistJoinRequest.self)
        guard body.partySize > 0 else {
            throw Abort(.badRequest, reason: "Party size must be at least 1.")
        }
        return try WaitlistStore.shared.join(
            name: body.name, phone: body.phone, partySize: body.partySize, note: body.note
        )
    }

    app.get("api", "waitlist") { req throws -> [WaitlistEntry] in
        try requireLogin(req)
        return try WaitlistStore.shared.active()
    }

    app.post("api", "waitlist", ":id", "notify") { req throws -> WaitlistEntry in
        try requireLogin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        return try WaitlistStore.shared.markNotified(id: id)
    }

    app.post("api", "waitlist", ":id", "remove") { req throws -> WaitlistEntry in
        try requireLogin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        return try WaitlistStore.shared.remove(id: id)
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
        ("specials", "pages/specials.html"),
        ("gallery", "pages/gallery.html"),
        ("privacy", "pages/privacy.html"),
        ("terms", "pages/terms.html"),
        ("waitlist", "pages/waitlist.html"),
    ]
    for (route, file) in cleanPages {
        app.get(PathComponent(stringLiteral: route)) { req in
            try await serveStatic(req, file: file)
        }
    }

    let staffPages: [(String, String, Bool)] = [
        ("edit.html", "staff/edit.html", false),
        ("edit-item.html", "staff/edit-item.html", false),
        ("loyalty-admin.html", "staff/loyalty-admin.html", false),
        ("waitlist-admin.html", "staff/waitlist-admin.html", false),
        ("events-admin.html", "staff/events-admin.html", true),
        ("account.html", "staff/account.html", false),
        ("change-password.html", "staff/change-password.html", false),
        ("create-account.html", "staff/create-account.html", true),
        ("manage-users.html", "staff/manage-users.html", true),
        ("analytics.html", "staff/analytics.html", true),
    ]
    for (route, file, adminOnly) in staffPages {
        app.get(PathComponent(stringLiteral: route)) { req in
            try await serveStaffPage(req, file: file, adminOnly: adminOnly)
        }
    }

    app.get("api", "analytics", "summary") { req throws -> AnalyticsSummary in
        try requireAdmin(req)
        let days = req.query[Int.self, at: "days"] ?? 30
        return try AnalyticsStore.shared.summary(days: days)
    }

    app.post("api", "analytics", "item-view") { req throws -> HTTPStatus in
        let body = try req.content.decode(ItemViewRequest.self)
        let name = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .ok }
        AnalyticsStore.shared.recordItemView(name: name)
        return .ok
    }

    app.post("api", "analytics", "dwell") { req throws -> HTTPStatus in
        let body = try req.content.decode(DwellRequest.self)
        AnalyticsStore.shared.recordDwell(path: body.path, seconds: body.seconds)
        return .ok
    }

    // Most-viewed items over a rolling window, cross-referenced against the
    // live menu so removed or 86'd items never show up here. This is a
    // "what are people looking at" signal, not a sales figure — there's no
    // real order data available to this site (ordering happens via ChowNow).
    app.get("api", "analytics", "popular-items") { req throws -> [MenuItem] in
        let days = req.query[Int.self, at: "days"] ?? 30
        let limit = req.query[Int.self, at: "limit"] ?? 6
        let candidateNames = try AnalyticsStore.shared.topItemNames(days: days, limit: limit * 3)
        let menu = try MenuStore.shared.get()
        var results: [MenuItem] = []
        for name in candidateNames {
            guard results.count < limit else { break }
            for category in menu.categories {
                if let item = category.items.first(where: { $0.name == name && $0.available != false }) {
                    results.append(item)
                    break
                }
            }
        }
        return results
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
