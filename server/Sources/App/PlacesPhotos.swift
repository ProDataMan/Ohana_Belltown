import Vapor

struct GooglePhotoRef: Codable {
    let photo_reference: String
    let html_attributions: [String]
}

struct GooglePlaceDetailsResult: Codable {
    let photos: [GooglePhotoRef]?
}

struct GooglePlaceDetailsResponse: Codable {
    let result: GooglePlaceDetailsResult?
    let status: String
}

struct FeaturedPhoto: Content {
    let url: String
    let attributionName: String
    let attributionUrl: String?
}

extension String {
    var decodingHTMLEntities: String {
        self
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    var strippedHTMLLinkText: String {
        guard let openTag = self.range(of: ">"),
              let closeTag = self.range(of: "<", range: openTag.upperBound..<self.endIndex) else {
            return self.decodingHTMLEntities
        }
        return String(self[openTag.upperBound..<closeTag.lowerBound]).decodingHTMLEntities
    }

    var hrefFromAnchorTag: String? {
        guard let hrefRange = self.range(of: "href=\""),
              let endRange = self.range(of: "\"", range: hrefRange.upperBound..<self.endIndex) else {
            return nil
        }
        return String(self[hrefRange.upperBound..<endRange.lowerBound])
    }
}

final class PlacesPhotoCache: @unchecked Sendable {
    static let shared = PlacesPhotoCache()

    private let lock = NSLock()
    private var cachedRefs: [GooglePhotoRef] = []
    private var refsFetchedAt: Date?
    private var cacheDirectory = "Data/places-cache/"
    private let refsTTL: TimeInterval = 6 * 3600
    private let imageTTL: TimeInterval = 24 * 3600

    func configure(dataDirectory: String) {
        lock.lock()
        defer { lock.unlock() }
        let dir = URL(fileURLWithPath: dataDirectory).appendingPathComponent("places-cache").path + "/"
        cacheDirectory = dir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    private func safeFilename(for reference: String) -> String {
        let filtered = reference.filter { $0.isLetter || $0.isNumber }
        return String(filtered.prefix(80)) + ".jpg"
    }

    func cachedImagePath(for reference: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return cacheDirectory + safeFilename(for: reference)
    }

    func isImageCacheFresh(at path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attrs[.modificationDate] as? Date else {
            return false
        }
        return Date().timeIntervalSince(modified) < imageTTL
    }

    func getPhotoRefs(client: Client, apiKey: String, placeId: String) async throws -> [GooglePhotoRef] {
        lock.lock()
        let isFresh = refsFetchedAt.map { Date().timeIntervalSince($0) < refsTTL } ?? false
        if isFresh {
            let refs = cachedRefs
            lock.unlock()
            return refs
        }
        lock.unlock()

        let uri = URI(string: "https://maps.googleapis.com/maps/api/place/details/json?place_id=\(placeId)&fields=photos&key=\(apiKey)")
        let response = try await client.get(uri).get()
        let decoded = try response.content.decode(GooglePlaceDetailsResponse.self)
        let refs = decoded.result?.photos ?? []

        lock.lock()
        cachedRefs = refs
        refsFetchedAt = Date()
        lock.unlock()

        return refs
    }
}

func registerPlacesPhotoRoutes(_ app: Application) {
    app.get("api", "places-photos") { req async throws -> [FeaturedPhoto] in
        guard let apiKey = Environment.get("GOOGLE_PLACES_API_KEY"),
              let placeId = Environment.get("GOOGLE_PLACE_ID") else {
            return []
        }

        let refs = try await PlacesPhotoCache.shared.getPhotoRefs(client: req.client, apiKey: apiKey, placeId: placeId)

        return refs.map { ref in
            let attributionHTML = ref.html_attributions.first ?? ""
            let name = attributionHTML.strippedHTMLLinkText
            let link = attributionHTML.hrefFromAnchorTag
            let encodedRef = ref.photo_reference.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref.photo_reference
            return FeaturedPhoto(
                url: "/places-photo/\(encodedRef)",
                attributionName: name.isEmpty ? "Google Maps" : name,
                attributionUrl: link
            )
        }
    }

    app.get("places-photo", "**") { req async throws -> Response in
        guard let apiKey = Environment.get("GOOGLE_PLACES_API_KEY") else {
            throw Abort(.notFound)
        }
        let reference = req.parameters.getCatchall().joined(separator: "/")
        guard !reference.isEmpty else {
            throw Abort(.badRequest)
        }

        let cachePath = PlacesPhotoCache.shared.cachedImagePath(for: reference)
        if PlacesPhotoCache.shared.isImageCacheFresh(at: cachePath) {
            return try await req.fileio.asyncStreamFile(at: cachePath)
        }

        let uri = URI(string: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=1200&photoreference=\(reference)&key=\(apiKey)")
        let response = try await req.client.get(uri).get()
        guard var body = response.body, response.status == .ok || response.status == .movedPermanently || response.status == .found else {
            throw Abort(.badGateway)
        }
        let data = body.readData(length: body.readableBytes) ?? Data()
        try data.write(to: URL(fileURLWithPath: cachePath))
        return try await req.fileio.asyncStreamFile(at: cachePath)
    }
}
