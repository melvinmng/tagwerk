import Foundation

/// Text rules for notes that contain Markdown: the plain text for titles, previews, search and everything that may
/// leave the device, the references to attachments and the checkboxes of task lists. Line based and without a parser,
/// because the title of a note is needed for every line of every list.
public enum MarkdownText {
    // MARK: Plain text

    /// The text without Markdown and HTML markup, keeping one output line per input line. It removes headings, quotes,
    /// list and checkbox markers, emphasis, inline code ticks, link targets (the link text stays), images, HTML tags and
    /// table pipes; entities are decoded. Lines inside a fenced code block stay as they are, the fences go.
    public static func plainText(_ markdown: String) -> String {
        var inFence = false
        var result: [String] = []
        for rawLine in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if isFence(line) {
                inFence.toggle()
                result.append("")
                continue
            }
            result.append(inFence ? line : plainLine(line))
        }
        return result.joined(separator: "\n")
    }

    private static func plainLine(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        if matches(horizontalRule, text) || matches(tableSeparator, text) { return "" }
        text = replace(blockPrefix, in: text, with: "")
        if text.hasPrefix("|") || text.hasSuffix("|") {
            text = text.split(separator: "|", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        text = replace(image, in: text, with: "")
        text = replace(link, in: text, with: "$1")
        text = replace(htmlTag, in: text, with: "")
        text = replace(inlineCode, in: text, with: "$1")
        for expression in [strongStar, strongUnderscore, strike, emphasisStar, emphasisUnderscore] {
            text = replace(expression, in: text, with: "$1")
        }
        return decodeEntities(text).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Attachments

    /// The scheme of a reference to an attachment.
    public static let attachmentScheme = "attachment"

    /// The IDs of all attachments the text refers to, as `attachment:<UUID>` in a link, an image or a raw HTML attribute.
    /// The scheme is matched without regard to case. Other schemes and addresses that merely contain the word are ignored.
    public static func attachmentIDs(in markdown: String) -> Set<UUID> {
        Set(attachmentReferences(in: markdown))
    }

    /// The same IDs in the order of their first reference, each once (the first picture of a note is its thumbnail).
    public static func attachmentReferences(in markdown: String) -> [UUID] {
        let range = NSRange(markdown.startIndex..., in: markdown)
        var seen = Set<UUID>()
        return attachmentReference.matches(in: markdown, range: range).compactMap { match -> UUID? in
            guard let idRange = Range(match.range(at: 1), in: markdown), let id = UUID(uuidString: String(markdown[idRange])) else { return nil }
            return seen.insert(id).inserted ? id : nil
        }
    }

    /// The text with the attachment IDs in `mapping` replaced by their new IDs, for a copy of a note whose attachments were
    /// copied too. Only references the attachment pattern matches change; an ID without an entry stays as it is.
    public static func replacingAttachmentIDs(in markdown: String, with mapping: [UUID: UUID]) -> String {
        guard !mapping.isEmpty else { return markdown }
        var result = markdown
        let matches = attachmentReference.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))
        // Back to front, so the ranges of the earlier matches stay valid.
        for match in matches.reversed() {
            guard let idRange = Range(match.range(at: 1), in: markdown), let id = UUID(uuidString: String(markdown[idRange])),
                  let replacement = mapping[id], let target = Range(match.range(at: 1), in: result) else { continue }
            result.replaceSubrange(target, with: replacement.uuidString)
        }
        return result
    }

    /// The Markdown reference to an attachment: `![name](attachment:ID)` for an image, `[name](attachment:ID)` for a file.
    /// Brackets, parentheses and backslashes in the name are escaped.
    public static func reference(for id: UUID, name: String, isImage: Bool) -> String {
        "\(isImage ? "!" : "")[\(escapedLabel(name))](\(attachmentScheme):\(id.uuidString))"
    }

    private static func escapedLabel(_ name: String) -> String {
        name.reduce(into: "") { result, character in
            if "\\[]()".contains(character) { result.append("\\") }
            result.append(character)
        }
    }

    /// The text without the references to the attachment `id` (a deleted drawing). A line that held nothing else goes with them;
    /// other text of the line stays.
    public static func removingReference(to id: UUID, in markdown: String) -> String {
        let pattern = #"!?\[(?:\\.|[^\]\\\n])*\]\(attachment:"# + id.uuidString + #"\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return markdown }
        var lines: [String] = []
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let range = NSRange(line.startIndex..., in: line)
            guard expression.firstMatch(in: line, range: range) != nil else { lines.append(line); continue }
            let remaining = expression.stringByReplacingMatches(in: line, range: range, withTemplate: "")
            if !remaining.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(remaining) }
        }
        return lines.joined(separator: "\n")
    }

    /// The text with `paragraph` inserted as its own paragraph below the line that holds the reference to the attachment `id`
    /// (the recognised text of a scan). A blank line separates it from the reference and from what follows. Text without that
    /// reference, or an empty paragraph, stays as it is.
    public static func insertingParagraph(_ paragraph: String, belowReferenceTo id: UUID, in markdown: String) -> String {
        let body = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty,
              let expression = try? NSRegularExpression(pattern: #"attachment:"# + id.uuidString, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)),
              let matched = Range(match.range, in: markdown) else { return markdown }
        let lineEnd = markdown[matched.upperBound...].firstIndex(of: "\n") ?? markdown.endIndex
        let rest = markdown[lineEnd...]
        // What follows starts with a line break: one more makes the blank line, unless it is there already.
        let closing = rest.hasPrefix("\n\n") || rest.isEmpty ? "" : "\n"
        return String(markdown[..<lineEnd]) + "\n\n" + body + closing + String(rest)
    }

    /// The text with the label of every reference to the attachment `id` replaced by `name` (a renamed scan); the rest of the
    /// text, other attachments and the kind of reference (picture or link) stay as they are.
    public static func renamingReference(of id: UUID, to name: String, in markdown: String) -> String {
        let pattern = #"(\[)((?:\\.|[^\]\\\n])*)(\]\(attachment:"# + id.uuidString + #"\))"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return markdown }
        var result = markdown
        let matches = expression.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))
        // Back to front, so the ranges of the earlier matches stay valid.
        for match in matches.reversed() {
            guard let target = Range(match.range(at: 2), in: result) else { continue }
            result.replaceSubrange(target, with: escapedLabel(name))
        }
        return result
    }

    // MARK: Checkboxes

    /// Flips the checkbox with the given zero-based position among all checkboxes of the text, in document order.
    /// A checkbox is a list item `- [ ] text` or `- [x] text` (also with `*`, `+` or `1.`, indented) with text behind the
    /// box, which is what the Markdown parser takes as a task. Lines inside fenced code blocks do not count. Text stays unchanged for a position that does not exist.
    public static func togglingCheckbox(at index: Int, in markdown: String) -> String {
        guard index >= 0 else { return markdown }
        var lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var inFence = false
        var position = 0
        for (offset, line) in lines.enumerated() {
            if isFence(line) {
                inFence.toggle()
                continue
            }
            guard !inFence, let match = checkbox.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let markRange = Range(match.range(at: 1), in: line) else { continue }
            if position == index {
                lines[offset] = line.replacingCharacters(in: markRange, with: line[markRange] == " " ? "x" : " ")
                return lines.joined(separator: lineBreak(of: markdown))
            }
            position += 1
        }
        return markdown
    }

    /// The mark behind a checkbox line of a Bible Study note whose text became a task (BS5b). "→ Task" is read as well, so a line
    /// stays marked when the note was written in the other language.
    public static let taskMarker = "→ Aufgabe"
    private static let taskMarkers = ["→ Aufgabe", "→ Task"]

    /// The text of the checkbox line at `index` (position among all checkboxes, as in `togglingCheckbox`) without the box and
    /// without the task marker; `nil` for a position that does not exist.
    public static func checkboxTitle(at index: Int, in markdown: String) -> String? {
        guard let line = checkboxLine(at: index, in: markdown) else { return nil }
        let withoutBox = line.text.replacingOccurrences(of: #"^\s*(?:[-*+]|\d+[.)])\s+\[[ xX]\]\s+"#, with: "", options: .regularExpression)
        return withoutTaskMarker(withoutBox).trimmingCharacters(in: .whitespaces)
    }

    /// Appends the task marker to the checkbox line at `index`. A line that already has it, and a position that does not exist,
    /// leave the text unchanged; no other line changes.
    public static func markingCheckboxAsTask(at index: Int, in markdown: String) -> String {
        guard let line = checkboxLine(at: index, in: markdown), !hasTaskMarker(line.text) else { return markdown }
        var lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let withoutTrailingSpace = line.text.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        lines[line.offset] = withoutTrailingSpace + " " + taskMarker
        return lines.joined(separator: lineBreak(of: markdown))
    }

    /// Whether the line ends with the task marker.
    public static func hasTaskMarker(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return taskMarkers.contains { trimmed.hasSuffix($0) }
    }

    /// Whether the checkbox at `index` is ticked; `nil` for a position that does not exist.
    public static func isCheckboxChecked(at index: Int, in markdown: String) -> Bool? {
        guard let line = checkboxLine(at: index, in: markdown),
              let match = checkbox.firstMatch(in: line.text, range: NSRange(line.text.startIndex..., in: line.text)),
              let markRange = Range(match.range(at: 1), in: line.text) else { return nil }
        return line.text[markRange] != " "
    }

    /// The position among all checkboxes of the checkbox on the 1-based source `line`; `nil` when that line is no checkbox.
    public static func checkboxIndex(atLine line: Int, in markdown: String) -> Int? {
        var inFence = false
        var position = 0
        for (offset, text) in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init).enumerated() {
            if isFence(text) { inFence.toggle(); continue }
            guard !inFence, matches(checkbox, text) else { continue }
            if offset + 1 == line { return position }
            position += 1
        }
        return nil
    }

    private static func checkboxLine(at index: Int, in markdown: String) -> (offset: Int, text: String)? {
        guard index >= 0 else { return nil }
        var inFence = false
        var position = 0
        for (offset, text) in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init).enumerated() {
            if isFence(text) { inFence.toggle(); continue }
            guard !inFence, matches(checkbox, text) else { continue }
            if position == index { return (offset, text) }
            position += 1
        }
        return nil
    }

    private static func withoutTaskMarker(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = taskMarkers.first(where: { trimmed.hasSuffix($0) }) else { return trimmed }
        return String(trimmed.dropLast(marker.count))
    }

    /// The number of checkboxes in the text (same rules as `togglingCheckbox`).
    public static func checkboxCount(in markdown: String) -> Int {
        var inFence = false
        var count = 0
        for rawLine in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if isFence(line) { inFence.toggle(); continue }
            if !inFence, matches(checkbox, line) { count += 1 }
        }
        return count
    }

    // MARK: Entities

    /// Decodes the entities that appear in notes and web pages: the five XML ones, `&nbsp;` and numeric references.
    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        var result = ""
        var cursor = text.startIndex
        for match in entity.matches(in: text, range: range) {
            guard let whole = Range(match.range, in: text), let body = Range(match.range(at: 1), in: text) else { continue }
            result += text[cursor..<whole.lowerBound]
            result += decodeEntity(String(text[body])) ?? String(text[whole])
            cursor = whole.upperBound
        }
        result += text[cursor...]
        return result
    }

    private static func decodeEntity(_ name: String) -> String? {
        switch name {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return " "
        default:
            if let named = namedEntities[name] { return named }
        }
        guard name.hasPrefix("#") else { return nil }
        let digits = name.dropFirst()
        let value = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10)
        guard let value, let scalar = Unicode.Scalar(value) else { return nil }
        return String(Character(scalar))
    }

    /// Named entities beyond the XML ones that German and English pages use; anything else stays as written.
    private static let namedEntities: [String: String] = [
        "auml": "ä", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß", "euro": "€",
        "hellip": "…", "ndash": "–", "mdash": "—", "bull": "•", "middot": "·", "laquo": "«", "raquo": "»",
        "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "deg": "°", "frac12": "½", "frac14": "¼", "frac34": "¾",
        "times": "×", "copy": "©", "reg": "®", "eacute": "é", "egrave": "è", "agrave": "à", "ccedil": "ç"
    ]

    // MARK: Helpers

    private static func isFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    /// The line break the text uses, so a toggled text keeps its endings.
    private static func lineBreak(of text: String) -> String {
        text.contains("\r\n") ? "\r\n" : "\n"
    }

    private static func matches(_ expression: NSRegularExpression, _ text: String) -> Bool {
        expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func replace(_ expression: NSRegularExpression, in text: String, with template: String) -> String {
        expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func make(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // The patterns are constants; a failure here is a programming error caught by the tests.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let blockPrefix = make(#"^(?:>\s*)*(?:#{1,6}\s+|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)?"#)
    private static let horizontalRule = make(#"^(?:-{3,}|\*{3,}|_{3,})$"#)
    private static let tableSeparator = make(#"^\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)*\|?$"#)
    private static let image = make(#"!\[[^\]]*\]\([^)]*\)"#)
    private static let link = make(#"\[([^\]]*)\]\([^)]*\)"#)
    private static let htmlTag = make(#"</?[A-Za-z][^>]*>|<!--.*?-->"#)
    private static let inlineCode = make(#"`+([^`]*)`+"#)
    private static let strongStar = make(#"\*\*(.+?)\*\*"#)
    private static let strongUnderscore = make(#"(?<![\w])__(.+?)__(?![\w])"#)
    private static let strike = make(#"~~(.+?)~~"#)
    private static let emphasisStar = make(#"(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])"#)
    private static let emphasisUnderscore = make(#"(?<![\w])_(?=\S)(.+?)(?<=\S)_(?![\w])"#)
    private static let entity = make(#"&(#[0-9]+|#[xX][0-9a-fA-F]+|[A-Za-z]+);"#)
    private static let checkbox = make(#"^\s*(?:[-*+]|\d+[.)])\s+\[([ xX])\]\s+\S"#)
    private static let attachmentReference = make(
        #"(?<![\w/:.\-])attachment:([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})"#, .caseInsensitive)
}
