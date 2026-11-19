import Foundation

/// One item recognized in typed or dictated text.
public struct ParsedItem: Sendable, Hashable {
    public var name: String
    public var quantity: String?

    public init(name: String, quantity: String?) {
        self.name = name
        self.quantity = quantity
    }
}

/// Splits free text such as "Kaffee, Reis und 2 Zwiebeln" into items with an optional quantity.
/// German and English separators, number words and units are recognized at the same time.
public enum ShoppingInputParser {
    public static let maxItems = 20
    public static let maxNameLength = 80

    public struct ParseResult: Sendable, Equatable {
        public var items: [ParsedItem]
        /// Items beyond `maxItems` that were recognized but left out.
        public var droppedCount: Int

        public init(items: [ParsedItem], droppedCount: Int) {
            self.items = items
            self.droppedCount = droppedCount
        }
    }

    private static let numberWords: [String: Int] = [
        "ein": 1, "eine": 1, "einen": 1, "eins": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "sechs": 6,
        "sieben": 7, "acht": 8, "neun": 9, "zehn": 10, "elf": 11, "zwölf": 12,
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12,
    ]

    private static let units: Set<String> = [
        "g", "kg", "ml", "l", "stück", "packung", "packungen", "dose", "dosen", "flasche", "flaschen", "glas",
        "becher", "bund", "tüte", "tüten", "kasten", "pack", "packs", "can", "cans", "bottle", "bottles", "bag", "bags",
    ]

    private static let conjunctions: Set<String> = ["und", "and"]

    public static func parse(_ text: String) -> [ParsedItem] {
        parseAll(text).items
    }

    public static func parseAll(_ text: String) -> ParseResult {
        let all = text
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .flatMap { splitAtConjunctions(String($0)) }
            .compactMap(item)
        return ParseResult(items: Array(all.prefix(maxItems)), droppedCount: max(0, all.count - maxItems))
    }

    /// Splits at "und" / "and" standing as a word of their own; a part that is only the conjunction is dropped.
    private static func splitAtConjunctions(_ part: String) -> [[Substring]] {
        part.split(whereSeparator: \.isWhitespace)
            .split(whereSeparator: { conjunctions.contains($0.lowercased()) })
            .map(Array.init)
    }

    private static func item(_ words: [Substring]) -> ParsedItem? {
        guard !words.isEmpty else { return nil }
        var nameWords = words
        var quantity: String?
        if words.count >= 2, let number = number(words[0]) {
            if units.contains(words[1].lowercased()) {
                // A number with a unit but without a name is not a quantity ("500 g" stays the name).
                if words.count >= 3 {
                    quantity = "\(number) \(words[1])"
                    nameWords = Array(words.dropFirst(2))
                }
            } else {
                quantity = number
                nameWords = Array(words.dropFirst())
            }
        }
        let joined = nameWords.joined(separator: " ")
        let name = String((joined.prefix(1).uppercased() + joined.dropFirst()).prefix(maxNameLength))
        return name.isEmpty ? nil : ParsedItem(name: name, quantity: quantity)
    }

    /// Digits stay as typed; number words from one to twelve become digits.
    private static func number(_ word: Substring) -> String? {
        if word.allSatisfy(\.isASCIIDigit) { return String(word) }
        return numberWords[word.lowercased()].map(String.init)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
