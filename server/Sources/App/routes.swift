import Vapor

func routes(_ app: Application) throws {
    app.get("healthz") { _ in "ok" }

    app.get("api", "menu") { _ throws -> Menu in
        try MenuStore.shared.get()
    }

    app.put("api", "menu") { req throws -> Menu in
        let incoming = try req.content.decode(Menu.self)
        return try MenuStore.shared.save(incoming)
    }

    func serveStatic(_ req: Request, file: String) async throws -> Response {
        let path = req.application.directory.publicDirectory + file
        return try await req.fileio.asyncStreamFile(at: path)
    }

    let cleanPages: [(String, String)] = [
        ("menu", "pages/menu.html"),
        ("sushi", "pages/sushi.html"),
        ("drinks", "pages/drinks.html"),
        ("happy-hour", "pages/happy-hour.html"),
        ("local", "pages/local.html"),
        ("about", "pages/about.html"),
        ("catering", "pages/catering.html"),
        ("contact", "pages/contact.html"),
    ]
    for (route, file) in cleanPages {
        app.get(PathComponent(stringLiteral: route)) { req in
            try await serveStatic(req, file: file)
        }
    }

    let legacyRedirects: [(String, String)] = [
        ("menu.html", "/menu"),
        ("sushi.html", "/sushi"),
        ("drinks.html", "/drinks"),
        ("happy-hour.html", "/happy-hour"),
        ("local.html", "/local"),
        ("about-ohanas.html", "/about"),
        ("contact.html", "/contact"),
    ]
    for (legacyPath, target) in legacyRedirects {
        app.get(PathComponent(stringLiteral: legacyPath)) { req in
            req.redirect(to: target, redirectType: .permanent)
        }
    }
}
