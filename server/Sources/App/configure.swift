import Vapor

func configure(_ app: Application) throws {
    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080

    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory, defaultFile: "index.html"))

    let dataDirectory = Environment.get("DATA_DIR") ?? app.directory.workingDirectory + "Data"
    MenuStore.shared.configure(dataDirectory: dataDirectory)

    try routes(app)
}
