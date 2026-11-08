import Vapor

/// Pulls closed tickets from Heartland Restaurant's API
/// (https://api.hrpos.heartland.us, "Genius for Restaurants API v2") into
/// PosOrderStore: `GET /v2/orders/{start}/{end}` for the tickets (14 days per
/// request, paginated), and `GET /v2/setup/rooms` to turn each dine-in
/// ticket's table id into the table's name.
///
/// Needs `HEARTLAND_API_KEY` (the location key from the Heartland Admin
/// Portal's Integrations page) and, if Heartland requires it for this
/// account, `HEARTLAND_PARTNER_KEY`. Without the API key the daily sync is
/// off and staff use the CSV upload instead.
enum HeartlandSync {
    /// Overridable for testing against a stand-in server.
    static var baseURL: String { Environment.get("HEARTLAND_API_BASE_URL") ?? "https://api.hrpos.heartland.us" }
    static let maxDaysPerRequest = 14
    static let pageSize = 100

    struct SyncError: Error, CustomStringConvertible {
        var description: String
    }

    static var apiKey: String? { Environment.get("HEARTLAND_API_KEY").flatMap { $0.isEmpty ? nil : $0 } }
    static var partnerKey: String? { Environment.get("HEARTLAND_PARTNER_KEY").flatMap { $0.isEmpty ? nil : $0 } }
    static var isConfigured: Bool { apiKey != nil }

    /// Imports every closed ticket with a business date in `from...to`
    /// (YYYY-MM-DD, inclusive). Records the outcome either way, so the POS
    /// Orders page can show when the last sync ran and why it failed.
    @discardableResult
    static func sync(client: Client, from: String, to: String) async throws -> Int {
        let started = ISO8601DateFormatter().string(from: Date())
        do {
            guard let apiKey else { throw SyncError(description: "HEARTLAND_API_KEY is not set on the server.") }
            let tables = try await tableNames(client: client, apiKey: apiKey)
            var orders: [PosOrder] = []
            for (rangeStart, rangeEnd) in try chunks(from: from, to: to) {
                var page = 1
                while true {
                    let body = try await get(
                        client: client, apiKey: apiKey,
                        path: "/v2/orders/\(rangeStart)/\(rangeEnd)?page=\(page)&limit=\(pageSize)"
                    )
                    guard let object = body as? [String: Any], let data = object["data"] as? [[String: Any]] else {
                        throw SyncError(description: "Unexpected response from Heartland's orders endpoint.")
                    }
                    orders.append(contentsOf: data.compactMap { parseOrder($0, tables: tables) })
                    let totalPages = (object["pagination"] as? [String: Any]).flatMap { int($0["total_pages"]) } ?? 1
                    if page >= totalPages || data.isEmpty { break }
                    page += 1
                }
            }
            try PosOrderStore.shared.upsert(orders, status: PosSyncStatus(
                at: started, source: "heartland-api", from: from, to: to, ordersImported: orders.count, error: nil
            ))
            return orders.count
        } catch {
            PosOrderStore.shared.recordFailure(PosSyncStatus(
                at: started, source: "heartland-api", from: from, to: to, ordersImported: 0, error: "\(error)"
            ))
            throw error
        }
    }

