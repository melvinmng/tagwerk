import Foundation

/// What kind of number a typed stepper field holds.
public enum NumberEntryKind: Sendable, Equatable {
    /// Whole numbers: rounds, kilocalories, millilitres, steps.
    case integer
    /// Numbers with decimals, for example a quantity factor or liters.
    case decimal(fractionDigits: Int)
    /// Minutes. Also reads "1,5 h", "1:30" and "1 h 30".
    case durationMinutes
}

/// Rules for numbers that are typed into a stepper field: reading, limiting to the range and rounding to the step.
/// No field accepts negative values.
public enum NumberEntry {
    private static let hourUnit = #"(?:h|std\.?|stunden?|hours?|hrs?)"#
    private static let minuteUnit = #"(?:m|min\.?|minuten?|minutes?)"#

    /// Reads the typed text; `nil` when it is empty or not a number of the given kind.
    public static func parse(_ text: String, kind: NumberEntryKind, locale: Locale) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        switch kind {
        case .integer:
            return parseInteger(trimmed, locale: locale)
        case .decimal:
            return parseDecimal(trimmed, locale: locale)
        case .durationMinutes:
            return parseDuration(trimmed, locale: locale)
        }
    }

    /// Limits the value to `range` and rounds it to the nearest step counted from `range.lowerBound`.
    public static func normalize(_ value: Double, range: ClosedRange<Double>, step: Double) -> Double {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        guard step > 0 else { return clamped }
        var steps = ((clamped - range.lowerBound) / step).rounded()
        var snapped = range.lowerBound + steps * step
        if snapped > range.upperBound {
            // The upper bound is not on the step grid: take the last step inside the range.
            steps = ((range.upperBound - range.lowerBound) / step).rounded(.down)
            snapped = range.lowerBound + steps * step
        }
        // Removes floating point drift such as 0.30000000000000004.
        return (snapped * 1_000_000).rounded() / 1_000_000
    }

    /// Whether `normalize` changed the typed value (for the "adjusted to …" hint).
    public static func wasAdjusted(_ raw: Double, normalized: Double) -> Bool {
        abs(raw - normalized) > 1e-9
    }

    /// Text for the input field without unit and without grouping separator, for example "2300" or "1,5".
    public static func editingText(_ value: Double, kind: NumberEntryKind, locale: Locale) -> String {
        let fractionDigits: Int
        switch kind {
        case .integer, .durationMinutes: fractionDigits = 0
        case .decimal(let digits): fractionDigits = max(0, digits)
        }
        return value.formatted(.number.grouping(.never).precision(.fractionLength(0...fractionDigits)).locale(locale))
    }

    // MARK: - Reading

    private static let allowedCharacters = CharacterSet(charactersIn: "0123456789.,")

    private static func isPlainNumber(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy(allowedCharacters.contains)
            && text.unicodeScalars.contains { $0.properties.numericType != nil }
    }

    /// Whole numbers: a grouping separator of the locale between groups of three digits is ignored ("2.300" in German).
    /// Anything else is read like a decimal number and rounded by `normalize` later.
    private static func parseInteger(_ text: String, locale: Locale) -> Double? {
        guard isPlainNumber(text) else { return nil }
        let grouping = locale.groupingSeparator ?? ","
        if grouping == "." || grouping == "," {
            let escaped = NSRegularExpression.escapedPattern(for: grouping)
            if text.range(of: "^[0-9]{1,3}(\(escaped)[0-9]{3})+$", options: .regularExpression) != nil {
                return Double(text.replacingOccurrences(of: grouping, with: ""))
            }
        }
        return parseDecimal(text, locale: locale)
    }

    /// Decimal numbers: one separator is the decimal mark (comma or point, whichever was typed).
    /// With both, the decimal separator of the locale must come last and exactly once.
    private static func parseDecimal(_ text: String, locale: Locale) -> Double? {
        guard isPlainNumber(text) else { return nil }
        let commas = text.filter { $0 == "," }.count
        let points = text.filter { $0 == "." }.count
        switch (commas, points) {
        case (0, 0), (1, 0), (0, 1):
            return Double(text.replacingOccurrences(of: ",", with: "."))
        case (_, _) where commas > 0 && points > 0:
            let decimalMark = locale.decimalSeparator == "," ? "," : "."
            let groupingMark = decimalMark == "," ? "." : ","
            let decimalCount = decimalMark == "," ? commas : points
            guard decimalCount == 1, let last = text.last(where: { $0 == "," || $0 == "." }), String(last) == decimalMark else { return nil }
            return Double(text.replacingOccurrences(of: groupingMark, with: "").replacingOccurrences(of: ",", with: "."))
        default:
            return nil
        }
    }

    /// Minutes: "90", "45 min", "1,5 h", "1:30", "1 h 30", "1h30min".
    private static func parseDuration(_ text: String, locale: Locale) -> Double? {
        if let match = text.wholeMatch(of: #/(\d{1,3}):(\d{1,2})/#) {
            guard let hours = Double(match.1), let minutes = Double(match.2), minutes < 60 else { return nil }
            return hours * 60 + minutes
        }
        if let match = try? Regex("(\\d+)\\s*\(hourUnit)\\s*(\\d+)\\s*(?:\(minuteUnit))?").wholeMatch(in: text),
           let hours = match.output[1].substring.flatMap({ Double($0) }),
           let minutes = match.output[2].substring.flatMap({ Double($0) }) {
            return hours * 60 + minutes
        }
        if let match = try? Regex("([0-9.,]+)\\s*\(hourUnit)").wholeMatch(in: text),
           let hours = match.output[1].substring.flatMap({ parseDecimal(String($0), locale: locale) }) {
            return hours * 60
        }
        if let match = try? Regex("([0-9.,]+)\\s*\(minuteUnit)").wholeMatch(in: text),
           let minutes = match.output[1].substring.flatMap({ parseInteger(String($0), locale: locale) }) {
            return minutes
        }
        return parseInteger(text, locale: locale)
    }
}
