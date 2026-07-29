import Vapor

func configure(_ app: Application) throws {
    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080

    app.middleware.use(NoCacheMiddleware())
    app.middleware.use(AnalyticsMiddleware())
    app.sessions.use(.memory)
    app.middleware.use(app.sessions.middleware)
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory, defaultFile: "index.html"))

    let dataDirectory = Environment.get("DATA_DIR") ?? app.directory.workingDirectory + "Data"
    MenuStore.shared.configure(dataDirectory: dataDirectory, resourcesDirectory: app.directory.resourcesDirectory)
    Uploads.configure(dataDirectory: dataDirectory)
    PlacesPhotoCache.shared.configure(dataDirectory: dataDirectory)
    EventsStore.shared.configure(dataDirectory: dataDirectory)
    LoyaltyStore.shared.configure(dataDirectory: dataDirectory)
    UserStore.shared.configure(dataDirectory: dataDirectory)
    CustomerUserStore.shared.configure(dataDirectory: dataDirectory)
    AnalyticsStore.shared.configure(dataDirectory: dataDirectory)
    WaitlistStore.shared.configure(dataDirectory: dataDirectory)
    TableOrdersStore.shared.configure(dataDirectory: dataDirectory)
    StaffingStore.shared.configure(dataDirectory: dataDirectory)
    FeedbackStore.shared.configure(dataDirectory: dataDirectory)
    StaffRewardsStore.shared.configure(dataDirectory: dataDirectory)
    CompetitorPricingStore.shared.configure(dataDirectory: dataDirectory)

    app.routes.defaultMaxBodySize = "10mb"

    if app.environment != .testing {
        FeedbackDigest.schedule(app)
    }

    try routes(app)
}
