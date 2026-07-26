import XCTest
@testable import App

final class WaitlistStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        WaitlistStore.shared.configure(dataDirectory: tempDir.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testJoinAddsToActiveQueue() throws {
        let entry = try WaitlistStore.shared.join(name: "Kai", phone: "206-555-1234", partySize: 3, note: nil)
        XCTAssertEqual(entry.status, "waiting")
        XCTAssertEqual(entry.phone, "2065551234")

        let active = try WaitlistStore.shared.active()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active[0].name, "Kai")
    }

    func testActiveQueueIsOldestFirst() throws {
        try WaitlistStore.shared.join(name: "First", phone: "2065551111", partySize: 2, note: nil)
        try WaitlistStore.shared.join(name: "Second", phone: "2065552222", partySize: 4, note: nil)

        let active = try WaitlistStore.shared.active()
        XCTAssertEqual(active.map { $0.name }, ["First", "Second"])
    }

    func testMarkNotifiedKeepsEntryOnActiveQueue() throws {
        let entry = try WaitlistStore.shared.join(name: "Kai", phone: "2065551234", partySize: 2, note: nil)
        let notified = try WaitlistStore.shared.markNotified(id: entry.id)
        XCTAssertEqual(notified.status, "notified")

        // Still shown on the live queue until staff actually removes them —
        // "notified" just means staff has reached out, not that the table's filled.
        let active = try WaitlistStore.shared.active()
        XCTAssertEqual(active.count, 1)
    }

    func testRemoveTakesEntryOffActiveQueue() throws {
        let entry = try WaitlistStore.shared.join(name: "Kai", phone: "2065551234", partySize: 2, note: nil)
        try WaitlistStore.shared.remove(id: entry.id)

        let active = try WaitlistStore.shared.active()
        XCTAssertTrue(active.isEmpty)
    }

    func testRemovingUnknownEntryThrows() throws {
        XCTAssertThrowsError(try WaitlistStore.shared.remove(id: "does-not-exist")) { error in
            guard let waitlistError = error as? WaitlistError else { return XCTFail("wrong error type") }
            XCTAssertEqual(waitlistError, .entryNotFound)
        }
    }

    func testStaleEntriesDropOffTheActiveQueue() throws {
        let staleTimestamp = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(-(WaitlistStore.staleAfterSeconds + 60))
        )
        let seeded = [
            WaitlistEntry(
                id: UUID().uuidString, name: "Stale", phone: "2065551234", partySize: 2, note: nil,
                status: "waiting", createdAt: staleTimestamp, updatedAt: staleTimestamp
            )
        ]
        try JSONEncoder().encode(seeded).write(to: tempDir.appendingPathComponent("waitlist.json"))
        WaitlistStore.shared.configure(dataDirectory: tempDir.path)

        let active = try WaitlistStore.shared.active()
        XCTAssertTrue(active.isEmpty, "an entry older than the stale window shouldn't show on the live queue")
    }
}
