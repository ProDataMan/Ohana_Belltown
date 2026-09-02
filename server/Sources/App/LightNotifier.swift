import Foundation
import Vapor

/// Physical Feit/Tuya bulbs driven by table-order lifecycle events.
actor LightNotifier {
    static let shared = LightNotifier()

    static let threeFlashOnMs: UInt64 = 280
    static let threeFlashOffMs: UInt64 = 220
    static let threeFlashCount = 3
    static let needsEntryHoldSeconds: TimeInterval = 30
    static let pulseOnMs: UInt64 = 500
    static let pulseOffMs: UInt64 = 500

    private var client: (any TuyaCommanding)?
    private var deviceIds: [LightFixture: String] = [:]
    private var tasks: [LightFixture: Task<Void, Never>] = [:]
    private var announcedReadyIds = Set<String>()
    private var lastNeedsEntryAt: [PrepStation: Date] = [:]

    func configure(client: (any TuyaCommanding)?, devices: [LightFixture: String]) {
        self.client = client
        self.deviceIds = devices.filter { !$0.value.isEmpty }
        cancelAll()
        announcedReadyIds.removeAll()
    }

    func configureFromEnvironment() {
        configure(client: TuyaCloudClient.fromEnvironment(), devices: LightFixture.devicesFromEnvironment())
    }

    var isEnabled: Bool { client != nil && !deviceIds.isEmpty }

    func notifyPlaced(_ entry: TableOrderEntry) {
        guard isEnabled else { return }
        let station = PrepStation.from(menuSection: entry.section)
        let now = Date()
        if let last = lastNeedsEntryAt[station], now.timeIntervalSince(last) < 2 {
            return
        }
        lastNeedsEntryAt[station] = now
        startPulse(.server, color: station.needsEntryColor, until: now.addingTimeInterval(Self.needsEntryHoldSeconds))
    }

    func notifyEntered(_ entry: TableOrderEntry) {
        guard isEnabled else { return }
        let station = PrepStation.from(menuSection: entry.section)
        stop(.server)
        Task {
            await threeFlashes(on: LightFixture.forPrepStation(station), color: PrepStation.processingPurple)
            await threeFlashes(on: .server, color: PrepStation.processingPurple)
            await resumeServerHoldIfNeeded(excludingReadyPulse: false)
        }
    }

    func notifyReady(_ entry: TableOrderEntry) {
        guard isEnabled else { return }
        guard announcedReadyIds.insert(entry.id).inserted else { return }
        let station = PrepStation.from(menuSection: entry.section)
        Task { await threeFlashes(on: LightFixture.forPrepStation(station), color: PrepStation.awaitingPink) }
        startPulse(.server, color: PrepStation.awaitingPink, until: nil)
    }

    func notifyDelivered(_ entry: TableOrderEntry) {
        guard isEnabled else { return }
        announcedReadyIds.remove(entry.id)
        Task { await resumeServerHoldIfNeeded(excludingReadyPulse: true) }
    }

    private func resumeServerHoldIfNeeded(excludingReadyPulse: Bool) async {
        let ready: [TableOrderEntry]
        let pending: [TableOrderEntry]
        do {
            ready = try TableOrdersStore.shared.readyForDelivery()
            pending = try TableOrdersStore.shared.needsEntry()
        } catch {
            return
        }
        if !ready.isEmpty {
            startPulse(.server, color: PrepStation.awaitingPink, until: nil)
            return
        }
        if excludingReadyPulse { stop(.server) }
        if let oldest = pending.first {
            let station = PrepStation.from(menuSection: oldest.section)
            startPulse(.server, color: station.needsEntryColor, until: Date().addingTimeInterval(Self.needsEntryHoldSeconds))
        } else {
            stop(.server)
        }
    }

    func pollReadyOrders() {
        guard isEnabled else { return }
        let ready: [TableOrderEntry]
        do { ready = try TableOrdersStore.shared.readyForDelivery() } catch { return }
        let liveIds = Set(ready.map(\.id))
        announcedReadyIds = announcedReadyIds.intersection(liveIds)
        for entry in ready { notifyReady(entry) }
        if ready.isEmpty {
            let pending: Int
            do { pending = try TableOrdersStore.shared.needsEntry().count } catch { pending = 0 }
            if pending == 0 { stop(.server) }
        }
    }

    private func startPulse(_ fixture: LightFixture, color: LightColor, until: Date?) {
        guard deviceIds[fixture] != nil else { return }
        stop(fixture)
        tasks[fixture] = Task { [weak self] in
            guard let self else { return }
            await self.runPulse(fixture: fixture, color: color, until: until)
        }
    }

    private func runPulse(fixture: LightFixture, color: LightColor, until: Date?) async {
        while !Task.isCancelled {
            if let until, Date() >= until { break }
            await send(fixture, color: color, on: true)
            try? await Task.sleep(nanoseconds: Self.pulseOnMs * 1_000_000)
            if Task.isCancelled { break }
            await send(fixture, color: color, on: false)
            try? await Task.sleep(nanoseconds: Self.pulseOffMs * 1_000_000)
        }
        if !Task.isCancelled {
            await send(fixture, color: color, on: false)
        }
    }

    private func threeFlashes(on fixture: LightFixture, color: LightColor) async {
        guard deviceIds[fixture] != nil else { return }
        if !(tasks[fixture] != nil && fixture == .server) { stop(fixture) }
        for _ in 0..<Self.threeFlashCount {
            if Task.isCancelled { break }
            await send(fixture, color: color, on: true)
            try? await Task.sleep(nanoseconds: Self.threeFlashOnMs * 1_000_000)
            await send(fixture, color: color, on: false)
            try? await Task.sleep(nanoseconds: Self.threeFlashOffMs * 1_000_000)
        }
    }

    private func send(_ fixture: LightFixture, color: LightColor, on: Bool) async {
        guard let client, let deviceId = deviceIds[fixture] else { return }
        try? await client.setColor(deviceId: deviceId, color: color, on: on)
    }

    private func stop(_ fixture: LightFixture) {
        tasks[fixture]?.cancel()
        tasks[fixture] = nil
    }

    private func cancelAll() {
        LightFixture.allCases.forEach { stop($0) }
    }

    static func scheduleReadyPoll(_ app: Application) {
        app.eventLoopGroup.next().scheduleRepeatedTask(initialDelay: .seconds(5), delay: .seconds(5)) { _ in
            let promise = app.eventLoopGroup.next().makePromise(of: Void.self)
            promise.completeWithTask { await LightNotifier.shared.pollReadyOrders() }
        }
    }
}

