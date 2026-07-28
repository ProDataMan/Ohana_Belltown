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

struct TableOrderRequest: Content {
    var tableId: String
    var itemName: String
    var itemId: String?
    var section: String?
    var modifiers: [String]?
}

struct TableOrdersDashboard: Content {
    var needsEntry: [TableOrderEntry]
    var awaitingDelivery: [TableOrderEntry]
    var readyCount: Int
}

struct StaffRewardAwardRequest: Content {
    var staffId: String
    var category: String
    var note: String?
}

struct StaffRewardSelfReportRequest: Content {
    var category: String
    var note: String?
}

struct FeedbackSubmission: Content {
    var category: String
    var rating: Int?
    var message: String
    var page: String?
    var contactEmail: String?
}

struct FeedbackUnacknowledgedCount: Content {
    var count: Int
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
    var modifiers: [MenuItemModifier]?
}

func routes(_ app: Application) throws {
    try registerAuthRoutes(app)
    try registerCustomerAuthRoutes(app)
    try registerOAuthRoutes(app)

    app.get("healthz") { _ in "ok" }

    // QR-code smart landing: sends whoever scans the table-card straight to
    // Happy Hour during the window, otherwise the full menu. A per-table QR
    // also carries a `table` id, which rides along on the redirect so the
    // menu page can show a per-item Order button tied to that table.
    app.get("scan") { req in
        var target = HappyHourSchedule.landingPath()
        if let table = req.query[String.self, at: "table"]?.trimmingCharacters(in: .whitespacesAndNewlines), !table.isEmpty,
           let encoded = table.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            target += "?table=\(encoded)"
        }
        return req.redirect(to: target, redirectType: .normal)
    }

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
        let staff = try requireLogin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        let body = try req.content.decode(MenuItemUpdateRequest.self)
        let before = try? MenuStore.shared.findItem(id: id).item
        let updated = try MenuStore.shared.updateItem(id: id) { item in
            item.name = body.name
            item.description = body.description
            item.price = body.price
            item.images = body.images
            item.tags = body.tags
            item.featured = body.featured
            item.available = body.available
            item.modifiers = body.modifiers ?? []
            item.happyHour = body.happyHour
        }
        StaffRewardsStore.shared.awardForMenuEdit(staffId: staff.id, before: before, after: updated)
        return updated
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

    app.on(.DELETE, "api", "uploads", ":filename") { req throws -> HTTPStatus in
        try requireLogin(req)
        guard let filename = req.parameters.get("filename"), !filename.contains("..") else {
            throw Abort(.badRequest)
        }
        // Refuse to delete a photo still in use — callers must repoint every
        // referencing menu item at a replacement first (see MenuStore.get()).
        let url = "/uploads/\(filename)"
        let menu = try MenuStore.shared.get()
        let stillReferenced = menu.categories.contains { category in
            category.items.contains { $0.images.contains(url) }
        }
        guard !stillReferenced else {
            throw Abort(.conflict, reason: "This photo is still used by a menu item — remove or repoint it first.")
        }
        let path = Uploads.directory + filename
        guard FileManager.default.fileExists(atPath: path) else {
            throw Abort(.notFound)
        }
        try FileManager.default.removeItem(atPath: path)
        return .noContent
    }

    registerPlacesPhotoRoutes(app)

    app.get("api", "events") { _ throws -> EventsList in
        try EventsStore.shared.get()
    }

    app.put("api", "events") { req throws -> EventsList in
        let admin = try requireAdmin(req)
        let beforeIds = Set((try? EventsStore.shared.get().events.map(\.id)) ?? [])
        let incoming = try req.content.decode(EventsList.self)
        let saved = try EventsStore.shared.save(incoming)
        if saved.events.contains(where: { !beforeIds.contains($0.id) }) {
            try? StaffRewardsStore.shared.award(staffId: admin.id, category: "event", note: nil, awardedBy: nil)
        }
        return saved
    }

    // Staff rewards: a punch card earned by keeping the site itself up to
    // date (photos, prices, specials on menu-item edits; new events), plus
    // manual admin grants for anything that can't be auto-detected (a
    // social media post, going above and beyond, etc.).
    app.get("api", "staff-rewards", "me") { req throws -> StaffRewardStatus in
        let staff = try requireLogin(req)
        return try StaffRewardsStore.shared.status(staffId: staff.id)
    }

    app.get("api", "staff-rewards") { req throws -> [StaffRewardCard] in
        try requireAdmin(req)
        return try StaffRewardsStore.shared.allCards()
    }

    app.get("api", "staff-rewards", "events") { req throws -> [StaffRewardEvent] in
        try requireAdmin(req)
        let limit = req.query[Int.self, at: "limit"] ?? 50
        return try StaffRewardsStore.shared.recentEvents(limit: limit)
    }

    app.post("api", "staff-rewards", "log") { req throws -> StaffRewardStatus in
        let staff = try requireLogin(req)
        let body = try req.content.decode(StaffRewardSelfReportRequest.self)
        return try StaffRewardsStore.shared.selfReport(staffId: staff.id, category: body.category, note: body.note)
    }

    app.post("api", "staff-rewards", "award") { req throws -> StaffRewardStatus in
        let admin = try requireAdmin(req)
        let body = try req.content.decode(StaffRewardAwardRequest.self)
        return try StaffRewardsStore.shared.award(
            staffId: body.staffId, category: body.category, note: body.note, awardedBy: admin.id
        )
    }

    app.post("api", "staff-rewards", ":staffId", "redeem") { req throws -> StaffRewardStatus in
        try requireAdmin(req)
        guard let staffId = req.parameters.get("staffId") else { throw Abort(.badRequest) }
        return try StaffRewardsStore.shared.redeem(staffId: staffId, note: req.query[String.self, at: "note"])
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

    // A "table order" just flags staff that a dine-in guest tapped Order next
    // to a menu item while scanned in from a numbered table — not routed
    // through ChowNow or any payment system, just a heads-up to go take it.
    // Lifecycle: pending (just placed) -> entered (staff checked with the
    // table and entered it into the order system) -> delivered.
    app.post("api", "table-orders") { req throws -> TableOrderEntry in
        let body = try req.content.decode(TableOrderRequest.self)
        let tableId = body.tableId.trimmingCharacters(in: .whitespacesAndNewlines)
        let itemName = body.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tableId.isEmpty, !itemName.isEmpty else {
            throw Abort(.badRequest, reason: "Table ID and item name are required.")
        }
        let customerId = try? currentCustomer(req)?.id
        return try TableOrdersStore.shared.place(
            tableId: tableId, itemName: itemName, itemId: body.itemId, section: body.section, customerId: customerId,
            modifiers: body.modifiers ?? []
        )
    }

    app.get("api", "table-map") { _ throws -> [TableMapEntry] in
        TableMap.entries
    }

    app.get("api", "table-orders", "dashboard") { req throws -> TableOrdersDashboard in
        try requireLogin(req)
        return try TableOrdersDashboard(
            needsEntry: TableOrdersStore.shared.needsEntry(),
            awaitingDelivery: TableOrdersStore.shared.awaitingDelivery(),
            readyCount: TableOrdersStore.shared.readyForDeliveryCount()
        )
    }

    app.post("api", "table-orders", ":id", "enter") { req throws -> TableOrderEntry in
        try requireLogin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        let staffOnDuty = try StaffingStore.shared.get().staffOnDuty
        return try TableOrdersStore.shared.markEntered(id: id, staffOnDuty: staffOnDuty)
    }

    // Public — either staff (from the admin queue) or the customer
    // themselves (a "Mark Received" tap on the menu page) can confirm this.
    app.post("api", "table-orders", ":id", "deliver") { req throws -> TableOrderEntry in
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        return try TableOrdersStore.shared.markDelivered(id: id)
    }

    app.get("api", "table-orders", "delivery-stats") { req throws -> DeliveryStatsSummary in
        try requireLogin(req)
        let days = req.query[Int.self, at: "days"] ?? 30
        return try TableOrdersStore.shared.deliveryStats(days: days)
    }

    app.get("api", "table-orders", "staffing") { req throws -> StaffingConfig in
        try requireLogin(req)
        return try StaffingStore.shared.get()
    }

    app.post("api", "table-orders", "staffing") { req throws -> StaffingConfig in
        try requireLogin(req)
        let body = try req.content.decode(StaffingConfig.self)
        return try StaffingStore.shared.setStaffOnDuty(body.staffOnDuty)
    }

    // Feedback: a widget on every public page lets a guest leave feedback on
    // the website, food, or service without needing an account.
    app.post("api", "feedback") { req throws -> FeedbackEntry in
        let body = try req.content.decode(FeedbackSubmission.self)
        let message = body.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            throw Abort(.badRequest, reason: "Feedback message can't be empty.")
        }
        let category = ["website", "food", "service", "other"].contains(body.category) ? body.category : "other"
        if let rating = body.rating {
            guard (1...5).contains(rating) else {
                throw Abort(.badRequest, reason: "Rating must be between 1 and 5.")
            }
        }
        // A logged-in customer or staff member's account email is more
        // trustworthy than a free-text field, so it wins over whatever
        // (if anything) was typed into the optional email box.
        let loggedInEmail = try currentCustomer(req)?.email ?? currentUser(req)?.email
        return try FeedbackStore.shared.submit(
            category: category, rating: body.rating, message: message,
            page: body.page, contactEmail: loggedInEmail ?? body.contactEmail
        )
    }

    app.get("api", "feedback") { req throws -> [FeedbackEntry] in
        try requireLogin(req)
        let days = req.query[Int.self, at: "days"] ?? 30
        return try FeedbackStore.shared.recent(days: days)
    }

    app.get("api", "feedback", "unacknowledged-count") { req throws -> FeedbackUnacknowledgedCount in
        try requireLogin(req)
        return FeedbackUnacknowledgedCount(count: try FeedbackStore.shared.unacknowledgedCount())
    }

    app.post("api", "feedback", "acknowledge-all") { req throws -> HTTPStatus in
        try requireLogin(req)
        try FeedbackStore.shared.acknowledgeAll()
        return .ok
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
        ("faq", "pages/faq.html"),
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
        ("table-orders-admin.html", "staff/table-orders-admin.html", false),
        ("events-admin.html", "staff/events-admin.html", true),
        ("account.html", "staff/account.html", false),
        ("change-password.html", "staff/change-password.html", false),
        ("create-account.html", "staff/create-account.html", true),
        ("manage-users.html", "staff/manage-users.html", true),
        ("analytics.html", "staff/analytics.html", true),
        ("staff-rewards-admin.html", "staff/staff-rewards-admin.html", true),
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
