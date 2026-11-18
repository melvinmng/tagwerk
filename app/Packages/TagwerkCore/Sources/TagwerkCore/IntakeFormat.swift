import Foundation

/// Display texts of the "Erfassen" tab, formatted for the given locale. Estimates always carry "~" or a range (anti-goal: no exact-looking estimates).
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
    public static func kcal(_ value: Double, estimated: Bool, locale: Locale = .current) -> String {
        String(localized: "\(kcalNumber(value, estimated: estimated, locale: locale)) kcal", bundle: .module)
    }

    /// "~1.310" or "95", without the unit.
    public static func kcalNumber(_ value: Double, estimated: Bool, locale: Locale = .current) -> String {
        let number = estimated ? roundedKcal(value) : Int(value.rounded())
        return "\(estimated ? "~" : "")\(grouped(number, locale: locale))"
    }

    /// Quantity factor of an item: "×1,5", "×2".
    public static func factor(_ value: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.maximumFractionDigits = 1
        let number = formatter.string(from: NSNumber(value: value)) ?? "1"
        return String(localized: "×\(number)", bundle: .module)
    }

    /// "wahrscheinlich zwischen 410 und 550 kcal".
    public static func range(min: Double, max: Double, locale: Locale = .current) -> String {
        let low = grouped(roundedKcal(min), locale: locale), high = grouped(roundedKcal(max), locale: locale)
        return String(localized: "wahrscheinlich zwischen \(low) und \(high) kcal", bundle: .module)
    }

    /// The range sentence, or `nil` for exact values (min equals max after rounding).
    public static func rangeIfEstimated(min: Double, max: Double, locale: Locale = .current) -> String? {
        roundedKcal(min) == roundedKcal(max) ? nil : range(min: min, max: max, locale: locale)
    }

    /// "410–550" for lists.
    public static func shortRange(min: Double, max: Double, locale: Locale = .current) -> String {
        "\(grouped(roundedKcal(min), locale: locale))–\(grouped(roundedKcal(max), locale: locale))"
    }

    /// "~22 g" or "5 g".
    public static func grams(_ value: Double, estimated: Bool) -> String {
        let number = "\(estimated ? "~" : "")\(Int(value.rounded()))"
        return String(localized: "\(number) g", bundle: .module)
    }

    /// "noch ~990" while below the goal, "120 über Ziel" above it.
    public static func remaining(goal: Int, intake: DayIntake, locale: Locale = .current) -> Remaining {
        let difference = Double(goal) - intake.kcal
        if difference < 0 {
            let over = intake.hasEstimate ? roundedKcal(-difference) : Int((-difference).rounded())
            let number = "\(intake.hasEstimate ? "~" : "")\(grouped(over, locale: locale))"
            return Remaining(text: String(localized: "\(number) über Ziel", bundle: .module), isOver: true)
        }
        let value = intake.hasEstimate ? roundedKcal(difference) : Int(difference.rounded())
        let number = "\(intake.hasEstimate ? "~" : "")\(grouped(value, locale: locale))"
        return Remaining(text: String(localized: "noch \(number)", bundle: .module), isOver: false)
    }

    /// "1,2 l", "2,0 l", "0,25 l".
    public static func liters(_ milliliters: Int, locale: Locale = .current) -> String {
        String(localized: "\(litersNumber(milliliters, locale: locale)) l", bundle: .module)
    }

    /// "1,2", "0,25", without the unit.
    public static func litersNumber(_ milliliters: Int, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: Double(milliliters) / 1000)) ?? "0"
    }

    /// Value of the settings row "Erfassen": "2.300 kcal · 2,0 l · 2 h 30 min"; without the training part when its goal is 0.
    public static func goalSummary(kcal: Int, waterMilliliters: Int, workoutMinutesPerWeek: Int, locale: Locale = .current) -> String {
        let energy = grouped(kcal, locale: locale), water = liters(waterMilliliters, locale: locale)
        guard workoutMinutesPerWeek > 0 else { return String(localized: "\(energy) kcal · \(water)", bundle: .module) }
        let training = duration(minutes: workoutMinutesPerWeek)
        return String(localized: "\(energy) kcal · \(water) · \(training)", bundle: .module)
    }

    /// Training time (decision 6 of the steps plan): "45 min" below an hour, "1 h 17 min" and "2 h" from 60 minutes on.
    public static func duration(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return String(localized: "\(minutes) min", bundle: .module) }
        if rest == 0 { return String(localized: "\(hours) h", bundle: .module) }
        return String(localized: "\(hours) h \(rest) min", bundle: .module)
    }

    /// "2 h 7 min / 2 h 30 min": both sides in the same format, also against a goal.
    public static func duration(minutes: Int, goal: Int) -> String {
        "\(duration(minutes: minutes)) / \(duration(minutes: goal))"
    }

    /// "2 Stunden und 7 Minuten" for VoiceOver; the units are written out by the system formatter.
    public static func spokenDuration(minutes: Int, locale: Locale = .current) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide).locale(locale))
    }

    /// Step count with the locale's digit grouping: "6.412".
    public static func steps(_ count: Int, locale: Locale = .current) -> String {
        grouped(count, locale: locale)
    }

    /// Value of the steps tile: "6.412 / 8.000", only the count without a goal, "–" without data (never 0,
    /// because iOS does not tell a denied read from a day without steps).
    public static func stepsValue(_ count: Int?, goal: Int, locale: Locale = .current) -> String {
        guard let count else { return "–" }
        guard goal > 0 else { return steps(count, locale: locale) }
        return "\(steps(count, locale: locale)) / \(grouped(goal, locale: locale))"
    }

    /// Digit grouping of the locale: 2300 → "2.300" (German), "2,300" (English).
    public static func grouped(_ value: Int, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
