import Foundation

/// The day template of the journal "Tagebuch mit Gott" (#182): three sections as plain text, like the guiding questions
/// of the thoughts note. After insertion the text belongs to the entry and is no longer translated.
public enum JournalTemplate {
    public enum Section: CaseIterable, Sendable {
        case mood, events, journal
    }

    /// Heading of a section in the language of `locale`.
    public static func heading(_ section: Section, locale: Locale) -> String {
        heading(section, language: VoiceLanguage.from(locale: locale))
    }

    static func heading(_ section: Section, language: VoiceLanguage) -> String {
        func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .module) }
        switch section {
        case .mood: return text("Allgemeine Stimmung")
        case .events: return text("Haupterlebnisse des heutigen Tages")
        case .journal: return text("Tagebuch")
        }
    }

    /// The guiding question under "Allgemeine Stimmung".
    public static func moodQuestion(locale: Locale) -> String {
        moodQuestion(language: VoiceLanguage.from(locale: locale))
    }

    static func moodQuestion(language: VoiceLanguage) -> String {
        Localized.string("Wie geht es mir im Moment grundsätzlich?", in: language, bundle: .module)
    }

    /// The template of a new entry: each heading followed by free lines to write into.
    public static func text(locale: Locale) -> String {
        text(language: VoiceLanguage.from(locale: locale))
    }

    static func text(language: VoiceLanguage) -> String {
        [heading(.mood, language: language) + "\n" + moodQuestion(language: language) + "\n\n",
         heading(.events, language: language) + "\n\n",
         heading(.journal, language: language) + "\n\n"].joined(separator: "\n")
    }

    /// Whether the text has nothing but the template: every line that is a heading or the question of the template (in any
    /// supported language, ignoring case, a trailing colon and surrounding space) is ignored, and nothing else is left.
    /// An empty text counts as untouched.
    public static func isOnlyTemplate(_ text: String) -> Bool {
        let known = knownLines
        return text.split(whereSeparator: \.isNewline).allSatisfy { line in
            let normalized = normalize(String(line))
            return normalized.isEmpty || known.contains(normalized)
        }
    }

    /// The lines of an entry without the template lines, joined, for a short preview.
    public static func contentLines(_ text: String) -> [String] {
        let known = knownLines
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !known.contains(normalize($0)) }
    }

    private static var knownLines: Set<String> {
        var lines = Set<String>()
        for language in [VoiceLanguage.german, .english] {
            lines.insert(normalize(moodQuestion(language: language)))
            for section in Section.allCases { lines.insert(normalize(heading(section, language: language))) }
        }
        return lines
    }

    static func normalize(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(":") { text.removeLast() }
        return SearchText.fold(text.trimmingCharacters(in: .whitespaces))
    }
}
