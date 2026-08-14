import Crypto
import Foundation
import Vapor

/// Holds the on-disk directory `FileSessions` reads/writes, mirroring every
/// other store's `static let shared` + `configure(dataDirectory:)` pattern
/// (see `MenuStore`, `StaffRewardsStore`, etc.) rather than baking the path
/// into the driver at `app.sessions.use` time — that would lock in
/// `configure.swift`'s real `DATA_DIR` permanently, including in tests,
/// which reconfigure every other store onto an isolated temp directory
/// *after* `configure(app)` already ran once.
final class FileSessionsStore: @unchecked Sendable {
    static let shared = FileSessionsStore()

    private let lock = NSLock()
    private var directory = URL(fileURLWithPath: "Data/sessions")

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        directory = URL(fileURLWithPath: dataDirectory).appendingPathComponent("sessions")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var currentDirectory: URL {
        lock.lock()
        defer { lock.unlock() }
        return directory
    }

    /// Deletes session files untouched for longer than a normal login would
    /// last, so a browser closed without logging out doesn't leave a file
    /// behind forever — the one cleanup `.memory` got for free just by
    /// living in process memory that eventually restarts.
    func pruneExpired(olderThan maxAge: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-maxAge)
        let dir = currentDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for file in files {
            guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}

/// File-backed session store — Vapor's built-in `.memory` driver keeps
/// sessions only in process memory, so every deploy/restart logs out the
/// whole staff team (and any customer accounts) at once. This persists each
/// session as one JSON file under `<DATA_DIR>/sessions/`, the same
/// Azure Files–backed volume every other store already relies on to survive
/// restarts, so logins actually outlive a deploy.
///
/// Session IDs are already random/opaque, but they're base64 (contains `/`),
/// so filenames are derived via SHA-256 rather than used directly.
struct FileSessions: AsyncSessionDriver {
    func createSession(_ data: SessionData, for request: Request) async throws -> SessionID {
        let id = SessionID(string: [UInt8].random(count: 32).base64String())
        try write(data, id: id)
        return id
    }

    func readSession(_ sessionID: SessionID, for request: Request) async throws -> SessionData? {
        guard let raw = try? Data(contentsOf: fileURL(for: sessionID)) else { return nil }
        return try? JSONDecoder().decode(SessionData.self, from: raw)
    }

    func updateSession(_ sessionID: SessionID, to data: SessionData, for request: Request) async throws -> SessionID {
        try write(data, id: sessionID)
        return sessionID
    }

    func deleteSession(_ sessionID: SessionID, for request: Request) async throws {
        try? FileManager.default.removeItem(at: fileURL(for: sessionID))
    }

    private func fileURL(for id: SessionID) -> URL {
        let digest = SHA256.hash(data: Data(id.string.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return FileSessionsStore.shared.currentDirectory.appendingPathComponent("\(hex).json")
    }

    private func write(_ data: SessionData, id: SessionID) throws {
        let raw = try JSONEncoder().encode(data)
        try raw.write(to: fileURL(for: id), options: .atomic)
    }
}
