import Foundation

/// A chapter and verse inside one book ("3,21").
public struct BibleReference: Sendable, Hashable, Comparable {
    public var chapter: Int
    public var verse: Int

    public init(chapter: Int, verse: Int) {
        self.chapter = chapter
        self.verse = verse
    }

    public static func < (lhs: BibleReference, rhs: BibleReference) -> Bool {
        (lhs.chapter, lhs.verse) < (rhs.chapter, rhs.verse)
    }

    /// "3,21", the German way of writing a reference.
    public var text: String { "\(chapter),\(verse)" }
}

/// A passage of one book as numbers: where it starts and, once known, where it ends (BV2b).
public struct BiblePassage: Sendable, Hashable {
    public var start: BibleReference
    /// `nil` while the end is open (BV2b).
    public var end: BibleReference?

    public init(start: BibleReference, end: BibleReference? = nil) {
        self.start = start
        self.end = end
    }

    /// "3,21–31", "3,21–4,9", "3,21–" (open end). A passage that ends where it starts reads "3,21"; the stored numbers,
    /// not this text, tell the two cases apart.
    public func text() -> String {
        guard let end else { return start.text + "–" }
        if end == start { return start.text }
        return start.chapter == end.chapter ? "\(start.text)–\(end.verse)" : "\(start.text)–\(end.text)"
    }

    /// Whether the passage lies inside the verse table of `book` and does not end before it starts.
    public func isValid(in book: Int) -> Bool {
        guard BibleVerseCounts.isValid(book: book, chapter: start.chapter, verse: start.verse) else { return false }
        guard let end else { return true }
        return BibleVerseCounts.isValid(book: book, chapter: end.chapter, verse: end.verse) && end >= start
    }

    /// Reads "3,21-31", "3,21–4,9", "3,21", "3,21–" and "3, 21 - 31"; anything else is `nil`, because free text stays
    /// free text. A passage without a dash has no end (the verse is where reading starts). The text does not name a
    /// book, so whether the numbers exist is checked with `isValid(in:)`.
    public static func parse(_ text: String) -> BiblePassage? {
        let dashes: Set<Character> = ["-", "–", "—", "‑"]
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(omittingEmptySubsequences: false) { dashes.contains($0) }
        guard parts.count <= 2, let first = parts.first, let start = reference(String(first), defaultChapter: nil) else { return nil }
        guard parts.count == 2 else { return BiblePassage(start: start) }
        let rest = String(parts[1]).trimmingCharacters(in: .whitespaces)
        if rest.isEmpty { return BiblePassage(start: start) }
        guard let end = reference(rest, defaultChapter: start.chapter), end >= start else { return nil }
        return BiblePassage(start: start, end: end)
    }

    /// "3,21" or, with a default chapter, a bare verse "31". Positive numbers of at most three digits only.
    private static func reference(_ text: String, defaultChapter: Int?) -> BibleReference? {
        let pieces = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let numbers = pieces.map { piece -> Int? in
            guard !piece.isEmpty, piece.count <= 3, piece.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(piece)
        }
        switch numbers.count {
        case 2:
            guard let chapter = numbers[0], let verse = numbers[1], chapter >= 1, verse >= 1 else { return nil }
            return BibleReference(chapter: chapter, verse: verse)
        case 1:
            guard let defaultChapter, let verse = numbers[0], verse >= 1 else { return nil }
            return BibleReference(chapter: defaultChapter, verse: verse)
        default:
            return nil
        }
    }
}

/// What to read next in a book, derived from the sessions already held (BS2b, BV2b, BV3a).
public enum BibleProgress {
    public enum Next: Sendable, Equatable {
        /// The next verse, or 1,1 for a first session.
        case start(BibleReference)
        /// The last session ended on the last verse of the book.
        case bookFinished(last: BibleReference)
    }

    /// The verse after `end` in the book: the next verse, the first verse of the next chapter, or `bookFinished`. An
    /// `end` outside the table counts as the nearest verse inside it. An unknown book starts at 1,1.
    public static func next(after end: BibleReference, book: Int) -> Next {
        let chapters = BibleVerseCounts.chapterCount(book: book)
        guard chapters > 0 else { return .start(BibleReference(chapter: 1, verse: 1)) }
        let chapter = min(max(end.chapter, 1), chapters)
        let verses = BibleVerseCounts.verseCount(book: book, chapter: chapter)
        // A chapter behind the book is the end of the book, whatever the verse says.
        let verse = end.chapter > chapters ? verses : min(max(end.verse, 1), verses)
        if verse < verses { return .start(BibleReference(chapter: chapter, verse: verse + 1)) }
        if chapter < chapters { return .start(BibleReference(chapter: chapter + 1, verse: 1)) }
        return .bookFinished(last: BibleReference(chapter: chapter, verse: verse))
    }

    /// The suggestion for a new session from the latest session of the book: after its end, or "Weiter ab" its start while
    /// it has no end. Without any session, and for a start outside the table, it is 1,1.
    public static func suggestion(lastStart: BibleReference?, lastEnd: BibleReference?, book: Int) -> Next {
        if let lastEnd { return next(after: lastEnd, book: book) }
        if let lastStart, BibleVerseCounts.isValid(book: book, chapter: lastStart.chapter, verse: lastStart.verse) {
            return .start(lastStart)
        }
        return .start(BibleReference(chapter: 1, verse: 1))
    }

    /// The end offered when a session is completed: the chosen end, else the end of the start chapter. A chosen end before
    /// the start is ignored; a start in an unknown chapter ends where it starts.
    public static func defaultEnd(start: BibleReference, chosenEnd: BibleReference?, book: Int) -> BibleReference {
        if let chosenEnd, chosenEnd >= start { return chosenEnd }
        let verses = BibleVerseCounts.verseCount(book: book, chapter: start.chapter)
        return verses > 0 ? BibleReference(chapter: start.chapter, verse: max(verses, start.verse)) : start
    }
}
