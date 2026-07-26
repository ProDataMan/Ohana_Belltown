import XCTest
@testable import App

final class AnalyticsStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        AnalyticsStore.shared.configure(dataDirectory: tempDir.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testDeviceTypeClassification() {
        XCTAssertEqual(AnalyticsStore.deviceType(from: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Mobile/15E148"), "mobile")
        XCTAssertEqual(AnalyticsStore.deviceType(from: "Mozilla/5.0 (Linux; Android 14) Mobile"), "mobile")
        XCTAssertEqual(AnalyticsStore.deviceType(from: "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X)"), "tablet")
        XCTAssertEqual(AnalyticsStore.deviceType(from: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15)"), "desktop")
        XCTAssertEqual(AnalyticsStore.deviceType(from: nil), "unknown")
    }

    func testRecordViewTracksPathAndDevice() throws {
        AnalyticsStore.shared.recordView(path: "/menu", userAgent: "Mozilla/5.0 (iPhone) Mobile/15E148")
        AnalyticsStore.shared.recordView(path: "/menu", userAgent: "Mozilla/5.0 (Macintosh)")

        let summary = try AnalyticsStore.shared.summary(days: 7)
        XCTAssertEqual(summary.totalViews, 2)
        XCTAssertEqual(summary.topPages.first?.path, "/menu")
        XCTAssertEqual(summary.topPages.first?.count, 2)

        let deviceCounts = Dictionary(uniqueKeysWithValues: summary.deviceBreakdown.map { ($0.device, $0.count) })
        XCTAssertEqual(deviceCounts["mobile"], 1)
        XCTAssertEqual(deviceCounts["desktop"], 1)
    }

    func testExcludedPagesDoNotAppearInTopPages() throws {
        AnalyticsStore.shared.recordView(path: "/edit.html", userAgent: nil)
        AnalyticsStore.shared.recordView(path: "/menu", userAgent: nil)

        let summary = try AnalyticsStore.shared.summary(days: 7)
        XCTAssertFalse(summary.topPages.contains { $0.path == "/edit.html" })
        XCTAssertTrue(summary.topPages.contains { $0.path == "/menu" })
    }

    func testItemViewsAreCountedAndRankedMostViewedFirst() throws {
        AnalyticsStore.shared.recordItemView(name: "Volcano Roll")
        AnalyticsStore.shared.recordItemView(name: "Volcano Roll")
        AnalyticsStore.shared.recordItemView(name: "Spam Musubi")

        let summary = try AnalyticsStore.shared.summary(days: 7)
        XCTAssertEqual(summary.topItems.first?.name, "Volcano Roll")
        XCTAssertEqual(summary.topItems.first?.count, 2)

        let topNames = try AnalyticsStore.shared.topItemNames(days: 7, limit: 1)
        XCTAssertEqual(topNames, ["Volcano Roll"])
    }

    func testDwellAveragesAcrossSamplesAndIgnoresOutOfRangeValues() throws {
        AnalyticsStore.shared.recordDwell(path: "/menu", seconds: 10)
        AnalyticsStore.shared.recordDwell(path: "/menu", seconds: 20)
        AnalyticsStore.shared.recordDwell(path: "/menu", seconds: 30)
        // Out of range — should be silently dropped, not skew the average.
        AnalyticsStore.shared.recordDwell(path: "/menu", seconds: 0.1)
        AnalyticsStore.shared.recordDwell(path: "/menu", seconds: 999_999)

        let summary = try AnalyticsStore.shared.summary(days: 7)
        let menuDwell = try XCTUnwrap(summary.pageDwell.first { $0.path == "/menu" })
        XCTAssertEqual(menuDwell.samples, 3)
        XCTAssertEqual(menuDwell.avgSeconds, 20, accuracy: 0.01)
    }

    func testDwellRequiresAtLeastThreeSamplesToAppear() throws {
        AnalyticsStore.shared.recordDwell(path: "/about", seconds: 15)
        AnalyticsStore.shared.recordDwell(path: "/about", seconds: 25)

        let summary = try AnalyticsStore.shared.summary(days: 7)
        XCTAssertFalse(summary.pageDwell.contains { $0.path == "/about" })
    }

    func testOldAnalyticsFileWithoutNewFieldsStillDecodes() throws {
        let legacyJSON = """
        [{"date":"2026-01-01","counts":{"/menu":5}}]
        """
        try legacyJSON.write(to: tempDir.appendingPathComponent("analytics.json"), atomically: true, encoding: .utf8)
        AnalyticsStore.shared.configure(dataDirectory: tempDir.path)

        let summary = try AnalyticsStore.shared.summary(days: 365)
        XCTAssertEqual(summary.topPages.first?.count, 5)
        XCTAssertTrue(summary.deviceBreakdown.isEmpty)
        XCTAssertTrue(summary.topItems.isEmpty)
    }
}
