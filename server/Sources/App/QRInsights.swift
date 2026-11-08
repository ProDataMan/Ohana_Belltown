import Vapor

/// Aggregate reporting over QR visits for a date range — backs
/// /qr-insights.html. Everything here is derived from QRVisitStore's visit
/// summaries plus the floor map (TableMap) and the live menu; nothing new is
/// stored. Visits without a table (front-door QR) are counted in totals and
/// time-of-day charts under the "none" section, but not on the floor map.
struct QRInsights: Content {
    var from: String
    var to: String
    var totalVisits: Int
    var tables: [QRInsightsTable]
    var sections: [QRInsightsSection]
    var byHour: [QRInsightsTimeBucket]
    var byWeekday: [QRInsightsTimeBucket]
    var happyHour: QRInsightsHappyHour
    var items: [QRInsightsItem]
    var searches: [QRInsightsSearch]
    var paths: [QRInsightsPath]
    var returning: QRInsightsReturning
    var parties: QRInsightsParties
    var deviceMix: [QRInsightsCount]
    /// Nil until POS orders have been imported for this range.
    var pos: QRInsightsPos?
    /// Tables with no QR visit in the last 7 days, listed only when the
    /// rest of the floor had enough scans (`QRInsightsBuilder.quietThreshold`)
    /// that silence probably means a missing or damaged card, not a slow week.
    var quietTables: [String] = []
    /// From waitlist parties staff marked "Seated" at a table. Nil when none
    /// were in this range.
    var seating: QRInsightsSeating? = nil
}

struct QRInsightsSeating: Content {
    var seatedParties: Int
    var avgWaitMinutes: Double?
    /// Seated parties whose table had a QR visit within 90 minutes.
    var partiesThatScanned: Int
    var avgMinutesSeatedToFirstScan: Double?
}

/// QR visits compared with what the POS says each table ordered.
struct QRInsightsPos: Content {
    var orders: Int
    /// Tickets on a table that's on the floor map (dine-in).
    var tableOrders: Int
    /// …of which overlapped a QR visit at that table.
    var tableOrdersWithQRVisit: Int
    var qrVisitsWithOrder: Int
    var qrVisitsWithTable: Int
    /// Per guest (or per ticket when the guest count is missing).
    var avgNetSalesWithQR: Double?
    var avgNetSalesWithoutQR: Double?
    var avgItemsWithQR: Double?
    var avgItemsWithoutQR: Double?
    /// POS item names that don't match anything on the website menu, most
    /// ordered first, so a naming mismatch can be fixed on one side.
    var unmatchedPosItems: [QRInsightsCount]
}

struct QRInsightsCount: Content {
    var label: String
    var count: Int
}

/// One QR code's spot on the floor map, for the heat map.
struct QRInsightsTable: Content {
    var table: String
    var section: String
    var x: Double
    var y: Double
    var shape: String
    var visits: Int
    var devices: Int
    var detailViews: Int
    var avgDurationSeconds: Double?
    var lastVisitAt: String?
}

struct QRInsightsSection: Content {
    /// A TableMap section, or "none" for visits with no table.
    var section: String
    var tableCount: Int
    var tablesWithVisits: Int
    var visits: Int
    var avgDurationSeconds: Double?
    var avgFirstTapSeconds: Double?
    var firstTapSamples: Int
    /// Share of visits that opened at least one item's details.
    var openedItemRate: Double?
    /// Share of visits from a device that had an earlier QR visit.
    var returningRate: Double?
    var topItems: [QRInsightsCount]
    var deviceMix: [QRInsightsCount]
}

/// Visits that started in one hour of the day (0–23) or weekday (1 = Sunday
/// … 7 = Saturday), in restaurant time, per section.
struct QRInsightsTimeBucket: Content {
    var bucket: Int
    var section: String
    var visits: Int
}

struct QRInsightsHappyHour: Content {
    /// Scans of the "flip the card over" Happy Hour QR.
    var cardVisits: Int
    /// …of which never left /happy-hour.
    var cardStayedOnHappyHour: Int
    /// …of which also opened another menu page.
    var cardWentToOtherPages: Int
    var cardTopItems: [QRInsightsCount]
    /// Any QR visit that started Mon–Fri 3–6pm.
    var visitsDuringHappyHour: Int
    /// …of which opened at least one item on /happy-hour.
    var duringHappyHourOpenedHappyHourItem: Int
}

