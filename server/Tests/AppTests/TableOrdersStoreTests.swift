import XCTest
@testable import App

final class TableOrdersStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        TableOrdersStore.shared.configure(dataDirectory: tempDir.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testPlaceAddsToPendingQueue() throws {
        let entry = try TableOrdersStore.shared.place(tableId: "5", itemName: "Spam Musubi")
        XCTAssertEqual(entry.status, "pending")

        let pending = try TableOrdersStore.shared.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].tableId, "5")
        XCTAssertEqual(pending[0].itemName, "Spam Musubi")
    }

    func testPendingQueueIsOldestFirst() throws {
        try TableOrdersStore.shared.place(tableId: "1", itemName: "First")
        try TableOrdersStore.shared.place(tableId: "2", itemName: "Second")

        let pending = try TableOrdersStore.shared.pending()
        XCTAssertEqual(pending.map { $0.itemName }, ["First", "Second"])
    }

    func testAcknowledgeTakesEntryOffPendingQueue() throws {
        let entry = try TableOrdersStore.shared.place(tableId: "5", itemName: "Spam Musubi")
        let acknowledged = try TableOrdersStore.shared.acknowledge(id: entry.id)
        XCTAssertEqual(acknowledged.status, "acknowledged")

        let pending = try TableOrdersStore.shared.pending()
        XCTAssertTrue(pending.isEmpty)
    }

    func testAcknowledgingUnknownEntryThrows() throws {
        XCTAssertThrowsError(try TableOrdersStore.shared.acknowledge(id: "does-not-exist")) { error in
            guard let orderError = error as? TableOrderError else { return XCTFail("wrong error type") }
            XCTAssertEqual(orderError, .entryNotFound)
        }
    }

    func testStaleEntriesDropOffThePendingQueue() throws {
        let staleTimestamp = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(-(TableOrdersStore.staleAfterSeconds + 60))
        )
        let seeded = [
            TableOrderEntry(
                id: UUID().uuidString, tableId: "5", itemName: "Spam Musubi",
                status: "pending", createdAt: staleTimestamp, updatedAt: staleTimestamp
            )
        ]
        try JSONEncoder().encode(seeded).write(to: tempDir.appendingPathComponent("table-orders.json"))
        TableOrdersStore.shared.configure(dataDirectory: tempDir.path)

        let pending = try TableOrdersStore.shared.pending()
        XCTAssertTrue(pending.isEmpty, "an order older than the stale window shouldn't show on the live queue")
    }
}
