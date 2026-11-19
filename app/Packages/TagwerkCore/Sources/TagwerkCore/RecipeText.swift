import Foundation

/// Gets the text of a recipe page on the device, so that only the part that matters goes to ChatGPT: the ingredient list
/// from the page's structured data when it has one, otherwise the page's visible text, cut to a fixed length.
public enum RecipeText {
    /// The most characters of page text that are sent.
    public static let maximumLength = 8000

    // MARK: Structured data

    /// The ingredients from a `<script type="application/ld+json">` block that describes a `Recipe` (found directly, in an
    /// array or in a `@graph`). `nil` when the page has none or the recipe lists no ingredient.
    public static func ingredients(fromHTML html: String) -> [String]? {
        let range = NSRange(html.startIndex..., in: html)
        for match in jsonLDBlock.matches(in: html, range: range) {
            guard let bodyRange = Range(match.range(at: 1), in: html),
                  let data = String(html[bodyRange]).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let found = recipeIngredients(in: json), !found.isEmpty { return found }
        }
        return nil
    }

    private static func recipeIngredients(in json: Any) -> [String]? {
        if let array = json as? [Any] {
            for element in array { if let found = recipeIngredients(in: element), !found.isEmpty { return found } }
            return nil
        }
        guard let object = json as? [String: Any] else { return nil }
        if isRecipe(object["@type"]) {
            let raw = object["recipeIngredient"] ?? object["ingredients"]
            let list: [String] = (raw as? [Any])?.compactMap { $0 as? String } ?? (raw as? String).map { [$0] } ?? []
            let cleaned = list.map(clean).filter { !$0.isEmpty }
            if !cleaned.isEmpty { return cleaned }
        }
        for key in ["@graph", "mainEntity", "mainEntityOfPage"] {
            if let nested = object[key], let found = recipeIngredients(in: nested), !found.isEmpty { return found }
        }
        return nil
    }

    private static func isRecipe(_ type: Any?) -> Bool {
        if let name = type as? String { return name.hasSuffix("Recipe") }
        if let names = type as? [Any] { return names.contains { isRecipe($0) } }
        return false
    }

    private static func clean(_ text: String) -> String {
        collapseSpaces(MarkdownText.decodeEntities(replace(anyTag, in: text, with: "")))
    }

    // MARK: Visible text

    /// The text of the page: script, style, navigation, header and footer parts go with their content, the other tags go,
    /// entities are decoded and white space is collapsed. Block elements keep their line breaks.
    public static func plainText(fromHTML html: String) -> String {
        var text = replace(comment, in: html, with: " ")
        text = replace(droppedElement, in: text, with: " ")
        // Line breaks in the source are only white space; the block tags below make the real ones.
        text = collapseSpaces(text)
        text = replace(blockTag, in: text, with: "\n")
        text = replace(anyTag, in: text, with: "")
        let lines = MarkdownText.decodeEntities(text).split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map { collapseSpaces(String($0)) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    /// At most `maximumLength` characters.
    public static func limited(_ text: String) -> String {
        String(text.prefix(maximumLength))
    }

    // MARK: Helpers

    private static func collapseSpaces(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func replace(_ expression: NSRegularExpression, in text: String, with template: String) -> String {
        expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func make(_ pattern: String) -> NSRegularExpression {
        // The patterns are constants; a failure here is a programming error caught by the tests.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    private static let jsonLDBlock = make(#"<script\b[^>]*\btype\s*=\s*["']?application/ld\+json["']?[^>]*>(.*?)</script\s*>"#)
    private static let comment = make(#"<!--.*?-->"#)
    private static let droppedElement = make(#"<(script|style|nav|header|footer|noscript|svg|template)\b[^>]*>.*?</\1\s*>"#)
    private static let blockTag = make(#"</?(?:p|div|br|li|ul|ol|tr|td|th|table|h[1-6]|section|article|main|aside|dd|dt|dl|blockquote|figure|figcaption)\b[^>]*>"#)
    private static let anyTag = make(#"<[^>]*>"#)
}
