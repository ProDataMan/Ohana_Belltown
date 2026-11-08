import Vapor

/// The classic menu engineering matrix (Kasavana & Smith) over POS sales:
/// each item is popular or not (its share of items sold against 70% of an
/// even share), and profitable or not (its margin per unit against the
/// average margin per unit sold). That puts every dish in one of four boxes:
///
/// - **star**: popular and profitable — keep, feature
/// - **plowhorse**: popular, below-average margin — reprice or re-cost
/// - **puzzle**: profitable, not popular — promote, rename, re-photo, reposition
/// - **dog**: neither — rework or drop
///
/// Margin needs plate costs from the POS. Without any, items are ranked by
/// average price instead, and the report says so (`usesCost == false`).
struct MenuEngineeringReport: Content {
    var from: String
    var to: String
    var usesCost: Bool
    var itemsSold: Double
    var items: [MenuEngineeringItem]
}

struct MenuEngineeringItem: Content {
    var name: String
    var quantity: Double
    var netSales: Double
    var avgPrice: Double
    /// Average plate cost per unit, when the POS reports costs for it.
    var avgCost: Double?
    var marginPerUnit: Double?
    var foodCostPercent: Double?
    var popularityShare: Double
    var popular: Bool
    var profitable: Bool
    /// "star", "plowhorse", "puzzle", or "dog".
    var category: String
    /// QR visits that opened this dish's details in the same range, when the
    /// name matches a website menu item.
    var qrDetailViews: Int?
}

enum MenuEngineering {
    /// An item is "popular" at 70% of an even share or more — the standard
    /// threshold from the original method.
    static let popularityFactor = 0.7

    static func build(orders: [PosOrder], from: Date, to: Date, qrViews: [String: Int] = [:]) -> MenuEngineeringReport {
        struct Tally { var quantity = 0.0, sales = 0.0, cost = 0.0, costedQuantity = 0.0 }
        var tallies: [String: Tally] = [:]
        for order in orders {
            for item in order.items where item.quantity > 0 {
                var tally = tallies[item.name] ?? Tally()
                tally.quantity += item.quantity
                tally.sales += item.netSales ?? 0
                if let cost = item.cost {
                    // Heartland reports cost per ticket line, like net sales.
                    tally.cost += cost
                    tally.costedQuantity += item.quantity
                }
                tallies[item.name] = tally
            }
        }
        let totalQuantity = tallies.values.reduce(0) { $0 + $1.quantity }
        let usesCost = tallies.values.contains { $0.costedQuantity > 0 }
        let evenShare = tallies.isEmpty ? 0 : 1 / Double(tallies.count)

        func value(_ t: Tally) -> Double? {
            let price = t.sales / t.quantity
            guard usesCost else { return price }
            guard t.costedQuantity > 0 else { return nil }
            return price - t.cost / t.costedQuantity
        }
        // Weighted by units sold, so the benchmark is "the average unit sold".
        let weighted = tallies.values.compactMap { t in value(t).map { ($0 * t.quantity, t.quantity) } }
        let weightedUnits = weighted.reduce(0) { $0 + $1.1 }
        let benchmark = weightedUnits > 0 ? weighted.reduce(0) { $0 + $1.0 } / weightedUnits : 0

        let items = tallies.map { name, t -> MenuEngineeringItem in
            let share = totalQuantity > 0 ? t.quantity / totalQuantity : 0
            let popular = share >= evenShare * popularityFactor
            let itemValue = value(t)
            let profitable = (itemValue ?? -.greatestFiniteMagnitude) >= benchmark
            let avgCost = t.costedQuantity > 0 ? t.cost / t.costedQuantity : nil
            let avgPrice = t.sales / t.quantity
            let category = popular ? (profitable ? "star" : "plowhorse") : (profitable ? "puzzle" : "dog")
            let qr = qrViews.first { PosMatching.sameItem(name, $0.key) }?.value
            return MenuEngineeringItem(
                name: name, quantity: t.quantity, netSales: t.sales, avgPrice: avgPrice, avgCost: avgCost,
                marginPerUnit: avgCost.map { avgPrice - $0 },
                foodCostPercent: avgCost.flatMap { avgPrice > 0 ? $0 / avgPrice : nil },
                popularityShare: share, popular: popular, profitable: profitable, category: category, qrDetailViews: qr
            )
        }
        .sorted { $0.quantity != $1.quantity ? $0.quantity > $1.quantity : $0.name < $1.name }

        let iso = ISO8601DateFormatter()
        return MenuEngineeringReport(
            from: iso.string(from: from), to: iso.string(from: to), usesCost: usesCost, itemsSold: totalQuantity, items: items
        )
    }
}
