import Vapor

/// Vapor answers 400 to a byte-range request that runs past the end of the
/// file (e.g. `Range: bytes=0-524287` for a 6KB page), where HTTP says a
/// server should send what it has. Facebook's link-preview crawler sends
/// exactly that on every fetch, so every shared link to this site (Facebook,
/// Instagram, Messenger, WhatsApp) was failing to preview.
///
/// When a GET/HEAD with a Range header comes back 400, this answers it again
/// without the Range header — a full 200, which HTTP allows for any range
/// request. In-bounds ranges (video seeking on /uploads) are untouched.
struct LenientRangeMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard request.method == .GET || request.method == .HEAD, request.headers.first(name: .range) != nil else {
            return try await next.respond(to: request)
        }
        let response: Response
        do {
            response = try await next.respond(to: request)
        } catch let error as AbortError where error.status == .badRequest {
            return try await retryWithoutRange(request, next: next)
        }
        guard response.status == .badRequest else { return response }
        return try await retryWithoutRange(request, next: next)
    }

    private func retryWithoutRange(_ request: Request, next: any AsyncResponder) async throws -> Response {
        request.headers.remove(name: .range)
        return try await next.respond(to: request)
    }
}
