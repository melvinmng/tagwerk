import Foundation
import NaturalLanguage

/// Languages supported by dictation and read-aloud.
public enum VoiceLanguage: String, CaseIterable, Sendable {
    case german = "de-DE"
    case english = "en-US"

    /// Minimum number of words required before language detection is attempted.
    private static let minimumWordCount = 3
    /// Minimum recognizer confidence required to trust a detection result.
    private static let minimumConfidence = 0.6

    public var locale: Locale { Locale(identifier: rawValue) }

    public var shortName: String {
        switch self {
        case .german: "DE"
        case .english: "EN"
        }
    }

    /// Maps any locale to a supported language: English stays English, everything else falls back to German.
    public static func from(locale: Locale) -> VoiceLanguage {
        locale.language.languageCode?.identifier == "en" ? .english : .german
    }

    /// Detects German or English in `text`; returns `fallback` for short or ambiguous text.
    public static func detect(_ text: String, fallback: VoiceLanguage) -> VoiceLanguage {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        guard wordCount >= minimumWordCount else { return fallback }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.german, .english]
        recognizer.processString(text)

        guard let best = recognizer.languageHypotheses(withMaximum: 1).first,
              best.value >= minimumConfidence
        else { return fallback }

        switch best.key {
        case .german: return .german
        case .english: return .english
        default: return fallback
        }
    }
}
