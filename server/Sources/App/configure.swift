import Vapor

func configure(_ app: Application) throws {
    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080

    let dataDirectory = Environment.get("DATA_DIR") ?? app.directory.workingDirectory + "Data"

    app.middleware.use(NoCacheMiddleware())
    app.middleware.use(AnalyticsMiddleware())
    // File-backed rather than `.memory`, so logins survive a deploy/restart —
    // stored on the same DATA_DIR volume every other store already persists
    // to. See FileSessions.swift.
    FileSessionsStore.shared.configure(dataDirectory: dataDirectory)
    app.sessions.use { _ in FileSessions() }
    app.middleware.use(app.sessions.middleware)
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory, defaultFile: "index.html"))
    if app.environment != .testing {
        let oneDay: TimeInterval = 24 * 60 * 60
        app.eventLoopGroup.next().scheduleRepeatedTask(initialDelay: .minutes(5), delay: .hours(24)) { _ in
            FileSessionsStore.shared.pruneExpired(olderThan: 30 * oneDay)
        }
    }

    MenuStore.shared.configure(dataDirectory: dataDirectory, resourcesDirectory: app.directory.resourcesDirectory)
    Uploads.configure(dataDirectory: dataDirectory)
    UploadMetadataStore.shared.configure(dataDirectory: dataDirectory)
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
    CompetitorPhotoReviewStore.shared.configure(dataDirectory: dataDirectory)
    SwagStore.shared.configure(dataDirectory: dataDirectory)
    SwagOrdersStore.shared.configure(dataDirectory: dataDirectory)
    GiftCardOrdersStore.shared.configure(dataDirectory: dataDirectory)

    app.routes.defaultMaxBodySize = "10mb"

    if app.environment != .testing {
        FeedbackDigest.schedule(app)
        Task { await LightNotifier.shared.configureFromEnvironment() }
        LightNotifier.scheduleReadyPoll(app)
        // A "pending"/"entered" order nobody ever entered or delivered used
        // to just silently drop off staff's queues once stale, with nothing
        // ever actually marking it resolved — harmless as a heads-up-only
        // queue, but a real liability once anything (e.g. charging a
        // table's card) might key off an order's status. Runs every 30
        // minutes so staleness becomes a real, visible "cancelled" state.
        app.eventLoopGroup.next().scheduleRepeatedTask(initialDelay: .minutes(5), delay: .minutes(30)) { _ in
            let promise = app.eventLoopGroup.next().makePromise(of: Void.self)
            promise.completeWithTask {
                guard let cancelled = try? TableOrdersStore.shared.cancelStaleOrders() else { return }
                for entry in cancelled {
                    await LightNotifier.shared.notifyCancelled(entry)
                }
            }
        }
    }

    try routes(app)
}
