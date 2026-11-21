import Foundation
import TagwerkCore

/// Texts of the weekly review section "Schätzung und Ist". Pure, so they can be tested in both languages.
enum EffortReviewText {
    /// Deviations up to this many percent count as "as estimated".
    static let tolerancePercent = 5

    /// Name of a group: the source or the label.
    static func name(of kind: EffortGroupKind, language: VoiceLanguage = .app) -> String {
        switch kind {
        case .label(let label): return label
        case .source(let source):
            switch source {
            case .reminders: return Localized.string("Erinnerungen", in: language, bundle: .main)
            case .github: return Localized.string("GitHub-Issues", in: language, bundle: .main)
            case .local: return Localized.string("Lokale Aufgaben", in: language, bundle: .main)
            }
        }
    }

    /// "Dauern im Schnitt 40 % länger als geschätzt", or "Noch zu wenige Messungen." below three samples.
    static func detail(of group: EffortGroup, language: VoiceLanguage = .app) -> String {
        func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .main) }
        guard let deviation = group.deviationPercent else { return text("Noch zu wenige Messungen.") }
        if abs(deviation) <= tolerancePercent { return text("Dauern etwa so lange wie geschätzt") }
        let amount = percent(abs(deviation), language: language)
        return deviation > 0 ? text("Dauern im Schnitt \(amount) länger als geschätzt")
                             : text("Dauern im Schnitt \(amount) kürzer als geschätzt")
    }

    /// "7 Aufgaben" (singular for one).
    static func count(_ number: Int, language: VoiceLanguage = .app) -> String {
        Localized.string("\(number) Aufgaben", in: language, bundle: .main)
    }

    /// Scale of the bars: −50 % … +100 %, with "wie geschätzt" at a third of the width.
    static let scale = -50...100

    /// Position of a deviation on the scale, 0...1, clamped; 1/3 is "as estimated".
    static func position(deviationPercent: Int) -> Double {
        let clamped = min(max(deviationPercent, scale.lowerBound), scale.upperBound)
        return Double(clamped - scale.lowerBound) / Double(scale.upperBound - scale.lowerBound)
    }

    /// "+40 %", "±0 %" (within the tolerance), "−15 %" (with the minus sign).
    static func deviationLabel(_ percent: Int, language: VoiceLanguage = .app) -> String {
        if abs(percent) <= tolerancePercent { return "±\(Self.percent(0, language: language))" }
        return (percent > 0 ? "+" : "−") + Self.percent(abs(percent), language: language)
    }

    /// "2 von 3 Messungen" for a group below the minimum.
    static func pendingLabel(count: Int, language: VoiceLanguage = .app) -> String {
        Localized.string("\(count) von \(EffortStats.minimumSamples) Messungen", in: language, bundle: .main)
    }

    private static func percent(_ value: Int, language: VoiceLanguage) -> String {
        (Double(value) / 100).formatted(.percent.precision(.fractionLength(0)).locale(language == .app ? .current : language.locale))
    }
}
