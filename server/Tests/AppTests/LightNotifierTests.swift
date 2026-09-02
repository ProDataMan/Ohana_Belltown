import XCTest
@testable import App

final class LightNotifierTests: XCTestCase {
    func testMenuSectionMapsToPrepStation() {
        XCTAssertEqual(PrepStation.from(menuSection: "drinks"), .bar)
        XCTAssertEqual(PrepStation.from(menuSection: "sushi"), .sushi)
        XCTAssertEqual(PrepStation.from(menuSection: "menu"), .kitchen)
        XCTAssertEqual(PrepStation.from(menuSection: "happy_hour"), .kitchen)
        XCTAssertEqual(PrepStation.from(menuSection: nil), .kitchen)
    }

    func testMapStageColorsMatchCSS() {
        XCTAssertEqual(PrepStation.needsEntryGold.hex, "f2a93c")
        XCTAssertEqual(PrepStation.processingPurple.hex, "8f5fd6")
        XCTAssertEqual(PrepStation.awaitingPink.hex, "ff2f8f")
    }

    func testAreaNeedsEntryColorsAreDistinct() {
        let colors = Set(PrepStation.allCases.map { $0.needsEntryColor.hex })
        XCTAssertEqual(colors.count, 3)
        XCTAssertEqual(PrepStation.kitchen.needsEntryColor.hex, PrepStation.needsEntryGold.hex)
    }

    func testTuyaColourDataIsTwelveHexDigits() {
        let gold = PrepStation.needsEntryGold.tuyaColourData
        XCTAssertEqual(gold.count, 12)
        XCTAssertNotNil(Int(gold, radix: 16))
    }

    func testNeedsEntryOnlyHitsServerStation() {
        for station in PrepStation.allCases {
            let cues = LightCuePlanner.cues(forPlacedAt: station)
            XCTAssertEqual(cues.map(\.fixture), [.server])
            XCTAssertEqual(cues.first?.pattern, .pulseThirtySeconds)
            XCTAssertEqual(cues.first?.color, station.needsEntryColor)
        }
    }

    func testConfirmEntryFlashesPrepStationAndServerThreeTimes() {
        let cues = LightCuePlanner.cues(forEnteredAt: .sushi)
        XCTAssertEqual(cues.map(\.fixture), [.sushi, .server])
        XCTAssertTrue(cues.allSatisfy { $0.pattern == .threeFlash })
        XCTAssertTrue(cues.allSatisfy { $0.color == PrepStation.processingPurple })
    }

    func testOrderUpFlashesPrepStationThreeTimesAndHoldsServerPink() {
        let cues = LightCuePlanner.cues(forReadyAt: .bar)
        XCTAssertEqual(cues[0].fixture, .bar)
        XCTAssertEqual(cues[0].pattern, .threeFlash)
        XCTAssertEqual(cues[0].color, PrepStation.awaitingPink)
        XCTAssertEqual(cues[1].fixture, .server)
        XCTAssertEqual(cues[1].pattern, .pulseUntilStopped)
        XCTAssertEqual(cues[1].color, PrepStation.awaitingPink)
    }

    func testKitchenDoesNotReceiveDrinkCues() {
        let placed = LightCuePlanner.cues(forPlacedAt: .bar)
        XCTAssertFalse(placed.contains { $0.fixture == .kitchen })
        let entered = LightCuePlanner.cues(forEnteredAt: .bar)
        XCTAssertFalse(entered.contains { $0.fixture == .kitchen || $0.fixture == .sushi })
    }

    func testReadyForDeliveryReturnsOnlyPastEstimate() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        TableOrdersStore.shared.configure(dataDirectory: tempDir.path)

        let entry = try TableOrdersStore.shared.place(
            tableId: "46", itemName: "California Roll", itemId: nil, section: "sushi", customerId: nil
        )
        try TableOrdersStore.shared.markEntered(id: entry.id, staffOnDuty: 10)
        XCTAssertTrue(try TableOrdersStore.shared.readyForDelivery().isEmpty)
        XCTAssertEqual(try TableOrdersStore.shared.readyForDeliveryCount(), 0)
    }
}
