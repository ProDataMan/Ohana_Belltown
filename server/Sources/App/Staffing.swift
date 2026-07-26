import Vapor

struct StaffingConfig: Codable, Content {
    var staffOnDuty: Int
}

/// A single manually-set "how many staff are working right now" number, fed
/// into PrepTimeEstimator. There's no shift/clock-in system in this app, so
/// this is deliberately simple — whoever's on the floor updates it from
/// /table-orders-admin.html at the start of a shift.
final class StaffingStore: @unchecked Sendable {
    static let shared = StaffingStore()
    static let defaultStaffOnDuty = 3

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/staffing.json")
    private var config = StaffingConfig(staffOnDuty: StaffingStore.defaultStaffOnDuty)
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("staffing.json")
        loaded = false
    }

    func get() throws -> StaffingConfig {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        return config
    }

    @discardableResult
    func setStaffOnDuty(_ count: Int) throws -> StaffingConfig {
        lock.lock()
        defer { lock.unlock() }
        try loadIfNeeded()
        config.staffOnDuty = max(1, count)
        try persist()
        return config
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            config = try JSONDecoder().decode(StaffingConfig.self, from: data)
        } else {
            try persist()
        }
        loaded = true
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}