enum LightPattern: String, Equatable, Sendable {
    case threeFlash
    case pulseThirtySeconds
    case pulseUntilStopped
}

struct LightCue: Equatable, Sendable {
    var fixture: LightFixture
    var color: LightColor
    var pattern: LightPattern
}

enum LightCuePlanner {
    static func cues(forPlacedAt station: PrepStation) -> [LightCue] {
        [LightCue(fixture: .server, color: station.needsEntryColor, pattern: .pulseThirtySeconds)]
    }
    static func cues(forEnteredAt station: PrepStation) -> [LightCue] {
        [
            LightCue(fixture: LightFixture.forPrepStation(station), color: PrepStation.processingPurple, pattern: .threeFlash),
            LightCue(fixture: .server, color: PrepStation.processingPurple, pattern: .threeFlash)
        ]
    }
    static func cues(forReadyAt station: PrepStation) -> [LightCue] {
        [
            LightCue(fixture: LightFixture.forPrepStation(station), color: PrepStation.awaitingPink, pattern: .threeFlash),
            LightCue(fixture: .server, color: PrepStation.awaitingPink, pattern: .pulseUntilStopped)
        ]
    }
}

enum LightFixture: String, CaseIterable, Sendable {
    case server, kitchen, sushi, bar
    static func forPrepStation(_ station: PrepStation) -> LightFixture {
        switch station {
        case .kitchen: return .kitchen
        case .sushi: return .sushi
        case .bar: return .bar
        }
    }
    static func devicesFromEnvironment() -> [LightFixture: String] {
        var devices: [LightFixture: String] = [:]
        func take(_ fixture: LightFixture, _ key: String) {
            if let value = Environment.get(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                devices[fixture] = value
            }
        }
        take(.server, "TUYA_DEVICE_ID_SERVER")
        take(.kitchen, "TUYA_DEVICE_ID_KITCHEN")
        take(.sushi, "TUYA_DEVICE_ID_SUSHI")
        take(.bar, "TUYA_DEVICE_ID_BAR")
        if devices[.server] == nil, let shared = Environment.get("TUYA_DEVICE_ID")?.trimmingCharacters(in: .whitespacesAndNewlines), !shared.isEmpty {
            devices[.server] = shared
        }
        return devices
    }
}

struct LightStationsStatus: Content {
    var enabled: Bool
    var fixtures: [String]
    var colors: [String: String]
}

extension LightNotifier {
    func status() -> LightStationsStatus {
        LightStationsStatus(
            enabled: isEnabled,
            fixtures: deviceIds.keys.map(\.rawValue).sorted(),
            colors: [
                "needsEntryGold": PrepStation.needsEntryGold.hex,
                "processingPurple": PrepStation.processingPurple.hex,
                "awaitingPink": PrepStation.awaitingPink.hex,
                "kitchenNeedsEntry": PrepStation.kitchen.needsEntryColor.hex,
                "sushiNeedsEntry": PrepStation.sushi.needsEntryColor.hex,
                "barNeedsEntry": PrepStation.bar.needsEntryColor.hex
            ]
        )
    }
}
