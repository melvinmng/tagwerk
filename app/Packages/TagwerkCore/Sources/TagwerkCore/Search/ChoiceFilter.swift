import Foundation

/// Filters the entries of a picker (repositories, projects) by what the user typed. The comparison is the one of the search:
/// case, accents and umlauts are ignored (`SearchText.fold`).
public enum ChoiceFilter {
    /// The items in which every word of `query` occurs in at least one of their texts. Items where every word starts a word
    /// (after "/", "-", a space or the start of the text) come first; the order of `items` is kept within both groups. A blank
    /// query returns all items unchanged.
    public static func matching<Item>(_ items: [Item], query: String, text: (Item) -> [String]) -> [Item] {
        let words = query.split(whereSeparator: \.isWhitespace).map { SearchText.fold(String($0)) }
        guard !words.isEmpty else { return items }
        var prefixHits: [Item] = []
        var otherHits: [Item] = []
        for item in items {
            let fields = text(item).map(SearchText.fold)
            guard words.allSatisfy({ word in fields.contains { $0.contains(word) } }) else { continue }
            let startsEveryWord = words.allSatisfy { word in fields.contains { startsAWord(word, in: $0) } }
            if startsEveryWord { prefixHits.append(item) } else { otherHits.append(item) }
        }
        return prefixHits + otherHits
    }

    private static func startsAWord(_ word: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: word, range: searchStart..<text.endIndex) {
            if range.lowerBound == text.startIndex { return true }
            let before = text[text.index(before: range.lowerBound)]
            if !before.isLetter && !before.isNumber { return true }
            searchStart = text.index(after: range.lowerBound)
        }
        return false
    }
}

/// The "Zuletzt verwendet" list of a picker: newest first, no duplicates.
public enum RecentChoices {
    /// Entries kept per list; more than `visibleLimit`, so entries that disappeared can be skipped without an empty list.
    public static let storedLimit = 5
    /// Entries shown above the full list.
    public static let visibleLimit = 3

    /// `recent` with `choice` moved to the front, cut to the `limit` newest. A blank choice changes nothing.
    public static func recorded(_ choice: String, in recent: [String], limit: Int) -> [String] {
        let trimmed = choice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return recent }
        return Array(([trimmed] + recent.filter { $0 != trimmed }).prefix(limit))
    }

    /// The entries of `recent` that are still `available` (a repository can disappear), at most `limit`, in the order of `recent`.
    public static func visible(_ recent: [String], available: [String], limit: Int) -> [String] {
        let known = Set(available)
        return Array(recent.filter(known.contains).prefix(limit))
    }
}
