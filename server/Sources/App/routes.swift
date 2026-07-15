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
}
