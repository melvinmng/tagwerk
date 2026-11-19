import Foundation

/// Cleans raw HTML that a note contains. It rebuilds every tag from scratch out of an allowlist, so nothing of the
/// original markup is echoed: unknown tags go (their text stays), scripts, frames, forms and the like go with their
/// content, attributes come from a per-tag allowlist, link targets need an allowed scheme and images may only point to
/// attachments of the note.
///
/// This is one layer. The page that shows the result runs without JavaScript, under a Content Security Policy and with
/// content rules that block every network scheme (see `NoteHTMLRenderer.contentSecurityPolicy`).
public struct HTMLSanitizer: Sendable {
    /// Tags that survive, written in lower case.
    public static let allowedTags: Set<String> = [
        "p", "br", "b", "strong", "i", "em", "u", "s", "del", "mark", "sub", "sup", "small",
        "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "pre", "code", "hr",
        "table", "thead", "tbody", "tr", "th", "td", "span", "div", "details", "summary", "a", "img"
    ]

    /// Tags that go with everything between their opening and closing tag.
    public static let droppedWithContent: Set<String> = [
        "script", "style", "iframe", "object", "embed", "form", "svg", "math", "template", "noscript"
    ]

    /// Schemes a link may use. `attachment` must carry the ID of an attachment.
    public static let linkSchemes: Set<String> = ["http", "https", "mailto", "tel", MarkdownText.attachmentScheme]

    /// The scheme the page uses for the images of a note's attachments.
    public static let imageScheme = "tagwerk-attachment"

    private static let voidTags: Set<String> = ["br", "hr", "img"]

    private var suppressedTag: String?
    private var suppressedDepth = 0

    public init() {}

    /// Whether the text that follows currently belongs to an element that is dropped with its content.
    public var isSuppressing: Bool { suppressedTag != nil }

    /// Ends a dropped element that was never closed, so it cannot swallow what comes after the current block.
    public mutating func reset() {
        suppressedTag = nil
        suppressedDepth = 0
    }

    /// Cleans a complete fragment. A dropped element that stays open runs to the end of the fragment only.
    public static func clean(_ html: String) -> String {
        var sanitizer = HTMLSanitizer()
        return sanitizer.feed(html)
    }

