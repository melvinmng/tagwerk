import Foundation
import Markdown

/// One block of an assistant answer, ready for the chat to draw. Inline content is an `AttributedString` that uses only
/// the presentation intents (bold, italic, code, strikethrough) and links; SwiftUI's `Text` draws both without a web view.
public enum ChatBlock: Equatable, Sendable {
    case paragraph(AttributedString)
    case heading(level: Int, text: AttributedString)
    case code(language: String?, text: String)
    case quote([ChatBlock])
    case list(ChatList)
    case table(ChatTable)
    case rule
}

public struct ChatList: Equatable, Sendable {
    public var isOrdered: Bool
    /// The number of the first item of an ordered list.
    public var start: Int
    public var items: [ChatListItem]
}

public struct ChatListItem: Equatable, Sendable {
    /// `nil` for an ordinary item, otherwise whether the task box is ticked.
    public var checkbox: Bool?
    public var blocks: [ChatBlock]
}

public enum ChatColumnAlignment: Equatable, Sendable { case leading, center, trailing }

public struct ChatTable: Equatable, Sendable {
    public var alignments: [ChatColumnAlignment]
    public var header: [AttributedString]
    /// Every row has as many cells as the widest row or the header.
    public var rows: [[AttributedString]]
}

/// Turns the Markdown (and the few HTML tags) of an answer into `ChatBlock`s. The rules are pure so they can be tested
/// without a view; the view only draws the result.
///
/// Safety: nothing is ever loaded or run. Raw HTML goes through `HTMLSanitizer` first (scripts, frames, forms and their
/// content are dropped, attributes never survive, links need an allowed scheme) and is then flattened to text; only the
/// plain formatting tags map to styles. Links are limited to http, https, mailto and tel; images show their description.
public enum ChatMarkdown {
    /// Deeper nesting of quotes and lists is shown as plain text, so crafted input cannot nest views without limit.
    static let maximumDepth = 8

    /// The schemes a link in an answer may open.
    static let linkSchemes: Set<String> = ["http", "https", "mailto", "tel"]

    public static func blocks(_ markdown: String) -> [ChatBlock] {
        // Smart punctuation stays off: an answer shows exactly what the model wrote (code, quotes, dashes).
        let document = Document(parsing: markdown, options: [.disableSmartOpts])
        var converter = Converter()
        return converter.blocks(of: document, depth: 0)
    }

