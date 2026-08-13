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

    /// iPhones save photos as HEIC by default, which no major browser
    /// renders — unlike optimizeSynchronously (re-compresses in place, same
    /// format in and out), this has to actually change format or the
    /// "uploaded" photo would be broken everywhere it's shown. Returns
    /// false (rather than silently keeping the unusable original) if
    /// ImageMagick can't decode it — depends on the HEIF delegate being
    /// present in the deployed image.
    static func convertHEICToJPEGSynchronously(sourcePath: String, outputPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/convert")
        process.arguments = [
            sourcePath,
            "-auto-orient",
            "-resize", "1600x1600>",
            "-strip",
            "-quality", "85",
            outputPath,
        ]
        let devNull = FileHandle.nullDevice
        process.standardOutput = devNull
        process.standardError = devNull
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputPath)
        } catch {
            return false
        }
    }

    static func convertHEICToJPEG(sourcePath: String, outputPath: String, on app: Application) async throws -> Bool {
        try await app.threadPool.runIfActive {
            convertHEICToJPEGSynchronously(sourcePath: sourcePath, outputPath: outputPath)
        }
    }

    /// Pixel dimensions via ImageMagick's `identify` (ships alongside
    /// `convert` in the same apt package, see Dockerfile) rather than
    /// decoding the image ourselves — nothing else in this codebase parses
    /// image formats directly, and shelling out matches how HEIC conversion
    /// and resizing already work.
    static func dimensionsSynchronously(at path: String) -> (width: Int, height: Int)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/identify")
        process.arguments = ["-format", "%w %h", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, let text = String(data: output, encoding: .utf8) else { return nil }
            let parts = text.split(separator: " ")
            guard parts.count >= 2, let width = Int(parts[0]), let height = Int(parts[1]) else { return nil }
            return (width, height)
        } catch {
            return nil
        }
    }

    static func dimensions(at path: String, on app: Application) async throws -> (width: Int, height: Int)? {
        try await app.threadPool.runIfActive {
            dimensionsSynchronously(at: path)
        }
    }
}
