import Foundation

/// The numbers behind the checks of the goals and the weight trend. Every value carries its source from the fact check of
/// 21.11.2026 (`docs/superpowers/research/2026-11-21-ernaehrung-faktenpruefung.md`); no other place in the code names these
/// numbers. They are computing aids of the app, not medical limits, and not adjustable.
///
/// The goal planning (strand G) adds its constants here; this file starts with the weight pace, which the trends page uses.
public enum GoalGuardConstants {
    /// A weight loss faster than `min(share of the body weight, kilograms)` per week triggers a hint. This is a rule of the app:
    /// neither "1 % per week" nor "1 kg per week" is a guideline. The CDC names about 0.45–0.9 kg per week as a usual pace; the
    /// percentage values in the literature come from sport (Garthe et al. 2011, doi:10.1123/ijsnem.21.2.97: 0.7 % of the body weight
    /// per week did better than 1.4 % for athletes in a diet phase).
    public static let maxWeeklyChangeShare = 0.01
    public static let maxWeeklyChangeKilograms = 1.0

    /// The weekly weight loss above which Tagwerk warns for a body weight of `bodyWeightKg`.
    public static func weeklyLossLimit(bodyWeightKg: Double) -> Double {
        min(maxWeeklyChangeShare * bodyWeightKg, maxWeeklyChangeKilograms)
    }

    /// Whether a trend of `trendPerWeek` kilograms per week (negative for losing weight) is above the limit. A gain never warns here.
    public static func exceedsWeeklyLossLimit(trendPerWeek: Double, bodyWeightKg: Double) -> Bool {
        trendPerWeek < 0 && -trendPerWeek > weeklyLossLimit(bodyWeightKg: bodyWeightKg)
    }
}
