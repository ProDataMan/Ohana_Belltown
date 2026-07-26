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
