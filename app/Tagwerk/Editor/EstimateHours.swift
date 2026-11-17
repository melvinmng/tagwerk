import Foundation

/// Effort shown and entered in hours (quarter-hour steps, 0,25–24 h), stored as minutes.
enum EstimateHours {
    static let stepMinutes = 15
    static let maxMinutes = 24 * 60
    static let quickValues: [Double] = [0.25, 0.5, 1, 2, 4]

    /// "0,75 h", "1 h", "1,5 h"; "–" without effort.
    static func text(minutes: Int?) -> String {
        guard let minutes else { return "–" }
        return "\(number(minutes)) h"
    }

    /// Hours as a number without unit, German decimal comma.
    static func number(_ minutes: Int) -> String {
        (Double(minutes) / 60).formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "de_DE")))
    }

    /// Rounds typed hours to the nearest quarter hour within 0,25–24 h; 0 or nothing means no effort.
    static func minutes(fromHours hours: Double?) -> Int? {
        guard let hours, hours > 0 else { return nil }
        let quarters = max(1, Int((hours * 4).rounded()))
        return min(quarters * stepMinutes, maxMinutes)
    }

    /// One quarter hour up (`direction` 1) or down (-1); below 0,25 h means no effort.
    static func stepped(minutes: Int?, by direction: Int) -> Int? {
        let next = (minutes ?? 0) + direction * stepMinutes
        guard next > 0 else { return nil }
        return min(next, maxMinutes)
    }
}
