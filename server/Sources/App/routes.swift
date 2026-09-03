import Vapor

struct PhoneRequest: Content {
    var phone: String
}

struct BonusClaimRequest: Content {
    var phone: String
    var type: String
    var content: String
    var note: String?
    var menuItemId: String?
    var menuItemName: String?
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

struct CancelOrderRequest: Content {
    var reason: String?
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

struct StaffRewardRedeemRequest: Content {
    var catalogItemId: String
    var note: String?
}

struct StaffSocialRequestSubmission: Content {
    var link: String
    var note: String?
}

struct StaffRewardReviewRequest: Content {
    var approve: Bool
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

struct CompetitorUnreviewedPhotoCount: Content {
    var count: Int
}

struct MarkPhotoReviewedRequest: Content {
    var url: String
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
    var choiceGroups: [MenuItemChoiceGroup]?
    var requiresModifierSelection: Bool?
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
        var queryParts: [String] = []
        if let table = req.query[String.self, at: "table"]?.trimmingCharacters(in: .whitespacesAndNewlines), !table.isEmpty,
           let encoded = table.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryParts.append("table=\(encoded)")
        }
        // The front-door "browse the menu while you wait" QR — real prices,
        // still no table, so no ordering UI unlocks. See getPriceViewFlag()
        // in menu-section.js.
        if req.query[String.self, at: "prices"] == "1" {
            queryParts.append("prices=1")
        }
        if !queryParts.isEmpty {
            target += "?" + queryParts.joined(separator: "&")
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

    // Reusable add-on definitions staff pick from when adding a modifier to
    // any item, instead of retyping the same name/price every time.
    app.get("api", "additions-catalog") { req throws -> [AdditionCatalogItem] in
        try requireLogin(req)
        return try MenuStore.shared.additionsCatalog()
    }

    app.put("api", "additions-catalog") { req throws -> [AdditionCatalogItem] in
        try requireLogin(req)
        let items = try req.content.decode([AdditionCatalogItem].self)
        return try MenuStore.shared.saveAdditionsCatalog(items)
    }

    // One-click "scan the menu for add-ons already written into item
    // descriptions" — seeds the shared catalog and adds matching modifiers
    // to whichever known items don't already have them. Idempotent.
    app.post("api", "menu", "seed-additions") { req throws -> SeedAdditionsResult in
        try requireLogin(req)
        return try MenuStore.shared.seedCommonAdditions()
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
            item.choiceGroups = body.choiceGroups ?? []
            item.requiresModifierSelection = body.requiresModifierSelection ?? false
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

    // maxSize raised from the original 8mb — real phone photos (especially
    // newer high-res cameras) routinely land in the 8-15mb range and were
    // getting a bare 413, which is what staff were seeing as "upload failed."
    app.on(.POST, "api", "upload", body: .collect(maxSize: "20mb")) { req async throws -> UploadResponse in
        let upload = try req.content.decode(ImageUpload.self)
        let allowedExtensions = ["jpg", "jpeg", "png", "webp", "gif", "heic", "heif"]
        let ext = (upload.image.extension ?? "").lowercased()
        guard allowedExtensions.contains(ext) else {
            throw Abort(.unsupportedMediaType, reason: "Only jpg, png, webp, gif, or heic/heif images are allowed.")
        }
        guard let data = upload.image.data.getData(
            at: upload.image.data.readerIndex,
            length: upload.image.data.readableBytes
        ) else {
            throw Abort(.badRequest)
        }
        // Shared by staff menu-photo uploads and anonymous customer
        // loyalty-bonus-claim photos — record whoever's actually logged in,
        // nil for a guest, rather than requiring login on a route customers
        // also use.
        let uploaderName = (try? currentUser(req)).flatMap { $0 }?.displayName

        // iPhones default to saving photos as HEIC, which no major browser
        // can render — convert to JPEG rather than save+link a file that
        // would just show up broken everywhere it's used.
        if ext == "heic" || ext == "heif" {
            let sourceFilename = UUID().uuidString + "." + ext
            let sourcePath = Uploads.directory + sourceFilename
            try data.write(to: URL(fileURLWithPath: sourcePath))
            let jpegFilename = UUID().uuidString + ".jpg"
            let jpegPath = Uploads.directory + jpegFilename
            let converted = try await ImageOptimizer.convertHEICToJPEG(sourcePath: sourcePath, outputPath: jpegPath, on: req.application)
            try? FileManager.default.removeItem(atPath: sourcePath)
            guard converted else {
                throw Abort(.unprocessableEntity, reason: "This photo couldn't be converted — try a JPEG or PNG instead.")
            }
            UploadMetadataStore.shared.record(filename: jpegFilename, uploadedByName: uploaderName)
            return UploadResponse(url: "/uploads/\(jpegFilename)")
        }

        let filename = UUID().uuidString + "." + ext
        let path = Uploads.directory + filename
        try data.write(to: URL(fileURLWithPath: path))
        if ImageOptimizer.optimizableExtensions.contains(ext) {
            try await ImageOptimizer.optimize(at: path, on: req.application)
        }
        UploadMetadataStore.shared.record(filename: filename, uploadedByName: uploaderName)
        return UploadResponse(url: "/uploads/\(filename)")
    }

    app.get("uploads", ":filename") { req async throws -> Response in
        guard let filename = req.parameters.get("filename"), !filename.contains("..") else {
            throw Abort(.badRequest)
        }
        return try await req.fileio.asyncStreamFile(at: Uploads.directory + filename)
    }

    // Backs the click-to-preview detail panel on the menu photo editors
    // (edit.html / edit-item.html) — resolution and file size are read live
    // off the file itself (no need to store them), date/uploader come from
    // UploadMetadataStore and are simply absent for anything uploaded before
    // that store existed.
    app.get("api", "uploads", ":filename", "info") { req async throws -> UploadInfo in
        try requireLogin(req)
        guard let filename = req.parameters.get("filename"), !filename.contains("..") else {
            throw Abort(.badRequest)
        }
        let path = Uploads.directory + filename
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            throw Abort(.notFound)
        }
        let sizeBytes = (attributes[.size] as? Int) ?? 0
        let dimensions = try await ImageOptimizer.dimensions(at: path, on: req.application)
        let metadata = UploadMetadataStore.shared.entry(for: filename)
        return UploadInfo(
            filename: filename,
            sizeBytes: sizeBytes,
            width: dimensions?.width,
            height: dimensions?.height,
            uploadedAt: metadata?.uploadedAt,
            uploadedByName: metadata?.uploadedByName
        )
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

    // The reward catalog — what points can actually be redeemed for. Staff
    // can see it (so they know what they're saving toward); only an admin
    // can change what's in it or set/update a point cost.
    app.get("api", "staff-rewards", "catalog") { req throws -> [RewardCatalogItem] in
        try requireLogin(req)
        return try StaffRewardsStore.shared.catalog()
    }

    app.put("api", "staff-rewards", "catalog") { req throws -> [RewardCatalogItem] in
        try requireAdmin(req)
        let items = try req.content.decode([RewardCatalogItem].self)
        return try StaffRewardsStore.shared.saveCatalog(items)
    }

    // How many points each category is worth — staff can see it (it's
    // already shown throughout the rewards pages); only an admin can change it.
    app.get("api", "staff-rewards", "point-values") { req throws -> [String: Int] in
        try requireLogin(req)
        return try StaffRewardsStore.shared.pointValues()
    }

    app.put("api", "staff-rewards", "point-values") { req throws -> [String: Int] in
        try requireAdmin(req)
        let values = try req.content.decode([String: Int].self)
        return try StaffRewardsStore.shared.savePointValues(values)
    }

    app.post("api", "staff-rewards", "log") { req throws -> StaffRewardStatus in
        let staff = try requireLogin(req)
        let body = try req.content.decode(StaffRewardSelfReportRequest.self)
        return try StaffRewardsStore.shared.selfReport(staffId: staff.id, category: body.category, note: body.note)
    }

    // Social media posts can't be auto-detected, so instead of an instant
    // self-report they go through a request/approval queue (mirroring the
    // customer loyalty bonus-request flow above) — a link is required, and
    // no points land until an admin approves it.
    app.post("api", "staff-rewards", "social-requests") { req throws -> StaffSocialRequest in
        let staff = try requireLogin(req)
        let body = try req.content.decode(StaffSocialRequestSubmission.self)
        return try StaffRewardsStore.shared.submitSocialRequest(staffId: staff.id, link: body.link, note: body.note)
    }

    app.get("api", "staff-rewards", "social-requests") { req throws -> [StaffSocialRequest] in
        try requireAdmin(req)
        return try StaffRewardsStore.shared.allSocialRequests()
    }

    app.post("api", "staff-rewards", "social-requests", ":id", "review") { req throws -> StaffSocialRequest in
        let admin = try requireAdmin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        let body = try req.content.decode(StaffRewardReviewRequest.self)
        return try StaffRewardsStore.shared.reviewSocialRequest(id: id, approve: body.approve, reviewerId: admin.id)
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
        let body = try req.content.decode(StaffRewardRedeemRequest.self)
        return try StaffRewardsStore.shared.redeem(staffId: staffId, catalogItemId: body.catalogItemId, note: body.note)
    }

    // Competitor menu-price comparison — entirely staff-curated (there's no
    // reliable live API for a competitor's actual published prices), admin
    // only since this is competitive pricing strategy, same gating as
    // /analytics.html itself.
    // Sources the restaurant list from Google Maps' own Nearby Search instead
    // of asking staff to type a name/address by hand — Google just doesn't
    // expose a competitor's actual menu prices, so that part still needs a
    // person to look at the competitor's own site/menu.
    app.get("api", "competitor-pricing", "nearby-restaurants") { req async throws -> [NearbyRestaurantCandidate] in
        try requireAdmin(req)
        guard let apiKey = Environment.get("GOOGLE_PLACES_API_KEY"), let placeId = Environment.get("GOOGLE_PLACE_ID") else {
            return []
        }
        let radiusMiles = req.query[Double.self, at: "radiusMiles"] ?? 3.0
        return try await CompetitorPricingStore.shared.nearbyRestaurants(client: req.client, apiKey: apiKey, placeId: placeId, radiusMiles: radiusMiles)
    }

    app.get("api", "competitor-pricing", "restaurants") { req throws -> [CompetitorRestaurant] in
        try requireAdmin(req)
        return try CompetitorPricingStore.shared.restaurants()
    }

    app.put("api", "competitor-pricing", "restaurants") { req throws -> [CompetitorRestaurant] in
        try requireAdmin(req)
        let items = try req.content.decode([CompetitorRestaurant].self)
        return try CompetitorPricingStore.shared.saveRestaurants(items)
    }

    app.get("api", "competitor-pricing", "groups") { req throws -> [MenuPriceComparisonGroup] in
        try requireAdmin(req)
        return try CompetitorPricingStore.shared.groups()
    }

    app.put("api", "competitor-pricing", "groups") { req throws -> [MenuPriceComparisonGroup] in
        try requireAdmin(req)
        let items = try req.content.decode([MenuPriceComparisonGroup].self)
        return try CompetitorPricingStore.shared.saveGroups(items)
    }

    app.get("api", "competitor-pricing", "entries") { req throws -> [CompetitorPriceEntry] in
        try requireAdmin(req)
        return try CompetitorPricingStore.shared.entries()
    }

    app.put("api", "competitor-pricing", "entries") { req throws -> [CompetitorPriceEntry] in
        try requireAdmin(req)
        let items = try req.content.decode([CompetitorPriceEntry].self)
        return try CompetitorPricingStore.shared.saveEntries(items)
    }

    app.get("api", "competitor-pricing", "report") { req throws -> [CompetitorPriceReportRow] in
        try requireAdmin(req)
        return try CompetitorPricingStore.shared.report()
    }

    // Drives the site-wide staff notification badge (nav.js) telling the
    // owner there are competitor menu photos still waiting to be read
    // (by a future Claude session, or by hand) for prices/dishes.
    app.get("api", "competitor-pricing", "unreviewed-photo-count") { req throws -> CompetitorUnreviewedPhotoCount in
        try requireAdmin(req)
        return CompetitorUnreviewedPhotoCount(count: CompetitorPhotoReviewStore.shared.unreviewedCount())
    }

    app.get("api", "competitor-pricing", "photos", "unreviewed") { req throws -> [String] in
        try requireAdmin(req)
        return CompetitorPhotoReviewStore.shared.unreviewedURLs()
    }

    app.post("api", "competitor-pricing", "photos", "mark-reviewed") { req throws -> HTTPStatus in
        let user = try requireAdmin(req)
        let body = try req.content.decode(MarkPhotoReviewedRequest.self)
        CompetitorPhotoReviewStore.shared.markReviewed(url: body.url, reviewedByName: user.displayName)
        return .noContent
    }

    // Whether ANTHROPIC_API_KEY is set — a separate credential from any
    // claude.ai chat subscription. The client uses this to decide whether
    // to show the "Extract Items with AI" button at all, same as how the
    // Apple/Facebook Sign-In buttons stay hidden until configured.
    app.get("api", "competitor-pricing", "ai-extraction-status") { req throws -> AIExtractionStatus in
        try requireAdmin(req)
        return AIExtractionStatus(available: Environment.get("ANTHROPIC_API_KEY") != nil)
    }

    app.post("api", "competitor-pricing", "extract-menu") { req async throws -> AnthropicMenuExtraction.ExtractionResult in
        try requireAdmin(req)
        guard let apiKey = Environment.get("ANTHROPIC_API_KEY") else {
            throw AnthropicMenuExtraction.ExtractionError.notConfigured
        }
        let body = try req.content.decode(MenuExtractionRequest.self)
        guard body.photoUrl.hasPrefix("/uploads/"), !body.photoUrl.contains("..") else {
            throw Abort(.badRequest)
        }
        let filename = String(body.photoUrl.dropFirst("/uploads/".count))
        let path = Uploads.directory + filename
        guard let imageData = FileManager.default.contents(atPath: path) else {
            throw Abort(.notFound, reason: "Photo not found.")
        }
        let ext = filename.split(separator: ".").last.map(String.init)?.lowercased() ?? ""
        let items = try await AnthropicMenuExtraction.extractItems(
            client: req.client, apiKey: apiKey, imageData: imageData, mediaType: AnthropicMenuExtraction.mediaType(forExtension: ext)
        )
        return AnthropicMenuExtraction.ExtractionResult(items: items)
    }

    // MARK: - Swag / Shop

    app.get("api", "swag", "products") { req throws -> [SwagProduct] in
        try SwagStore.shared.list()
    }

    app.put("api", "swag", "products") { req throws -> [SwagProduct] in
        try requireLogin(req)
        let items = try req.content.decode([SwagProduct].self)
        return try SwagStore.shared.save(items)
    }

    // Whether Square's checkout credentials are set — the Shop page uses
    // this to decide whether to offer checkout at all, same "hidden until
    // configured" pattern as AI menu extraction / Apple / Facebook sign-in.
    app.get("api", "swag", "checkout-status") { req throws -> SquareCheckoutStatus in
        let accessToken = Environment.get("SQUARE_ACCESS_TOKEN")
        let locationId = Environment.get("SQUARE_LOCATION_ID")
        return SquareCheckoutStatus(available: accessToken?.isEmpty == false && locationId?.isEmpty == false)
    }

    // Creates a pending SwagOrder from the customer's cart, then a Square
    // Checkout payment link for it, and hands back the URL to redirect to.
    // Requires a scanned table (same as food ordering) so staff know where
    // to deliver it once it's paid.
    app.post("api", "swag", "checkout") { req async throws -> SwagCheckoutResponse in
        guard let accessToken = Environment.get("SQUARE_ACCESS_TOKEN"), !accessToken.isEmpty,
              let locationId = Environment.get("SQUARE_LOCATION_ID"), !locationId.isEmpty else {
            throw SwagError.checkoutNotConfigured
        }
        let body = try req.content.decode(SwagCheckoutRequest.self)
        let tableId = body.tableId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tableId.isEmpty, !body.items.isEmpty else {
            throw Abort(.badRequest, reason: "A table and at least one item are required.")
        }

        let productsById = Dictionary(uniqueKeysWithValues: try SwagStore.shared.list().map { ($0.id, $0) })
        var orderItems: [SwagOrderItem] = []
        for requested in body.items {
            guard requested.quantity > 0 else { continue }
            guard let product = productsById[requested.productId], product.available else {
                throw Abort(.badRequest, reason: "One of the items in your cart is no longer available.")
            }
            orderItems.append(SwagOrderItem(productId: product.id, name: product.name, price: product.price, quantity: requested.quantity))
        }
        guard !orderItems.isEmpty else { throw SwagError.emptyCart }

        let customerId = try? currentCustomer(req)?.id
        let order = try SwagOrdersStore.shared.createPendingOrder(tableId: tableId, customerId: customerId, items: orderItems)

        let base = PublicBaseURL.get()
        let encodedTable = tableId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tableId
        let link = try await SquareCheckout.createPaymentLink(
            client: req.client, accessToken: accessToken, locationId: locationId, orderId: order.id,
            items: orderItems.map { SquareCheckout.LineItemInput(name: $0.name, quantity: $0.quantity, priceCents: Int(($0.price * 100).rounded())) },
            metadata: ["tableId": tableId],
            redirectURL: "\(base)/shop?table=\(encodedTable)&checkout=success"
        )
        try SwagOrdersStore.shared.attachSquareOrderId(orderId: order.id, squareOrderId: link.squareOrderId)
        return SwagCheckoutResponse(checkoutURL: link.url)
    }

    // Square calls this once a payment actually completes — this is the
    // only place a SwagOrder/GiftCardOrder gets marked "paid," never the
    // client redirect (a customer can land on the success URL without
    // actually having paid, e.g. by hitting back). Verifies the raw body
    // against Square's signature so this can't be spoofed by a random POST.
    // The notification URL used for the signature must exactly match what's
    // configured for this webhook subscription in the Square Developer
    // Dashboard. Despite the "swag" in the path, this single subscription
    // now services both Swag and Gift Card payments — Square only lets you
    // subscribe a given event type once per notification URL, and both
    // features fire the same payment.updated event, so splitting them into
    // two endpoints would just mean two webhook subscriptions to keep in
    // sync instead of one. The order id is checked against both stores;
    // whichever one actually has it wins.
    app.on(.POST, "api", "swag", "square-webhook", body: .collect(maxSize: "1mb")) { req async throws -> HTTPStatus in
        guard let signatureKey = Environment.get("SQUARE_WEBHOOK_SIGNATURE_KEY") else {
            throw Abort(.serviceUnavailable)
        }
        guard let signatureHeader = req.headers.first(name: "x-square-hmacsha256-signature") else {
            throw Abort(.badRequest)
        }
        guard let bodyBuffer = req.body.data,
              let payload = bodyBuffer.getString(at: bodyBuffer.readerIndex, length: bodyBuffer.readableBytes) else {
            throw Abort(.badRequest)
        }
        let notificationURL = "\(PublicBaseURL.get())/api/swag/square-webhook"
        guard SquareCheckout.verifyWebhookSignature(payload: payload, notificationURL: notificationURL, signatureHeader: signatureHeader, signatureKey: signatureKey) else {
            throw Abort(.unauthorized)
        }
        let event = try JSONDecoder().decode(SquareWebhookEvent.self, from: Data(payload.utf8))
        if event.type == "payment.updated", let payment = event.data.object.payment,
           payment.status == "COMPLETED", let squareOrderId = payment.order_id {
            try SwagOrdersStore.shared.markPaidIfPresent(squareOrderId: squareOrderId)
            try GiftCardOrdersStore.shared.markPaidIfPresent(squareOrderId: squareOrderId)
        }
        return .ok
    }

    app.get("api", "swag", "orders") { req throws -> [SwagOrder] in
        try requireLogin(req)
        return try SwagOrdersStore.shared.all()
    }

    app.post("api", "swag", "orders", ":id", "deliver") { req throws -> SwagOrder in
        try requireLogin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        return try SwagOrdersStore.shared.markDelivered(id: id)
    }

    // MARK: - Gift Cards

    // Ohana already sells physical gift cards in person — this doesn't call
    // Square's Gift Card API to create/activate one, it just collects
    // payment online. Deliberately not tied to a table (unlike swag): most
    // gift cards are bought as a gift, not while dining in, so staff follow
    // up directly with the buyer using the contact info collected here.
    // Shares SQUARE_ACCESS_TOKEN/SQUARE_LOCATION_ID with swag checkout, so
    // reuses the same GET /api/swag/checkout-status the Shop page already
    // checks — it's really just "is Square configured," not swag-specific.
    app.post("api", "gift-cards", "checkout") { req async throws -> GiftCardCheckoutResponse in
        guard let accessToken = Environment.get("SQUARE_ACCESS_TOKEN"), !accessToken.isEmpty,
              let locationId = Environment.get("SQUARE_LOCATION_ID"), !locationId.isEmpty else {
            throw SwagError.checkoutNotConfigured
        }
        let body = try req.content.decode(GiftCardCheckoutRequest.self)
        let buyerName = body.buyerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let buyerEmail = body.buyerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !buyerName.isEmpty, !buyerEmail.isEmpty else {
            throw Abort(.badRequest, reason: "Your name and email are required.")
        }
        guard (giftCardMinAmount...giftCardMaxAmount).contains(body.amount) else {
            throw GiftCardError.invalidAmount
        }
        let trimmedRecipientName = body.recipientName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipientName = (trimmedRecipientName?.isEmpty ?? true) ? nil : trimmedRecipientName
        let trimmedNote = body.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote

        let customerId = try? currentCustomer(req)?.id
        let order = try GiftCardOrdersStore.shared.createPendingOrder(
            amount: body.amount, buyerName: buyerName, buyerEmail: buyerEmail,
            recipientName: recipientName, note: note, customerId: customerId
        )

        let base = PublicBaseURL.get()
        let link = try await SquareCheckout.createPaymentLink(
            client: req.client, accessToken: accessToken, locationId: locationId, orderId: order.id,
            items: [SquareCheckout.LineItemInput(name: "Ohana Belltown Gift Card", quantity: 1, priceCents: Int((body.amount * 100).rounded()))],
            metadata: ["buyerEmail": buyerEmail],
            redirectURL: "\(base)/gift-cards?checkout=success"
        )
        try GiftCardOrdersStore.shared.attachSquareOrderId(orderId: order.id, squareOrderId: link.squareOrderId)
        return GiftCardCheckoutResponse(checkoutURL: link.url)
    }

    app.get("api", "gift-cards", "orders") { req throws -> [GiftCardOrder] in
        try requireLogin(req)
        return try GiftCardOrdersStore.shared.all()
    }

    app.post("api", "gift-cards", "orders", ":id", "fulfill") { req throws -> GiftCardOrder in
        try requireLogin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        return try GiftCardOrdersStore.shared.markFulfilled(id: id)
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
        // A photo needs a dish to land in once approved; a social tag isn't
        // always about one specific dish, so it's optional there.
        if body.type == "photo" {
            guard let menuItemId = body.menuItemId, !menuItemId.isEmpty else {
                throw Abort(.badRequest, reason: "Please select which dish this photo is of.")
            }
        }
        return try LoyaltyStore.shared.submitBonusRequest(
            phone: body.phone, type: body.type, content: body.content, note: body.note,
            menuItemId: body.menuItemId, menuItemName: body.menuItemName
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
        let entry = try TableOrdersStore.shared.place(
            tableId: tableId, itemName: itemName, itemId: body.itemId, section: body.section, customerId: customerId,
            modifiers: body.modifiers ?? []
        )
        Task { await LightNotifier.shared.notifyPlaced(entry) }
        return entry
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
        let entry = try TableOrdersStore.shared.markEntered(id: id, staffOnDuty: staffOnDuty)
        Task { await LightNotifier.shared.notifyEntered(entry) }
        return entry
    }

    // Public — either staff (from the admin queue) or the customer
    // themselves (a "Mark Received" tap on the menu page) can confirm this.
    app.post("api", "table-orders", ":id", "deliver") { req throws -> TableOrderEntry in
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        let entry = try TableOrdersStore.shared.markDelivered(id: id)
        Task { await LightNotifier.shared.notifyDelivered(entry) }
        return entry
    }

    // Staff-only — a server talked to the table and they no longer want
    // this item, whether it's still waiting to be entered or already
    // cooking. Refuses (409) once it's been delivered; that's a different
    // situation than this handles. Not public like deliver is, since a
    // guest shouldn't be able to cancel their own order out from under
    // themselves via the same button that marks it received.
    app.post("api", "table-orders", ":id", "cancel") { req throws -> TableOrderEntry in
        try requireLogin(req)
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        let body = try? req.content.decode(CancelOrderRequest.self)
        let entry = try TableOrdersStore.shared.cancel(id: id, reason: body?.reason)
        Task { await LightNotifier.shared.notifyCancelled(entry) }
        return entry
    }

    // Lets staff confirm whether the physical station lights are actually
    // wired up (TUYA_* configured) without exposing the credentials
    // themselves — no secrets in the response, just booleans/ids/hex colors.
    app.get("api", "table-orders", "lights") { req async throws -> LightStationsStatus in
        try requireLogin(req)
        return await LightNotifier.shared.status()
    }

    // Admin-only — both are analytics.html data, and that page itself is
    // already admin-gated; this keeps the API from being a back door for a
    // non-admin employee who calls it directly.
    app.get("api", "table-orders", "delivery-stats") { req throws -> DeliveryStatsSummary in
        try requireAdmin(req)
        let days = req.query[Int.self, at: "days"] ?? 30
        return try TableOrdersStore.shared.deliveryStats(days: days)
    }

    app.get("api", "table-orders", "occupancy-stats") { req throws -> TableOccupancyStatsSummary in
        try requireAdmin(req)
        let days = req.query[Int.self, at: "days"] ?? 30
        return try TableOrdersStore.shared.tableOccupancyStats(days: days)
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

    // Admin-only, same reasoning as delivery-stats/occupancy-stats above —
    // reading the actual feedback content/list is analytics.html's job.
    // unacknowledged-count stays open to any staff member below: it only
    // exposes a bare number, and drives the site-wide "N new feedback"
    // badge every logged-in staff member sees, not just admins.
    app.get("api", "feedback") { req throws -> [FeedbackEntry] in
        try requireAdmin(req)
        let days = req.query[Int.self, at: "days"] ?? 30
        return try FeedbackStore.shared.recent(days: days)
    }

    app.get("api", "feedback", "unacknowledged-count") { req throws -> FeedbackUnacknowledgedCount in
        try requireLogin(req)
        return FeedbackUnacknowledgedCount(count: try FeedbackStore.shared.unacknowledgedCount())
    }

    app.post("api", "feedback", "acknowledge-all") { req throws -> HTTPStatus in
        try requireAdmin(req)
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
        ("shop", "pages/shop.html"),
        ("gift-cards", "pages/gift-cards.html"),
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
        ("competitor-pricing-admin.html", "staff/competitor-pricing-admin.html", true),
        ("competitor-pricing-findings.html", "staff/competitor-pricing-findings.html", true),
        ("swag-admin.html", "staff/swag-admin.html", false),
        ("gift-cards-admin.html", "staff/gift-cards-admin.html", false),
        ("help.html", "staff/help.html", false),
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