    /// The text of the blocks without any markup, one line per paragraph, item or row.
    public static func plainText(of blocks: [ChatBlock]) -> String {
        blocks.map(plainText(of:)).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func plainText(of block: ChatBlock) -> String {
        switch block {
        case .paragraph(let text), .heading(_, let text): String(text.characters)
        case .code(_, let text): text
        case .quote(let blocks): plainText(of: blocks)
        case .list(let list): list.items.map { plainText(of: $0.blocks) }.joined(separator: "\n")
        case .table(let table):
            ([table.header] + table.rows).map { $0.map { String($0.characters) }.joined(separator: " ") }.joined(separator: "\n")
        case .rule: ""
        }
    }

    // MARK: Conversion

    private struct Converter {
        /// One per block, like in the notes: a dropped element that stays open must not swallow the next block.
        var sanitizer = HTMLSanitizer()

        mutating func blocks(of container: Markup, depth: Int) -> [ChatBlock] {
            var result: [ChatBlock] = []
            for child in container.children {
                result.append(contentsOf: blocks(for: child, depth: depth))
                sanitizer.reset()
            }
            return result
        }

        private mutating func blocks(for markup: Markup, depth: Int) -> [ChatBlock] {
            switch markup {
            case let paragraph as Paragraph:
                let text = inline(of: paragraph)
                return text.characters.isEmpty ? [] : [.paragraph(text)]
            case let heading as Heading:
                let text = inline(of: heading)
                return text.characters.isEmpty ? [] : [.heading(level: min(max(heading.level, 1), 6), text: text)]
            case let code as CodeBlock:
                let language = code.language.flatMap { $0.isEmpty ? nil : $0 }
                var body = code.code
                if body.hasSuffix("\n") { body.removeLast() }
                return [.code(language: language, text: body)]
            case is ThematicBreak:
                return [.rule]
            case let html as HTMLBlock:
                return Self.flatten(sanitizer.feed(html.rawHTML)).map { [.paragraph($0)] } ?? []
            case let quote as BlockQuote:
                if depth >= ChatMarkdown.maximumDepth { return Self.plainParagraph(of: quote) }
                let inner = blocks(of: quote, depth: depth + 1)
                return inner.isEmpty ? [] : [.quote(inner)]
            case let list as UnorderedList:
                return depth >= ChatMarkdown.maximumDepth ? Self.plainParagraph(of: list)
                    : [.list(chatList(list.listItems, isOrdered: false, start: 1, depth: depth))]
            case let list as OrderedList:
                return depth >= ChatMarkdown.maximumDepth ? Self.plainParagraph(of: list)
                    : [.list(chatList(list.listItems, isOrdered: true, start: Int(list.startIndex), depth: depth))]
            case let table as Table:
                return [.table(chatTable(table))]
            default:
                // Anything else a parser may add keeps its text instead of vanishing.
                return Self.plainParagraph(of: markup)
            }
        }

        private static func plainParagraph(of markup: Markup) -> [ChatBlock] {
            let text = MarkdownText.plainText(markup.format()).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [.paragraph(AttributedString(text))]
        }

        private mutating func chatList(_ items: some Sequence<ListItem>, isOrdered: Bool, start: Int, depth: Int) -> ChatList {
            let converted = items.map { item in
                ChatListItem(checkbox: item.checkbox.map { $0 == .checked }, blocks: blocks(of: item, depth: depth + 1))
            }
            return ChatList(isOrdered: isOrdered, start: start, items: converted)
        }

        private mutating func chatTable(_ table: Table) -> ChatTable {
            var header: [AttributedString] = []
            for cell in table.head.cells { header.append(inline(of: cell)) }
            var rows: [[AttributedString]] = []
            for row in table.body.rows {
                var cells: [AttributedString] = []
                for cell in row.cells { cells.append(inline(of: cell)) }
                rows.append(cells)
            }
            let width = max(header.count, rows.map(\.count).max() ?? 0)
            func padded(_ cells: [AttributedString]) -> [AttributedString] { cells + Array(repeating: AttributedString(), count: max(0, width - cells.count)) }
            let alignments = (0..<width).map { index -> ChatColumnAlignment in
                guard index < table.columnAlignments.count, let alignment = table.columnAlignments[index] else { return .leading }
                switch alignment {
                case .left: return .leading
                case .center: return .center
                case .right: return .trailing
                }
            }
            return ChatTable(alignments: alignments, header: padded(header), rows: rows.map(padded))
        }

        // MARK: Inline

        private mutating func inline(of container: Markup) -> AttributedString {
            var builder = InlineBuilder(sanitizer: sanitizer)
            builder.visit(children: container.children, intent: [], link: nil)
            sanitizer = builder.sanitizer
            return builder.finish()
        }

        // MARK: HTML blocks

        /// The text of sanitized HTML: block ends become line breaks, list items get a bullet, every other tag goes.
        /// Formatting inside an HTML block is not kept; the block stays readable and nothing in it can act.
        static func flatten(_ sanitized: String) -> AttributedString? {
            var text = sanitized
            text = text.replacingOccurrences(of: #"<li(\s[^>]*)?>"#, with: "• ", options: .regularExpression)
            text = text.replacingOccurrences(of: #"<br\s*/?>|</(?:p|div|li|h[1-6]|tr|blockquote|pre|ul|ol|table|details|summary)>"#,
                                             with: "\n", options: .regularExpression)
            text = text.replacingOccurrences(of: #"</t[dh]>"#, with: "  ", options: .regularExpression)
            text = text.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
            text = MarkdownText.decodeEntities(text)
            let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return lines.isEmpty ? nil : AttributedString(lines.joined(separator: "\n"))
        }
    }

    // MARK: Inline builder

    private struct InlineBuilder: MarkupVisitor {
        typealias Result = Void

        var sanitizer: HTMLSanitizer
        private var output = AttributedString()
        /// Styles opened by raw HTML tags (`<b>`, `<a href>`), closed again by the matching end tag.
        private var htmlStack: [(tag: String, intent: InlinePresentationIntent, link: URL?)] = []
        private var intent: InlinePresentationIntent = []
        private var link: URL?

        init(sanitizer: HTMLSanitizer) { self.sanitizer = sanitizer }

        mutating func visit(children: MarkupChildren, intent: InlinePresentationIntent, link: URL?) {
            let saved = (self.intent, self.link)
            self.intent.formUnion(intent)
            if let link { self.link = link }
            for child in children { visit(child) }
            (self.intent, self.link) = saved
        }

        /// The finished text without the line breaks and spaces at either end.
        func finish() -> AttributedString {
            var text = output
            while let last = text.characters.last, last.isWhitespace || last.isNewline { text.characters.removeLast() }
            while let first = text.characters.first, first.isWhitespace || first.isNewline { text.characters.removeFirst() }
            return text
        }

        private mutating func append(_ string: String, intent extra: InlinePresentationIntent = []) {
            guard !sanitizer.isSuppressing, !string.isEmpty else { return }
            var piece = AttributedString(string)
            var combined = intent.union(extra)
            for entry in htmlStack { combined.formUnion(entry.intent) }
            if !combined.isEmpty { piece.inlinePresentationIntent = combined }
            if let target = link ?? htmlStack.last(where: { $0.link != nil })?.link { piece.link = target }
            output.append(piece)
        }

        mutating func defaultVisit(_ markup: Markup) { for child in markup.children { visit(child) } }

        mutating func visitText(_ text: Markdown.Text) { append(text.string) }
        mutating func visitSoftBreak(_ softBreak: SoftBreak) { append("\n") }
        mutating func visitLineBreak(_ lineBreak: LineBreak) { append("\n") }
        mutating func visitInlineCode(_ code: InlineCode) { append(code.code, intent: .code) }

        mutating func visitEmphasis(_ emphasis: Emphasis) { visit(children: emphasis.children, intent: .emphasized, link: nil) }
        mutating func visitStrong(_ strong: Strong) { visit(children: strong.children, intent: .stronglyEmphasized, link: nil) }
        mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
            visit(children: strikethrough.children, intent: .strikethrough, link: nil)
        }

        mutating func visitLink(_ markdownLink: Markdown.Link) {
            visit(children: markdownLink.children, intent: [], link: markdownLink.destination.flatMap(ChatMarkdown.allowedLink))
        }

        mutating func visitImage(_ image: Markdown.Image) {
            // The source is never loaded; the description (or a marker) stands in.
            guard !sanitizer.isSuppressing else { return }
            let alt = image.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            append(alt.isEmpty ? "[Bild]" : alt)
        }

        mutating func visitInlineHTML(_ html: InlineHTML) {
            handle(tag: sanitizer.feed(html.rawHTML))
        }

        /// Applies one sanitized tag (the sanitizer writes tags in a fixed form: lower case, double-quoted attributes).
        private mutating func handle(tag: String) {
            guard let match = ChatMarkdown.tagPattern.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                  let nameRange = Range(match.range(at: 2), in: tag) else { return }
            let name = String(tag[nameRange])
            let isClosing = match.range(at: 1).length > 0
            if name == "br" { append("\n"); return }
            if isClosing {
                if let index = htmlStack.lastIndex(where: { $0.tag == name }) { htmlStack.removeSubrange(index...) }
                return
            }
            let style: InlinePresentationIntent = switch name {
            case "b", "strong": .stronglyEmphasized
            case "i", "em": .emphasized
            case "code": .code
            case "s", "del": .strikethrough
            default: []
            }
            var target: URL?
            if name == "a", let hrefRange = Range(match.range(at: 3), in: tag).flatMap({ tag[$0].range(of: #"href="([^"]*)""#, options: .regularExpression) }) {
                let href = String(tag[hrefRange].dropFirst(6).dropLast())
                target = ChatMarkdown.allowedLink(MarkdownText.decodeEntities(href))
            }
            if !style.isEmpty || target != nil { htmlStack.append((name, style, target)) }
        }
    }

    /// `<name attributes>` or `</name>` as the sanitizer writes them: group 1 the slash, 2 the name, 3 the attributes.
    private static let tagPattern: NSRegularExpression = {
        // The pattern is a constant; a failure here is a programming error caught by the tests.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"^<(/?)([a-z][a-z0-9]*)((?:\s[^>]*)?)>$"#)
    }()

    /// The URL of a link target if it is safe to open from the chat: http, https, mailto or tel only.
    static func allowedLink(_ raw: String) -> URL? {
        guard let target = HTMLSanitizer.allowedLinkTarget(raw), let colon = target.firstIndex(of: ":"),
              linkSchemes.contains(target[..<colon].lowercased()) else { return nil }
        return URL(string: target)
    }
}
