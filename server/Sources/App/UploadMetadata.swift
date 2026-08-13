import Vapor

/// Who uploaded a file and when — nothing about `/api/upload` tracked this
/// before (it's shared by staff menu-photo uploads and anonymous customer
/// loyalty-bonus-claim photos alike), so this is opt-in: `record` is called
/// with whatever identity is available at upload time, `nil` if none. Photos
/// uploaded before this store existed simply have no entry — the info
/// endpoint reports that honestly rather than guessing.
struct UploadMetadataEntry: Codable, Content {
    var uploadedAt: String
    var uploadedByName: String?
}

final class UploadMetadataStore: @unchecked Sendable {
    static let shared = UploadMetadataStore()

    private let lock = NSLock()
    private var fileURL = URL(fileURLWithPath: "Data/upload-metadata.json")
    private var data: [String: UploadMetadataEntry] = [:]
    private var loaded = false

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = URL(fileURLWithPath: dataDirectory).appendingPathComponent("upload-metadata.json")
        loaded = false
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let raw = try? Data(contentsOf: fileURL) else { return }
        data = (try? JSONDecoder().decode([String: UploadMetadataEntry].self, from: raw)) ?? [:]
    }

    private func persist() {
        guard let raw = try? JSONEncoder().encode(data) else { return }
        try? raw.write(to: fileURL)
    }

    func record(filename: String, uploadedByName: String?, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        data[filename] = UploadMetadataEntry(
            uploadedAt: ISO8601DateFormatter().string(from: now),
            uploadedByName: uploadedByName
        )
        persist()
    }

    func entry(for filename: String) -> UploadMetadataEntry? {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return data[filename]
    }
}
