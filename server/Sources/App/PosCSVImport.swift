import Vapor

/// Imports POS tickets from a CSV export, for when the Heartland API key
/// isn't set up (or to backfill). One row per item; rows are grouped into
/// tickets by ticket number (or, without one, table + open time).
///
/// Column names vary by report, so each field is recognized from a list of
/// likely header names (case and punctuation ignored). Needs at least an
/// item column, a time column, and a ticket or table column.
enum PosCSVImport {
    struct Result: Content {
        var orders: Int
        var items: Int
        var skippedRows: Int
        /// Field → the header it was read from.
        var columns: [String: String]
        var ignoredColumns: [String]
        var added: Int
        var updated: Int
    }

    struct ImportError: Error, CustomStringConvertible {
        var description: String
    }

    static let headerNames: [String: [String]] = [
        "ticket": ["ticket", "ticketnumber", "ticketno", "ticketid", "check", "checknumber", "checkno", "order", "ordernumber", "orderid"],
        "table": ["table", "tablename", "tablenumber", "tableno"],
        "room": ["room", "roomname", "area", "section"],
        "opened": ["opened", "openedat", "opendt", "openeddt", "opentime", "timeopened", "openeddate", "opendate", "ordertime", "datetime", "addeddt", "added"],
        "closed": ["closed", "closedat", "closeddt", "closetime", "timeclosed", "closedate", "closeddate"],
        "date": ["date", "businessdate", "orderdate"],
        "time": ["time"],
        "item": ["item", "itemname", "menuitem", "product", "name", "description"],
        "quantity": ["qty", "quantity", "count", "itemcount"],
        "price": ["netsales", "net", "itemnetsales", "price", "amount", "subtotal", "total", "grosssales"],
        "guests": ["guests", "guestcount", "covers", "party", "partysize"],
        "voided": ["voided", "voideddt", "voidtime", "void"],
        "cost": ["cost", "platecost", "itemcost", "foodcost"],
    ]

