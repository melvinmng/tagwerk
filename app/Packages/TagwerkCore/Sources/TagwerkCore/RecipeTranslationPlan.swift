import Foundation

/// The line-based plan for translating a recipe note. The note is cut into lines; what is structure (the headings
/// "Zutaten" and "Zubereitung", the labels "Portionen" and "Quelle", blank lines, attachment references and bare addresses)
/// stays on the device and is written in the target language there. Only the translatable part of every other line goes
/// to ChatGPT, one entry per line. The answer is put back at the same place and checked: any difference in the lines, the
/// attachments, the links, the ingredient amounts or the recipe structure is a failure, never a text that is taken over.
///
/// `RecipeNote.parse` ignores everything outside the known sections, so translating through `RecipeNote` would lose the
/// user's own remarks and attachment references. Working on the original text line by line avoids that.
public struct RecipeTranslationPlan: Sendable, Equatable {
    /// One line of the note.
    public enum Segment: Sendable, Equatable {
        /// Stays as it is and is not sent: blank lines, attachment references, addresses, lines without letters.
        case fixed(String)
        /// The heading of the ingredients; the text is replaced by the heading of the target language.
        case ingredientsHeading(prefix: String)
        case stepsHeading(prefix: String)
        /// "Portionen: 4": the label is replaced, the value stays.
        case servings(value: String)
        /// "Quelle: …": the label is replaced, the value stays.
        case source(value: String)
        /// A line to translate. The prefix (indentation, hashes, bullet, check box, number) stays, the body is sent.
        case text(prefix: String, body: String, isIngredient: Bool)
    }

    /// Why an answer is not taken over.
    public enum Failure: Error, Equatable {
        /// The answer does not hold exactly the requested lines.
        case indexMismatch
        case emptyLine
        case lineBreak
        /// A line lost, gained or changed an attachment reference.
        case attachmentsChanged
        /// A line lost, gained or changed a link address.
        case linksChanged
        /// An ingredient line has other numbers than the original.
        case amountsChanged
        /// The translated note reads as another recipe: other sections, other number of ingredients or steps, other
        /// servings or other source.
        case structureChanged
        /// The original is no structured recipe.
        case notARecipe
    }

    /// At most this many lines are sent; a longer note is refused, never cut (a cut text would be lost on "replace").
    public static let maximumLines = 300
    /// At most this many characters are sent.
    public static let maximumCharacters = 12_000

    public let markdown: String
    public let segments: [Segment]
    private let lineBreak: String