    /// Cleans one piece of a document. The state of dropped elements carries over to the next piece, so a script that
    /// the Markdown parser splits into several inline pieces is still dropped as a whole.
    public mutating func feed(_ html: String) -> String {
        let scalars = Array(html.unicodeScalars.filter { $0 != "\u{0}" })
        var output = ""
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "<" else {
                let start = index
                while index < scalars.count, scalars[index] != "<" { index += 1 }
                if suppressedTag == nil { output.unicodeScalars.append(contentsOf: scalars[start..<index]) }
                continue
            }
            if Self.has(prefix: "<!--", in: scalars, at: index) {
                index = Self.find("-->", in: scalars, from: index + 4).map { $0 + 3 } ?? scalars.count
                continue
            }
            if index + 1 < scalars.count, scalars[index + 1] == "!" || scalars[index + 1] == "?" {
                // Doctype, CDATA or processing instruction: dropped up to the next ">".
                index = Self.find(">", in: scalars, from: index + 2).map { $0 + 1 } ?? scalars.count
                continue
            }
            guard let tag = Self.parseTag(scalars, at: index) else {
                // A "<" that does not open a tag is text.
                if suppressedTag == nil { output += "&lt;" }
                index += 1
                continue
            }
            index = tag.end
            output += handle(tag)
        }
        return output
    }

    // MARK: Tags

    private struct Tag {
        var name: String
        var isClosing: Bool
        var isSelfClosing: Bool
        var attributes: [(name: String, value: String)]
        var end: Int
    }

    private mutating func handle(_ tag: Tag) -> String {
        let name = tag.name
        if let suppressed = suppressedTag {
            guard name == suppressed else { return "" }
            if tag.isClosing {
                suppressedDepth -= 1
                if suppressedDepth <= 0 { reset() }
            } else if !tag.isSelfClosing {
                suppressedDepth += 1
            }
            return ""
        }
        if Self.droppedWithContent.contains(name) {
            // "embed" has no closing tag, so there is no content to wait for.
            if !tag.isClosing, !tag.isSelfClosing, name != "embed" {
                suppressedTag = name
                suppressedDepth = 1
            }
            return ""
        }
        guard Self.allowedTags.contains(name) else { return "" }
        if tag.isClosing { return Self.voidTags.contains(name) ? "" : "</\(name)>" }
        return Self.openTag(name, attributes: tag.attributes)
    }

    private static func openTag(_ name: String, attributes: [(name: String, value: String)]) -> String {
        var written: [String] = []
        var seen = Set<String>()
        for attribute in attributes where seen.insert(attribute.name).inserted {
            guard let value = cleanedValue(of: attribute.name, in: name, raw: attribute.value) else { continue }
            written.append(" \(attribute.name)=\"\(escapeAttribute(value))\"")
        }
        if name == "img" {
            // An image without an attachment as its source is dropped as a whole: nothing may be loaded.
            guard attributes.contains(where: { $0.name == "src" }), written.contains(where: { $0.hasPrefix(" src=") }) else { return "" }
        }
        return "<\(name)\(written.joined())>"
    }

    /// The value to write for an allowed attribute, or `nil` to drop the attribute.
    private static func cleanedValue(of attribute: String, in tag: String, raw: String) -> String? {
        switch (tag, attribute) {
        case (_, "title"):
            return MarkdownText.decodeEntities(raw)
        case ("a", "href"):
            return allowedLinkTarget(raw)
        case ("img", "src"):
            guard let id = attachmentID(inReference: raw) else { return nil }
            return "\(imageScheme)://\(id.uuidString)"
        case ("img", "alt"):
            return MarkdownText.decodeEntities(raw)
        case ("td", "colspan"), ("td", "rowspan"), ("th", "colspan"), ("th", "rowspan"):
            guard raw.count <= 3, let number = Int(raw), (1...100).contains(number) else { return nil }
            return String(number)
        default:
            return nil
        }
    }

    // MARK: Link targets

    /// The normalized target of a link if its scheme is allowed, otherwise `nil`. Entities are decoded and the
    /// whitespace and control characters that browsers ignore inside a scheme are removed before the scheme is read, so
    /// "java&#9;script:" is not a way around the list. Relative targets have nothing to point to and are refused.
    public static func allowedLinkTarget(_ raw: String) -> String? {
        let target = String(String.UnicodeScalarView(MarkdownText.decodeEntities(raw).unicodeScalars.filter { $0.value > 0x20 && $0.value != 0x7F }))
        guard let colon = target.firstIndex(of: ":") else { return nil }
        let scheme = target[..<colon].lowercased()
        guard let first = scheme.unicodeScalars.first, first.isASCII, CharacterSet.letters.contains(first),
              scheme.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "+-.".unicodeScalars.contains($0)) }),
              linkSchemes.contains(scheme) else { return nil }
        if scheme == MarkdownText.attachmentScheme {
            guard let id = attachmentID(inReference: target) else { return nil }
            return "\(MarkdownText.attachmentScheme):\(id.uuidString)"
        }
        return target
    }

    /// The ID in `attachment:<UUID>` (case-insensitive scheme), or `nil`.
    public static func attachmentID(inReference raw: String) -> UUID? {
        let value = String(String.UnicodeScalarView(MarkdownText.decodeEntities(raw).unicodeScalars.filter { $0.value > 0x20 && $0.value != 0x7F }))
        let prefix = MarkdownText.attachmentScheme + ":"
        guard value.lowercased().hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(value.dropFirst(prefix.count)))
    }

    // MARK: Escaping

    static func escapeAttribute(_ value: String) -> String {
        value.reduce(into: "") { result, character in
            switch character {
            case "&": result += "&amp;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.append(character)
            }
        }
    }

    // MARK: Scanning

    private static func has(prefix: String, in scalars: [Unicode.Scalar], at index: Int) -> Bool {
        let wanted = Array(prefix.unicodeScalars)
        guard index + wanted.count <= scalars.count else { return false }
        return Array(scalars[index..<index + wanted.count]) == wanted
    }

    private static func find(_ needle: String, in scalars: [Unicode.Scalar], from start: Int) -> Int? {
        let wanted = Array(needle.unicodeScalars)
        guard !wanted.isEmpty, start <= scalars.count - wanted.count else { return nil }
        for index in start...(scalars.count - wanted.count) where Array(scalars[index..<index + wanted.count]) == wanted { return index }
        return nil
    }

    private static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" || scalar == "\u{0C}"
    }

    private static func isNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == ":" || scalar == "_")
    }

    /// Reads a tag that starts at `start` (a "<"). `nil` when it is not a well-formed tag, for example "a < b" or a tag
    /// without its closing ">".
    private static func parseTag(_ scalars: [Unicode.Scalar], at start: Int) -> Tag? {
        var index = start + 1
        let isClosing = index < scalars.count && scalars[index] == "/"
        if isClosing { index += 1 }
        guard index < scalars.count, scalars[index].isASCII, CharacterSet.letters.contains(scalars[index]) else { return nil }
        let nameStart = index
        while index < scalars.count, isNameScalar(scalars[index]) { index += 1 }
        let name = String(String.UnicodeScalarView(scalars[nameStart..<index])).lowercased()
        guard index < scalars.count, isSpace(scalars[index]) || scalars[index] == "/" || scalars[index] == ">" else { return nil }

        var attributes: [(name: String, value: String)] = []
        var isSelfClosing = false
        while true {
            while index < scalars.count, isSpace(scalars[index]) || scalars[index] == "/" {
                isSelfClosing = scalars[index] == "/"
                index += 1
            }
            guard index < scalars.count else { return nil }
            if scalars[index] == ">" { return Tag(name: name, isClosing: isClosing, isSelfClosing: isSelfClosing, attributes: attributes, end: index + 1) }
            isSelfClosing = false
            let attributeStart = index
            while index < scalars.count, !isSpace(scalars[index]), scalars[index] != "=", scalars[index] != ">", scalars[index] != "/" { index += 1 }
            let attributeName = String(String.UnicodeScalarView(scalars[attributeStart..<index])).lowercased()
            while index < scalars.count, isSpace(scalars[index]) { index += 1 }
            var value = ""
            if index < scalars.count, scalars[index] == "=" {
                index += 1
                while index < scalars.count, isSpace(scalars[index]) { index += 1 }
                guard index < scalars.count else { return nil }
                if scalars[index] == "\"" || scalars[index] == "'" {
                    let quote = scalars[index]
                    index += 1
                    let valueStart = index
                    while index < scalars.count, scalars[index] != quote { index += 1 }
                    guard index < scalars.count else { return nil }
                    value = String(String.UnicodeScalarView(scalars[valueStart..<index]))
                    index += 1
                } else {
                    let valueStart = index
                    while index < scalars.count, !isSpace(scalars[index]), scalars[index] != ">" { index += 1 }
                    value = String(String.UnicodeScalarView(scalars[valueStart..<index]))
                }
            }
            if !attributeName.isEmpty { attributes.append((attributeName, value)) }
        }
    }
}
