import Foundation

/// Estimates how long a table is typically occupied — from sitting down to
/// getting up to leave — so staff can get a rough sense of table turnover
/// alongside the wait/prep/delivery KPIs.
///
/// There's no Seattle-specific published data on this (and no realistic way
/// to measure "how long until this table is available again" directly,
/// since nothing here tracks when a party actually leaves) — so this
/// combines one real measurement we do have with two informed-guess
/// constants grounded in general full-service casual-dining research:
///
/// 1. **Wait + prep time** (order placed -> food delivered) — the one part
///    of this that's a real measurement, reusing the same completed-order
///    data as `TableOrdersStore.deliveryStats`.
/// 2. **Eating time** — how long it takes to eat what was ordered. No
///    per-restaurant data exists for this either, so it uses rough
///    per-section baselines (a full entree takes longer to eat than a
///    shared appetizer or a sipped drink), combined the same way
///    `PrepTimeEstimator` combines multiple dishes cooking in parallel:
///    the slowest single dish, or half the combined total, whichever is
///    greater — since a table eating five things isn't eating for 5x as
///    long as a table eating one, but a table with one very slow dish
///    still can't finish before that dish does.
/// 3. **Arrival + social overhead** — time spent deciding what to order
///    before the first order goes in, plus time spent talking, requesting
///    the check, paying, and getting up once the food is gone. National
///    industry benchmarks put a full casual-dining visit at roughly
///    60-90 minutes seated-to-departure, which is what these two constants
///    are sized to land within once combined with 1 and 2 above.
enum DiningTimeEstimator {
    /// Menu-browsing and deciding, before the first order is actually placed.
    static let arrivalToOrderMinutes: Double = 7

    /// Conversation, requesting the check, paying, and gathering to leave,
    /// once the food/drinks are finished.
    static let socialOverheadMinutes: Double = 20

    /// How long it typically takes to eat/drink one dish from a given menu
    /// section — a full entree lingers longer than a shared appetizer or a
    /// sipped drink.
    static let eatingBaselineMinutes: [String: Double] = [
        "drinks": 18,
        "happy_hour": 18,
        "sushi": 22,
        "menu": 25,
    ]
    static let fallbackEatingBaselineMinutes: Double = 22

    /// Orders at the same table more than this far apart are treated as two
    /// separate dining parties rather than one long visit.
    static let sameSessionGapSeconds: TimeInterval = 90 * 60

    static func eatingBaseline(section: String?) -> Double {
        guard let section else { return fallbackEatingBaselineMinutes }
        return eatingBaselineMinutes[section] ?? fallbackEatingBaselineMinutes
    }

    /// Combines every dish's eating-time baseline the same way overlapping
    /// prep times are combined elsewhere: the single slowest dish, or half
    /// the combined total, whichever is greater.
    static func estimatedEatingMinutes(dishSections: [String?]) -> Double {
        let durations = dishSections.map(eatingBaseline)
        guard !durations.isEmpty else { return fallbackEatingBaselineMinutes }
        let longest = durations.max() ?? 0
        let halfOfTotal = durations.reduce(0, +) / 2
        return max(longest, halfOfTotal)
    }

    static func estimatedOccupancyMinutes(waitPlusPrepMinutes: Double, dishSections: [String?]) -> Double {
        arrivalToOrderMinutes + waitPlusPrepMinutes + estimatedEatingMinutes(dishSections: dishSections) + socialOverheadMinutes
    }
}