    /// Splits an inclusive date range into Heartland's 14-day maximum.
    static func chunks(from: String, to: String) throws -> [(String, String)] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = HappyHourSchedule.pacific
        formatter.dateFormat = "yyyy-MM-dd"
        guard var start = formatter.date(from: from), let end = formatter.date(from: to), start <= end else {
            throw SyncError(description: "Dates must be YYYY-MM-DD, with the start on or before the end.")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = HappyHourSchedule.pacific
        var result: [(String, String)] = []
        while start <= end {
            let chunkEnd = min(calendar.date(byAdding: .day, value: maxDaysPerRequest - 1, to: start) ?? end, end)
            result.append((formatter.string(from: start), formatter.string(from: chunkEnd)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: chunkEnd) else { break }
            start = next
        }
        return result
    }

    /// Heartland table id → (table name, room name).
    private static func tableNames(client: Client, apiKey: String) async throws -> [String: (String, String?)] {
        guard let rooms = try await get(client: client, apiKey: apiKey, path: "/v2/setup/rooms") as? [[String: Any]] else {
            throw SyncError(description: "Unexpected response from Heartland's rooms endpoint.")
        }
        var result: [String: (String, String?)] = [:]
        for room in rooms {
            for table in room["tables"] as? [[String: Any]] ?? [] {
                if let id = string(table["table_id"]), let name = string(table["table_name"]) {
                    result[id] = (name, string(room["name"]))
                }
            }
        }
        return result
    }

    private static func get(client: Client, apiKey: String, path: String) async throws -> Any {
        var headers = HTTPHeaders()
        headers.add(name: "x-Api-Key", value: apiKey)
        if let partnerKey { headers.add(name: "authentication", value: partnerKey) }
        headers.add(name: .accept, value: "application/json")
        let response = try await client.get(URI(string: baseURL + path), headers: headers)
        guard response.status == .ok else {
            let detail = response.body.map { String(buffer: $0).prefix(300) } ?? ""
            let hint = response.status == .unauthorized
                ? " Check HEARTLAND_API_KEY, and ask Heartland whether this account also needs a partner key (HEARTLAND_PARTNER_KEY)."
                : ""
            throw SyncError(description: "Heartland returned \(response.status.code) for \(path.split(separator: "?").first ?? "").\(hint) \(detail)")
        }
        guard let body = response.body else { return [] }
        return try JSONSerialization.jsonObject(with: Data(buffer: body))
    }

    /// One Heartland order → PosOrder, keeping only table, times, guests,
    /// and items (guest names, phones, and payment details are dropped).
    static func parseOrder(_ raw: [String: Any], tables: [String: (String, String?)]) -> PosOrder? {
        guard let id = string(raw["id"]), let opened = string(raw["opened_dt"]) else { return nil }
        let tableId = (raw["table"] as? [String: Any]).flatMap { string($0["id"]) }
        let tableInfo = tableId.flatMap { tables[$0] }
        let items: [PosOrderItem] = (raw["items"] as? [[String: Any]] ?? []).compactMap { item in
            guard let name = string(item["itemName"]) else { return nil }
            if string(item["voided_dt"]) != nil { return nil }
            // Sub items are add-ons rolled into their parent's price.
            if bool(item["sub_item"]) == true { return nil }
            let cost = double(item["cost"]).flatMap { $0 > 0 ? $0 : nil }
            return PosOrderItem(name: name, quantity: double(item["quantity"]) ?? 1, netSales: double(item["net_sales"]), cost: cost)
        }
        return PosOrder(
            id: "heartland:\(id)",
            source: "heartland-api",
            ticketNumber: string(raw["ticket_number"]),
            table: PosMatching.tableKey(tableInfo?.0),
            room: tableInfo?.1,
            openedAt: normalizedDate(opened) ?? opened,
            closedAt: string(raw["closed_dt"]).flatMap { normalizedDate($0) ?? $0 },
            guestCount: int(raw["guest_count"]),
            items: items,
            netSales: double(raw["net_sales"])
        )
    }

    /// Heartland sends "+00:00" offsets; store plain UTC ISO 8601.
    private static func normalizedDate(_ value: String) -> String? {
        PosMatching.date(value).map { ISO8601DateFormatter().string(from: $0) }
    }

    // Heartland's JSON mixes types for the same kind of field ("12.00" vs
    // 12, "false" vs false, and the literal string "null"), so every read
    // goes through these.
    static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String:
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed.lowercased() == "null" ? nil : trimmed
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        double(value).map { Int($0) }
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let b as Bool: return b
        case let s as String: return s.lowercased() == "true" ? true : s.lowercased() == "false" ? false : nil
        default: return nil
        }
    }

    /// Runs every day at 4:30am Pacific, after the night's tickets have
    /// closed, re-importing the previous two business days (a ticket closed
    /// after midnight belongs to the day before, and re-importing is
    /// harmless since orders are matched by id).
    static func schedule(_ app: Application) {
        guard isConfigured else {
            app.logger.info("HEARTLAND_API_KEY not set; daily POS sync is off (CSV upload still works).")
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = HappyHourSchedule.pacific
        let now = Date()
        var next = calendar.date(bySettingHour: 4, minute: 30, second: 0, of: now) ?? now
        if next <= now { next = calendar.date(byAdding: .day, value: 1, to: next) ?? now.addingTimeInterval(86_400) }
        let initialDelay = Int64(next.timeIntervalSince(now))
        app.eventLoopGroup.next().scheduleRepeatedTask(initialDelay: .seconds(initialDelay), delay: .hours(24)) { _ in
            let promise = app.eventLoopGroup.next().makePromise(of: Void.self)
            promise.completeWithTask {
                let (from, to) = recentBusinessDays(2)
                do {
                    let count = try await sync(client: app.client, from: from, to: to)
                    app.logger.info("Heartland sync imported \(count) orders for \(from)...\(to).")
                } catch {
                    app.logger.error("Heartland sync failed: \(error)")
                }
            }
        }
    }

    /// The last `days` business dates ending yesterday, as YYYY-MM-DD.
    static func recentBusinessDays(_ days: Int, now: Date = Date()) -> (String, String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = HappyHourSchedule.pacific
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: yesterday) ?? yesterday
        return (formatter.string(from: start), formatter.string(from: yesterday))
    }
}
