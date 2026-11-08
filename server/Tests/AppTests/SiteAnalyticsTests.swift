import XCTest
@testable import App

final class SiteAnalyticsTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        MenuItemEngagementStore.shared.configure(dataDirectory: tempDir.path)
    }

    override func tearDownWithError() throws {
        MenuItemEngagementStore.shared.flush()
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testBotDetection() {
        XCTAssertTrue(AnalyticsStore.isBot(userAgent: nil))
        XCTAssertTrue(AnalyticsStore.isBot(userAgent: ""))
        XCTAssertTrue(AnalyticsStore.isBot(userAgent: "Mozilla/5.0 (compatible; Googlebot/2.1)"))
        XCTAssertTrue(AnalyticsStore.isBot(userAgent: "facebookexternalhit/1.1"))
        XCTAssertTrue(AnalyticsStore.isBot(userAgent: "Mozilla/5.0 HeadlessChrome/152.0"))
        XCTAssertTrue(AnalyticsStore.isBot(userAgent: "UptimeRobot/2.0"))
        XCTAssertTrue(AnalyticsStore.isBot(userAgent: "curl/8.5.0"))
        XCTAssertFalse(AnalyticsStore.isBot(userAgent: DefaultUserAgentMiddleware.phone))
        XCTAssertFalse(AnalyticsStore.isBot(userAgent: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/130.0 Mobile Safari/537.36"))
    }

    func testLabelAndPathCleaning() {
        XCTAssertEqual(AnalyticsStore.cleanLabel(" Google-Maps "), "google-maps")
        XCTAssertEqual(AnalyticsStore.cleanLabel("other:yelp.com"), "other:yelp.com")
        XCTAssertNil(AnalyticsStore.cleanLabel("has space"))
        XCTAssertNil(AnalyticsStore.cleanLabel("<script>"))
        XCTAssertEqual(AnalyticsStore.cleanPath("/menu"), "/menu")
        XCTAssertNil(AnalyticsStore.cleanPath("menu"))
        XCTAssertNil(AnalyticsStore.cleanPath("/menu?x=1"))
        XCTAssertTrue(AnalyticsStore.isKnownAction("social:instagram"))
        XCTAssertFalse(AnalyticsStore.isKnownAction("social:myspace"))
    }

    func testImpressionsAreStoredAsDailyTotalsAndOldOnesAreConverted() throws {
        // Two impressions recorded the old way, as raw events.
        let now = ISO8601DateFormatter().string(from: Date())
        let legacy = [
            MenuItemEngagementEvent(id: "1", menuItemName: "Poke", clickType: "impression", deviceId: "d1", customerId: nil, timestamp: now),
            MenuItemEngagementEvent(id: "2", menuItemName: "Poke", clickType: "impression", deviceId: "d1", customerId: nil, timestamp: now),
            MenuItemEngagementEvent(id: "3", menuItemName: "Poke", clickType: "details", deviceId: "d1", customerId: nil, timestamp: now),
        ]
        let lines = try legacy.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        try lines.write(to: tempDir.appendingPathComponent("menu-item-engagement.jsonl"), atomically: true, encoding: .utf8)
        MenuItemEngagementStore.shared.configure(dataDirectory: tempDir.path)

        // New impressions go to the daily totals.
        try MenuItemEngagementStore.shared.recordBatch(menuItemNames: ["Poke", "Musubi"], clickType: .impression, deviceId: "d2", customerId: nil)
        try MenuItemEngagementStore.shared.recordBatch(menuItemNames: ["Poke"], clickType: .impression, deviceId: "d2", customerId: nil)
        MenuItemEngagementStore.shared.flush()

        let rawLog = try String(contentsOf: tempDir.appendingPathComponent("menu-item-engagement.jsonl"), encoding: .utf8)
        XCTAssertFalse(rawLog.contains("impression"), "impressions no longer kept as raw events")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("menu-item-impressions-daily.json").path))

        MenuItemEngagementStore.shared.configure(dataDirectory: tempDir.path)
        let poke = try MenuItemEngagementStore.shared.tapRateSummary(days: 1).first { $0.menuItemName == "Poke" }
        XCTAssertEqual(poke?.impressions, 4)
        XCTAssertEqual(poke?.taps, 1)
        let impressionRow = try MenuItemEngagementStore.shared.summary(days: 1).first { $0.menuItemName == "Poke" && $0.clickType == "impression" }
        XCTAssertEqual(impressionRow?.totalClicks, 4)
    }

    func testMenuEngineeringSortsDishesIntoFourGroups() {
        func order(_ items: [(String, Double, Double, Double?)]) -> PosOrder {
            PosOrder(id: UUID().uuidString, source: "csv", ticketNumber: nil, table: "30", room: nil,
                     openedAt: "2026-11-07T03:00:00Z", closedAt: nil, guestCount: 2,
                     items: items.map { PosOrderItem(name: $0.0, quantity: $0.1, netSales: $0.2, cost: $0.3) }, netSales: nil)
        }
        // Per unit: Star $20 price / $5 cost, Plowhorse $10 / $6, Puzzle $25 / $5, Dog $8 / $6.
        let orders = [
            order([("Star", 10, 200, 50), ("Plowhorse", 10, 100, 60)]),
            order([("Puzzle", 1, 25, 5), ("Dog", 1, 8, 6)]),
        ]
        let report = MenuEngineering.build(orders: orders, from: .distantPast, to: .distantFuture, qrViews: ["Puzzle": 7])
        XCTAssertTrue(report.usesCost)
        let category = Dictionary(uniqueKeysWithValues: report.items.map { ($0.name, $0.category) })
        XCTAssertEqual(category, ["Star": "star", "Plowhorse": "plowhorse", "Puzzle": "puzzle", "Dog": "dog"])
        let star = report.items.first { $0.name == "Star" }!
        XCTAssertEqual(star.marginPerUnit, 15)
        XCTAssertEqual(star.foodCostPercent!, 0.25, accuracy: 0.0001)
        XCTAssertEqual(report.items.first { $0.name == "Puzzle" }?.qrDetailViews, 7)
    }

    func testMenuEngineeringFallsBackToPriceWithoutCosts() {
        let order = PosOrder(id: "a", source: "csv", ticketNumber: nil, table: nil, room: nil, openedAt: "2026-11-07T03:00:00Z",
                             closedAt: nil, guestCount: nil,
                             items: [PosOrderItem(name: "Cheap", quantity: 5, netSales: 25), PosOrderItem(name: "Pricey", quantity: 5, netSales: 100)],
                             netSales: nil)
        let report = MenuEngineering.build(orders: [order], from: .distantPast, to: .distantFuture)
        XCTAssertFalse(report.usesCost)
        XCTAssertEqual(report.items.first { $0.name == "Pricey" }?.category, "star")
        XCTAssertEqual(report.items.first { $0.name == "Cheap" }?.category, "plowhorse")
    }

    private func visit(_ id: String, table: String, start: String) -> QRVisitSummary {
        QRVisitSummary(
            visitId: id, table: table, source: "table", device: nil, deviceId: "d-\(id)", customerId: nil, customerName: nil,
            startedAt: start, lastSeenAt: start, durationSeconds: 0, pageViews: 1, pages: [], detailViews: [], photoTaps: [],
            searches: [], emptySearches: [], addedToOrder: [], landingPage: nil, firstTapSeconds: nil, previousVisits: 0, timeline: []
        )
    }

    func testQuietTablesOnlyFlaggedWhenTheRestOfTheFloorIsBusy() {
        let busyTables = TableMap.entries.map(\.id).filter { $0 != "30" }
        let busy = (0..<QRInsightsBuilder.quietThreshold).map { visit("v\($0)", table: busyTables[$0 % busyTables.count], start: "2026-11-07T03:00:00Z") }
        XCTAssertTrue(QRInsightsBuilder.quietTables(lastWeek: busy).contains("30"))
        XCTAssertEqual(QRInsightsBuilder.quietTables(lastWeek: Array(busy.prefix(3))), [], "a slow week isn't an alert")
    }

    func testSeatingStatsMatchFirstScanAtTheSeatedTable() throws {
        let party = WaitlistEntry(
            id: "w1", name: "Kai", phone: "2065550100", partySize: 2, note: nil, status: "seated",
            createdAt: "2026-11-07T02:40:00Z", updatedAt: "2026-11-07T03:00:00Z", seatedTable: "30", seatedAt: "2026-11-07T03:00:00Z"
        )
        let stats = try XCTUnwrap(QRInsightsBuilder.seating(parties: [party], visits: [
            visit("other-table", table: "28", start: "2026-11-07T03:01:00Z"),
            visit("first", table: "30", start: "2026-11-07T03:04:00Z"),
            visit("later", table: "30", start: "2026-11-07T03:20:00Z"),
        ]))
        XCTAssertEqual(stats.seatedParties, 1)
        XCTAssertEqual(stats.avgWaitMinutes, 20)
        XCTAssertEqual(stats.partiesThatScanned, 1)
        XCTAssertEqual(stats.avgMinutesSeatedToFirstScan, 4)
        XCTAssertNil(QRInsightsBuilder.seating(parties: [], visits: []))
    }

    func testWeeklyDigestIsDueMondayMorningOnce() {
        let iso = ISO8601DateFormatter()
        let mondayTenAM = iso.date(from: "2026-11-09T18:00:00Z")! // 10am PST
        let mondayEightAM = iso.date(from: "2026-11-09T16:00:00Z")!
        let tuesday = iso.date(from: "2026-11-10T18:00:00Z")!
        XCTAssertTrue(WeeklyDigest.isDue(now: mondayTenAM, lastSentDay: "2026-11-02"))
        XCTAssertFalse(WeeklyDigest.isDue(now: mondayTenAM, lastSentDay: "2026-11-09"))
        XCTAssertFalse(WeeklyDigest.isDue(now: mondayEightAM, lastSentDay: nil))
        XCTAssertFalse(WeeklyDigest.isDue(now: tuesday, lastSentDay: nil))
    }
}
