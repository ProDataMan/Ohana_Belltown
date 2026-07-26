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
