import Foundation

/// Text normalization for the search: comparison ignores case, accents, umlauts and character width.
public enum SearchText {
    /// Case-, diacritic- and width-insensitive form; "ß" becomes "ss". "ue" stays "ue".
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "ß", with: "ss")
    }

    /// Ranges of `foldedWord` in `text`, expressed in indices of the original `text`.
    ///
    /// Folding can change the length ("ß" becomes "ss"), so every folded character remembers the original
    /// character it came from. A hit that ends inside such an expansion covers the whole original character.
    public static func ranges(of foldedWord: String, in text: String) -> [Range<String.Index>] {
        let word = Array(foldedWord)
        guard !word.isEmpty else { return [] }
        var folded: [Character] = []
        var origins: [String.Index] = []
        for index in text.indices {
            for character in foldCharacter(text[index]) {
                folded.append(character)
                origins.append(index)
            }
        }
        guard folded.count >= word.count else { return [] }
        var ranges: [Range<String.Index>] = []
        var position = 0
        while position + word.count <= folded.count {
            if folded[position] == word[0], folded[position..<(position + word.count)].elementsEqual(word) {
                let lower = origins[position]
                let upper = text.index(after: origins[position + word.count - 1])
                if let last = ranges.last, last.upperBound > lower {
                    ranges[ranges.count - 1] = last.lowerBound..<max(last.upperBound, upper)
                } else {
                    ranges.append(lower..<upper)
                }
                position += word.count
            } else {
                position += 1
            }
        }
        return ranges
    }

    /// Sorted ranges without overlaps; touching or overlapping ranges become one.
    static func merged(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, last.upperBound >= range.lowerBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    private static func foldCharacter(_ character: Character) -> String {
        if character.isASCII { return character.lowercased() }
        return fold(String(character))
    }
}
