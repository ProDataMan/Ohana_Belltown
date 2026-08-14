import Vapor

/// The site's own public HTTPS origin — needed to build OAuth redirect URIs,
/// since the server binds to 0.0.0.0 and doesn't otherwise know its public address.
enum PublicBaseURL {
    static func get() -> String {
        Environment.get("PUBLIC_BASE_URL")
            ?? "https://www.ohanasushigrill.com"
    }
}
