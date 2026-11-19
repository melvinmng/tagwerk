import Foundation

/// The guiding questions of the thoughts note (phase 7 design §7.7, #146): eight questions inserted as plain text. After
/// that they are part of the note and are no longer translated.
public enum NoteTemplate {
    /// The first questions of the former six-question template. Fixed strings, not localized: notes written before the
    /// eight questions of the original reflection template still start with one of them, and must not be offered the
    /// questions again.
    public static let legacyFirstQuestions = ["Was war mein Ziel?", "What was my goal?"]

    /// The eight questions in the language of `locale`. They follow the wording of the original reflection template;
    /// only two obvious typos are corrected.
    public static func guidingQuestions(locale: Locale) -> [String] {
        let language = VoiceLanguage.from(locale: locale)
        func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .module) }
        return [text("Was will ich in meinem Leben (im Moment) erreichen?"),
                text("Was habe ich gemacht, um zu erreichen, was ich will?"),
                text("Was habe ich gemacht, das mich davon abgehalten hat, zu erreichen, was ich will?"),
                text("Was für Erfahrungen habe ich in letzter Zeit mit anderen Menschen gemacht? (positive und negative)"),
                text("Was bedrückt mich sonst grade?"),
                text("Wie habe ich gehandelt und was für Gedanken habe ich mir gemacht, die diese Erfahrungen schlimmer gemacht haben, als nötig?"),
                text("Was für eine Rolle spiele ich in den negativen Dingen, die passiert sind? Kann ich Eigenverantwortung übernehmen?"),
                text("Was kann ich machen, um die negativen Dinge in meinem Leben aktiv zu verbessern?")]
    }

    /// The existing text, a blank line, then each question followed by a blank line. Trailing white space of the text is
    /// dropped first, so repeated insertion (after deleting the questions) does not pile up empty lines.
    public static func appendingGuidingQuestions(to text: String, locale: Locale) -> String {
        let block = guidingQuestions(locale: locale).map { $0 + "\n\n" }.joined()
        let existing = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return existing.isEmpty ? block : existing + "\n\n" + block
    }

    /// Whether the first question (or one of the legacy first questions) is already in the text; then the insert button
    /// is not offered.
    public static func containsGuidingQuestions(_ text: String, locale: Locale) -> Bool {
        guard let first = guidingQuestions(locale: locale).first else { return false }
        return text.contains(first) || legacyFirstQuestions.contains { text.contains($0) }
    }
}
