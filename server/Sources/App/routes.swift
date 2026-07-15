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

    app.on(.POST, "api", "upload", body: .collect(maxSize: "8mb")) { req throws -> UploadResponse in
        let upload = try req.content.decode(ImageUpload.self)
        let allowedExtensions = ["jpg", "jpeg", "png", "webp", "gif"]
        let ext = (upload.image.extension ?? "").lowercased()
        guard allowedExtensions.contains(ext) else {
            throw Abort(.unsupportedMediaType, reason: "Only jpg, png, webp, or gif images are allowed.")
        }
        guard let data = upload.image.data.getData(
            at: upload.image.data.readerIndex,
            length: upload.image.data.readableBytes
        ) else {
            throw Abort(.badRequest)
        }
        let filename = UUID().uuidString + "." + ext
        try data.write(to: URL(fileURLWithPath: Uploads.directory + filename))
        return UploadResponse(url: "/uploads/\(filename)")
    }

    app.get("uploads", ":filename") { req async throws -> Response in
        guard let filename = req.parameters.get("filename"), !filename.contains("..") else {
            throw Abort(.badRequest)
        }
        return try await req.fileio.asyncStreamFile(at: Uploads.directory + filename)
    }

    registerPlacesPhotoRoutes(app)

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
