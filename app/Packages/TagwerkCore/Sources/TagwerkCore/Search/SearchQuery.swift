import Foundation

/// Result of matching a query against a document.
public struct SearchMatch: Sendable, Equatable {
    /// Ranges in the document's title to highlight.
    public let titleRanges: [Range<String.Index>]
    /// Excerpt of the first matching field; only when no word hits the title.
    public let snippet: Snippet?
    /// Fields any word was found in, in `SearchField` declaration order.
    public let matchedFields: [SearchField]

    public struct Snippet: Sendable, Equatable {
        public let field: SearchField
        public let text: String
        public let ranges: [Range<String.Index>]
    }
}

/// A search text split into words. Every word must occur in at least one field (AND over words, OR over fields).
public struct SearchQuery: Sendable, Equatable {
    public static let minimumLength = 2
    static let snippetLength = 80

    enum Word: Sendable, Equatable {
        /// "#42": matches only an issue with exactly this number.
        case number(Int)
        /// "42": matches an issue with exactly this number or any occurrence in the text.
        case digits(Int?, String)
        case text(String)

        var folded: String? {
            switch self {
            case .number: nil
            case .digits(_, let text), .text(let text): text
            }
        }
    }

    /// Search text without surrounding whitespace.
    public let text: String
    let words: [Word]

    /// `nil` below two characters after trimming.
    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumLength else { return nil }
        text = trimmed
        words = trimmed.split(whereSeparator: \.isWhitespace).map { Self.word(String($0)) }
    }

    private static func word(_ raw: String) -> Word {
        let isDigits: (Substring) -> Bool = { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
        if raw.hasPrefix("#"), isDigits(raw.dropFirst()), let number = Int(raw.dropFirst()) {
            return .number(number)
        }
        if isDigits(Substring(raw)) {
            return .digits(Int(raw), raw)
        }
        return .text(SearchText.fold(raw))
    }

    public func match(_ document: SearchDocument) -> SearchMatch? {
        var matched: Set<SearchField> = []
        for word in words {
            var found = false
            switch word {
            case .number(let number):
                found = document.issueNumber == number
                if found { matched.insert(.issueNumber) }
            case .digits(let number, let text):
                if let number, document.issueNumber == number {
                    matched.insert(.issueNumber)
                    found = true
                }
                for entry in document.entries where entry.folded.contains(text) {
                    matched.insert(entry.field)
                    found = true
                }
            case .text(let text):
                for entry in document.entries where entry.folded.contains(text) {
                    matched.insert(entry.field)
                    found = true
                }
            }
            guard found else { return nil }
        }
        let fields = SearchField.allCases.filter(matched.contains)
        let titleRanges = matched.contains(.title) ? ranges(in: document.title) : []
        let snippet = matched.contains(.title) ? nil : snippet(of: document, fields: fields)
        return SearchMatch(titleRanges: titleRanges, snippet: snippet, matchedFields: fields)
    }

    /// Highlight ranges of all words in any text, for rows that show more than the title.
    public func ranges(in text: String) -> [Range<String.Index>] {
        SearchText.merged(words.compactMap(\.folded).flatMap { SearchText.ranges(of: $0, in: text) })
    }

    private func snippet(of document: SearchDocument, fields: [SearchField]) -> SearchMatch.Snippet? {
        guard let field = fields.first(where: { $0 != .issueNumber }) else { return nil }
        for entry in document.entries where entry.field == field {
            let flat = entry.text.replacingOccurrences(of: "\n", with: " ")
            guard let first = ranges(in: flat).first else { continue }
            let excerpt = Self.excerpt(of: flat, around: first)
            return SearchMatch.Snippet(field: field, text: excerpt, ranges: ranges(in: excerpt))
        }
        return nil
    }

    /// At most `snippetLength` characters around the hit, with "…" where text was cut.
    private static func excerpt(of text: String, around hit: Range<String.Index>) -> String {
        guard text.count > snippetLength else { return text }
        let budget = snippetLength - 2
        let offset = text.distance(from: text.startIndex, to: hit.lowerBound)
        let lead = min(offset, 24)
        let start = text.index(hit.lowerBound, offsetBy: -lead)
        let end = text.index(start, offsetBy: budget, limitedBy: text.endIndex) ?? text.endIndex
        var result = String(text[start..<end]).trimmingCharacters(in: .whitespaces)
        if start > text.startIndex { result = "…" + result }
        if end < text.endIndex { result += "…" }
        return result
    }
}
