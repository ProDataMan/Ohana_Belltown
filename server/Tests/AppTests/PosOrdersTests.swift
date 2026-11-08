import XCTest
@testable import App

final class PosOrdersTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        PosOrderStore.shared.configure(dataDirectory: tempDir.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: Matching

    func testTableAndItemKeys() {
        XCTAssertEqual(PosMatching.tableKey("Table 30"), "30")
        XCTAssertEqual(PosMatching.tableKey(" b1 "), "B1")
        XCTAssertEqual(PosMatching.tableKey("07"), "7")
        XCTAssertNil(PosMatching.tableKey("null"))
        XCTAssertTrue(PosMatching.sameItem("SPAM MUSUBI (2pc)", "Spam Musubi"))
        XCTAssertTrue(PosMatching.sameItem("Mango Cart 12oz Can", "Mango Cart (12oz Can)"))
        XCTAssertFalse(PosMatching.sameItem("Poke", "Poke Bowl Deluxe Extra"))
        XCTAssertFalse(PosMatching.sameItem("Tea", "Thai Iced Tea"))
    }

    private func visit(table: String, start: String, end: String) -> QRVisitSummary {
        QRVisitSummary(
            visitId: "v", table: table, source: "table", device: nil, deviceId: "d", customerId: nil, customerName: nil,
            startedAt: start, lastSeenAt: end, durationSeconds: 0, pageViews: 1, pages: [], detailViews: [], photoTaps: [],
            searches: [], emptySearches: [], addedToOrder: [], landingPage: nil, firstTapSeconds: nil, previousVisits: 0, timeline: []
        )
    }

    private func order(_ id: String, table: String?, opened: String, closed: String?) -> PosOrder {
        PosOrder(id: id, source: "csv", ticketNumber: id, table: table, room: nil, openedAt: opened, closedAt: closed,
                 guestCount: 2, items: [PosOrderItem(name: "Poke", quantity: 1, netSales: 15)], netSales: 15)
    }

    func testVisitMatchesOverlappingTicketAtSameTableOnly() {
        let v = visit(table: "30", start: "2026-11-07T03:00:00Z", end: "2026-11-07T03:10:00Z")
        let orders = [
            order("seated-first", table: "30", opened: "2026-11-07T02:50:00Z", closed: "2026-11-07T04:00:00Z"),
            order("ordered-after", table: "30", opened: "2026-11-07T04:00:00Z", closed: "2026-11-07T05:00:00Z"),
            order("too-late", table: "30", opened: "2026-11-07T05:00:00Z", closed: "2026-11-07T06:00:00Z"),
            order("earlier-party", table: "30", opened: "2026-11-07T00:00:00Z", closed: "2026-11-07T02:30:00Z"),
            order("other-table", table: "28", opened: "2026-11-07T03:00:00Z", closed: "2026-11-07T04:00:00Z"),
        ]
        XCTAssertEqual(PosMatching.orders(for: v, in: orders).map(\.id), ["seated-first", "ordered-after"])
    }

    // MARK: Store

    func testUpsertReplacesSameTicketAndSurvivesReload() throws {
        let first = order("a", table: "30", opened: ISO8601DateFormatter().string(from: Date()), closed: nil)
        var changed = first
        changed.guestCount = 4
        let status = PosSyncStatus(at: "now", source: "csv", from: nil, to: nil, ordersImported: 1, error: nil)
        XCTAssertEqual(try PosOrderStore.shared.upsert([first], status: status).added, 1)
        let second = try PosOrderStore.shared.upsert([changed], status: status)
        XCTAssertEqual(second.added, 0)
        XCTAssertEqual(second.updated, 1)

        PosOrderStore.shared.configure(dataDirectory: tempDir.path)
        let orders = PosOrderStore.shared.orders(from: Date().addingTimeInterval(-60), to: Date().addingTimeInterval(60))
        XCTAssertEqual(orders.map(\.guestCount), [4])
        XCTAssertEqual(PosOrderStore.shared.lastSync()?.source, "csv")
    }

    // MARK: Heartland API parsing

    func testHeartlandOrderKeepsTableTimesItemsAndDropsPersonalDetails() throws {
        let raw: [String: Any] = [
            "id": "dGlja2V0OjE=", "ticket_number": "V17", "opened_dt": "2026-11-07T03:00:00+00:00",
            "closed_dt": "2026-11-07T04:15:00+00:00", "guest_count": 3, "net_sales": "42.50",
            "table": ["id": "dGFibGU6NTM0", "name": "null"],
            "customer_info": ["name": "Pat Guest", "phone": "2065550100"],
            "transactions": [["card_num": "4111", "card_name": "PAT GUEST"]],
            "items": [
                ["itemName": "Spam Musubi", "quantity": 2, "net_sales": "10.00", "voided_dt": "", "sub_item": "false"],
                ["itemName": "Add Egg", "quantity": 1, "net_sales": "0.00", "voided_dt": "", "sub_item": "true"],
                ["itemName": "Poke", "quantity": 1, "net_sales": "15.00", "voided_dt": "2026-11-07T03:20:00+00:00", "sub_item": false],
            ],
        ]
        let order = try XCTUnwrap(HeartlandSync.parseOrder(raw, tables: ["dGFibGU6NTM0": ("Table 30", "Dining Room")]))
        XCTAssertEqual(order.id, "heartland:dGlja2V0OjE=")
        XCTAssertEqual(order.table, "30")
        XCTAssertEqual(order.room, "Dining Room")
        XCTAssertEqual(order.openedAt, "2026-11-07T03:00:00Z")
        XCTAssertEqual(order.guestCount, 3)
        XCTAssertEqual(order.netSales, 42.5)
        XCTAssertEqual(order.items, [PosOrderItem(name: "Spam Musubi", quantity: 2, netSales: 10)])
        let stored = String(decoding: try JSONEncoder().encode(order), as: UTF8.self)
        XCTAssertFalse(stored.contains("Pat"))
        XCTAssertFalse(stored.contains("2065550100"))
        XCTAssertFalse(stored.contains("4111"))
    }

    func testDateRangesSplitIntoFourteenDayRequests() throws {
        let chunks = try HeartlandSync.chunks(from: "2026-10-01", to: "2026-10-31")
        XCTAssertEqual(chunks.map(\.0), ["2026-10-01", "2026-10-15", "2026-10-29"])
        XCTAssertEqual(chunks.map(\.1), ["2026-10-14", "2026-10-28", "2026-10-31"])
        XCTAssertThrowsError(try HeartlandSync.chunks(from: "2026-10-31", to: "2026-10-01"))
    }

    // MARK: CSV import

    func testCSVGroupsRowsIntoTicketsWithFlexibleHeaders() throws {
        let csv = """
        \u{FEFF}Check #,Table Name,Open Time,Item Name,Qty,Net Sales,Guests,Customer Phone
        1001,Table 30,11/6/2026 7:05 PM,Spam Musubi,2,$10.00,3,2065550100
        1001,Table 30,11/6/2026 7:05 PM,"Poke, Spicy",1,"$1,015.00",3,2065550100
        1002,B1,11/6/2026 7:30 PM,Mango Cart (12oz Can),1,8.50,1,
        ,,,,,,,
        1003,,,Orphan Item,1,1,1,
        """
        let result = try PosCSVImport.run(csv: csv)
        XCTAssertEqual(result.orders, 2)
        XCTAssertEqual(result.items, 3)
        XCTAssertEqual(result.skippedRows, 1)
        XCTAssertEqual(result.columns["ticket"], "Check #")
        XCTAssertEqual(result.columns["price"], "Net Sales")
        XCTAssertEqual(result.ignoredColumns, ["Customer Phone"])

        let orders = PosOrderStore.shared.orders(from: .distantPast, to: .distantFuture)
        let first = try XCTUnwrap(orders.first { $0.ticketNumber == "1001" })
        XCTAssertEqual(first.table, "30")
        XCTAssertEqual(first.guestCount, 3)
        XCTAssertEqual(first.items.map(\.name), ["Spam Musubi", "Poke, Spicy"])
        XCTAssertEqual(first.netSales, 1025)
        // 7:05pm Pacific (PST) = 03:05 UTC the next day.
        XCTAssertEqual(first.openedAt, "2026-11-07T03:05:00Z")

        // Uploading the same file again updates rather than duplicates.
        let again = try PosCSVImport.run(csv: csv)
        XCTAssertEqual(again.added, 0)
        XCTAssertEqual(PosOrderStore.shared.orders(from: .distantPast, to: .distantFuture).count, 2)
    }

    func testCSVWithoutRequiredColumnsExplainsWhatItFound() {
        XCTAssertThrowsError(try PosCSVImport.run(csv: "Ticket,Total\n1,5\n")) { error in
            XCTAssertTrue("\(error)".contains("item column"))
            XCTAssertTrue("\(error)".contains("Ticket, Total"))
        }
    }

    // MARK: Insights

    func testInsightsCompareQRTablesWithTheRest() {
        let v = QRVisitSummary(
            visitId: "v1", table: "30", source: "table", device: nil, deviceId: "d1", customerId: nil, customerName: nil,
            startedAt: "2026-11-07T03:00:00Z", lastSeenAt: "2026-11-07T03:10:00Z", durationSeconds: 600, pageViews: 1,
            pages: ["/menu"], detailViews: [QRVisitItemCount(itemName: "Poke", count: 1), QRVisitItemCount(itemName: "Spam Musubi", count: 1)],
            photoTaps: [], searches: [], emptySearches: [], addedToOrder: [], landingPage: "/menu", firstTapSeconds: 5,
            previousVisits: 0, timeline: []
        )
        let withQR = PosOrder(id: "a", source: "csv", ticketNumber: "1", table: "30", room: nil,
                              openedAt: "2026-11-07T03:05:00Z", closedAt: "2026-11-07T04:00:00Z", guestCount: 2,
                              items: [PosOrderItem(name: "POKE", quantity: 2, netSales: 30)], netSales: 40)
        let withoutQR = PosOrder(id: "b", source: "csv", ticketNumber: "2", table: "28", room: nil,
                                 openedAt: "2026-11-07T03:05:00Z", closedAt: "2026-11-07T04:00:00Z", guestCount: 4,
                                 items: [PosOrderItem(name: "Mystery Special", quantity: 2, netSales: 40)], netSales: 40)
        let menu = Menu(restaurant: "Ohana", lastUpdated: "now", categories: [
            MenuCategory(section: "menu", name: "Food", note: nil, items: [MenuItem(name: "Poke"), MenuItem(name: "Spam Musubi")]),
        ])
        let insights = QRInsightsBuilder.build(visits: [v], from: .distantPast, to: .distantFuture, menu: menu, orders: [withQR, withoutQR])
        let pos = try! XCTUnwrap(insights.pos)
        XCTAssertEqual(pos.tableOrders, 2)
        XCTAssertEqual(pos.tableOrdersWithQRVisit, 1)
        XCTAssertEqual(pos.qrVisitsWithOrder, 1)
        XCTAssertEqual(pos.avgNetSalesWithQR, 20)
        XCTAssertEqual(pos.avgNetSalesWithoutQR, 10)
        XCTAssertEqual(pos.avgItemsWithQR, 1)
        XCTAssertEqual(pos.avgItemsWithoutQR, 0.5)
        XCTAssertEqual(pos.unmatchedPosItems.map(\.label), ["Mystery Special"])

        XCTAssertEqual(insights.items.first { $0.itemName == "Poke" }?.visitsThatOrdered, 1)
        XCTAssertEqual(insights.items.first { $0.itemName == "Poke" }?.timesOrdered, 1)
        XCTAssertEqual(insights.items.first { $0.itemName == "Spam Musubi" }?.visitsThatOrdered, 0)
    }
}
