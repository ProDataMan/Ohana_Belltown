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

    func testOperatingSystemClassification() {
        XCTAssertEqual(AnalyticsStore.operatingSystem(from: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"), "iPhone")
        XCTAssertEqual(AnalyticsStore.operatingSystem(from: "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X)"), "iPad")
        XCTAssertEqual(AnalyticsStore.operatingSystem(from: "Mozilla/5.0 (Linux; Android 14; Pixel 8)"), "Android")
        XCTAssertEqual(AnalyticsStore.operatingSystem(from: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"), "macOS")
        XCTAssertEqual(AnalyticsStore.operatingSystem(from: "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"), "Windows")
        XCTAssertEqual(AnalyticsStore.operatingSystem(from: "Mozilla/5.0 (X11; Linux x86_64)"), "Linux")
        XCTAssertEqual(AnalyticsStore.operatingSystem(from: nil), "Unknown")
    }

    func testBrowserClassificationPrefersMoreSpecificTokens() {
        // Edge, Samsung Internet, and Opera all include "Chrome" in their UA —
        // the more specific token has to win.
        XCTAssertEqual(AnalyticsStore.browserName(from: "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36 Edg/120.0"), "Edge")
        XCTAssertEqual(AnalyticsStore.browserName(from: "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120.0 SamsungBrowser/24.0"), "Samsung Internet")
        XCTAssertEqual(AnalyticsStore.browserName(from: "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 Chrome/120.0 Safari/537.36 OPR/106.0"), "Opera")
        XCTAssertEqual(AnalyticsStore.browserName(from: "Mozilla/5.0 (Windows NT 10.0; rv:120.0) Gecko/20100101 Firefox/120.0"), "Firefox")
        XCTAssertEqual(AnalyticsStore.browserName(from: "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"), "Chrome")
        XCTAssertEqual(AnalyticsStore.browserName(from: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"), "Safari")
        XCTAssertEqual(AnalyticsStore.browserName(from: nil), "Unknown")
    }

    func testAndroidModelParsing() {
        XCTAssertEqual(AnalyticsStore.androidModel(from: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36"), "Pixel 8")
        XCTAssertEqual(AnalyticsStore.androidModel(from: "Mozilla/5.0 (Linux; Android 13; SM-G991B Build/TP1A.220624.014) AppleWebKit/537.36"), "SM-G991B")
        // iOS never exposes a hardware model in its UA.
        XCTAssertNil(AnalyticsStore.androidModel(from: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"))
        XCTAssertNil(AnalyticsStore.androidModel(from: nil))
    }

    func testRecordViewTracksOSAndBrowserBreakdowns() throws {
        AnalyticsStore.shared.recordView(path: "/menu", userAgent: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/120.0")
        AnalyticsStore.shared.recordView(path: "/menu", userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Version/17.0 Mobile/15E148 Safari/604.1")

        let summary = try AnalyticsStore.shared.summary(days: 7)
        let osCounts = Dictionary(uniqueKeysWithValues: summary.osBreakdown.map { ($0.os, $0.count) })
        XCTAssertEqual(osCounts["Android"], 1)
        XCTAssertEqual(osCounts["iPhone"], 1)

        let browserCounts = Dictionary(uniqueKeysWithValues: summary.browserBreakdown.map { ($0.browser, $0.count) })
        XCTAssertEqual(browserCounts["Chrome"], 1)
        XCTAssertEqual(browserCounts["Safari"], 1)

        XCTAssertEqual(summary.deviceModelBreakdown.first?.model, "Pixel 8")
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