struct QRInsightsItem: Content {
    var itemName: String
    /// Visits that opened this item's details at least once.
    var visits: Int
    var detailViews: Int
    var photoTaps: Int
    var addedToOrder: Int
    /// Visits that opened this item and whose table's ticket includes it.
    var visitsThatOrdered: Int = 0
    /// Tickets in the range that include it, QR visit or not.
    var timesOrdered: Int = 0
    var hasPhoto: Bool
    /// False when the name no longer matches anything on the live menu.
    var onMenu: Bool
}

struct QRInsightsSearch: Content {
    var query: String
    var count: Int
    /// How many of those searches matched nothing (searches recorded before
    /// result counts were tracked count as neither).
    var emptyCount: Int
}

struct QRInsightsPath: Content {
    var pages: [String]
    var visits: Int
}

struct QRInsightsReturning: Content {
    var devices: Int
    /// Devices with more than one QR visit (in this range or before it).
    var returningDevices: Int
    var visitsFromReturningDevices: Int
    /// Of devices with 2+ visits in this range, how many always sat in the
    /// same section.
    var multiVisitDevicesInRange: Int
    var sameSectionDevices: Int
}

/// Several phones scanning the same table within `QRInsightsBuilder.partyWindow`
/// of each other are counted as one party.
struct QRInsightsParties: Content {
    var parties: Int
    var avgPhonesPerParty: Double?
    /// Label "1", "2", "3", "4+" → number of parties.
    var phonesPerParty: [QRInsightsCount]
}

enum QRInsightsBuilder {
    static let partyWindow: TimeInterval = 20 * 60
    static let quietWindowDays = 7
    static let quietThreshold = 20

    /// Matches each seated waitlist party to the first QR visit at its table
    /// from 5 minutes before to 90 minutes after it was seated.
    static func seating(parties: [WaitlistEntry], visits: [QRVisitSummary]) -> QRInsightsSeating? {
        guard !parties.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        var waits: [Double] = []
        var toScan: [Double] = []
        for party in parties {
            guard let seated = party.seatedAt.flatMap(iso.date), let table = party.seatedTable else { continue }
            if let joined = iso.date(from: party.createdAt) {
                waits.append(seated.timeIntervalSince(joined) / 60)
            }
            let firstScan = visits
                .filter { PosMatching.tableKey($0.table) == table }
                .compactMap { iso.date(from: $0.startedAt) }
                .filter { $0 >= seated.addingTimeInterval(-5 * 60) && $0 <= seated.addingTimeInterval(90 * 60) }
                .min()
            if let firstScan {
                toScan.append(max(0, firstScan.timeIntervalSince(seated) / 60))
            }
        }
        func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        return QRInsightsSeating(
            seatedParties: parties.count, avgWaitMinutes: average(waits),
            partiesThatScanned: toScan.count, avgMinutesSeatedToFirstScan: average(toScan)
        )
    }

    /// See `QRInsights.quietTables`.
    static func quietTables(lastWeek visits: [QRVisitSummary]) -> [String] {
        let scanned = Set(visits.compactMap { PosMatching.tableKey($0.table) })
        let tableVisits = visits.filter { PosMatching.tableKey($0.table).map { id in TableMap.entries.contains { $0.id == id } } ?? false }
        guard tableVisits.count >= quietThreshold else { return [] }
        return TableMap.entries.map(\.id).filter { !scanned.contains($0) }
    }

