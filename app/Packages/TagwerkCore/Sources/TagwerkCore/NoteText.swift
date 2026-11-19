import Foundation

<<<<<<< HEAD
/// Origin of a note: the user's own note, the thoughts captured at the start or the end of a day, the dream log of the
/// morning start, an entry of the journal "Tagebuch mit Gott", or a note of the Bible Study folder. An unknown stored
/// value reads as `.free`. The raw values are stored and written to backups: never rename, only append.
public enum NoteKind: String, Sendable, CaseIterable {
    case free, morning, evening, journal, bibleStudy
    /// One dated dream note per day, written in the morning routine ("Dream Log").
    case dream

    /// Private notes never leave the device: not to ChatGPT (not even with the consent for thought notes), not to the
    /// assistant's tools and not to the widget. The in-app search is local and may show them. Every place that sends or
    /// shares note content has to check this predicate. Whether a backup holds them is `isInDefaultBackup`.
    public var isPrivate: Bool {
        switch self {
        case .journal, .bibleStudy, .dream: true
        case .free, .morning, .evening: false
        }
    }

    /// Whether "Vorschläge holen" may send the note to ChatGPT: only the thought notes of the morning and the evening.
    public var allowsSuggestions: Bool {
        switch self {
        case .morning, .evening: true
        case .free, .journal, .bibleStudy, .dream: false
        }
    }

    /// Whether a backup holds notes of this kind without the switch "Tagebuch und Bible Study einschließen".
    /// Dreams are private like the gratitude entries (never sent anywhere), yet they belong to the daily routine
    /// and are restored with it, so they are backed up like the morning and evening notes.
    public var isInDefaultBackup: Bool {
        switch self {
        case .journal, .bibleStudy: false
        case .free, .morning, .evening, .dream: true
        }
    }
}

/// The day a thought note belongs to, stored as "YYYY-MM-DD".
public enum NoteDayKey {
    public static func string(_ day: PlanDay) -> String {
        String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
    }

    /// Parses exactly "YYYY-MM-DD"; anything else is `nil`.
    public static func day(_ key: String) -> PlanDay? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return PlanDay(year: year, month: month, day: day)
    }
}

/// A note has no title of its own: the title is its first line, the rest is the preview.
public enum NoteText {
    public static let maxTitleLength = 60

    /// The first non-empty line, trimmed and cut to `maxTitleLength` characters; empty for a note without text.
    public static func title(_ text: String) -> String {
        guard let line = lines(text).first(where: { !$0.isEmpty }) else { return "" }
        return String(line.prefix(maxTitleLength))
    }

    /// The non-empty lines after the title line.
    public static func preview(_ text: String) -> String {
        lines(text).filter { !$0.isEmpty }.dropFirst().joined(separator: "\n")
    }

    /// Whether every word of `query` occurs in `text`, ignoring case, accents and umlaut spelling like the global
    /// search does. An empty query matches everything.
    public static func matches(_ text: String, query: String) -> Bool {
        let words = SearchText.fold(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let folded = SearchText.fold(text)
        return words.allSatisfy { folded.contains($0) }
    }

    private static func lines(_ text: String) -> [String] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
