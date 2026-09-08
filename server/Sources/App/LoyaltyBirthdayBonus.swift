import Vapor

/// A daily sweep that pays a bonus punch to any customer whose birthday is
/// today and who has linked a rewards phone number — a real, ongoing perk on
/// top of the staff-visible birthday list CustomerUserStore already powers.
/// Idempotent per calendar year via LoyaltyCustomer.lastBirthdayBonusYear, so
/// running this more than once a day (or every day) is always safe.
enum LoyaltyBirthdayBonus {
    static func runSweep(_ app: Application) async {
        do {
            let year = Calendar(identifier: .gregorian).component(.year, from: Date())
            let customers = try CustomerUserStore.shared.upcomingBirthdays(withinDays: 0)
            for customer in customers {
                guard let phone = customer.loyaltyPhone else { continue }
                _ = try? LoyaltyStore.shared.awardBirthdayBonusIfNeeded(phone: phone, year: year)
            }
        } catch {
            app.logger.error("Loyalty birthday bonus sweep failed: \(error)")
        }
    }
}
