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

    private static func percent(_ value: Int, language: VoiceLanguage) -> String {
        (Double(value) / 100).formatted(.percent.precision(.fractionLength(0)).locale(language == .app ? .current : language.locale))
    }
}
