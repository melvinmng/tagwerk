import Foundation

/// The Health values of one day that Tagwerk keeps, so past days stay stable: the weekly review and the charts must not change
/// because Health later answers differently (or not at all).
public struct DayHealth: Sendable, Hashable {
    public var day: PlanDay
    /// The day's sum of the active energy from Health; `nil` when Health gave none.
    public var activeKcal: Double?
    /// The share of the active energy that counted on that day, in percent.
    public var creditPercent: Int
    /// Totals of other apps' nutrition entries; values `nil` when Health gave none.
    public var foreign: ForeignIntake

    public init(day: PlanDay, activeKcal: Double?, creditPercent: Int, foreign: ForeignIntake = ForeignIntake()) {
        self.day = day
        self.activeKcal = activeKcal
        self.creditPercent = creditPercent
        self.foreign = foreign
    }

    /// The stored value after a new reading.
    ///
    /// `overwritingUnknown` is for today: every load replaces the stored values, so an entry deleted in another app disappears
    /// from the sum. For a past day a reading only adds what Health delivers: iOS reports a denied or failed read like a day
    /// without data, and that must not erase a value that was known before.
    public func merged(with newer: DayHealth, overwritingUnknown: Bool) -> DayHealth {
        func pick(_ stored: Double?, _ fresh: Double?) -> Double? { overwritingUnknown ? fresh : (fresh ?? stored) }
        var foreign = ForeignIntake(
            kcal: pick(self.foreign.kcal, newer.foreign.kcal), protein: pick(self.foreign.protein, newer.foreign.protein),
            carbs: pick(self.foreign.carbs, newer.foreign.carbs), fat: pick(self.foreign.fat, newer.foreign.fat),
            waterMilliliters: pick(self.foreign.waterMilliliters, newer.foreign.waterMilliliters))
        for nutrient in Nutrient.allCases {
            foreign.nutrients[nutrient] = pick(self.foreign.nutrients[nutrient], newer.foreign.nutrients[nutrient])
        }
        foreign.sources = overwritingUnknown || !newer.foreign.sources.isEmpty ? newer.foreign.sources : self.foreign.sources
        return DayHealth(day: day, activeKcal: pick(activeKcal, newer.activeKcal),
                         creditPercent: overwritingUnknown ? newer.creditPercent : creditPercent, foreign: foreign)
    }
}
