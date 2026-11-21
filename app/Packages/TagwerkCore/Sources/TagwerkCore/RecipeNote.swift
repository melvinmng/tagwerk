import Foundation

/// A recipe as it is kept in a note of the folder "Rezepte": Markdown with a title, "Portionen", the section "Zutaten"
/// and the section "Zubereitung". Reading is line based and tolerant (German and English headings, bullets or numbers);
/// writing always produces the same layout in the language of the app.
///
///     # Linsencurry
///
///     Portionen: 4
///
///     ## Zutaten
///     - 250 g rote Linsen
///
///     ## Zubereitung
///     1. Zwiebeln würfeln.
///
///     Quelle: [chefkoch.de](https://www.chefkoch.de/…)
public struct RecipeNote: Sendable, Hashable {
    public var title: String
    /// The number of servings the amounts are written for; `nil` when the note names none.
    public var servings: Int?
    /// The raw ingredient lines without bullet or number ("250 g rote Linsen").
    public var ingredients: [String]
    public var steps: [String]
    /// The page the recipe was imported from; only a link import has one.
    public var sourceURL: URL?

    public init(title: String, servings: Int? = nil, ingredients: [String], steps: [String] = [], sourceURL: URL? = nil) {
        self.title = title
        self.servings = servings
        self.ingredients = ingredients
        self.steps = steps
        self.sourceURL = sourceURL
    }

    // MARK: Headings

    private static let ingredientHeadings: Set<String> = ["zutaten", "ingredients"]
    private static let stepHeadings: Set<String> = ["zubereitung", "anleitung", "instructions", "directions"]
    static let servingsLabels: Set<String> = ["portionen", "servings", "personen"]
    static let sourceLabels: Set<String> = ["quelle", "source"]

    private enum Section { case none, ingredients, steps, other }

    /// What a heading introduces: the ingredients, the steps or anything else.
    public enum SectionKind: Sendable, Equatable { case ingredients, steps, other }

    /// The kind of a section from the text of its heading, without hashes. Shared by `parse`, `outline` and the translation.
    static func sectionKind(ofHeading text: String) -> SectionKind {
        let name = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        if ingredientHeadings.contains(name) { return .ingredients }
        if stepHeadings.contains(name) { return .steps }
        return .other
    }

    // MARK: Reading