    static func build(visits: [QRVisitSummary], from: Date, to: Date, menu: Menu?, orders: [PosOrder] = []) -> QRInsights {
        let iso = ISO8601DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = HappyHourSchedule.pacific
        let sectionByTable = Dictionary(uniqueKeysWithValues: TableMap.entries.map { ($0.id, $0.section) })
        func section(of visit: QRVisitSummary) -> String {
            visit.table.flatMap { sectionByTable[$0] } ?? "none"
        }
        func average(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        func rate(_ part: Int, _ whole: Int) -> Double? {
            whole > 0 ? Double(part) / Double(whole) : nil
        }
        func ranked(_ counts: [String: Int], limit: Int = .max) -> [QRInsightsCount] {
            counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(limit)
                .map { QRInsightsCount(label: $0.key, count: $0.value) }
        }
        /// "iPhone · Safari" → "iPhone".
        func phone(of visit: QRVisitSummary) -> String {
            visit.device?.components(separatedBy: " · ").first ?? "Unknown"
        }
        let starts = Dictionary(uniqueKeysWithValues: visits.compactMap { v in iso.date(from: v.startedAt).map { (v.visitId, $0) } })

        // Floor map heat map: every table, including ones with no visits.
        let visitsByTable = Dictionary(grouping: visits.filter { $0.table != nil }, by: { $0.table! })
        let tables = TableMap.entries.map { entry -> QRInsightsTable in
            let tableVisits = visitsByTable[entry.id] ?? []
            return QRInsightsTable(
                table: entry.id, section: entry.section, x: entry.x, y: entry.y, shape: entry.shape,
                visits: tableVisits.count,
                devices: Set(tableVisits.map { $0.customerId ?? $0.deviceId }).count,
                detailViews: tableVisits.reduce(0) { $0 + $1.detailViews.reduce(0) { $0 + $1.count } },
                avgDurationSeconds: average(tableVisits.map(\.durationSeconds)),
                lastVisitAt: tableVisits.map(\.startedAt).max()
            )
        }

        // Per section.
        let visitsBySection = Dictionary(grouping: visits, by: section(of:))
        let sectionNames = TableMap.sections + (visitsBySection["none"] == nil ? [] : ["none"])
        let sections = sectionNames.map { name -> QRInsightsSection in
            let sectionVisits = visitsBySection[name] ?? []
            var items: [String: Int] = [:]
            var phones: [String: Int] = [:]
            for visit in sectionVisits {
                for item in visit.detailViews { items[item.itemName, default: 0] += 1 }
                phones[phone(of: visit), default: 0] += 1
            }
            let firstTaps = sectionVisits.compactMap(\.firstTapSeconds)
            return QRInsightsSection(
                section: name,
                tableCount: TableMap.entries.filter { $0.section == name }.count,
                tablesWithVisits: Set(sectionVisits.compactMap(\.table)).count,
                visits: sectionVisits.count,
                avgDurationSeconds: average(sectionVisits.map(\.durationSeconds)),
                avgFirstTapSeconds: average(firstTaps),
                firstTapSamples: firstTaps.count,
                openedItemRate: rate(sectionVisits.filter { !$0.detailViews.isEmpty }.count, sectionVisits.count),
                returningRate: rate(sectionVisits.filter { $0.previousVisits > 0 }.count, sectionVisits.count),
                topItems: ranked(items, limit: 10),
                deviceMix: ranked(phones)
            )
        }

        // Time of day / day of week.
        var hourCounts: [String: Int] = [:]
        var weekdayCounts: [String: Int] = [:]
        for visit in visits {
            guard let start = starts[visit.visitId] else { continue }
            let name = section(of: visit)
            hourCounts["\(calendar.component(.hour, from: start))|\(name)", default: 0] += 1
            weekdayCounts["\(calendar.component(.weekday, from: start))|\(name)", default: 0] += 1
        }
        func buckets(_ counts: [String: Int]) -> [QRInsightsTimeBucket] {
            counts.compactMap { key, count in
                let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2, let bucket = Int(parts[0]) else { return nil }
                return QRInsightsTimeBucket(bucket: bucket, section: parts[1], visits: count)
            }
            .sorted { $0.bucket != $1.bucket ? $0.bucket < $1.bucket : $0.section < $1.section }
        }

        // Happy Hour.
        let cardVisits = visits.filter { $0.source == "happy-hour-card" }
        var cardItems: [String: Int] = [:]
        for visit in cardVisits {
            for item in visit.detailViews { cardItems[item.itemName, default: 0] += 1 }
        }
        let duringHappyHour = visits.filter { starts[$0.visitId].map { HappyHourSchedule.isActive(at: $0) } ?? false }
        let happyHour = QRInsightsHappyHour(
            cardVisits: cardVisits.count,
            cardStayedOnHappyHour: cardVisits.filter { !$0.pages.isEmpty && $0.pages.allSatisfy { $0 == "/happy-hour" } }.count,
            cardWentToOtherPages: cardVisits.filter { $0.pages.contains { $0 != "/happy-hour" } }.count,
            cardTopItems: ranked(cardItems, limit: 10),
            visitsDuringHappyHour: duringHappyHour.count,
            duringHappyHourOpenedHappyHourItem: duringHappyHour.filter { visit in
                visit.timeline.contains { $0.type == "details" && $0.page == "/happy-hour" }
            }.count
        )

        // Items: opened, photo taps, added to order, against the live menu.
        var photoByName: [String: Bool] = [:]
        for category in menu?.categories ?? [] {
            for item in category.items {
                photoByName[item.name] = (photoByName[item.name] ?? false) || !item.images.isEmpty
            }
        }
        struct ItemTally { var visits = 0, detailViews = 0, photoTaps = 0, added = 0 }
        var tallies: [String: ItemTally] = [:]
        for visit in visits {
            for item in visit.detailViews {
                tallies[item.itemName, default: ItemTally()].visits += 1
                tallies[item.itemName, default: ItemTally()].detailViews += item.count
            }
            for item in visit.photoTaps { tallies[item.itemName, default: ItemTally()].photoTaps += item.count }
            for name in visit.addedToOrder { tallies[name, default: ItemTally()].added += 1 }
        }
        // Looked at vs. ordered, when POS orders are imported.
        let ordersByVisit = Dictionary(uniqueKeysWithValues: visits.map { ($0.visitId, PosMatching.orders(for: $0, in: orders)) })
        var visitsThatOrdered: [String: Int] = [:]
        for visit in visits {
            let orderedNames = (ordersByVisit[visit.visitId] ?? []).flatMap { $0.items.map(\.name) }
            for item in visit.detailViews where orderedNames.contains(where: { PosMatching.sameItem($0, item.itemName) }) {
                visitsThatOrdered[item.itemName, default: 0] += 1
            }
        }
        func timesOrdered(_ menuName: String) -> Int {
            orders.filter { $0.items.contains { PosMatching.sameItem($0.name, menuName) } }.count
        }
        let items = tallies
            .map { name, t in
                QRInsightsItem(
                    itemName: name, visits: t.visits, detailViews: t.detailViews, photoTaps: t.photoTaps,
                    addedToOrder: t.added, visitsThatOrdered: visitsThatOrdered[name] ?? 0,
                    timesOrdered: orders.isEmpty ? 0 : timesOrdered(name),
                    hasPhoto: photoByName[name] ?? false, onMenu: photoByName[name] != nil
                )
            }
            .sorted { $0.visits != $1.visits ? $0.visits > $1.visits : $0.itemName < $1.itemName }

        // Searches.
        var searchCounts: [String: Int] = [:]
        var emptyCounts: [String: Int] = [:]
        for visit in visits {
            for query in visit.searches { searchCounts[query, default: 0] += 1 }
            for query in visit.emptySearches { emptyCounts[query, default: 0] += 1 }
        }
        let searches = searchCounts
            .map { QRInsightsSearch(query: $0.key, count: $0.value, emptyCount: emptyCounts[$0.key] ?? 0) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.query < $1.query }
            .prefix(50)

        // Browsing paths.
        var pathCounts: [[String]: Int] = [:]
        for visit in visits where !visit.pages.isEmpty {
            pathCounts[visit.pages, default: 0] += 1
        }
        let paths = pathCounts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.joined() < $1.key.joined() }
            .prefix(15)
            .map { QRInsightsPath(pages: $0.key, visits: $0.value) }

        // Returning devices.
        let visitsByDevice = Dictionary(grouping: visits, by: { $0.customerId ?? $0.deviceId })
        let returningDevices = visitsByDevice.values.filter { deviceVisits in
            deviceVisits.count > 1 || deviceVisits.contains { $0.previousVisits > 0 }
        }
        let multiVisit = visitsByDevice.values.filter { $0.count > 1 }
        let returning = QRInsightsReturning(
            devices: visitsByDevice.count,
            returningDevices: returningDevices.count,
            visitsFromReturningDevices: returningDevices.reduce(0) { $0 + $1.count },
            multiVisitDevicesInRange: multiVisit.count,
            sameSectionDevices: multiVisit.filter { Set($0.map(section(of:))).count == 1 }.count
        )

        // Parties: phones scanning the same table within the party window of
        // the first phone in the group.
        var phoneCounts: [Int] = []
        for (_, tableVisits) in visitsByTable {
            let ordered = tableVisits.compactMap { v in starts[v.visitId].map { (v, $0) } }.sorted { $0.1 < $1.1 }
            var partyStart: Date?
            var partyPhones = Set<String>()
            for (visit, start) in ordered {
                if let begin = partyStart, start.timeIntervalSince(begin) <= partyWindow {
                    partyPhones.insert(visit.customerId ?? visit.deviceId)
                } else {
                    if partyStart != nil { phoneCounts.append(partyPhones.count) }
                    partyStart = start
                    partyPhones = [visit.customerId ?? visit.deviceId]
                }
            }
            if partyStart != nil { phoneCounts.append(partyPhones.count) }
        }
        var phonesPerParty: [String: Int] = [:]
        for count in phoneCounts { phonesPerParty[count >= 4 ? "4+" : String(count), default: 0] += 1 }
        let parties = QRInsightsParties(
            parties: phoneCounts.count,
            avgPhonesPerParty: average(phoneCounts.map(Double.init)),
            phonesPerParty: ["1", "2", "3", "4+"].map { QRInsightsCount(label: $0, count: phonesPerParty[$0] ?? 0) }
        )

        var overallPhones: [String: Int] = [:]
        for visit in visits { overallPhones[phone(of: visit), default: 0] += 1 }

        return QRInsights(
            from: iso.string(from: from), to: iso.string(from: to), totalVisits: visits.count,
            tables: tables, sections: sections,
            byHour: buckets(hourCounts), byWeekday: buckets(weekdayCounts),
            happyHour: happyHour, items: Array(items.prefix(100)), searches: Array(searches), paths: Array(paths),
            returning: returning, parties: parties, deviceMix: ranked(overallPhones),
            pos: orders.isEmpty ? nil : posComparison(visits: visits, orders: orders, ordersByVisit: ordersByVisit, menu: menu)
        )
    }

