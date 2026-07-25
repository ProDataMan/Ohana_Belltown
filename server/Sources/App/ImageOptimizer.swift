import Vapor

enum ImageOptimizer {
    /// Extensions worth running through ImageMagick. GIFs are skipped since
    /// naively re-encoding one can break animation.
    static let optimizableExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]

    /// Resizes (only if larger than 1600px on the long edge) and re-compresses
    /// the image in place. Runs `magick` synchronously — callers must dispatch
    /// this off the event loop (see `optimize(at:on:)`).
    static func optimizeSynchronously(at path: String) {
        let process = Process()
        // Ubuntu's `imagemagick` apt package ships ImageMagick 6, which uses
        // `convert` — the `magick` wrapper binary is an ImageMagick 7-ism and
        // isn't present here.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/convert")
        process.arguments = [
            path,
            "-auto-orient",
            "-resize", "1600x1600>",
            "-strip",
            "-quality", "85",
            path,
        ]
        let devNull = FileHandle.nullDevice
        process.standardOutput = devNull
        process.standardError = devNull
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // ImageMagick not available or the file couldn't be processed —
            // the original upload is still on disk and usable as-is.
        }
    }

    /// Runs the optimization off the event loop's thread, so a slow/large
    /// image doesn't stall request handling for everyone else.
    static func optimize(at path: String, on app: Application) async throws {
        try await app.threadPool.runIfActive {
            optimizeSynchronously(at: path)
        }
    }
}
