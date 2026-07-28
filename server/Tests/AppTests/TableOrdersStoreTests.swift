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

    func testPlaceAddsToNeedsEntryQueue() throws {
        let entry = try TableOrdersStore.shared.place(tableId: "5", itemName: "Spam Musubi", itemId: nil, section: "menu", customerId: nil)
        XCTAssertEqual(entry.status, "pending")

        let needsEntry = try TableOrdersStore.shared.needsEntry()
        XCTAssertEqual(needsEntry.count, 1)
        XCTAssertEqual(needsEntry[0].tableId, "5")
        XCTAssertEqual(needsEntry[0].itemName, "Spam Musubi")
    }

    func testNeedsEntryQueueIsOldestFirst() throws {
        try TableOrdersStore.shared.place(tableId: "1", itemName: "First", itemId: nil, section: nil, customerId: nil)
        try TableOrdersStore.shared.place(tableId: "2", itemName: "Second", itemId: nil, section: nil, customerId: nil)

        let needsEntry = try TableOrdersStore.shared.needsEntry()
        XCTAssertEqual(needsEntry.map { $0.itemName }, ["First", "Second"])
    }

    func testMarkEnteredMovesOrderToAwaitingDelivery() throws {
        let entry = try TableOrdersStore.shared.place(tableId: "5", itemName: "Spam Musubi", itemId: nil, section: "menu", customerId: nil)
        let entered = try TableOrdersStore.shared.markEntered(id: entry.id, staffOnDuty: 3)
        XCTAssertEqual(entered.status, "entered")
        XCTAssertNotNil(entered.enteredAt)
        XCTAssertNotNil(entered.estimatedReadyAt, "entering should compute an estimated ready time")

        XCTAssertTrue(try TableOrdersStore.shared.needsEntry().isEmpty)
        let awaiting = try TableOrdersStore.shared.awaitingDelivery()
        XCTAssertEqual(awaiting.count, 1)
        XCTAssertEqual(awaiting[0].id, entry.id)
    }

    func testMarkDeliveredCompletesTheOrder() throws {
        let entry = try TableOrdersStore.shared.place(tableId: "5", itemName: "Spam Musubi", itemId: nil, section: "menu", customerId: nil)
        try TableOrdersStore.shared.markEntered(id: entry.id, staffOnDuty: 3)
        let delivered = try TableOrdersStore.shared.markDelivered(id: entry.id)
        XCTAssertEqual(delivered.status, "delivered")
        XCTAssertNotNil(delivered.deliveredAt)

        XCTAssertTrue(try TableOrdersStore.shared.awaitingDelivery().isEmpty)
    }

    func testEnteringUnknownEntryThrows() throws {
        XCTAssertThrowsError(try TableOrdersStore.shared.markEntered(id: "does-not-exist", staffOnDuty: 3)) { error in
            guard let orderError = error as? TableOrderError else { return XCTFail("wrong error type") }
            XCTAssertEqual(orderError, .entryNotFound)
        }
    }

    func testDeliveringUnknownEntryThrows() throws {
        XCTAssertThrowsError(try TableOrdersStore.shared.markDelivered(id: "does-not-exist")) { error in
            guard let orderError = error as? TableOrderError else { return XCTFail("wrong error type") }
            XCTAssertEqual(orderError, .entryNotFound)
        }
    }

    func testStaleNeedsEntryOrdersDropOffTheQueue() throws {
        let staleTimestamp = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(-(TableOrdersStore.pendingStaleAfterSeconds + 60))
        )
        let seeded = [
            TableOrderEntry(
                id: UUID().uuidString, tableId: "5", itemName: "Spam Musubi",
                status: "pending", createdAt: staleTimestamp, updatedAt: staleTimestamp
            )
        ]
        try JSONEncoder().encode(seeded).write(to: tempDir.appendingPathComponent("table-orders.json"))
        TableOrdersStore.shared.configure(dataDirectory: tempDir.path)

        let needsEntry = try TableOrdersStore.shared.needsEntry()
        XCTAssertTrue(needsEntry.isEmpty, "an order older than the stale window shouldn't show on the live queue")
    }

    func testOldAcknowledgedStatusMigratesToEntered() throws {
        // Backward compatibility: entries persisted under the pre-lifecycle
        // "acknowledged" status should decode as "entered" instead.
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let raw = """
        [{"id":"legacy-1","tableId":"5","itemName":"Spam Musubi","status":"acknowledged","createdAt":"\(timestamp)","updatedAt":"\(timestamp)"}]
        """
        try raw.data(using: .utf8)!.write(to: tempDir.appendingPathComponent("table-orders.json"))
        TableOrdersStore.shared.configure(dataDirectory: tempDir.path)

        let awaiting = try TableOrdersStore.shared.awaitingDelivery()
        XCTAssertEqual(awaiting.map { $0.id }, ["legacy-1"])
    }

    func testOrdersForCustomerFiltersByCustomerId() throws {
        try TableOrdersStore.shared.place(tableId: "5", itemName: "Mine", itemId: nil, section: nil, customerId: "cust-1")
        try TableOrdersStore.shared.place(tableId: "5", itemName: "Not mine", itemId: nil, section: nil, customerId: "cust-2")
        try TableOrdersStore.shared.place(tableId: "5", itemName: "Anonymous", itemId: nil, section: nil, customerId: nil)

        let mine = try TableOrdersStore.shared.ordersForCustomer(customerId: "cust-1")
        XCTAssertEqual(mine.map { $0.itemName }, ["Mine"])
    }

    func testReadyForDeliveryCountReflectsEstimatedReadyTime() throws {
        let entry = try TableOrdersStore.shared.place(tableId: "5", itemName: "Spam Musubi", itemId: nil, section: "drinks", customerId: nil)
        try TableOrdersStore.shared.markEntered(id: entry.id, staffOnDuty: 10)
        // Fresh entry with a generous staff count shouldn't be "ready" immediately.
        XCTAssertEqual(try TableOrdersStore.shared.readyForDeliveryCount(), 0)
    }

    func testDeliveryStatsComputesAveragesFromCompletedOrders() throws {
        let entry = try TableOrdersStore.shared.place(tableId: "5", itemName: "Spam Musubi", itemId: nil, section: "menu", customerId: nil)
        try TableOrdersStore.shared.markEntered(id: entry.id, staffOnDuty: 3)
        try TableOrdersStore.shared.markDelivered(id: entry.id)

        let stats = try TableOrdersStore.shared.deliveryStats(days: 30)
        XCTAssertEqual(stats.completedOrders, 1)
        XCTAssertEqual(stats.items.count, 1)
        XCTAssertEqual(stats.items[0].itemName, "Spam Musubi")
        XCTAssertNotNil(stats.overallAvgTotalMinutes)
    }

    func testDeliveryStatsExcludesIncompleteOrders() throws {
        try TableOrdersStore.shared.place(tableId: "5", itemName: "Still Pending", itemId: nil, section: "menu", customerId: nil)
        let stats = try TableOrdersStore.shared.deliveryStats(days: 30)
        XCTAssertEqual(stats.completedOrders, 0)
        XCTAssertTrue(stats.items.isEmpty)
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func seedEntries(_ entries: [TableOrderEntry]) throws {
        try JSONEncoder().encode(entries).write(to: tempDir.appendingPathComponent("table-orders.json"))
        TableOrdersStore.shared.configure(dataDirectory: tempDir.path)
    }

    func testOccupancyStatsReturnsALabeledBaselineExampleWhenNoSessionsHaveCompleted() throws {
        let stats = try TableOrdersStore.shared.tableOccupancyStats(days: 30)
        XCTAssertEqual(stats.sessions, 0)
        XCTAssertTrue(stats.isBaselineOnly)
        XCTAssertGreaterThan(stats.averageWaitPlusPrepMinutes, 0, "baseline case should still report the generic number it used, not zero")
        XCTAssertGreaterThan(stats.averageEstimatedOccupancyMinutes, 0, "should still show a real (if generic) example estimate, not zero")
    }

    func testOccupancyStatsUsesRealMeasuredTimeForACompletedSession() throws {
        let created = Date().addingTimeInterval(-3600)
        let entered = created.addingTimeInterval(2 * 60)
        let delivered = created.addingTimeInterval(14 * 60)
        try seedEntries([
            TableOrderEntry(
                id: "a", tableId: "5", itemName: "Loco Moco", section: "menu", status: "delivered",
                createdAt: iso(created), updatedAt: iso(delivered), enteredAt: iso(entered), deliveredAt: iso(delivered)
            )
        ])

        let stats = try TableOrdersStore.shared.tableOccupancyStats(days: 30)
        XCTAssertEqual(stats.sessions, 1)
        XCTAssertFalse(stats.isBaselineOnly)
        XCTAssertEqual(stats.averageWaitPlusPrepMinutes, 14, accuracy: 0.01)
        XCTAssertEqual(
            stats.averageEstimatedOccupancyMinutes,
            DiningTimeEstimator.arrivalToOrderMinutes + 14 + stats.averageEstimatedEatingMinutes + DiningTimeEstimator.socialOverheadMinutes,
            accuracy: 0.01
        )
    }

    func testOccupancyStatsGroupsCloseTogetherOrdersAtTheSameTableIntoOneSession() throws {
        let firstCreated = Date().addingTimeInterval(-3600)
        let secondCreated = firstCreated.addingTimeInterval(10 * 60)
        let firstDelivered = firstCreated.addingTimeInterval(15 * 60)
        let secondDelivered = firstCreated.addingTimeInterval(25 * 60)
        try seedEntries([
            TableOrderEntry(
                id: "a", tableId: "5", itemName: "Loco Moco", section: "menu", status: "delivered",
                createdAt: iso(firstCreated), updatedAt: iso(firstDelivered), enteredAt: iso(firstCreated), deliveredAt: iso(firstDelivered)
            ),
            TableOrderEntry(
                id: "b", tableId: "5", itemName: "Mai Tai", section: "drinks", status: "delivered",
                createdAt: iso(secondCreated), updatedAt: iso(secondDelivered), enteredAt: iso(secondCreated), deliveredAt: iso(secondDelivered)
            ),
        ])

        let stats = try TableOrdersStore.shared.tableOccupancyStats(days: 30)
        XCTAssertEqual(stats.sessions, 1, "orders 10 minutes apart at the same table should be one dining session, not two")
        // The whole session's measured time is earliest created -> latest delivered = 25 minutes.
        XCTAssertEqual(stats.averageWaitPlusPrepMinutes, 25, accuracy: 0.01)
    }

    func testOccupancyStatsTreatsALargeGapAsSeparateDiningSessions() throws {
        let firstCreated = Date().addingTimeInterval(-4 * 3600)
        let firstDelivered = firstCreated.addingTimeInterval(15 * 60)
        let secondCreated = Date().addingTimeInterval(-3600) // well past the same-session gap
        let secondDelivered = secondCreated.addingTimeInterval(15 * 60)
        try seedEntries([
            TableOrderEntry(
                id: "a", tableId: "5", itemName: "Loco Moco", section: "menu", status: "delivered",
                createdAt: iso(firstCreated), updatedAt: iso(firstDelivered), enteredAt: iso(firstCreated), deliveredAt: iso(firstDelivered)
            ),
            TableOrderEntry(
                id: "b", tableId: "5", itemName: "Loco Moco", section: "menu", status: "delivered",
                createdAt: iso(secondCreated), updatedAt: iso(secondDelivered), enteredAt: iso(secondCreated), deliveredAt: iso(secondDelivered)
            ),
        ])

        let stats = try TableOrdersStore.shared.tableOccupancyStats(days: 30)
        XCTAssertEqual(stats.sessions, 2, "orders hours apart at the same table are two separate dining parties")
    }

    func testOccupancyStatsExcludesSessionsWithAnyOrderStillInProgress() throws {
        let created = Date().addingTimeInterval(-1800)
        try seedEntries([
            TableOrderEntry(
                id: "a", tableId: "5", itemName: "Loco Moco", section: "menu", status: "entered",
                createdAt: iso(created), updatedAt: iso(created), enteredAt: iso(created)
            )
        ])

        let stats = try TableOrdersStore.shared.tableOccupancyStats(days: 30)
        XCTAssertEqual(stats.sessions, 0, "a session isn't over until every order in it has actually been delivered")
        XCTAssertTrue(stats.isBaselineOnly)
    }
}