    private static func posComparison(
        visits: [QRVisitSummary], orders: [PosOrder], ordersByVisit: [String: [PosOrder]], menu: Menu?
    ) -> QRInsightsPos {
        let mapTables = Set(TableMap.entries.map(\.id))
        let tableOrders = orders.filter { $0.table.map(mapTables.contains) ?? false }
        let matchedIds = Set(ordersByVisit.values.flatMap { $0.map(\.id) })
        let withQR = tableOrders.filter { matchedIds.contains($0.id) }
        let withoutQR = tableOrders.filter { !matchedIds.contains($0.id) }
        func perGuest(_ list: [PosOrder], _ value: (PosOrder) -> Double?) -> Double? {
            let pairs = list.compactMap { order in value(order).map { ($0, Double(max(order.guestCount ?? 1, 1))) } }
            let guests = pairs.reduce(0) { $0 + $1.1 }
            return guests > 0 ? pairs.reduce(0) { $0 + $1.0 } / guests : nil
        }
        let itemCount: (PosOrder) -> Double? = { order in order.items.reduce(0) { $0 + $1.quantity } }
        let menuNames = (menu?.categories ?? []).flatMap { $0.items.map(\.name) }
        var unmatched: [String: Int] = [:]
        for order in orders {
            for item in order.items where !menuNames.contains(where: { PosMatching.sameItem(item.name, $0) }) {
                unmatched[item.name, default: 0] += 1
            }
        }
        let visitsWithTable = visits.filter { PosMatching.tableKey($0.table).map(mapTables.contains) ?? false }
        return QRInsightsPos(
            orders: orders.count,
            tableOrders: tableOrders.count,
            tableOrdersWithQRVisit: withQR.count,
            qrVisitsWithOrder: visitsWithTable.filter { !(ordersByVisit[$0.visitId] ?? []).isEmpty }.count,
            qrVisitsWithTable: visitsWithTable.count,
            avgNetSalesWithQR: perGuest(withQR, \.netSales),
            avgNetSalesWithoutQR: perGuest(withoutQR, \.netSales),
            avgItemsWithQR: perGuest(withQR, itemCount),
            avgItemsWithoutQR: perGuest(withoutQR, itemCount),
            unmatchedPosItems: unmatched
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(30)
                .map { QRInsightsCount(label: $0.key, count: $0.value) }
        )
    }
}
