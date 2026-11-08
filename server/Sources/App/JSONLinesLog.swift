import Foundation

/// Append-only, one-JSON-object-per-line file for high-volume event stores.
///
/// The original stores rewrote their whole JSON file on every event. That
/// was fine at a few KB, but `menu-item-engagement.json` grew to 17MB, and
/// re-encoding and rewriting it over the Azure Files mount on every menu tap
/// or impression batch, on an event-loop thread with 0.25 vCPU, stalled
/// every other request (image downloads included) for tens of seconds.
/// Appending one line costs the same no matter how big the file gets.
///
/// Writes go through a serial background queue so callers never wait on
/// disk. `flush()` waits for queued writes, for tests and for `configure()`.
final class JSONLinesLog<Element: Codable>: @unchecked Sendable {
    let fileURL: URL
    private let queue: DispatchQueue

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.queue = DispatchQueue(label: "jsonl.\(fileURL.lastPathComponent)")
    }

    /// Every decodable line in the file, in order. A malformed line (say, a
    /// write cut short by a crash) is skipped rather than failing the load.
    func readAll() -> [Element] {
        flush()
        guard let data = FileManager.default.contents(atPath: fileURL.path), !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        var result: [Element] = []
        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            if let element = try? decoder.decode(Element.self, from: Data(line)) {
                result.append(element)
            }
        }
        return result
    }

    func append(_ elements: [Element]) {
        guard !elements.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var chunk = Data()
        for element in elements {
            guard let line = try? encoder.encode(element) else { continue }
            chunk.append(line)
            chunk.append(UInt8(ascii: "\n"))
        }
        let url = fileURL
        let bytes = chunk
        queue.async {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: bytes)
        }
    }

    /// Replaces the whole file, used for occasional compaction (dropping
    /// events past retention) and for the one-time legacy migration.
    func rewrite(_ elements: [Element]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for element in elements {
            guard let line = try? encoder.encode(element) else { continue }
            data.append(line)
            data.append(UInt8(ascii: "\n"))
        }
        let url = fileURL
        let bytes = data
        queue.async {
            try? bytes.write(to: url, options: .atomic)
        }
    }

    func flush() {
        queue.sync {}
    }
}
