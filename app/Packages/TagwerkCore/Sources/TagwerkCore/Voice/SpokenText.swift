import Foundation

/// Turns assistant answers into text that a speech synthesizer can read, and splits it into sentences.
public enum SpokenText {
    // MARK: Preparation

    /// Removes Markdown, emoji and decorative symbols, spells out priority tokens and time ranges,
    /// and collapses whitespace. Single times such as "16:00" are kept unchanged.
    public static func prepare(_ text: String, language: VoiceLanguage) -> String {
        var result = text
        result = replacing(#"\[([^\]\n]*)\]\([^)\n]*\)"#, in: result, with: "$1")
        result = replacing(#"(?m)^[ \t]*#{1,6}[ \t]+"#, in: result, with: "")
        result = replacing(#"(?m)^[ \t]*(?:[-*]|\d+\.)[ \t]+"#, in: result, with: "")
        for marker in ["**", "__", "`"] {
            result = result.replacingOccurrences(of: marker, with: "")
        }
        result = replaceDecorativeScalars(in: result)
        result = replacing(#"(\d{1,2}:\d{2})\s*[–—-]\s*(\d{1,2}:\d{2})"#, in: result, with: "$1 \(rangeConnector(language)) $2")
        for (digit, word) in priorityWords(language).enumerated() {
            result = replacing("\\bP\(digit + 1)\\b", in: result, with: word)
        }
        result = replacing(#"\s+"#, in: result, with: " ")
        result = replacing(#" ([.,!?;:])"#, in: result, with: "$1")
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func rangeConnector(_ language: VoiceLanguage) -> String {
        switch language {
        case .german: "bis"
        case .english: "to"
        }
    }

    private static func priorityWords(_ language: VoiceLanguage) -> [String] {
        switch language {
        case .german: ["Priorität eins", "Priorität zwei", "Priorität drei", "Priorität vier"]
        case .english: ["priority one", "priority two", "priority three", "priority four"]
        }
    }

    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }

    /// Symbols that carry no spoken meaning in this app.
    private static let decorativeSymbols: Set<Unicode.Scalar> = ["✦", "⚑", "✓", "✕", "→"]

    /// Smallest scalar value from which `isEmoji` is not satisfied by plain digits, "#", "*" or "©" / "®".
    private static let firstSymbolEmojiValue: UInt32 = 0x203C

    private static func replaceDecorativeScalars(in text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            scalars.append(isRemovable(scalar) ? " " : scalar)
        }
        return String(scalars)
    }

    private static func isRemovable(_ scalar: Unicode.Scalar) -> Bool {
        if decorativeSymbols.contains(scalar) { return true }
        switch scalar.value {
        case 0x200D, 0xFE0F, 0x20E3, 0xE0020...0xE007F: return true
        default: break
        }
        let properties = scalar.properties
        return properties.isEmojiPresentation || (properties.isEmoji && scalar.value >= firstSymbolEmojiValue)
    }

    // MARK: Sentences

    /// Splits prepared text on ".", "!" and "?" followed by whitespace or the end of the text.
    /// Decimals, ordinal dates and common abbreviations do not end a sentence.
    public static func sentences(_ text: String) -> [String] {
        let characters = Array(text)
        var result: [String] = []
        var sentenceStart = 0

        for index in characters.indices where isSentenceTerminator(at: index, in: characters) {
            result.append(String(characters[sentenceStart...index]))
            sentenceStart = index + 1
        }
        if sentenceStart < characters.count {
            result.append(String(characters[sentenceStart...]))
        }
        return result
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isSentenceTerminator(at index: Int, in characters: [Character]) -> Bool {
        let character = characters[index]
        guard character == "." || character == "!" || character == "?" else { return false }
        if index + 1 < characters.count, !characters[index + 1].isWhitespace { return false }
        if character == ".", isNonTerminatingPeriod(at: index, in: characters) { return false }
        return true
    }

    // MARK: Abbreviations and ordinals

    private static let abbreviations: Set<String> = [
        "ca.", "bzw.", "usw.", "etc.", "evtl.", "ggf.", "inkl.", "vgl.", "nr.", "tel.", "max.", "min.", "std.",
        "e.g.", "i.e.", "vs.", "dr.", "prof.", "mr.", "mrs.", "ms.", "no.",
        "mo.", "di.", "mi.", "do.", "fr.", "sa.", "mon.", "tue.", "wed.", "thu.", "fri.", "sat.", "sun.",
        "jan.", "feb.", "mär.", "apr.", "jun.", "jul.", "aug.", "sep.", "sept.", "okt.", "oct.", "nov.", "dez.", "dec."
    ]

    private static let monthNames: Set<String> = [
        "januar", "jan", "februar", "feb", "märz", "mär", "april", "apr", "mai", "juni", "jun", "juli", "jul",
        "august", "aug", "september", "sep", "sept", "oktober", "okt", "november", "nov", "dezember", "dez",
        "january", "february", "march", "mar", "may", "june", "july", "october", "oct", "december", "dec"
    ]

    private static func isNonTerminatingPeriod(at index: Int, in characters: [Character]) -> Bool {
        let token = token(endingAt: index, in: characters)
        if abbreviations.contains(token.lowercased()) { return true }
        if isOrdinalNumber(token), let next = nextWord(after: index, in: characters) {
            let lowered = next.lowercased()
            if let first = lowered.first, first.isLowercase { return true }
            if monthNames.contains(trimmedTrailingPunctuation(lowered)) { return true }
        }
        if isSingleLetterAbbreviation(token) {
            if let previous = previousToken(before: index, in: characters), isSingleLetterAbbreviation(previous) { return true }
            if let next = nextWord(after: index, in: characters), isSingleLetterAbbreviation(next) { return true }
        }
        return false
    }

    /// The whitespace-delimited token that ends at `index`, without leading punctuation such as quotes or brackets.
    private static func token(endingAt index: Int, in characters: [Character]) -> String {
        var start = index
        while start > 0, !characters[start - 1].isWhitespace { start -= 1 }
        let slice = characters[start...index].drop { !$0.isLetter && !$0.isNumber }
        return String(slice)
    }

    private static func previousToken(before index: Int, in characters: [Character]) -> String? {
        var end = index
        while end > 0, !characters[end - 1].isWhitespace { end -= 1 }
        while end > 0, characters[end - 1].isWhitespace { end -= 1 }
        guard end > 0 else { return nil }
        return token(endingAt: end - 1, in: characters)
    }

    private static func nextWord(after index: Int, in characters: [Character]) -> String? {
        var start = index + 1
        while start < characters.count, characters[start].isWhitespace { start += 1 }
        guard start < characters.count else { return nil }
        var end = start
        while end < characters.count, !characters[end].isWhitespace { end += 1 }
        return String(characters[start..<end])
    }

    private static func isOrdinalNumber(_ token: String) -> Bool {
        guard token.hasSuffix(".") else { return false }
        let digits = token.dropLast()
        return (1...2).contains(digits.count) && digits.allSatisfy(\.isNumber)
    }

    private static func isSingleLetterAbbreviation(_ token: String) -> Bool {
        let characters = Array(token)
        return characters.count == 2 && characters[0].isLetter && characters[1] == "."
    }

    private static func trimmedTrailingPunctuation(_ word: String) -> String {
        String(word.reversed().drop { !$0.isLetter }.reversed())
    }
}
