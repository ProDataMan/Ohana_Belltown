import XCTest
@testable import App

final class ScanFeatureTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func writeMenu(_ menu: Menu) throws {
        try JSONEncoder().encode(menu).write(to: tempDir.appendingPathComponent("menu.json"))
        MenuStore.shared.configure(dataDirectory: tempDir.path, resourcesDirectory: tempDir.path)
    }

    private var sampleMenu: Menu {
        Menu(restaurant: "Ohana", lastUpdated: "now", categories: [
            MenuCategory(section: "menu", name: "Entrees", note: nil, items: [
                MenuItem(id: "katsu", name: "Chicken Katsu"),
                MenuItem(id: "kalua", name: "Kalua Pork", scanPitch: "Our own words"),
                MenuItem(id: "tacos", name: "Kalua Pork Tacos"),
            ]),
            MenuCategory(section: "drinks", name: "Cocktails", note: nil, items: [MenuItem(id: "bh", name: "Blue Hawaiian")]),
            MenuCategory(section: "happy_hour", name: "Drinks", note: nil, items: [MenuItem(id: "bh-hh", name: "Blue Hawaiian")]),
        ])
    }

    func testStartingPitchesAreAppliedOnceByExactNameAndSection() throws {
        try writeMenu(sampleMenu)
        let items = Dictionary(uniqueKeysWithValues: try MenuStore.shared.get().categories.flatMap(\.items).map { ($0.id, $0) })
        XCTAssertTrue(items["katsu"]?.scanPitch?.contains("Broke da mouth") == true)
        XCTAssertEqual(items["kalua"]?.scanPitch, "Our own words", "an existing pitch is kept")
        XCTAssertNil(items["tacos"]?.scanPitch, "only the exact name matches")
        XCTAssertTrue(items["bh"]?.scanPitch?.contains("Aloha in a glass") == true)
        XCTAssertTrue(items["bh-hh"]?.scanPitch?.contains("Happy Hour") == true)

        // Staff clear one; a save (which never carries the flag) and a
        // restart must not bring it back.
        var menu = try MenuStore.shared.get()
        menu.categories[0].items[0].scanPitch = nil
        menu.scanPitchesSeeded = false
        try MenuStore.shared.save(menu)
        MenuStore.shared.configure(dataDirectory: tempDir.path, resourcesDirectory: tempDir.path)
        XCTAssertNil(try MenuStore.shared.get().categories[0].items[0].scanPitch)
    }

    func testLycheeMartiniPhotoFixAppliesOnceToBothMenus() throws {
        var menu = sampleMenu
        menu.categories[1].items.append(MenuItem(id: "lm", name: "Lychee Martini", images: ["/uploads/olive.jpg"]))
        menu.categories[2].items.append(MenuItem(id: "lm-hh", name: "Lychee Martini", images: ["/uploads/olive.jpg"]))
        try writeMenu(menu)
        let items = Dictionary(uniqueKeysWithValues: try MenuStore.shared.get().categories.flatMap(\.items).map { ($0.id, $0) })
        XCTAssertEqual(items["lm"]?.images, ["/images/lychee-martini.jpg"])
        XCTAssertEqual(items["lm-hh"]?.images, ["/images/lychee-martini.jpg"])

        // A later edit (e.g. staff upload their own photo) survives a save
        // and a restart.
        var edited = try MenuStore.shared.get()
        edited.appliedFixes = []
        edited.categories[1].items[1].images = ["/uploads/our-own.jpg"]
        try MenuStore.shared.save(edited)
        MenuStore.shared.configure(dataDirectory: tempDir.path, resourcesDirectory: tempDir.path)
        XCTAssertEqual(try MenuStore.shared.get().categories[1].items[1].images, ["/uploads/our-own.jpg"])
    }

    func testBlankPitchDecodesAsNotFeatured() throws {
        let item = try JSONDecoder().decode(MenuItem.self, from: Data(#"{"name":"Poke","scanPitch":"   "}"#.utf8))
        XCTAssertNil(item.scanPitch)
        let kept = try JSONDecoder().decode(MenuItem.self, from: Data(#"{"name":"Poke","scanPitch":" Try it! "}"#.utf8))
        XCTAssertEqual(kept.scanPitch, "Try it!")
    }

    private func visit(_ id: String, table: String, shown: [String], tapped: [String] = []) -> QRVisitSummary {
        QRVisitSummary(
            visitId: id, table: table, source: "table", device: nil, deviceId: "d-\(id)", customerId: nil, customerName: nil,
            startedAt: "2026-11-15T03:00:00Z", lastSeenAt: "2026-11-15T03:05:00Z", durationSeconds: 300, pageViews: 1,
            pages: ["/menu"], detailViews: [], photoTaps: [], searches: [], emptySearches: [], addedToOrder: [],
            featureShown: shown, featureTapped: tapped, landingPage: "/menu", firstTapSeconds: nil, previousVisits: 0, timeline: []
        )
    }

    func testInsightsCompareOrdersWhenFeaturedAgainstOtherwise() {
        func ticket(_ id: String, table: String, items: [String]) -> PosOrder {
            PosOrder(id: id, source: "csv", ticketNumber: id, table: table, room: nil, openedAt: "2026-11-15T03:10:00Z",
                     closedAt: "2026-11-15T04:00:00Z", guestCount: 2,
                     items: items.map { PosOrderItem(name: $0, quantity: 1, netSales: 20) }, netSales: 40)
        }
        let visits = [
            visit("a", table: "30", shown: ["Chicken Katsu"], tapped: ["Chicken Katsu"]),
            visit("b", table: "28", shown: ["Chicken Katsu"]),
            visit("c", table: "26", shown: ["Kalua Pork"]),
            visit("d", table: "24", shown: []),
        ]
        let orders = [
            ticket("1", table: "30", items: ["CHICKEN KATSU"]),
            ticket("2", table: "28", items: ["Poke"]),
            ticket("3", table: "26", items: ["Chicken Katsu"]),
            ticket("4", table: "24", items: ["Poke"]),
        ]
        let insights = QRInsightsBuilder.build(visits: visits, from: .distantPast, to: .distantFuture, menu: nil, orders: orders)
        let katsu = insights.scanFeatures.first { $0.itemName == "Chicken Katsu" }!
        XCTAssertEqual(katsu.shown, 2)
        XCTAssertEqual(katsu.tapped, 1)
        XCTAssertEqual(katsu.visitsWithTicketWhenShown, 2)
        XCTAssertEqual(katsu.orderedWhenShown, 1)
        XCTAssertEqual(katsu.visitsWithTicketWhenNotShown, 2)
        XCTAssertEqual(katsu.orderedWhenNotShown, 1)
        XCTAssertEqual(insights.scanFeatures.map(\.itemName), ["Chicken Katsu", "Kalua Pork"])
    }
}
