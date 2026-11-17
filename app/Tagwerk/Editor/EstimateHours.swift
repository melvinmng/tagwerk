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

/// Text and value of the effort field. Every keystroke updates the value at once, so saving
/// while the keyboard is open never loses input; steps and quick values rewrite the text.
struct EstimateInput: Equatable {
    private(set) var text: String
    private(set) var minutes: Int?

    init(minutes: Int?) {
        self.minutes = minutes
        self.text = minutes.map(EstimateHours.number) ?? ""
    }

    /// Typed text: empty or 0 means no effort, an unreadable entry keeps the last value.
    mutating func typed(_ newText: String) {
        text = newText
        let normalized = newText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        if normalized.isEmpty {
            minutes = nil
        } else if let hours = Double(normalized) {
            minutes = EstimateHours.minutes(fromHours: hours)
        }
    }

    mutating func step(_ direction: Int) {
        minutes = EstimateHours.stepped(minutes: minutes, by: direction)
        syncText()
    }

    mutating func choose(_ value: Int?) {
        minutes = value
        syncText()
    }

    /// Leaving the field shows the stored value in canonical form; the value itself stays.
    mutating func endEditing() {
        syncText()
    }

    private mutating func syncText() {
        text = minutes.map(EstimateHours.number) ?? ""
    }
}
