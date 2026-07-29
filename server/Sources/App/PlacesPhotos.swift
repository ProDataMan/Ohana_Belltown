import Vapor

struct GooglePhotoRef: Codable {
    let photo_reference: String
    let html_attributions: [String]
}

struct GoogleReview: Codable {
    let author_name: String
    let profile_photo_url: String?
    let rating: Int?
    let relative_time_description: String?
    let text: String?
}

struct GoogleLatLng: Codable {
    let lat: Double
    let lng: Double
}

struct GoogleGeometry: Codable {
    let location: GoogleLatLng
}

struct GooglePlaceDetailsResult: Codable {
    let photos: [GooglePhotoRef]?
    let reviews: [GoogleReview]?
    let rating: Double?
    let user_ratings_total: Int?
    let geometry: GoogleGeometry?

    init(photos: [GooglePhotoRef]?, reviews: [GoogleReview]?, rating: Double?, user_ratings_total: Int?, geometry: GoogleGeometry? = nil) {
        self.photos = photos
        self.reviews = reviews
        self.rating = rating
        self.user_ratings_total = user_ratings_total
        self.geometry = geometry
    }
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

struct PlaceReview: Content {
    var authorName: String
    var profilePhotoUrl: String?
    var rating: Int
    var relativeTime: String
    var text: String
}

struct PlaceReviewsSummary: Content {
    var reviews: [PlaceReview]
    var overallRating: Double?
    var totalRatings: Int?

    /// 1-star reviews are excluded from the on-site widget — the review
    /// itself is untouched on Google, just not amplified here. overallRating
    /// and totalRatings still reflect Google's real totals, unfiltered, so
    /// the site never misrepresents the actual rating.
    static func build(from details: GooglePlaceDetailsResult) -> PlaceReviewsSummary {
        let reviews = (details.reviews ?? [])
            .filter { ($0.rating ?? 0) > 1 }
            .map { review in
                PlaceReview(
                    authorName: review.author_name,
                    profilePhotoUrl: review.profile_photo_url,
                    rating: review.rating ?? 0,
                    relativeTime: review.relative_time_description ?? "",
                    text: review.text ?? ""
                )
            }
        return PlaceReviewsSummary(reviews: reviews, overallRating: details.rating, totalRatings: details.user_ratings_total)
    }
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
    private var cachedDetails: GooglePlaceDetailsResult?
    private var detailsFetchedAt: Date?
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

    /// Photos and reviews both come off the same Place Details call (Google
    /// bills per call, not per field), so they share one 6-hour cache instead
    /// of hitting the API twice.
    func getDetails(client: Client, apiKey: String, placeId: String) async throws -> GooglePlaceDetailsResult {
        lock.lock()
        let isFresh = detailsFetchedAt.map { Date().timeIntervalSince($0) < refsTTL } ?? false
        if isFresh, let cached = cachedDetails {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let uri = URI(string: "https://maps.googleapis.com/maps/api/place/details/json?place_id=\(placeId)&fields=photos,reviews,rating,user_ratings_total,geometry&key=\(apiKey)")
        let response = try await client.get(uri).get()
        let decoded = try response.content.decode(GooglePlaceDetailsResponse.self)
        let result = decoded.result ?? GooglePlaceDetailsResult(photos: nil, reviews: nil, rating: nil, user_ratings_total: nil, geometry: nil)

        lock.lock()
        cachedDetails = result
        detailsFetchedAt = Date()
        lock.unlock()

        return result
    }

    func getPhotoRefs(client: Client, apiKey: String, placeId: String) async throws -> [GooglePhotoRef] {
        try await getDetails(client: client, apiKey: apiKey, placeId: placeId).photos ?? []
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

    // Real Google reviews, embedded on-site instead of just linked out —
    // same Place Details data already fetched for photos, so no extra quota.
    app.get("api", "place-reviews") { req async throws -> PlaceReviewsSummary in
        guard let apiKey = Environment.get("GOOGLE_PLACES_API_KEY"),
              let placeId = Environment.get("GOOGLE_PLACE_ID") else {
            return PlaceReviewsSummary(reviews: [], overallRating: nil, totalRatings: nil)
        }

        let details = try await PlacesPhotoCache.shared.getDetails(client: req.client, apiKey: apiKey, placeId: placeId)
        return PlaceReviewsSummary.build(from: details)
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
