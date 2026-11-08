import XCTest
@testable import App

final class QRInsightsTests: XCTestCase {
    private let iso = ISO8601DateFormatter()

    /// A Wednesday at 3pm Pacific (PST, the start of Happy Hour), plus `minutes`.
    private func at(_ minutes: Double) -> String {
        iso.string(from: iso.date(from: "2026-11-04T23:00:00Z")!.addingTimeInterval(minutes * 60))
    }

    private func visit(
        _ id: String, table: String?, device: String, start: Double, minutes: Double = 5,
        source: String = "table", pages: [String] = ["/menu"], details: [String] = [],
        photos: [String] = [], searches: [String] = [], emptySearches: [String] = [],
        added: [String] = [], previousVisits: Int = 0, firstTap: Double? = nil, phone: String = "iPhone · Safari"
    ) -> QRVisitSummary {
        let detailEvents = details.map { QRVisitTimelineEntry(type: "details", at: at(start + 1), page: pages.last, itemName: $0, query: nil, resultCount: nil) }
        return QRVisitSummary(
            visitId: id, table: table, source: source, device: phone, deviceId: device, customerId: nil,
            customerName: nil, startedAt: at(start), lastSeenAt: at(start + minutes),
            durationSeconds: minutes * 60, pageViews: pages.count, pages: pages,
            detailViews: details.map { QRVisitItemCount(itemName: $0, count: 1) },
            photoTaps: photos.map { QRVisitItemCount(itemName: $0, count: 1) },
            searches: searches, emptySearches: emptySearches, addedToOrder: added,
            landingPage: pages.first, firstTapSeconds: firstTap, previousVisits: previousVisits,
            timeline: detailEvents
        )
    }

    private func build(_ visits: [QRVisitSummary], menu: Menu? = nil) -> QRInsights {
        QRInsightsBuilder.build(visits: visits, from: .distantPast, to: .distantFuture, menu: menu)
    }

    func testFloorMapCountsEveryTableIncludingUnscannedOnes() {
        let insights = build([
            visit("v1", table: "30", device: "d1", start: 0, details: ["Poke"]),
            visit("v2", table: "30", device: "d2", start: 60),
            visit("v3", table: "84", device: "d3", start: 0),
            visit("v4", table: nil, device: "d4", start: 0, source: "front-door"),
        ])
        XCTAssertEqual(insights.totalVisits, 4)
        XCTAssertEqual(insights.tables.count, TableMap.entries.count)
        let t30 = insights.tables.first { $0.table == "30" }
        XCTAssertEqual(t30?.visits, 2)
        XCTAssertEqual(t30?.devices, 2)
        XCTAssertEqual(t30?.detailViews, 1)
        XCTAssertEqual(insights.tables.first { $0.table == "R1" }?.visits, 0)
        XCTAssertEqual(insights.sections.first { $0.section == "dining" }?.visits, 2)
        XCTAssertEqual(insights.sections.first { $0.section == "none" }?.visits, 1)
    }

    func testSectionStatsAndTimeBuckets() {
        let insights = build([
            visit("v1", table: "30", device: "d1", start: 0, details: ["Poke", "Musubi"], previousVisits: 1, firstTap: 10),
            visit("v2", table: "28", device: "d2", start: 0, details: ["Poke"], firstTap: 30, phone: "Android · Chrome"),
            visit("v3", table: "26", device: "d3", start: 0),
        ])
        let dining = insights.sections.first { $0.section == "dining" }!
        XCTAssertEqual(dining.tablesWithVisits, 3)
        XCTAssertEqual(dining.avgFirstTapSeconds, 20)
        XCTAssertEqual(dining.openedItemRate!, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(dining.returningRate!, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(dining.topItems.first?.label, "Poke")
        XCTAssertEqual(dining.topItems.first?.count, 2)
        XCTAssertEqual(Set(dining.deviceMix.map(\.label)), ["iPhone", "Android"])
        // 3pm Wednesday Pacific.
        XCTAssertEqual(insights.byHour.map(\.bucket), [15])
        XCTAssertEqual(insights.byWeekday.map(\.bucket), [4])
    }

    func testPartiesGroupPhonesOnOneTableWithinTwentyMinutes() {
        let insights = build([
            visit("v1", table: "30", device: "d1", start: 0),
            visit("v2", table: "30", device: "d2", start: 5),
            visit("v3", table: "30", device: "d3", start: 19),
            // A new party at the same table later on.
            visit("v4", table: "30", device: "d4", start: 90),
            // Same phone scanning twice is still one phone.
            visit("v5", table: "84", device: "d5", start: 0),
            visit("v6", table: "84", device: "d5", start: 2),
        ])
        XCTAssertEqual(insights.parties.parties, 3)
        XCTAssertEqual(insights.parties.phonesPerParty.first { $0.label == "1" }?.count, 2)
        XCTAssertEqual(insights.parties.phonesPerParty.first { $0.label == "3" }?.count, 1)
    }

    func testHappyHourCardItemsSearchesPathsAndReturning() {
        let menu = Menu(restaurant: "Ohana", lastUpdated: "now", categories: [
            MenuCategory(section: "menu", name: "Food", note: nil, items: [
                MenuItem(id: "1", name: "Poke", description: nil, price: 10, images: ["/uploads/p.jpg"]),
                MenuItem(id: "2", name: "Musubi", description: nil, price: 5, images: []),
            ]),
        ])
        let insights = build([
            visit("v1", table: "30", device: "d1", start: 0, source: "happy-hour-card", pages: ["/happy-hour"], details: ["Poke"]),
            visit("v2", table: "28", device: "d1", start: 100, source: "happy-hour-card", pages: ["/happy-hour", "/menu"],
                  details: ["Musubi"], photos: ["Musubi"], searches: ["gyoza", "poke"], emptySearches: ["gyoza"], added: ["Musubi"]),
            visit("v3", table: "26", device: "d2", start: 0, details: ["Gone Dish"]),
        ], menu: menu)

        XCTAssertEqual(insights.happyHour.cardVisits, 2)
        XCTAssertEqual(insights.happyHour.cardStayedOnHappyHour, 1)
        XCTAssertEqual(insights.happyHour.cardWentToOtherPages, 1)
        // All three start between 3:00 and 4:40pm on a weekday.
        XCTAssertEqual(insights.happyHour.visitsDuringHappyHour, 3)
        XCTAssertEqual(insights.happyHour.duringHappyHourOpenedHappyHourItem, 1)

        let musubi = insights.items.first { $0.itemName == "Musubi" }!
        XCTAssertEqual(musubi.photoTaps, 1)
        XCTAssertEqual(musubi.addedToOrder, 1)
        XCTAssertFalse(musubi.hasPhoto)
        XCTAssertTrue(insights.items.first { $0.itemName == "Poke" }!.hasPhoto)
        XCTAssertFalse(insights.items.first { $0.itemName == "Gone Dish" }!.onMenu)

        XCTAssertEqual(insights.searches.first { $0.query == "gyoza" }?.emptyCount, 1)
        XCTAssertEqual(insights.searches.first { $0.query == "poke" }?.emptyCount, 0)
        XCTAssertEqual(insights.paths.first { $0.pages == ["/happy-hour", "/menu"] }?.visits, 1)

        XCTAssertEqual(insights.returning.devices, 2)
        XCTAssertEqual(insights.returning.returningDevices, 1)
        XCTAssertEqual(insights.returning.multiVisitDevicesInRange, 1)
        XCTAssertEqual(insights.returning.sameSectionDevices, 1)
    }
}
