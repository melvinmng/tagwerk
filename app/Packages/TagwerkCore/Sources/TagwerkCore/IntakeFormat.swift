import Foundation

/// German display texts of the "Erfassen" tab. Estimates always carry "~" or a range (anti-goal: no exact-looking estimates).
public enum IntakeFormat {
    public struct Remaining: Sendable, Hashable {
        public var text: String
        public var isOver: Bool

        public init(text: String, isOver: Bool) {
            self.text = text
            self.isOver = isOver
        }
    }

    /// Rounds kilocalories to tens.
    public static func roundedKcal(_ value: Double) -> Int {
        Int((value / 10).rounded()) * 10
    }

    /// "~520 kcal" for estimates, "80 kcal" for typed values.
    public static func kcal(_ value: Double, estimated: Bool) -> String {
        "\(kcalNumber(value, estimated: estimated)) kcal"
    }

    /// "~1.310" or "95", without the unit.
    public static func kcalNumber(_ value: Double, estimated: Bool) -> String {
        let number = estimated ? roundedKcal(value) : Int(value.rounded())
        return "\(estimated ? "~" : "")\(grouped(number))"
    }

    /// Quantity factor of an item: "×1,5", "×2".
    public static func factor(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.maximumFractionDigits = 1
        return "×\(formatter.string(from: NSNumber(value: value)) ?? "1")"
    }

    /// "wahrscheinlich zwischen 410 und 550 kcal".
    public static func range(min: Double, max: Double) -> String {
        "wahrscheinlich zwischen \(grouped(roundedKcal(min))) und \(grouped(roundedKcal(max))) kcal"
    }

    /// The range sentence, or `nil` for exact values (min equals max after rounding).
    public static func rangeIfEstimated(min: Double, max: Double) -> String? {
        roundedKcal(min) == roundedKcal(max) ? nil : range(min: min, max: max)
    }

    /// "410–550" for lists.
    public static func shortRange(min: Double, max: Double) -> String {
        "\(grouped(roundedKcal(min)))–\(grouped(roundedKcal(max)))"
    }

    /// "~22 g" or "5 g".
    public static func grams(_ value: Double, estimated: Bool) -> String {
        "\(estimated ? "~" : "")\(Int(value.rounded())) g"
    }

    /// "noch ~990" while below the goal, "120 über Ziel" above it.
    public static func remaining(goal: Int, intake: DayIntake) -> Remaining {
        let difference = Double(goal) - intake.kcal
        if difference < 0 {
            return Remaining(text: "\(grouped(roundedKcal(-difference))) über Ziel", isOver: true)
        }
        let value = intake.hasEstimate ? roundedKcal(difference) : Int(difference.rounded())
        return Remaining(text: "noch \(intake.hasEstimate ? "~" : "")\(grouped(value))", isOver: false)
    }

    /// "1,2 l", "2,0 l", "0,25 l".
    public static func liters(_ milliliters: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: NSNumber(value: Double(milliliters) / 1000)) ?? "0") l"
    }

    /// Value of the settings row "Erfassen": "2.300 kcal · 2,0 l · 3×".
    public static func goalSummary(kcal: Int, waterMilliliters: Int, workoutsPerWeek: Int) -> String {
        "\(grouped(kcal)) kcal · \(liters(waterMilliliters)) · \(workoutsPerWeek)×"
    }

    /// German digit grouping: 2300 → "2.300".
    public static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