    public init(markdown: String) {
        self.markdown = markdown
        lineBreak = markdown.contains("\r\n") ? "\r\n" : "\n"
        var result: [Segment] = []
        var inIngredients = false
        for raw in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw)
            result.append(Self.classify(line, inIngredients: inIngredients))
            // Like `RecipeNote.parse`, every heading ends the previous section.
            if let found = RecipeNote.heading(line.trimmingCharacters(in: .whitespaces)) {
                inIngredients = RecipeNote.sectionKind(ofHeading: found.text) == .ingredients
            }
        }
        segments = result
    }

    // MARK: Request

    /// The lines to translate, each with the index of its segment.
    public var request: [(index: Int, text: String)] {
        segments.enumerated().compactMap { index, segment in
            if case .text(_, let body, _) = segment { return (index, body) }
            return nil
        }
    }

    /// Whether the request stays within `maximumLines` and `maximumCharacters`.
    public var isWithinLimits: Bool {
        let lines = request
        return lines.count <= Self.maximumLines && lines.reduce(0) { $0 + $1.text.count } <= Self.maximumCharacters
    }

    // MARK: Assembling

    /// The note with the translated lines put back. `translations` is keyed by the indices of `request`. Checks, in this
    /// order: the same indices, no empty line and no line break, the same attachments and links per line, the same numbers
    /// in the ingredient lines, and the same recipe structure as the original. Blank lines, the line endings and a final
    /// line break of the original stay.
    public func assembled(translations: [Int: String], language: VoiceLanguage) throws(Failure) -> String {
        guard let original = RecipeNote.parse(markdown) else { throw .notARecipe }
        let requested = request
        guard Set(translations.keys) == Set(requested.map(\.index)) else { throw .indexMismatch }

        func label(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .module) }
        var lines: [String] = []
        for (index, segment) in segments.enumerated() {
            switch segment {
            case .fixed(let line):
                lines.append(line)
            case .ingredientsHeading(let prefix):
                lines.append(prefix + label("Zutaten"))
            case .stepsHeading(let prefix):
                lines.append(prefix + label("Zubereitung"))
            case .servings(let value):
                lines.append("\(label("Portionen")): \(value)")
            case .source(let value):
                lines.append("\(label("Quelle")): \(value)")
            case .text(let prefix, let body, let isIngredient):
                guard let answer = translations[index] else { throw .indexMismatch }
                let translated = answer.trimmingCharacters(in: .whitespaces)
                guard !translated.isEmpty else { throw .emptyLine }
                guard !translated.contains(where: \.isNewline) else { throw .lineBreak }
                guard MarkdownText.attachmentReferences(in: body) == MarkdownText.attachmentReferences(in: translated) else {
                    throw .attachmentsChanged
                }
                guard Self.linkTargets(in: body) == Self.linkTargets(in: translated) else { throw .linksChanged }
                if isIngredient, Self.numberTokens(in: body) != Self.numberTokens(in: translated) { throw .amountsChanged }
                lines.append(prefix + translated)
            }
        }
        let result = lines.joined(separator: lineBreak)
        guard let translated = RecipeNote.parse(result),
              RecipeNote.outline(result) == RecipeNote.outline(markdown),
              translated.ingredients.count == original.ingredients.count,
              translated.steps.count == original.steps.count,
              translated.servings == original.servings,
              translated.sourceURL == original.sourceURL else { throw .structureChanged }
        return result
    }

    // MARK: Classification

    private static func classify(_ raw: String, inIngredients: Bool) -> Segment {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .fixed(raw) }
        if let found = RecipeNote.heading(trimmed) {
            let leading = String(raw.prefix { $0 == " " || $0 == "\t" })
            let prefix = leading + String(repeating: "#", count: found.level) + " "
            switch RecipeNote.sectionKind(ofHeading: found.text) {
            case .ingredients: return .ingredientsHeading(prefix: prefix)
            case .steps: return .stepsHeading(prefix: prefix)
            case .other:
                return hasLetter(found.text) ? .text(prefix: prefix, body: found.text, isIngredient: false) : .fixed(raw)
            }
        }
        if let (label, value) = RecipeNote.labelled(trimmed) {
            if RecipeNote.servingsLabels.contains(label) { return .servings(value: value) }
            if RecipeNote.sourceLabels.contains(label) { return .source(value: value) }
        }
        let (prefix, body) = split(raw)
        if body.isEmpty || !hasLetter(body) || isAttachmentOnly(body) || isAddress(body) { return .fixed(raw) }
        return .text(prefix: prefix, body: body, isIngredient: inIngredients)
    }

    /// Indentation, quote marks, bullet, check box or number in front of the text of a line, and the text.
    private static func split(_ line: String) -> (prefix: String, body: String) {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = listPrefix.firstMatch(in: line, range: range), let prefixRange = Range(match.range, in: line) else {
            return ("", line.trimmingCharacters(in: .whitespaces))
        }
        return (String(line[prefixRange]), line[prefixRange.upperBound...].trimmingCharacters(in: .whitespaces))
    }

    private static func hasLetter(_ text: String) -> Bool { text.contains(where: \.isLetter) }

    /// Only references to attachments and white space: nothing to translate.
    private static func isAttachmentOnly(_ body: String) -> Bool {
        let range = NSRange(body.startIndex..., in: body)
        guard attachmentMarkup.firstMatch(in: body, range: range) != nil else { return false }
        let rest = attachmentMarkup.stringByReplacingMatches(in: body, range: range, withTemplate: "")
        return !rest.contains { $0.isLetter || $0.isNumber }
    }

    /// A bare web or mail address.
    private static func isAddress(_ body: String) -> Bool {
        guard !body.contains(where: \.isWhitespace), let url = URL(string: body), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }

    // MARK: Checks

    /// The link addresses of a line in order, each occurrence: the targets of Markdown links and images (attachment
    /// references included) and bare web addresses.
    static func linkTargets(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return linkExpression.matches(in: text, range: range).compactMap { match in
            for group in 1...2 {
                guard let found = Range(match.range(at: group), in: text) else { continue }
                var target = String(text[found])
                if group == 2 { while let last = target.last, ".,;:!?".contains(last) { target.removeLast() } }
                return target
            }
            return nil
        }
    }

    /// The numbers of a line in order: every run of digits is one number, and every other numeric character (½ ¼ ¾ ⅓ ⅔ …) is
    /// one too. A decimal separator splits a number into two runs, so "1.5" and "1,5" read the same; "½" and "1/2" do not.
    static func numberTokens(in text: String) -> [String] {
        var tokens: [String] = []
        var run = ""
        for character in text {
            if character.isASCII, character.isNumber {
                run.append(character)
                continue
            }
            if !run.isEmpty { tokens.append(run); run = "" }
            if character.isNumber { tokens.append(String(character)) }
        }
        if !run.isEmpty { tokens.append(run) }
        return tokens
    }

    // MARK: Expressions

    private static func make(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // The patterns are constants; a failure here is a programming error caught by the tests.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let listPrefix = make(#"^[ \t]*(?:>[ \t]*)*(?:[-*+•](?:[ \t]+|$)(?:\[[ xX]\][ \t]+)?|\d{1,3}[.)](?:[ \t]+|$))?"#)
    private static let attachmentMarkup = make(#"!?\[(?:\\.|[^\]\\])*\]\(\s*attachment:[^)\s]*\s*\)"#, .caseInsensitive)
    private static let linkExpression = make(#"\]\(\s*<?([^)\s>]+)|(?<![(\w"=])(https?://[^\s)\]>"]+)"#, .caseInsensitive)
}
