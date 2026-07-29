import XCTest
@testable import App

final class CompetitorPricingStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        CompetitorPricingStore.shared.configure(dataDirectory: tempDir.path)
        MenuStore.shared.configure(dataDirectory: tempDir.path, resourcesDirectory: tempDir.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func seedMenuItem(id: String, name: String, price: Double?) throws {
        let menu = Menu(restaurant: "Ohana", lastUpdated: "now", categories: [
            MenuCategory(section: "menu", name: "Test Category", note: nil, items: [
                MenuItem(id: id, name: name, price: price)
            ])
        ])
        _ = try MenuStore.shared.save(menu)
    }

    func testSaveRestaurantsRoundTrips() throws {
        let saved = try CompetitorPricingStore.shared.saveRestaurants([
            CompetitorRestaurant(name: "Toulouse Petit", distanceMiles: 0.3),
            CompetitorRestaurant(name: "Some Other Place", distanceMiles: 1.8),
        ])
        XCTAssertEqual(saved.count, 2)

        let loaded = try CompetitorPricingStore.shared.restaurants()
        // Sorted nearest-first.
        XCTAssertEqual(loaded.map(\.name), ["Toulouse Petit", "Some Other Place"])
    }

    func testSavingRestaurantsCascadeDeletesTheirEntries() throws {
        let restaurants = try CompetitorPricingStore.shared.saveRestaurants([
            CompetitorRestaurant(id: "r1", name: "Restaurant One"),
        ])
        let groups = try CompetitorPricingStore.shared.saveGroups([
            MenuPriceComparisonGroup(id: "g1", label: "Cheeseburger"),
        ])
        _ = try CompetitorPricingStore.shared.saveEntries([
            CompetitorPriceEntry(id: "e1", groupId: groups[0].id, restaurantId: restaurants[0].id, price: 16, checkedAt: "2026-07-29"),
        ])
        XCTAssertEqual(try CompetitorPricingStore.shared.entries().count, 1)

        // Removing the restaurant (an empty list, since it's the only one) should
        // drop any entry that pointed at it, not leave an orphaned reference.
        try CompetitorPricingStore.shared.saveRestaurants([])
        XCTAssertEqual(try CompetitorPricingStore.shared.entries().count, 0)
    }

    func testSavingGroupsCascadeDeletesTheirEntries() throws {
        let restaurants = try CompetitorPricingStore.shared.saveRestaurants([CompetitorRestaurant(id: "r1", name: "Restaurant One")])
        _ = try CompetitorPricingStore.shared.saveGroups([MenuPriceComparisonGroup(id: "g1", label: "Cheeseburger")])
        _ = try CompetitorPricingStore.shared.saveEntries([
            CompetitorPriceEntry(id: "e1", groupId: "g1", restaurantId: restaurants[0].id, price: 16, checkedAt: "2026-07-29"),
        ])

        try CompetitorPricingStore.shared.saveGroups([])
        XCTAssertEqual(try CompetitorPricingStore.shared.entries().count, 0)
    }

    func testReportComputesAverageMinMaxAndDeltaAgainstLiveMenuPrice() throws {
        try seedMenuItem(id: "burger-1", name: "Ohana Burger", price: 18)

        let restaurants = try CompetitorPricingStore.shared.saveRestaurants([
            CompetitorRestaurant(id: "r1", name: "Restaurant One"),
            CompetitorRestaurant(id: "r2", name: "Restaurant Two"),
        ])
        let groups = try CompetitorPricingStore.shared.saveGroups([
            MenuPriceComparisonGroup(id: "g1", label: "Classic Burger", ourMenuItemId: "burger-1"),
        ])
        _ = try CompetitorPricingStore.shared.saveEntries([
            CompetitorPriceEntry(id: "e1", groupId: groups[0].id, restaurantId: restaurants[0].id, price: 14, checkedAt: "2026-07-29"),
            CompetitorPriceEntry(id: "e2", groupId: groups[0].id, restaurantId: restaurants[1].id, price: 16, checkedAt: "2026-07-29"),
        ])

        let report = try CompetitorPricingStore.shared.report()
        XCTAssertEqual(report.count, 1)
        let row = report[0]
        XCTAssertEqual(row.ourPrice, 18)
        XCTAssertEqual(row.ourMenuItemName, "Ohana Burger")
        XCTAssertEqual(row.competitorCount, 2)
        XCTAssertEqual(row.competitorAverage, 15)
        XCTAssertEqual(row.competitorMin, 14)
        XCTAssertEqual(row.competitorMax, 16)
        // We're $3 above the $15 average, i.e. 20% over.
        XCTAssertEqual(row.deltaVsAverage ?? 0, 3, accuracy: 0.001)
        XCTAssertEqual(row.deltaPercentVsAverage ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(row.entries.count, 2)
    }

    func testReportHandlesUnlinkedGroupAndNoEntriesGracefully() throws {
        _ = try CompetitorPricingStore.shared.saveGroups([
            MenuPriceComparisonGroup(id: "g1", label: "Something we haven't priced yet"),
        ])

        let report = try CompetitorPricingStore.shared.report()
        XCTAssertEqual(report.count, 1)
        XCTAssertNil(report[0].ourPrice)
        XCTAssertNil(report[0].competitorAverage)
        XCTAssertNil(report[0].deltaVsAverage)
        XCTAssertEqual(report[0].competitorCount, 0)
        XCTAssertTrue(report[0].entries.isEmpty)
    }

    func testReportSkipsEntriesWhoseRestaurantWasRemoved() throws {
        // Guards against a stale entry surviving under a groupId whose
        // restaurant no longer exists in the current restaurants list —
        // shouldn't happen via the store's own cascade-delete, but the
        // report should still degrade gracefully rather than crash if it
        // ever does (e.g. hand-edited data file).
        _ = try CompetitorPricingStore.shared.saveGroups([MenuPriceComparisonGroup(id: "g1", label: "Burger")])
        _ = try CompetitorPricingStore.shared.saveRestaurants([CompetitorRestaurant(id: "r1", name: "Restaurant One")])
        _ = try CompetitorPricingStore.shared.saveEntries([
            CompetitorPriceEntry(id: "e1", groupId: "g1", restaurantId: "ghost-restaurant", price: 12, checkedAt: "2026-07-29"),
        ])

        let report = try CompetitorPricingStore.shared.report()
        XCTAssertEqual(report[0].entries.count, 0)
    }
}
