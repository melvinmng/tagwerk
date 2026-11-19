import Foundation

/// The guiding questions of the thoughts note (phase 7 design §7.7, #146): six questions inserted as plain text. After
/// that they are part of the note and are no longer translated.
public enum NoteTemplate {
    /// The six questions in the language of `locale`.
    public static func guidingQuestions(locale: Locale) -> [String] {
        let language = VoiceLanguage.from(locale: locale)
        func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .module) }
        return [text("Was war mein Ziel?"), text("Was hat geholfen?"), text("Was hat abgehalten?"),
                text("Erfahrungen mit anderen"), text("Meine eigene Rolle"), text("Nächste Schritte")]
    }

    /// The existing text, a blank line, then each question followed by a blank line. Trailing white space of the text is
    /// dropped first, so repeated insertion (after deleting the questions) does not pile up empty lines.
    public static func appendingGuidingQuestions(to text: String, locale: Locale) -> String {
        let block = guidingQuestions(locale: locale).map { $0 + "\n\n" }.joined()
        let existing = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return existing.isEmpty ? block : existing + "\n\n" + block
    }

    /// Whether the first question is already in the text; then the insert button is not offered.
    public static func containsGuidingQuestions(_ text: String, locale: Locale) -> Bool {
        guard let first = guidingQuestions(locale: locale).first else { return false }
        return text.contains(first)
    }
}
