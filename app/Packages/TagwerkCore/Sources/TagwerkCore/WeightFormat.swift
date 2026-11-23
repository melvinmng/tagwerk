import Foundation

/// The texts of the body weight: values, changes, the projection and the line of the morning start. Numbers follow `locale`.
public enum WeightFormat {
    private static func number(_ value: Double, fractionDigits: Int = 1, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// "81,9 kg"
    public static func kilograms(_ value: Double, locale: Locale = .current) -> String {
        String(localized: "\(number(value, locale: locale)) kg", bundle: .module)
    }

    /// A change with its sign, "−2,5 kg" or "+0,3 kg" (the true minus sign); a change that rounds to zero has none.
    public static func change(_ value: Double, locale: Locale = .current) -> String {
        String(localized: "\(signedNumber(value, locale: locale)) kg", bundle: .module)
    }

    /// "−0,3 kg/Woche"
    public static func changePerWeek(_ value: Double, locale: Locale = .current) -> String {
        String(localized: "\(signedNumber(value, locale: locale)) kg/Woche", bundle: .module)
    }

    private static func signedNumber(_ value: Double, locale: Locale) -> String {
        let rounded = (value * 10).rounded() / 10
        let text = number(abs(rounded), locale: locale)
        if rounded > 0 { return "+" + text }
        if rounded < 0 { return "\u{2212}" + text }
        return text
    }

    /// "22,5 %"
    public static func bodyFat(_ percent: Double, locale: Locale = .current) -> String {
        String(localized: "\(number(percent, locale: locale)) %", bundle: .module)
    }

    /// The distance to the target, "4,1 kg" (always positive; the label says which way).
    public static func distance(_ value: Double, locale: Locale = .current) -> String {
        kilograms(abs(value), locale: locale)
    }

    /// "Bei diesem Tempo etwa Ende Februar 2027." The month is divided in thirds, so the text never claims a day.
    public static func projection(_ projection: WeightTrend.Projection, calendar: Calendar, locale: Locale = .current) -> String {
        let start = projection.day.startDate(in: calendar)
        var style = Date.FormatStyle.dateTime.month(.wide).year().locale(locale)
        style.timeZone = calendar.timeZone
        let month = start.formatted(style)
        switch projection.day.day {
        case ...10: return String(localized: "Bei diesem Tempo etwa Anfang \(month).", bundle: .module)
        case ...20: return String(localized: "Bei diesem Tempo etwa Mitte \(month).", bundle: .module)
        default: return String(localized: "Bei diesem Tempo etwa Ende \(month).", bundle: .module)
        }
    }

    /// The hint next to a trend above the limit of the app. The numbers come from `GoalGuardConstants`; the text calls the limit a rule
    /// of the app, not a guideline.
    public static func paceHint(trend: Double, limit: Double, locale: Locale = .current) -> String {
        let share = number(GoalGuardConstants.maxWeeklyChangeShare * 100, fractionDigits: 0, locale: locale)
        let kilograms = number(GoalGuardConstants.maxWeeklyChangeKilograms, locale: locale)
        let current = number(abs(trend), fractionDigits: 1, locale: locale)
        return String(localized: "Dein Trend liegt bei \(current) kg Abnahme pro Woche. Tagwerk weist ab dem kleineren Wert von \(share) % des Körpergewichts und \(kilograms) kg pro Woche darauf hin. Das ist eine Regel der App, keine Leitlinie; sprich bei Fragen mit einer Ärztin oder einem Arzt.", bundle: .module)
    }

    /// The caption under the weight row of the morning start: "Gestern 82,3 kg · 7-Tage-Mittel 82,1 kg"; `nil` without either.
    public static func morningCaption(yesterday: Double?, mean: Double?, locale: Locale = .current) -> String? {
        var parts: [String] = []
        if let yesterday { parts.append(String(localized: "Gestern \(kilograms(yesterday, locale: locale))", bundle: .module)) }
        if let mean { parts.append(String(localized: "7-Tage-Mittel \(kilograms(mean, locale: locale))", bundle: .module)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The weight figures of the morning start and of the trends row: today's value, yesterday's and the 7-day mean.
public struct WeightOverview: Sendable, Hashable {
    public var today: Double?
    public var yesterday: Double?
    public var mean: Double?
    /// The newest day value up to today, whichever day it is; `nil` without any.
    public var latest: Double?

    public init(today: Double? = nil, yesterday: Double? = nil, mean: Double? = nil, latest: Double? = nil) {
        self.today = today
        self.yesterday = yesterday
        self.mean = mean
        self.latest = latest
    }

    public static func make(_ days: [PlanDay: DayWeight], today: PlanDay, calendar: Calendar) -> WeightOverview {
        let values = days.mapValues(\.kilograms)
        let summary = WeightTrend.summary(days, today: today, targetKg: nil, calendar: calendar)
        return WeightOverview(today: values[today], yesterday: values[today.adding(days: -1, calendar: calendar)],
                              mean: summary.mean, latest: summary.latest?.kilograms)
    }
}