    static func normalizeHeader(_ header: String) -> String {
        header.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func run(csv: String) throws -> Result {
        let rows = parse(csv)
        guard let header = rows.first else { throw ImportError(description: "The file is empty.") }

        var columns: [String: Int] = [:]
        var columnNames: [String: String] = [:]
        var used = Set<Int>()
        // Fields claim headers in this order, so "date" doesn't take a
        // column "opened" already matched.
        for field in ["ticket", "table", "room", "opened", "closed", "date", "time", "item", "quantity", "price", "guests", "voided", "cost"] {
            let names = headerNames[field] ?? []
            for name in names {
                if let index = header.indices.first(where: { !used.contains($0) && normalizeHeader(header[$0]) == name }) {
                    columns[field] = index
                    columnNames[field] = header[index]
                    used.insert(index)
                    break
                }
            }
        }
        guard columns["item"] != nil else {
            throw ImportError(description: "Couldn't find an item column (looked for: Item, Item Name, Menu Item, Name). Columns found: \(header.joined(separator: ", ")).")
        }
        guard columns["opened"] != nil || columns["date"] != nil else {
            throw ImportError(description: "Couldn't find a time column (looked for: Opened, Open Time, Date, Order Time). Columns found: \(header.joined(separator: ", ")).")
        }
        guard columns["ticket"] != nil || columns["table"] != nil else {
            throw ImportError(description: "Couldn't find a ticket or table column (looked for: Ticket, Check, Order Number, Table). Columns found: \(header.joined(separator: ", ")).")
        }

        func value(_ row: [String], _ field: String) -> String? {
            guard let index = columns[field], index < row.count else { return nil }
            let text = row[index].trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }

        var orders: [String: PosOrder] = [:]
        var order: [String] = []
        var skipped = 0
        var itemCount = 0
        for row in rows.dropFirst() where !row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            guard let itemName = value(row, "item") else { skipped += 1; continue }
            if let voided = value(row, "voided"), !["", "false", "no", "0"].contains(voided.lowercased()) { continue }
            var openedText = value(row, "opened")
            if openedText == nil, let date = value(row, "date") {
                openedText = value(row, "time").map { "\(date) \($0)" } ?? date
            } else if let opened = openedText, let time = value(row, "time"), !opened.contains(":") {
                openedText = "\(opened) \(time)"
            }
            guard let opened = openedText.flatMap(parseDate) else { skipped += 1; continue }
            let table = PosMatching.tableKey(value(row, "table"))
            let ticket = value(row, "ticket")
            guard ticket != nil || table != nil else { skipped += 1; continue }

            let businessDay = businessDate(opened)
            let key = ticket.map { "csv:\(businessDay):\($0)" }
                ?? "csv:\(businessDay):table-\(table!):\(ISO8601DateFormatter().string(from: opened))"
            var current = orders[key] ?? PosOrder(
                id: key, source: "csv", ticketNumber: ticket, table: table, room: value(row, "room"),
                openedAt: ISO8601DateFormatter().string(from: opened),
                closedAt: value(row, "closed").flatMap(parseDate).map { ISO8601DateFormatter().string(from: $0) },
                guestCount: value(row, "guests").flatMap { Int(Double($0) ?? 0) },
                items: [], netSales: nil
            )
            if orders[key] == nil { order.append(key) }
            // A ticket's open time is its earliest row.
            if let existing = PosMatching.date(current.openedAt), opened < existing {
                current.openedAt = ISO8601DateFormatter().string(from: opened)
            }
            if current.table == nil { current.table = table }
            let price = value(row, "price").flatMap(parseMoney)
            current.items.append(PosOrderItem(
                name: itemName, quantity: value(row, "quantity").flatMap { Double($0) } ?? 1, netSales: price,
                cost: value(row, "cost").flatMap(parseMoney)
            ))
            if let price { current.netSales = (current.netSales ?? 0) + price }
            orders[key] = current
            itemCount += 1
        }
        let imported = order.compactMap { orders[$0] }
        guard !imported.isEmpty else {
            throw ImportError(description: "No usable rows found (\(skipped) skipped). Each row needs an item, a time, and a ticket or table.")
        }
        let outcome = try PosOrderStore.shared.upsert(imported, status: PosSyncStatus(
            at: ISO8601DateFormatter().string(from: Date()), source: "csv", from: nil, to: nil,
            ordersImported: imported.count, error: nil
        ))
        return Result(
            orders: imported.count, items: itemCount, skippedRows: skipped, columns: columnNames,
            ignoredColumns: header.indices.filter { !used.contains($0) }.map { header[$0] },
            added: outcome.added, updated: outcome.updated
        )
    }

    /// "$1,234.50" → 1234.5.
    static func parseMoney(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
    }

    /// ISO 8601, or common US report formats in restaurant time.
    static func parseDate(_ text: String) -> Date? {
        if let date = PosMatching.date(text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = HappyHourSchedule.pacific
        for format in [
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd h:mm a", "yyyy-MM-dd h:mm:ss a",
            "M/d/yyyy h:mm a", "M/d/yyyy h:mm:ss a", "M/d/yyyy HH:mm", "M/d/yyyy HH:mm:ss",
            "M/d/yy h:mm a", "M/d/yy HH:mm", "MM/dd/yyyy hh:mm a", "M/d/yyyy", "yyyy-MM-dd",
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static func businessDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = HappyHourSchedule.pacific
        formatter.dateFormat = "yyyy-MM-dd"
        // Tickets opened before 4am belong to the previous business day.
        return formatter.string(from: date.addingTimeInterval(-4 * 3600))
    }

    /// RFC 4180-style CSV: quoted fields, doubled quotes, newlines in quotes.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").makeIterator()
        var pending: Character? = nil
        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else if char == "\"" {
                inQuotes = true
            } else if char == "," {
                row.append(field)
                field = ""
            } else if char == "\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        // Strip a UTF-8 byte-order mark Excel adds to the first header.
        if var first = rows.first, let head = first.first, head.hasPrefix("\u{FEFF}") {
            first[0] = String(head.dropFirst())
            rows[0] = first
        }
        return rows
    }
}
