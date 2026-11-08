import Vapor

struct NoCacheMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)
        // A route that sets its own policy (e.g. /uploads, which are
        // write-once and cached for good) keeps it.
        if response.headers.first(name: .cacheControl) == nil {
            response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        }
        return response
    }
}
