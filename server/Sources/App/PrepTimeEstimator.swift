import Foundation

/// Estimates how long a dish will take to prepare, for the "should be ready
/// around..." staff notification. Two layers, cheapest-available-data-wins:
///
/// 1. Once a specific item has at least 3 completed (entered -> delivered)
///    samples, its own real average is used — this is the thing that
///    actually gets more accurate over time as the table-order system runs.
/// 2. Until then, a rough per-section baseline guess is used instead.
///
/// Either way, the result is adjusted for how busy the kitchen looks right
/// now: more occupied tables than on-duty staff can comfortably run in
/// parallel adds time. This is a simple, explainable heuristic — not a
/// measured relationship — and is expected to matter less over time as
/// real per-item averages take over from the baseline guesses.
enum PrepTimeEstimator {
    /// Rough, informed-guess baselines per menu section (`MENU_SECTION` on
    /// the public menu pages), in minutes.
    static let sectionBaselineMinutes: [String: Double] = [
        "drinks": 3,
        "happy_hour": 7,
        "sushi": 12,
        "menu": 12,
    ]
    static let fallbackBaselineMinutes: Double = 10

    /// Each occupied table beyond what on-duty staff can comfortably run in
    /// parallel adds 15% more time.
    static let overloadPenaltyPerTable: Double = 0.15

    static func baselineMinutes(section: String?) -> Double {
        guard let section else { return fallbackBaselineMinutes }
        return sectionBaselineMinutes[section] ?? fallbackBaselineMinutes
    }

    static func loadAdjustedMinutes(baseline: Double, occupiedTables: Int, staffOnDuty: Int) -> Double {
        let staff = max(1, staffOnDuty)
        let overload = max(0, occupiedTables - staff)
        let multiplier = 1.0 + (Double(overload) * overloadPenaltyPerTable)
        return baseline * multiplier
    }
}