    /// Reads a note. `nil` when it is not a structured recipe: there has to be a section "Zutaten" ("Ingredients") with at
    /// least one line. The servings may be missing. Text outside the known sections is ignored.
    public static func parse(_ markdown: String) -> RecipeNote? {
        var headingTitle: String?
        var firstLine: String?
        var servings: Int?
        var sourceURL: URL?
        var ingredients: [String] = []
        var steps: [String] = []
        var section = Section.none
        for raw in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let found = heading(line) {
                if found.level == 1, headingTitle == nil { headingTitle = found.text }
                switch sectionKind(ofHeading: found.text) {
                case .ingredients: section = .ingredients
                case .steps: section = .steps
                case .other: section = .other
                }
                continue
            }
            if let (label, value) = labelled(line) {
                if servingsLabels.contains(label) {
                    if servings == nil { servings = firstNumber(in: value) }
                    continue
                }
                if sourceLabels.contains(label) {
                    if sourceURL == nil { sourceURL = link(in: value) }
                    continue
                }
            }
            switch section {
            case .none: if firstLine == nil { firstLine = line }
            case .ingredients: ingredients.append(listItem(line))
            case .steps: steps.append(listItem(line))
            case .other: break
            }
        }
        ingredients = ingredients.filter { !$0.isEmpty }
        steps = steps.filter { !$0.isEmpty }
        guard !ingredients.isEmpty else { return nil }
        // Without a "# " heading the title is the first line, as in `NoteText.title`.
        let title = headingTitle ?? firstLine.map { listItem($0) } ?? ""
        return RecipeNote(title: title, servings: servings, ingredients: ingredients, steps: steps, sourceURL: sourceURL)
    }

    /// A Markdown heading: its level and its text without the hashes.
    static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " || rest.isEmpty else { return nil }
        return (hashes.count, rest.trimmingCharacters(in: .whitespaces))
    }

    /// "Portionen: 4" → ("portionen", "4"); `nil` without a colon or when the label is longer than three words.
    static func labelled(_ line: String) -> (label: String, value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let label = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        guard !label.isEmpty, label.split(separator: " ").count <= 3 else { return nil }
        return (label, line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
    }

    private static func firstNumber(in text: String) -> Int? {
        let digits = text.drop { !$0.isNumber }.prefix { $0.isNumber }
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }

    /// The address of "[chefkoch.de](https://…)" or of a bare address.
    private static func link(in text: String) -> URL? {
        if let open = text.range(of: "]("), let close = text[open.upperBound...].firstIndex(of: ")") {
            return URL(string: String(text[open.upperBound..<close]))
        }
        guard !text.contains(where: \.isWhitespace) else { return nil }
        return URL(string: text)
    }

    /// The line without its bullet ("- ", "* ", "• "), check box or number ("1. ", "2) ").
    private static func listItem(_ line: String) -> String {
        var text = Substring(line)
        // A bullet or number without text is an empty list item, as in the template.
        if ["-", "*", "+", "•"].contains(text) { return "" }
        for marker in ["- [ ] ", "- [x] ", "- ", "* ", "+ ", "• "] where text.hasPrefix(marker) {
            text = text.dropFirst(marker.count)
            break
        }
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 3, let separator = text.dropFirst(digits.count).first, separator == "." || separator == ")" {
            let rest = text.dropFirst(digits.count + 1)
            if rest.isEmpty { return "" }
            if rest.first == " " { text = rest }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Outline

    /// The sections of a note in order, classified like `parse` does: the headings from level 2 on, plus a level 1 heading
    /// when `parse` reads it as the section "Zutaten" or "Zubereitung". The translation compares the outline before and
    /// after, so a heading that changed its role is noticed.
    public static func outline(_ markdown: String) -> [SectionKind] {
        markdown.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).compactMap { raw in
            guard let found = heading(raw.trimmingCharacters(in: .whitespaces)) else { return nil }
            let kind = sectionKind(ofHeading: found.text)
            return found.level >= 2 || kind != .other ? kind : nil
        }
    }

    /// The language of the section headings: German for "Zutaten", English for "Ingredients", `nil` when the note has
    /// neither heading.
    public static func headingLanguage(_ markdown: String) -> VoiceLanguage? {
        for raw in markdown.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            guard let found = heading(raw.trimmingCharacters(in: .whitespaces)),
                  sectionKind(ofHeading: found.text) == .ingredients else { continue }
            return found.text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ": ")) == "zutaten" ? .german : .english
        }
        return nil
    }

    // MARK: Template

    /// The skeleton of a recipe the user writes by hand: the title line, the servings and the two sections, empty, in
    /// `language`. Once an ingredient is written under "Zutaten" it reads as a recipe (`parse`).
    public static func template(language: VoiceLanguage) -> String {
        func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .module) }
        return "# \n\n\(text("Portionen")): \n\n## \(text("Zutaten"))\n- \n\n## \(text("Zubereitung"))\n1. \n"
    }

    /// Whether the text is still the untouched skeleton, in any language: it is no recipe yet, and the note is removed again
    /// when it is closed unchanged.
    public static func isOnlyTemplate(_ text: String) -> Bool {
        func normalized(_ value: String) -> [String] {
            value.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let lines = normalized(text)
        return !lines.isEmpty && VoiceLanguage.allCases.contains { normalized(template(language: $0)) == lines }
    }

    // MARK: Writing

    /// The note in the fixed layout. The headings and labels are in `language`; a source line only exists with an address.
    public func markdown(language: VoiceLanguage) -> String {
        func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .module) }
        func oneLine(_ value: String) -> String {
            value.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }
        var blocks: [String] = []
        let name = oneLine(title)
        if !name.isEmpty { blocks.append("# " + name) }
        if let servings { blocks.append("\(text("Portionen")): \(servings)") }
        blocks.append((["## " + text("Zutaten")] + ingredients.map { "- " + oneLine($0) }).joined(separator: "\n"))
        if !steps.isEmpty {
            let numbered = steps.enumerated().map { "\($0.offset + 1). " + oneLine($0.element) }
            blocks.append((["## " + text("Zubereitung")] + numbered).joined(separator: "\n"))
        }
        if let sourceURL {
            let host = sourceURL.host(percentEncoded: false).map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? sourceURL.absoluteString
            blocks.append("\(text("Quelle")): [\(host)](\(sourceURL.absoluteString))")
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }
}
