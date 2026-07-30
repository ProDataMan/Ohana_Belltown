import XCTVapor
@testable import App

final class RouteTests: XCTestCase {
    var app: Application!
    var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        app = try await Application.make(.testing)
        try configure(app)

        // Point every store at an isolated temp directory so tests don't touch
        // real data or interfere with each other.
        MenuStore.shared.configure(dataDirectory: tempDir.path, resourcesDirectory: app.directory.resourcesDirectory)
        Uploads.configure(dataDirectory: tempDir.path)
        EventsStore.shared.configure(dataDirectory: tempDir.path)
        LoyaltyStore.shared.configure(dataDirectory: tempDir.path)
        UserStore.shared.configure(dataDirectory: tempDir.path)
        CustomerUserStore.shared.configure(dataDirectory: tempDir.path)
        AnalyticsStore.shared.configure(dataDirectory: tempDir.path)
        WaitlistStore.shared.configure(dataDirectory: tempDir.path)
        TableOrdersStore.shared.configure(dataDirectory: tempDir.path)
        StaffingStore.shared.configure(dataDirectory: tempDir.path)
        FeedbackStore.shared.configure(dataDirectory: tempDir.path)
        StaffRewardsStore.shared.configure(dataDirectory: tempDir.path)
        CompetitorPricingStore.shared.configure(dataDirectory: tempDir.path)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testHealthz() throws {
        try app.test(.GET, "healthz") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "ok")
        }
    }

    func testScanRedirectsToMenuOrHappyHour() throws {
        try app.test(.GET, "scan") { res in
            XCTAssertEqual(res.status, .seeOther)
            let location = res.headers.first(name: .location)
            XCTAssertTrue(location == "/menu" || location == "/happy-hour", "unexpected redirect target: \(location ?? "nil")")
        }
    }

    func testScanPreservesTableIdOnRedirect() throws {
        try app.test(.GET, "scan?table=5") { res in
            XCTAssertEqual(res.status, .seeOther)
            let location = res.headers.first(name: .location)
            XCTAssertTrue(location == "/menu?table=5" || location == "/happy-hour?table=5", "unexpected redirect target: \(location ?? "nil")")
        }
    }

    func testTableOrderFullLifecycleFlow() throws {
        let orderBody = ByteBuffer(string: #"{"tableId":"5","itemName":"Spam Musubi","section":"menu"}"#)
        var orderId: String?
        try app.test(.POST, "api/table-orders", headers: ["Content-Type": "application/json"], body: orderBody) { res in
            XCTAssertEqual(res.status, .ok)
            let entry = try res.content.decode(TableOrderEntry.self)
            XCTAssertEqual(entry.tableId, "5")
            XCTAssertEqual(entry.status, "pending")
            orderId = entry.id
        }
        guard let id = orderId else { return XCTFail("expected an order id") }

        try app.test(.GET, "api/table-orders/dashboard") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }

        let bootstrapBody = ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"], body: bootstrapBody) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        try app.test(.GET, "api/table-orders/dashboard", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let dashboard = try res.content.decode(TableOrdersDashboard.self)
            XCTAssertEqual(dashboard.needsEntry.map { $0.id }, [id])
            XCTAssertTrue(dashboard.awaitingDelivery.isEmpty)
        }

        try app.test(.POST, "api/table-orders/\(id)/enter", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let entered = try res.content.decode(TableOrderEntry.self)
            XCTAssertEqual(entered.status, "entered")
            XCTAssertNotNil(entered.estimatedReadyAt)
        }
        try app.test(.GET, "api/table-orders/dashboard", headers: ["Cookie": cookie]) { res in
            let dashboard = try res.content.decode(TableOrdersDashboard.self)
            XCTAssertTrue(dashboard.needsEntry.isEmpty)
            XCTAssertEqual(dashboard.awaitingDelivery.map { $0.id }, [id])
        }

        // Delivery confirmation is public — no cookie needed, since a
        // customer can tap "Mark Received" themselves.
        try app.test(.POST, "api/table-orders/\(id)/deliver") { res in
            XCTAssertEqual(res.status, .ok)
            let delivered = try res.content.decode(TableOrderEntry.self)
            XCTAssertEqual(delivered.status, "delivered")
        }
        try app.test(.GET, "api/table-orders/dashboard", headers: ["Cookie": cookie]) { res in
            let dashboard = try res.content.decode(TableOrdersDashboard.self)
            XCTAssertTrue(dashboard.awaitingDelivery.isEmpty)
        }

        try app.test(.GET, "api/table-orders/delivery-stats", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let stats = try res.content.decode(DeliveryStatsSummary.self)
            XCTAssertEqual(stats.completedOrders, 1)
        }

        try app.test(.GET, "api/table-orders/occupancy-stats") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try app.test(.GET, "api/table-orders/occupancy-stats", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let stats = try res.content.decode(TableOccupancyStatsSummary.self)
            XCTAssertEqual(stats.sessions, 1)
            XCTAssertFalse(stats.isBaselineOnly)
        }
    }

    func testStaffingCanBeReadAndUpdated() throws {
        let bootstrapBody = ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"], body: bootstrapBody) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        try app.test(.GET, "api/table-orders/staffing", headers: ["Cookie": cookie]) { res in
            let config = try res.content.decode(StaffingConfig.self)
            XCTAssertEqual(config.staffOnDuty, StaffingStore.defaultStaffOnDuty)
        }

        let updateBody = ByteBuffer(string: #"{"staffOnDuty":5}"#)
        try app.test(.POST, "api/table-orders/staffing", headers: ["Content-Type": "application/json", "Cookie": cookie], body: updateBody) { res in
            let config = try res.content.decode(StaffingConfig.self)
            XCTAssertEqual(config.staffOnDuty, 5)
        }
    }

    func testTableOrderCapturesSelectedModifiers() throws {
        let orderBody = ByteBuffer(string: #"{"tableId":"5","itemName":"Chicken Teriyaki","modifiers":["Yosh Size","Add Katsu"]}"#)
        try app.test(.POST, "api/table-orders", headers: ["Content-Type": "application/json"], body: orderBody) { res in
            XCTAssertEqual(res.status, .ok)
            let entry = try res.content.decode(TableOrderEntry.self)
            XCTAssertEqual(entry.modifiers, ["Yosh Size", "Add Katsu"])
        }
    }

    func testFeedbackSubmitIsPublicButListingRequiresLogin() throws {
        let body = ByteBuffer(string: #"{"category":"food","rating":5,"message":"Great sushi!","page":"/menu"}"#)
        try app.test(.POST, "api/feedback", headers: ["Content-Type": "application/json"], body: body) { res in
            XCTAssertEqual(res.status, .ok)
            let entry = try res.content.decode(FeedbackEntry.self)
            XCTAssertEqual(entry.category, "food")
            XCTAssertEqual(entry.rating, 5)
        }

        try app.test(.GET, "api/feedback") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }

        let bootstrapBody = ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"], body: bootstrapBody) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        try app.test(.GET, "api/feedback", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let entries = try res.content.decode([FeedbackEntry].self)
            XCTAssertEqual(entries.count, 1)
        }

        try app.test(.GET, "api/feedback/unacknowledged-count", headers: ["Cookie": cookie]) { res in
            let count = try res.content.decode(FeedbackUnacknowledgedCount.self)
            XCTAssertEqual(count.count, 1)
        }

        try app.test(.POST, "api/feedback/acknowledge-all", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
        }
        try app.test(.GET, "api/feedback/unacknowledged-count", headers: ["Cookie": cookie]) { res in
            let count = try res.content.decode(FeedbackUnacknowledgedCount.self)
            XCTAssertEqual(count.count, 0)
        }
    }

    func testFeedbackFromLoggedInCustomerCapturesAccountEmailAutomatically() throws {
        let registerBody = ByteBuffer(string: #"{"email":"guest@example.com","displayName":"Guest","password":"guestpass1"}"#)
        var sessionCookie: String?
        try app.test(.POST, "api/customer/register", headers: ["Content-Type": "application/json"], body: registerBody) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from register") }

        // No contactEmail in the request body — it should still get attached
        // server-side from the logged-in customer's account.
        let body = ByteBuffer(string: #"{"category":"food","message":"Loved it!"}"#)
        try app.test(.POST, "api/feedback", headers: ["Content-Type": "application/json", "Cookie": cookie], body: body) { res in
            XCTAssertEqual(res.status, .ok)
            let entry = try res.content.decode(FeedbackEntry.self)
            XCTAssertEqual(entry.contactEmail, "guest@example.com")
        }
    }

    func testFeedbackRejectsEmptyMessageAndInvalidRating() throws {
        let emptyBody = ByteBuffer(string: #"{"category":"food","message":""}"#)
        try app.test(.POST, "api/feedback", headers: ["Content-Type": "application/json"], body: emptyBody) { res in
            XCTAssertEqual(res.status, .badRequest)
        }

        let badRatingBody = ByteBuffer(string: #"{"category":"food","message":"Hi","rating":9}"#)
        try app.test(.POST, "api/feedback", headers: ["Content-Type": "application/json"], body: badRatingBody) { res in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testTableOrderRejectsEmptyFields() throws {
        let orderBody = ByteBuffer(string: #"{"tableId":"","itemName":"Spam Musubi"}"#)
        try app.test(.POST, "api/table-orders", headers: ["Content-Type": "application/json"], body: orderBody) { res in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testCustomerOrderHistoryReflectsOrdersPlacedWhileSignedIn() throws {
        let registerBody = ByteBuffer(string: #"{"email":"guest@example.com","displayName":"Guest","password":"guestpass1"}"#)
        var sessionCookie: String?
        try app.test(.POST, "api/customer/register", headers: ["Content-Type": "application/json"], body: registerBody) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from register") }

        try app.test(.GET, "api/customer/order-history") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }

        let orderBody = ByteBuffer(string: #"{"tableId":"5","itemName":"Spam Musubi"}"#)
        try app.test(.POST, "api/table-orders", headers: ["Content-Type": "application/json", "Cookie": cookie], body: orderBody) { res in
            XCTAssertEqual(res.status, .ok)
        }
        // Placed anonymously (no customer cookie) — shouldn't show up in this customer's history.
        let anonBody = ByteBuffer(string: #"{"tableId":"5","itemName":"Someone Else's Order"}"#)
        try app.test(.POST, "api/table-orders", headers: ["Content-Type": "application/json"], body: anonBody) { res in
            XCTAssertEqual(res.status, .ok)
        }

        try app.test(.GET, "api/customer/order-history", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let orders = try res.content.decode([TableOrderEntry].self)
            XCTAssertEqual(orders.map { $0.itemName }, ["Spam Musubi"])
        }
    }

    func testCustomerLoyaltyPhoneLinkingRequiresLoginAndReflectsPunches() throws {
        let phoneBody = ByteBuffer(string: #"{"phone":"2065550100"}"#)
        try app.test(.POST, "api/customer/loyalty-phone", headers: ["Content-Type": "application/json"], body: phoneBody) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }

        let registerBody = ByteBuffer(string: #"{"email":"guest@example.com","displayName":"Guest","password":"guestpass1"}"#)
        var sessionCookie: String?
        try app.test(.POST, "api/customer/register", headers: ["Content-Type": "application/json"], body: registerBody) { res in
            XCTAssertEqual(res.status, .ok)
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from register") }

        try app.test(.GET, "api/customer/loyalty", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let view = try res.content.decode(CustomerLoyaltyView.self)
            XCTAssertNil(view.linkedPhone)
        }

        try app.test(.POST, "api/customer/loyalty-phone", headers: ["Content-Type": "application/json", "Cookie": cookie], body: phoneBody) { res in
            XCTAssertEqual(res.status, .ok)
        }
        try LoyaltyStore.shared.addPunch(phone: "2065550100", count: 3)

        try app.test(.GET, "api/customer/loyalty", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let view = try res.content.decode(CustomerLoyaltyView.self)
            XCTAssertEqual(view.linkedPhone, "2065550100")
            XCTAssertEqual(view.status?.punches, 3)
        }

        let unlinkBody = ByteBuffer(string: #"{"phone":null}"#)
        try app.test(.POST, "api/customer/loyalty-phone", headers: ["Content-Type": "application/json", "Cookie": cookie], body: unlinkBody) { res in
            XCTAssertEqual(res.status, .ok)
        }
        try app.test(.GET, "api/customer/loyalty", headers: ["Cookie": cookie]) { res in
            let view = try res.content.decode(CustomerLoyaltyView.self)
            XCTAssertNil(view.linkedPhone)
        }
    }

    func testPlaceReviewsReturnsEmptyWithoutAPIConfigured() throws {
        try app.test(.GET, "api/place-reviews") { res in
            XCTAssertEqual(res.status, .ok)
            let summary = try res.content.decode(PlaceReviewsSummary.self)
            XCTAssertTrue(summary.reviews.isEmpty)
        }
    }

    func testNearbyRestaurantsRequiresAdminAndReturnsEmptyWithoutAPIConfigured() throws {
        try app.test(.GET, "api/competitor-pricing/nearby-restaurants") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }

        let bootstrapBody = ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"], body: bootstrapBody) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        // No GOOGLE_PLACES_API_KEY/GOOGLE_PLACE_ID in the test environment —
        // same graceful empty-list fallback as /api/place-reviews.
        try app.test(.GET, "api/competitor-pricing/nearby-restaurants", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let candidates = try res.content.decode([NearbyRestaurantCandidate].self)
            XCTAssertTrue(candidates.isEmpty)
        }
    }

    func testAIExtractionStatusAndExtractReflectNoAPIKeyConfigured() throws {
        let bootstrapBody = ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"], body: bootstrapBody) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        // No ANTHROPIC_API_KEY in the test environment — the status check
        // should report unavailable, and attempting the extraction anyway
        // should fail with a clear "not configured" reason (503) rather
        // than a confusing crash or generic error.
        try app.test(.GET, "api/competitor-pricing/ai-extraction-status", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let status = try res.content.decode(AIExtractionStatus.self)
            XCTAssertFalse(status.available)
        }

        let extractBody = ByteBuffer(string: #"{"photoUrl":"/uploads/does-not-exist.jpg"}"#)
        try app.test(.POST, "api/competitor-pricing/extract-menu", headers: ["Cookie": cookie, "Content-Type": "application/json"], body: extractBody) { res in
            XCTAssertEqual(res.status, .serviceUnavailable)
        }
    }

    func testMenuAPIReturnsSeedMenuWithoutAuth() throws {
        try app.test(.GET, "api/menu") { res in
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testMenuWriteRequiresLogin() throws {
        let body = ByteBuffer(string: #"{"restaurant":"Ohana","lastUpdated":"now","categories":[]}"#)
        try app.test(.PUT, "api/menu", headers: ["Content-Type": "application/json"], body: body) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }

    func testAdditionsCatalogRequiresLoginToViewAndSave() throws {
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"],
                      body: ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        try app.test(.GET, "api/additions-catalog") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try app.test(.GET, "api/additions-catalog", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let items = try res.content.decode([AdditionCatalogItem].self)
            XCTAssertEqual(items, [])
        }

        let newCatalogBody = ByteBuffer(string: #"[{"id":"a1","name":"Add Bacon","priceDelta":5.5}]"#)
        try app.test(.PUT, "api/additions-catalog", headers: ["Content-Type": "application/json"], body: newCatalogBody) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try app.test(.PUT, "api/additions-catalog", headers: ["Content-Type": "application/json", "Cookie": cookie], body: newCatalogBody) { res in
            XCTAssertEqual(res.status, .ok)
            let items = try res.content.decode([AdditionCatalogItem].self)
            XCTAssertEqual(items, [AdditionCatalogItem(id: "a1", name: "Add Bacon", priceDelta: 5.5)])
        }
        try app.test(.GET, "api/additions-catalog", headers: ["Cookie": cookie]) { res in
            let items = try res.content.decode([AdditionCatalogItem].self)
            XCTAssertEqual(items.count, 1, "saved catalog should persist across requests")
        }
    }

    func testSeedAdditionsRequiresLoginAndAppliesKnownModifiers() throws {
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"],
                      body: ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        let menuBody = ByteBuffer(string: #"""
        {"restaurant":"Ohana","lastUpdated":"now","categories":[
          {"section":"menu","name":"Entrees","note":null,"items":[
            {"name":"Loco Moco","price":18}
          ]}
        ]}
        """#)
        try app.test(.PUT, "api/menu", headers: ["Content-Type": "application/json", "Cookie": cookie], body: menuBody) { res in
            XCTAssertEqual(res.status, .ok)
        }

        try app.test(.POST, "api/menu/seed-additions") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try app.test(.POST, "api/menu/seed-additions", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let result = try res.content.decode(SeedAdditionsResult.self)
            XCTAssertEqual(result.catalogAdded, 15)
            XCTAssertEqual(result.itemsUpdated, ["Loco Moco"])
        }

        try app.test(.GET, "api/menu") { res in
            let menu = try res.content.decode(Menu.self)
            let locoMoco = menu.categories.first?.items.first { $0.name == "Loco Moco" }
            XCTAssertEqual(locoMoco?.modifiers.count, 6)
        }
    }

    func testSingleItemGetPatchDeleteLifecycle() throws {
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"],
                      body: ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        let menuBody = ByteBuffer(string: #"""
        {"restaurant":"Ohana","lastUpdated":"now","categories":[
          {"section":"menu","name":"Rolls","note":null,"items":[
            {"id":"item-1","name":"Volcano Roll","description":null,"price":14,"images":[],"tags":[],"featured":false,"available":true,"happyHour":false}
          ]}
        ]}
        """#)
        try app.test(.PUT, "api/menu", headers: ["Content-Type": "application/json", "Cookie": cookie], body: menuBody) { res in
            XCTAssertEqual(res.status, .ok)
        }

        try app.test(.GET, "api/menu/items/item-1") { res in
            XCTAssertEqual(res.status, .ok)
            let location = try res.content.decode(MenuItemLocation.self)
            XCTAssertEqual(location.item.name, "Volcano Roll")
            XCTAssertEqual(location.categoryName, "Rolls")
        }

        try app.test(.GET, "api/menu/items/does-not-exist") { res in
            XCTAssertEqual(res.status, .notFound)
        }

        let patchBody = ByteBuffer(string: #"""
        {"name":"Volcano Roll","description":"Now spicier","price":16,"images":["/uploads/x.jpg"],"tags":[],"featured":true,"available":true,"happyHour":true}
        """#)
        try app.test(.PATCH, "api/menu/items/item-1", headers: ["Content-Type": "application/json"], body: patchBody) { res in
            XCTAssertEqual(res.status, .unauthorized, "editing an item requires a logged-in employee")
        }
        try app.test(.PATCH, "api/menu/items/item-1", headers: ["Content-Type": "application/json", "Cookie": cookie], body: patchBody) { res in
            XCTAssertEqual(res.status, .ok)
            let updated = try res.content.decode(MenuItem.self)
            XCTAssertEqual(updated.price, 16)
            XCTAssertTrue(updated.featured)
            XCTAssertTrue(updated.happyHour)
            XCTAssertEqual(updated.modifiers, [], "a PATCH body omitting modifiers shouldn't error — older clients haven't sent this field yet")
        }

        let patchWithModifiersBody = ByteBuffer(string: #"""
        {"name":"Volcano Roll","description":"Now spicier","price":16,"images":[],"tags":[],"featured":true,"available":true,"happyHour":true,"modifiers":[{"id":"m1","name":"Yosh Size","priceDelta":25.2}]}
        """#)
        try app.test(.PATCH, "api/menu/items/item-1", headers: ["Content-Type": "application/json", "Cookie": cookie], body: patchWithModifiersBody) { res in
            XCTAssertEqual(res.status, .ok)
            let updated = try res.content.decode(MenuItem.self)
            XCTAssertEqual(updated.modifiers.map { $0.name }, ["Yosh Size"])
            XCTAssertEqual(updated.modifiers.map { $0.priceDelta }, [25.2])
        }

        try app.test(.DELETE, "api/menu/items/item-1") { res in
            XCTAssertEqual(res.status, .unauthorized, "deleting an item requires a logged-in employee")
        }
        try app.test(.DELETE, "api/menu/items/item-1", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .noContent)
        }
        try app.test(.GET, "api/menu/items/item-1") { res in
            XCTAssertEqual(res.status, .notFound)
        }
    }

    func testDeleteUploadRefusesWhileReferencedThenSucceedsOnceFreed() throws {
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"],
                      body: ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        let path = Uploads.directory + "dup.jpg"
        try Data("fake image bytes".utf8).write(to: URL(fileURLWithPath: path))

        let menuBody = ByteBuffer(string: #"""
        {"restaurant":"Ohana","lastUpdated":"now","categories":[
          {"section":"menu","name":"Rolls","note":null,"items":[
            {"id":"item-1","name":"Volcano Roll","description":null,"price":14,"images":["/uploads/dup.jpg"],"tags":[],"featured":false,"available":true,"happyHour":false}
          ]}
        ]}
        """#)
        try app.test(.PUT, "api/menu", headers: ["Content-Type": "application/json", "Cookie": cookie], body: menuBody) { res in
            XCTAssertEqual(res.status, .ok)
        }

        try app.test(.DELETE, "api/uploads/dup.jpg", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .conflict, "still referenced by item-1, shouldn't delete out from under it")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        let freedMenuBody = ByteBuffer(string: #"""
        {"restaurant":"Ohana","lastUpdated":"now","categories":[
          {"section":"menu","name":"Rolls","note":null,"items":[
            {"id":"item-1","name":"Volcano Roll","description":null,"price":14,"images":[],"tags":[],"featured":false,"available":true,"happyHour":false}
          ]}
        ]}
        """#)
        try app.test(.PUT, "api/menu", headers: ["Content-Type": "application/json", "Cookie": cookie], body: freedMenuBody) { res in
            XCTAssertEqual(res.status, .ok)
        }

        try app.test(.DELETE, "api/uploads/dup.jpg") { res in
            XCTAssertEqual(res.status, .unauthorized, "deleting an upload requires a logged-in employee")
        }
        try app.test(.DELETE, "api/uploads/dup.jpg", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .noContent)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))

        try app.test(.DELETE, "api/uploads/dup.jpg", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .notFound, "already deleted")
        }

        try app.test(.DELETE, "api/uploads/..%2F..%2Fetc%2Fpasswd", headers: ["Cookie": cookie]) { res in
            // Vapor's router rejects the encoded ".." segments before this
            // route's own ".." guard ever runs — still blocked either way.
            XCTAssertEqual(res.status, .forbidden, "path traversal attempt")
        }
    }

    func testMenuItemPatchAutoAwardsStaffRewardPoints() throws {
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"],
                      body: ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        let menuBody = ByteBuffer(string: #"""
        {"restaurant":"Ohana","lastUpdated":"now","categories":[
          {"section":"menu","name":"Rolls","note":null,"items":[
            {"id":"item-1","name":"Volcano Roll","description":null,"price":null,"images":[],"tags":[],"featured":false,"available":true,"happyHour":false}
          ]}
        ]}
        """#)
        try app.test(.PUT, "api/menu", headers: ["Content-Type": "application/json", "Cookie": cookie], body: menuBody) { res in
            XCTAssertEqual(res.status, .ok)
        }

        // Adds this item's first-ever photo (bounty rate, 50 pts), sets a
        // price (10 pts), and marks it featured (10 pts) — 70 points total.
        let patchBody = ByteBuffer(string: #"""
        {"name":"Volcano Roll","description":null,"price":18,"images":["/uploads/a.jpg"],"tags":[],"featured":true,"available":true,"happyHour":false}
        """#)
        try app.test(.PATCH, "api/menu/items/item-1", headers: ["Content-Type": "application/json", "Cookie": cookie], body: patchBody) { res in
            XCTAssertEqual(res.status, .ok)
        }

        try app.test(.GET, "api/staff-rewards/me", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let status = try res.content.decode(StaffRewardStatus.self)
            // photo_bounty (50) + price (10) + special (10) = 70.
            XCTAssertEqual(status.points, 70)
        }
    }

    func testStaffRewardsAwardAndRedeemRequireAdmin() throws {
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"],
                      body: ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        let awardBody = ByteBuffer(string: #"{"staffId":"admin1","category":"social","note":"Instagram post"}"#)
        try app.test(.POST, "api/staff-rewards/award", headers: ["Content-Type": "application/json"], body: awardBody) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try app.test(.POST, "api/staff-rewards/award", headers: ["Content-Type": "application/json", "Cookie": cookie], body: awardBody) { res in
            XCTAssertEqual(res.status, .ok)
            let status = try res.content.decode(StaffRewardStatus.self)
            XCTAssertEqual(status.points, 30, "social = 30 points")
        }

        try app.test(.GET, "api/staff-rewards") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try app.test(.GET, "api/staff-rewards", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let cards = try res.content.decode([StaffRewardCard].self)
            XCTAssertEqual(cards.count, 1)
        }

        let redeemBody = ByteBuffer(string: #"{"catalogItemId":"roll-or-appetizer","note":null}"#)
        try app.test(.POST, "api/staff-rewards/admin1/redeem", headers: ["Content-Type": "application/json"], body: redeemBody) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try app.test(.POST, "api/staff-rewards/admin1/redeem", headers: ["Content-Type": "application/json", "Cookie": cookie], body: redeemBody) { res in
            XCTAssertEqual(res.status, .badRequest, "only 30 points so far, needs 100 for the default reward")
        }
    }

    func testUpdateDisplayNameRequiresAdminAndFixesATypo() throws {
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"],
                      body: ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        var userId: String?
        let createBody = ByteBuffer(string: #"{"username":"dayna","displayName":"Dana","password":"12345","role":"employee"}"#)
        try app.test(.POST, "api/users", headers: ["Content-Type": "application/json", "Cookie": cookie], body: createBody) { res in
            XCTAssertEqual(res.status, .ok)
            userId = try res.content.decode(StaffUserPublic.self).id
        }
        guard let id = userId else { return XCTFail("expected a created user id") }

        let renameBody = ByteBuffer(string: #"{"displayName":"Dayna"}"#)
        try app.test(.POST, "api/users/\(id)/display-name", headers: ["Content-Type": "application/json"], body: renameBody) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try app.test(.POST, "api/users/\(id)/display-name", headers: ["Content-Type": "application/json", "Cookie": cookie], body: renameBody) { res in
            XCTAssertEqual(res.status, .ok)
            let updated = try res.content.decode(StaffUserPublic.self)
            XCTAssertEqual(updated.displayName, "Dayna")
        }
    }

    func testStaffCanLogOtherActivityInstantlyButNotAutoDetectedOrSocialCategories() throws {
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"],
                      body: ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        let logBody = ByteBuffer(string: #"{"category":"other","note":"Helped set up the patio"}"#)
        try app.test(.POST, "api/staff-rewards/log", headers: ["Content-Type": "application/json"], body: logBody) { res in
            XCTAssertEqual(res.status, .unauthorized, "logging your own activity still requires being logged in")
        }
        try app.test(.POST, "api/staff-rewards/log", headers: ["Content-Type": "application/json", "Cookie": cookie], body: logBody) { res in
            XCTAssertEqual(res.status, .ok)
            let status = try res.content.decode(StaffRewardStatus.self)
            XCTAssertEqual(status.points, 20, "other = 20 points, credited instantly")
        }

        let claimedPhotoBody = ByteBuffer(string: #"{"category":"photo","note":"totally added a photo, trust me"}"#)
        try app.test(.POST, "api/staff-rewards/log", headers: ["Content-Type": "application/json", "Cookie": cookie], body: claimedPhotoBody) { res in
            XCTAssertEqual(res.status, .badRequest, "photo/price/special/event can only be earned by actually doing the edit")
        }

        let claimedSocialBody = ByteBuffer(string: #"{"category":"social","note":"trust me"}"#)
        try app.test(.POST, "api/staff-rewards/log", headers: ["Content-Type": "application/json", "Cookie": cookie], body: claimedSocialBody) { res in
            XCTAssertEqual(res.status, .badRequest, "social posts go through the request/review queue instead of instant self-report")
        }
    }

    func testSocialRequestNeedsALinkAndOnlyCreditsPointsOnceApproved() throws {
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"],
                      body: ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        let emptyLinkBody = ByteBuffer(string: #"{"link":"","note":null}"#)
        try app.test(.POST, "api/staff-rewards/social-requests", headers: ["Content-Type": "application/json", "Cookie": cookie], body: emptyLinkBody) { res in
            XCTAssertEqual(res.status, .badRequest, "a link is required")
        }

        var requestId: String?
        let submitBody = ByteBuffer(string: #"{"link":"https://instagram.com/p/abc123","note":"New roll post"}"#)
        try app.test(.POST, "api/staff-rewards/social-requests", headers: ["Content-Type": "application/json"], body: submitBody) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try app.test(.POST, "api/staff-rewards/social-requests", headers: ["Content-Type": "application/json", "Cookie": cookie], body: submitBody) { res in
            XCTAssertEqual(res.status, .ok)
            let request = try res.content.decode(StaffSocialRequest.self)
            XCTAssertEqual(request.status, "pending")
            requestId = request.id
        }
        guard let id = requestId else { return XCTFail("expected a request id") }

        // No points yet — still pending.
        try app.test(.GET, "api/staff-rewards/me", headers: ["Cookie": cookie]) { res in
            let status = try res.content.decode(StaffRewardStatus.self)
            XCTAssertEqual(status.points, 0)
        }

        try app.test(.GET, "api/staff-rewards/social-requests") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try app.test(.GET, "api/staff-rewards/social-requests", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let requests = try res.content.decode([StaffSocialRequest].self)
            XCTAssertEqual(requests.count, 1)
        }

        let approveBody = ByteBuffer(string: #"{"approve":true}"#)
        try app.test(.POST, "api/staff-rewards/social-requests/\(id)/review", headers: ["Content-Type": "application/json"], body: approveBody) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try app.test(.POST, "api/staff-rewards/social-requests/\(id)/review", headers: ["Content-Type": "application/json", "Cookie": cookie], body: approveBody) { res in
            XCTAssertEqual(res.status, .ok)
            let request = try res.content.decode(StaffSocialRequest.self)
            XCTAssertEqual(request.status, "approved")
        }

        try app.test(.GET, "api/staff-rewards/me", headers: ["Cookie": cookie]) { res in
            let status = try res.content.decode(StaffRewardStatus.self)
            XCTAssertEqual(status.points, 30, "approval credits the social point value")
        }

        // Reviewing again should fail — it's already been decided.
        try app.test(.POST, "api/staff-rewards/social-requests/\(id)/review", headers: ["Content-Type": "application/json", "Cookie": cookie], body: approveBody) { res in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testRewardCatalogRequiresLoginToViewAndAdminToEdit() throws {
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"],
                      body: ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        try app.test(.GET, "api/staff-rewards/catalog") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try app.test(.GET, "api/staff-rewards/catalog", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let items = try res.content.decode([RewardCatalogItem].self)
            XCTAssertTrue(items.contains { $0.id == "roll-or-appetizer" && $0.pointCost == 100 })
            XCTAssertTrue(items.contains { $0.id == "hat" && $0.pointCost == nil })
            XCTAssertTrue(items.contains { $0.id == "tshirt" && $0.pointCost == nil })
        }

        let newCatalogBody = ByteBuffer(string: #"[{"id":"hat","name":"Ohana Hat","pointCost":750}]"#)
        try app.test(.PUT, "api/staff-rewards/catalog", headers: ["Content-Type": "application/json"], body: newCatalogBody) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try app.test(.PUT, "api/staff-rewards/catalog", headers: ["Content-Type": "application/json", "Cookie": cookie], body: newCatalogBody) { res in
            XCTAssertEqual(res.status, .ok)
            let items = try res.content.decode([RewardCatalogItem].self)
            XCTAssertEqual(items, [RewardCatalogItem(id: "hat", name: "Ohana Hat", pointCost: 750)])
        }
    }

    func testPointValuesRequireLoginToViewAndAdminToEdit() throws {
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"],
                      body: ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        try app.test(.GET, "api/staff-rewards/point-values") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try app.test(.GET, "api/staff-rewards/point-values", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
            let values = try res.content.decode([String: Int].self)
            XCTAssertEqual(values, StaffRewardsStore.defaultPointValues)
        }

        let newValuesBody = ByteBuffer(string: #"{"photo":99,"photo_bounty":150,"price":10,"special":10,"event":35,"other":20,"social":30}"#)
        try app.test(.PUT, "api/staff-rewards/point-values", headers: ["Content-Type": "application/json"], body: newValuesBody) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try app.test(.PUT, "api/staff-rewards/point-values", headers: ["Content-Type": "application/json", "Cookie": cookie], body: newValuesBody) { res in
            XCTAssertEqual(res.status, .ok)
            let values = try res.content.decode([String: Int].self)
            XCTAssertEqual(values["photo"], 99)
        }

        // A manual award for "photo" should now reflect the saved override.
        let awardBody = ByteBuffer(string: #"{"staffId":"admin1","category":"photo","note":null}"#)
        try app.test(.POST, "api/staff-rewards/award", headers: ["Content-Type": "application/json", "Cookie": cookie], body: awardBody) { res in
            XCTAssertEqual(res.status, .ok)
            let status = try res.content.decode(StaffRewardStatus.self)
            XCTAssertEqual(status.points, 99)
        }
    }

    func testTableMapIsPublicAndCoversAllSections() throws {
        try app.test(.GET, "api/table-map") { res in
            XCTAssertEqual(res.status, .ok)
            let entries = try res.content.decode([TableMapEntry].self)
            XCTAssertEqual(entries.count, TableMap.entries.count)
            let sections = Set(entries.map(\.section))
            XCTAssertEqual(sections, Set(TableMap.sections))
            XCTAssertEqual(Set(entries.map(\.id)), TableMap.allIds)
        }
    }

    func testEventsWriteRequiresAdmin() throws {
        let body = ByteBuffer(string: #"{"events":[]}"#)
        try app.test(.PUT, "api/events", headers: ["Content-Type": "application/json"], body: body) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }

    func testLoyaltyLookupIsPublicButPunchIsNot() throws {
        let lookupBody = ByteBuffer(string: #"{"phone":"2065551234"}"#)
        try app.test(.POST, "api/loyalty/lookup", headers: ["Content-Type": "application/json"], body: lookupBody) { res in
            XCTAssertEqual(res.status, .notFound, "no card exists yet for this number")
        }

        let punchBody = ByteBuffer(string: #"{"phone":"2065551234"}"#)
        try app.test(.POST, "api/loyalty/punch", headers: ["Content-Type": "application/json"], body: punchBody) { res in
            XCTAssertEqual(res.status, .unauthorized, "punching requires a logged-in employee")
        }
    }

    func testStaffBootstrapLoginAndSessionGatedRoute() throws {
        let bootstrapBody = ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)
        var sessionCookie: String?

        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"], body: bootstrapBody) { res in
            XCTAssertEqual(res.status, .ok)
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }

        guard let cookie = sessionCookie else {
            return XCTFail("expected a session cookie from bootstrap")
        }

        try app.test(.GET, "edit.html", headers: ["Cookie": cookie]) { res in
            XCTAssertEqual(res.status, .ok)
        }

        try app.test(.GET, "edit.html") { res in
            XCTAssertEqual(res.status, .seeOther, "should redirect to /login without a session")
        }
    }

    func testCustomerRegisterAndLogin() throws {
        let registerBody = ByteBuffer(string: #"{"email":"guest@example.com","displayName":"Guest","password":"guestpass1"}"#)
        try app.test(.POST, "api/customer/register", headers: ["Content-Type": "application/json"], body: registerBody) { res in
            XCTAssertEqual(res.status, .ok)
        }

        let loginBody = ByteBuffer(string: #"{"email":"guest@example.com","password":"guestpass1"}"#)
        try app.test(.POST, "api/customer/login", headers: ["Content-Type": "application/json"], body: loginBody) { res in
            XCTAssertEqual(res.status, .ok)
        }

        let wrongBody = ByteBuffer(string: #"{"email":"guest@example.com","password":"wrong"}"#)
        try app.test(.POST, "api/customer/login", headers: ["Content-Type": "application/json"], body: wrongBody) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }

    func testPopularItemsExcludesSoldOutAndRanksByViews() throws {
        let menuBody = ByteBuffer(string: #"""
        {"restaurant":"Ohana","lastUpdated":"now","categories":[
          {"section":"menu","name":"Rolls","note":null,"items":[
            {"name":"Volcano Roll","description":null,"price":14,"images":[],"tags":[],"featured":false,"available":true},
            {"name":"Rainbow Roll","description":null,"price":13,"images":[],"tags":[],"featured":false,"available":true},
            {"name":"Sold Out Roll","description":null,"price":12,"images":[],"tags":[],"featured":false,"available":false}
          ]}
        ]}
        """#)
        var sessionCookie: String?
        try app.test(.POST, "api/auth/bootstrap", headers: ["Content-Type": "application/json"],
                      body: ByteBuffer(string: #"{"username":"admin1","displayName":"Admin","password":"adminpass"}"#)) { res in
            if let cookies = res.headers.setCookie?.all, let (name, value) = cookies.first {
                sessionCookie = "\(name)=\(value.string)"
            }
        }
        guard let cookie = sessionCookie else { return XCTFail("expected a session cookie from bootstrap") }

        try app.test(.PUT, "api/menu", headers: ["Content-Type": "application/json", "Cookie": cookie], body: menuBody) { res in
            XCTAssertEqual(res.status, .ok)
        }

        func recordView(_ name: String, times: Int) throws {
            for _ in 0..<times {
                try app.test(.POST, "api/analytics/item-view", headers: ["Content-Type": "application/json"],
                             body: ByteBuffer(string: #"{"name":"\#(name)"}"#)) { res in
                    XCTAssertEqual(res.status, .ok)
                }
            }
        }
        try recordView("Volcano Roll", times: 3)
        try recordView("Rainbow Roll", times: 1)
        try recordView("Sold Out Roll", times: 5)

        try app.test(.GET, "api/analytics/popular-items?days=30&limit=6") { res in
            XCTAssertEqual(res.status, .ok)
            let items = try res.content.decode([MenuItem].self)
            XCTAssertEqual(items.map { $0.name }, ["Volcano Roll", "Rainbow Roll"], "sold-out item should be excluded despite having the most views")
        }
    }
}
