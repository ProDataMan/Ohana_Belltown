import Foundation

/// Where a dine-in line item is prepared. Mapped from the menu page the
/// guest ordered on (`MENU_SECTION` / `TableOrderEntry.section`).
enum PrepStation: String, Codable, CaseIterable, Sendable {
    case kitchen
    case sushi
    case bar

    /// Floor-map stage colors (`style.css`): gold needs-entry, purple
    /// processing, pink awaiting-delivery.
    static let needsEntryGold = LightColor(hex: "f2a93c")
    static let processingPurple = LightColor(hex: "8f5fd6")
    static let awaitingPink = LightColor(hex: "ff2f8f")

    /// Distinct area colors used on the *server-station* bulb for needs-entry
    /// so staff can see *which* station the new ticket belongs to. Kitchen
    /// reuses map gold; sushi and bar get hues that stay readable against
    /// gold / purple / pink.
    var needsEntryColor: LightColor {
        switch self {
        case .kitchen: return Self.needsEntryGold
        case .sushi: return LightColor(hex: "2ec4b6")
        case .bar: return LightColor(hex: "3d8bfd")
        }
    }

    var displayName: String {
        switch self {
        case .kitchen: return "Kitchen"
        case .sushi: return "Sushi Bar"
        case .bar: return "Bar"
        }
    }

    /// `drinks` → bar, `sushi` → sushi bar, everything else (full menu,
    /// happy hour, missing section) → kitchen.
    static func from(menuSection: String?) -> PrepStation {
        switch (menuSection ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "drinks", "bar", "cocktail", "cocktails":
            return .bar
        case "sushi", "sushi_bar", "sushibar":
            return .sushi
        default:
            return .kitchen
        }
    }
}

/// RGB + the 12-char Tuya `colour_data` hex (`HHHHSSSSVVVV`).
struct LightColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        let value = UInt32(raw, radix: 16) ?? 0
        if raw.count == 6 {
            self.red = Double((value >> 16) & 0xFF) / 255
            self.green = Double((value >> 8) & 0xFF) / 255
            self.blue = Double(value & 0xFF) / 255
        } else {
            self.red = 1
            self.green = 1
            self.blue = 1
        }
    }

    var hex: String {
        let r = UInt8((red * 255).rounded())
        let g = UInt8((green * 255).rounded())
        let b = UInt8((blue * 255).rounded())
        return String(format: "%02x%02x%02x", r, g, b)
    }

    /// Tuya HSV: hue 0–360, sat/value 0–1000, each as 4 hex digits.
    var tuyaColourData: String {
        let maxC = max(red, green, blue)
        let minC = min(red, green, blue)
        let delta = maxC - minC
        var hue: Double = 0
        if delta > 0.0001 {
            if maxC == red {
                hue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == green {
                hue = 60 * (((blue - red) / delta) + 2)
            } else {
                hue = 60 * (((red - green) / delta) + 4)
            }
        }
        if hue < 0 { hue += 360 }
        let sat = maxC == 0 ? 0.0 : delta / maxC
        let h = Int(hue.rounded())
        let s = Int((sat * 1000).rounded())
        let v = Int((maxC * 1000).rounded())
        return String(format: "%04x%04x%04x", h, s, v)
    }
}
