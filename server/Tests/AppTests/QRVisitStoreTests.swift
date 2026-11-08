import XCTest
@testable import App

final class QRVisitStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        QRVisitStore.shared.configure(dataDirectory: tempDir.path)
        MenuItemEngagementStore.shared.configure(dataDirectory: tempDir.path)
        CustomerUserStore.shared.configure(dataDirectory: tempDir.path)
    }

    override func tearDownWithError() throws {
        QRVisitStore.shared.flush()
        MenuItemEngagementStore.shared.flush()
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func event(_ type: String, visit: String = "visit-aaaa-0001", device: String = "device-aaaa-0001",
                       table: String? = "5", item: String? = nil, at: Date = Date()) -> QRVisitEvent {
        QRVisitEvent(
            visitId: visit, deviceId: device, customerId: nil, table: table,
            source: type == "start" ? "table" : nil, device: nil, type: type,
            page: "/menu", itemName: item, query: nil, at: ISO8601DateFormatter().string(from: at)
        )
    }

    private var wholeDay: (Date, Date) { (Date().addingTimeInterval(-86_400), Date().addingTimeInterval(60)) }

    func testEventsSurviveAReloadFromDisk() {
        XCTAssertTrue(QRVisitStore.shared.record(event("start")))
        XCTAssertTrue(QRVisitStore.shared.record(event("details", item: "Poke")))
        QRVisitStore.shared.configure(dataDirectory: tempDir.path)

        let visits = QRVisitStore.shared.visits(from: wholeDay.0, to: wholeDay.1)
        XCTAssertEqual(visits.count, 1)
        XCTAssertEqual(visits[0].detailViews.map(\.itemName), ["Poke"])
    }

    func testRejectsJunkIdsAndUnknownTypes() {
        XCTAssertFalse(QRVisitStore.shared.record(event("start", visit: "short")))
        XCTAssertFalse(QRVisitStore.shared.record(event("start", device: "has spaces in it")))
        XCTAssertFalse(QRVisitStore.shared.record(event("delete-everything")))
        XCTAssertTrue(QRVisitStore.shared.visits(from: wholeDay.0, to: wholeDay.1).isEmpty)
    }

    func testCapsEventsPerVisit() {
        for _ in 0..<QRVisitStore.maxEventsPerVisit {
            QRVisitStore.shared.record(event("page"))
        }
        XCTAssertFalse(QRVisitStore.shared.record(event("page")))
    }

    func testVisitsAreFilteredByStartTimeAndTableAndCountRepeatDevices() {
        let earlier = Date().addingTimeInterval(-3 * 3600)
        QRVisitStore.shared.record(event("start", visit: "visit-old-00001", table: "5", at: earlier))
        QRVisitStore.shared.record(event("start", visit: "visit-new-00001", table: "5"))
        QRVisitStore.shared.record(event("start", visit: "visit-new-00002", device: "device-bbbb-0002", table: "9"))

        let table5 = QRVisitStore.shared.visits(from: Date().addingTimeInterval(-3600), to: wholeDay.1, table: "5")
        XCTAssertEqual(table5.map(\.visitId), ["visit-new-00001"])
        XCTAssertEqual(table5[0].previousVisits, 1)

        let all = QRVisitStore.shared.visits(from: Date().addingTimeInterval(-3600), to: wholeDay.1)
        XCTAssertEqual(Set(all.map(\.table)), ["5", "9"])
    }

    func testEngagementStoreMigratesLegacyJSONArrayToAppendOnlyLog() throws {
        let legacy = [MenuItemEngagementEvent(
            id: "1", menuItemName: "Poke", clickType: "details", deviceId: "d1", customerId: nil,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )]
        try JSONEncoder().encode(legacy).write(to: tempDir.appendingPathComponent("menu-item-engagement.json"))
        MenuItemEngagementStore.shared.configure(dataDirectory: tempDir.path)

        try MenuItemEngagementStore.shared.record(menuItemName: "Poke", clickType: .details, deviceId: "d2", customerId: nil)
        MenuItemEngagementStore.shared.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("menu-item-engagement.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("menu-item-engagement.json.migrated").path))

        MenuItemEngagementStore.shared.configure(dataDirectory: tempDir.path)
        let summary = try MenuItemEngagementStore.shared.summary(days: 1)
        XCTAssertEqual(summary.first?.totalClicks, 2)
        XCTAssertEqual(summary.first?.uniqueDevices, 2)
    }
}
