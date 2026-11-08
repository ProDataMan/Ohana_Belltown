import Vapor

/// Smaller copies of uploaded photos, requested as `/uploads/<file>?w=480`.
///
/// Every menu photo is stored at up to 1600px (median ~240KB), and the menu
/// page used to download that full file for every card, roughly 60 per page,
/// all over the Azure Files mount. Cards now ask for a 480px copy and the
/// detail view for a 960px one; only the lightbox loads the original.
///
/// Copies are cached on the container's local disk, not the data volume:
/// they're cheap to regenerate, so losing them on a redeploy only costs one
/// re-resize, and local disk is far faster to read than the network share.
enum UploadVariants {
    static let widths: Set<Int> = [480, 960]

    static var cacheDirectory = NSTemporaryDirectory() + "upload-variants/"

    /// One resize at a time. With 0.25 vCPU, resizing a page's worth of
    /// photos in parallel would starve request handling, and keeping this
    /// off `app.threadPool` means file streaming (which runs there) never
    /// waits behind ImageMagick.
    private static let queue = DispatchQueue(label: "upload-variants")

    static func cachedPath(filename: String, width: Int) -> String {
        cacheDirectory + "\(width)/" + filename
    }

    /// The resized copy's path, creating it first if needed. Nil when the
    /// file can't be resized (unsupported type, ImageMagick missing or
    /// failing); the caller then serves the original.
    static func path(for filename: String, width: Int) async -> String? {
        let ext = (filename.split(separator: ".").last.map(String.init) ?? "").lowercased()
        guard widths.contains(width), ImageOptimizer.optimizableExtensions.contains(ext) else { return nil }
        let output = cachedPath(filename: filename, width: width)
        if FileManager.default.fileExists(atPath: output) { return output }
        let source = Uploads.directory + filename
        guard FileManager.default.fileExists(atPath: source) else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: resizeSynchronously(source: source, output: output, width: width) ? output : nil)
            }
        }
    }

    private static func resizeSynchronously(source: String, output: String, width: Int) -> Bool {
        // Another request may have made it while this one waited in the queue.
        if FileManager.default.fileExists(atPath: output) { return true }
        let directory = (output as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        // Written under a temporary name and renamed, so a half-written file
        // is never served.
        let ext = (output as NSString).pathExtension
        let temporary = directory + "/." + UUID().uuidString + "." + ext
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/convert")
        process.arguments = [source, "-auto-orient", "-resize", "\(width)x\(width)>", "-strip", "-quality", "80", temporary]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: temporary) else {
            try? FileManager.default.removeItem(atPath: temporary)
            return false
        }
        do {
            try FileManager.default.moveItem(atPath: temporary, toPath: output)
        } catch {
            try? FileManager.default.removeItem(atPath: temporary)
            return FileManager.default.fileExists(atPath: output)
        }
        return true
    }

    /// Resizes every current menu photo ahead of time, so the first guests
    /// after a deploy don't wait on ImageMagick.
    static func prewarm(menu: Menu) async {
        let filenames = Set(menu.categories.flatMap { $0.items.flatMap(\.images) }
            .filter { $0.hasPrefix("/uploads/") }
            .map { String($0.dropFirst("/uploads/".count)) })
        for filename in filenames.sorted() {
            for width in widths.sorted() {
                _ = await path(for: filename, width: width)
            }
        }
    }
}
