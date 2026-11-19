import Foundation

/// Origin of a note: the user's own note, or the thoughts captured at the start or the end of a day.
public enum NoteKind: String, Sendable, CaseIterable {
    case free, morning, evening
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
