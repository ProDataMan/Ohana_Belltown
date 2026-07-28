import Vapor

/// One table/seat's position on the staff-facing floor map — purely a
/// visual reference, positions are percentages of the section's canvas so
/// the map lays out reasonably at any screen size. Digitized from photos
/// of the POS's own floor plan (2026-07-28); the actual seating chart is
/// the source of truth if it ever changes — just edit `TableMap.entries`.
struct TableMapEntry: Content {
    var id: String
    var section: String
    var x: Double
    var y: Double
    var shape: String

    init(_ id: String, section: String, x: Double, y: Double, shape: String = "round") {
        self.id = id
        self.section = section
        self.x = x
        self.y = y
        self.shape = shape
    }
}

enum TableMap {
    static let sections = ["dining", "bar", "sushi", "deck"]

    static let entries: [TableMapEntry] = [
        // Deck (patio) — two rows of round 4-tops.
        TableMapEntry("84", section: "deck", x: 29, y: 38),
        TableMapEntry("85", section: "deck", x: 42, y: 38),
        TableMapEntry("86", section: "deck", x: 57, y: 38),
        TableMapEntry("87", section: "deck", x: 72, y: 38),
        TableMapEntry("83", section: "deck", x: 31, y: 62),
        TableMapEntry("81", section: "deck", x: 50, y: 63),
        TableMapEntry("80", section: "deck", x: 65, y: 63),

        // Sushi bar.
        TableMapEntry("72", section: "sushi", x: 23, y: 20, shape: "square"),
        TableMapEntry("70", section: "sushi", x: 70, y: 33, shape: "square"),
        TableMapEntry("73", section: "sushi", x: 23, y: 40, shape: "square"),
        TableMapEntry("71", section: "sushi", x: 30, y: 41, shape: "square"),
        TableMapEntry("65", section: "sushi", x: 22, y: 68, shape: "square"),
        TableMapEntry("64", section: "sushi", x: 32, y: 68, shape: "square"),
        TableMapEntry("63", section: "sushi", x: 43, y: 68, shape: "square"),
        TableMapEntry("62", section: "sushi", x: 54, y: 68, shape: "square"),
        TableMapEntry("61", section: "sushi", x: 66, y: 68, shape: "square"),
        TableMapEntry("60", section: "sushi", x: 77, y: 68, shape: "square"),

        // Bar — R = rail seating, B = bar tables.
        TableMapEntry("R1", section: "bar", x: 21, y: 29, shape: "square"),
        TableMapEntry("R2", section: "bar", x: 28, y: 29, shape: "square"),
        TableMapEntry("R3", section: "bar", x: 37, y: 29, shape: "square"),
        TableMapEntry("R4", section: "bar", x: 45, y: 29, shape: "square"),
        TableMapEntry("R5", section: "bar", x: 53, y: 29, shape: "square"),
        TableMapEntry("R6", section: "bar", x: 61, y: 29, shape: "square"),
        TableMapEntry("B1", section: "bar", x: 13, y: 58, shape: "square"),
        TableMapEntry("B2", section: "bar", x: 21, y: 58, shape: "square"),
        TableMapEntry("B3", section: "bar", x: 29, y: 58, shape: "square"),
        TableMapEntry("B4", section: "bar", x: 37, y: 58, shape: "square"),
        TableMapEntry("B5", section: "bar", x: 45, y: 58, shape: "square"),
        TableMapEntry("B6", section: "bar", x: 53, y: 58, shape: "square"),
        TableMapEntry("B7", section: "bar", x: 61, y: 64, shape: "square"),
        TableMapEntry("B8", section: "bar", x: 61, y: 74, shape: "square"),
        TableMapEntry("B9", section: "bar", x: 62, y: 84, shape: "square"),

        // Dining room — two columns.
        TableMapEntry("30", section: "dining", x: 28, y: 33, shape: "square"),
        TableMapEntry("28", section: "dining", x: 28, y: 47, shape: "round"),
        TableMapEntry("26", section: "dining", x: 28, y: 60, shape: "round"),
        TableMapEntry("24", section: "dining", x: 27, y: 76, shape: "round"),
        TableMapEntry("49", section: "dining", x: 53, y: 14, shape: "square"),
        TableMapEntry("48", section: "dining", x: 53, y: 25, shape: "square"),
        TableMapEntry("47", section: "dining", x: 53, y: 35, shape: "round"),
        TableMapEntry("46", section: "dining", x: 53, y: 45, shape: "round"),
        TableMapEntry("44", section: "dining", x: 52, y: 57, shape: "round"),
        TableMapEntry("42", section: "dining", x: 52, y: 68, shape: "square"),
        TableMapEntry("40", section: "dining", x: 52, y: 80, shape: "round"),
    ]

    static let allIds = Set(entries.map(\.id))
}
