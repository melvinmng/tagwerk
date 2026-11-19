import Foundation
import Markdown

/// Turns the Markdown of a note into the HTML page that the note view shows. The page runs without JavaScript;
/// everything that could load or run something is handled here and again by the view (see `contentSecurityPolicy`).
public enum NoteHTMLRenderer {
    /// What the page may load: nothing but the images of the note's attachments, and its own inline styles.
    public static let contentSecurityPolicy =
        "default-src 'none'; img-src \(HTMLSanitizer.imageScheme):; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"

    /// The scheme of the links that flip a checkbox: `tagwerk-toggle:<index>`. Only this renderer writes it; links in
    /// the text cannot, because the scheme is not in `HTMLSanitizer.linkSchemes`.
    public static let toggleScheme = "tagwerk-toggle"

    /// The HTML of the note body. `attachmentNames` names the attachments for links without a label.
    public static func html(markdown: String, attachmentNames: [UUID: String] = [:]) -> String {
        // Smart punctuation stays off: a note shows exactly what was typed.
        let document = Document(parsing: markdown, options: [.disableSmartOpts])
        var visitor = BodyVisitor(attachmentNames: attachmentNames)
        return visitor.visit(document)
    }

    public enum ColorScheme: Sendable { case system, light, dark }

    /// The complete page: CSP, style sheet and the body. `textScale` follows the user's text size (1 is the default).
    public static func page(body: String, colorScheme: ColorScheme = .system, textScale: Double = 1) -> String {
        let scale = min(max(textScale, 0.5), 4)
        let scheme: String = switch colorScheme {
        case .system: "light dark"
        case .light: "light"
        case .dark: "dark"
        }
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: \(scheme); --text: #1c1c1e; --muted: #6c6c70; --line: #d1d1d6; --code: #f2f2f7; --accent: #0a84ff; }
        \(colorScheme == .dark ? ":root { " + Self.darkVariables + " }" : "")
        \(colorScheme == .system ? "@media (prefers-color-scheme: dark) { :root { " + Self.darkVariables + " } }" : "")
        html { -webkit-text-size-adjust: 100%; }
        body { margin: 0; padding: 4px 2px 24px; color: var(--text); background: transparent; word-wrap: break-word;
               font: \(String(format: "%.2f", 17 * scale))px/1.45 -apple-system, system-ui, sans-serif; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.2; margin: 1.1em 0 .4em; }
        h1 { font-size: 1.6em; } h2 { font-size: 1.35em; } h3 { font-size: 1.15em; } h4, h5, h6 { font-size: 1em; }
        p { margin: .5em 0; }
        ul, ol { padding-left: 1.4em; margin: .4em 0; }
        li > p { margin: .15em 0; }
        li.task { list-style: none; margin-left: -1.4em; }
        a { color: var(--accent); text-decoration: none; }
        a.task-box { display: inline-block; width: 1.1em; margin-right: .4em; text-align: center; font-size: 1.1em; line-height: 1; }
        a.file { display: inline-block; padding: .1em .6em; border: 1px solid var(--line); border-radius: 1em; }
        blockquote { margin: .6em 0; padding: 0 0 0 .9em; border-left: 3px solid var(--line); color: var(--muted); }
        code { font: .9em ui-monospace, Menlo, monospace; background: var(--code); border-radius: 4px; padding: .05em .3em; }
        pre { background: var(--code); border-radius: 8px; padding: .6em .8em; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        hr { border: 0; border-top: 1px solid var(--line); margin: 1em 0; }
        table { border-collapse: collapse; margin: .6em 0; max-width: 100%; display: block; overflow-x: auto; }
        th, td { border: 1px solid var(--line); padding: .3em .6em; vertical-align: top; }
        th { background: var(--code); }
        td.right, th.right { text-align: right; } td.center, th.center { text-align: center; }
        img { max-width: 100%; height: auto; border-radius: 8px; }
        mark { background: #ffe66d; color: #1c1c1e; }
        details { margin: .4em 0; }
        </style></head>
        <body>
        \(body)
        </body></html>
        """
    }

    private static let darkVariables = "--text: #f2f2f7; --muted: #aeaeb2; --line: #48484a; --code: #2c2c2e; --accent: #0a84ff;"

    // MARK: Escaping

    static func escape(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
    }

    // MARK: Visitor

    private struct BodyVisitor: MarkupVisitor {
        typealias Result = String

        let attachmentNames: [UUID: String]
        /// The checkboxes are numbered in document order, like `MarkdownText.togglingCheckbox` counts them.
        var checkboxIndex = 0
        var sanitizer = HTMLSanitizer()

        init(attachmentNames: [UUID: String]) { self.attachmentNames = attachmentNames }

        mutating func defaultVisit(_ markup: Markup) -> String { children(of: markup) }

        /// A dropped element that was left open must not swallow the next block.
        mutating func visit(_ markup: Markup) -> String {
            let output = markup.accept(&self)
            if markup is BlockMarkup { sanitizer.reset() }
            return output
        }

        private mutating func children(of markup: Markup) -> String {
            var output = ""
            for child in markup.children { output += visit(child) }
            return output
        }

        // Blocks

        mutating func visitHeading(_ heading: Heading) -> String {
            let level = min(max(heading.level, 1), 6)
            return "<h\(level)>\(children(of: heading))</h\(level)>\n"
        }

        mutating func visitParagraph(_ paragraph: Paragraph) -> String { "<p>\(children(of: paragraph))</p>\n" }

        mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String { "<blockquote>\n\(children(of: blockQuote))</blockquote>\n" }

        mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
            "<pre><code>\(NoteHTMLRenderer.escape(codeBlock.code))</code></pre>\n"
        }

        mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String { "<hr>\n" }

        mutating func visitHTMLBlock(_ html: HTMLBlock) -> String { sanitizer.feed(html.rawHTML) + "\n" }

        mutating func visitUnorderedList(_ list: UnorderedList) -> String { "<ul>\n\(children(of: list))</ul>\n" }

        mutating func visitOrderedList(_ list: OrderedList) -> String {
            let start = list.startIndex == 1 ? "" : " start=\"\(list.startIndex)\""
            return "<ol\(start)>\n\(children(of: list))</ol>\n"
        }

        mutating func visitListItem(_ item: ListItem) -> String {
            guard let checkbox = item.checkbox else { return "<li>\(content(of: item))</li>\n" }
            let index = checkboxIndex
            checkboxIndex += 1
            let isChecked = checkbox == .checked
            // A link instead of an input: it needs no script to react, and a disabled input would swallow the tap.
            let box = "<a class=\"task-box\" href=\"\(NoteHTMLRenderer.toggleScheme):\(index)\" data-index=\"\(index)\" role=\"checkbox\" "
                + "aria-checked=\"\(isChecked)\">\(isChecked ? "☑" : "☐")</a>"
            return "<li class=\"task\">\(box)\(content(of: item))</li>\n"
        }

        /// The content of a list item. A single paragraph is written without its own <p>, so short items stay compact.
        private mutating func content(of item: ListItem) -> String {
            let paragraphs = item.children.filter { $0 is Paragraph }
            guard paragraphs.count == 1, let paragraph = paragraphs.first else { return children(of: item) }
            var output = ""
            for child in item.children { output += child is Paragraph ? children(of: paragraph) : visit(child) }
            return output
        }

        mutating func visitTable(_ table: Table) -> String {
            let alignments = table.columnAlignments
            func row(_ cells: some Sequence<Table.Cell>, tag: String) -> String {
                var output = "<tr>"
                for (offset, cell) in cells.enumerated() {
                    let alignment = offset < alignments.count ? alignments[offset] : nil
                    let cssClass: String = switch alignment {
                    case .right?: " class=\"right\""
                    case .center?: " class=\"center\""
                    default: ""
                    }
                    var inner = ""
                    for child in cell.children { inner += visit(child) }
                    output += "<\(tag)\(cssClass)>\(inner)</\(tag)>"
                }
                return output + "</tr>\n"
            }
            var output = "<table>\n<thead>\n\(row(table.head.cells, tag: "th"))</thead>\n<tbody>\n"
            for bodyRow in table.body.rows { output += row(bodyRow.cells, tag: "td") }
            return output + "</tbody>\n</table>\n"
        }

        // Inlines

        mutating func visitText(_ text: Text) -> String {
            sanitizer.isSuppressing ? "" : NoteHTMLRenderer.escape(text.string)
        }

        // A single line break in a note is a line break on the page.
        mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { sanitizer.isSuppressing ? "" : "<br>\n" }

        mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { sanitizer.isSuppressing ? "" : "<br>\n" }

        mutating func visitEmphasis(_ emphasis: Emphasis) -> String { wrap("em", emphasis) }

        mutating func visitStrong(_ strong: Strong) -> String { wrap("strong", strong) }

        mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String { wrap("del", strikethrough) }

        mutating func visitInlineCode(_ code: InlineCode) -> String {
            sanitizer.isSuppressing ? "" : "<code>\(NoteHTMLRenderer.escape(code.code))</code>"
        }

        mutating func visitInlineHTML(_ html: InlineHTML) -> String { sanitizer.feed(html.rawHTML) }

        mutating func visitLink(_ link: Link) -> String {
            let label = children(of: link)
            guard !sanitizer.isSuppressing else { return "" }
            guard let target = link.destination.flatMap(HTMLSanitizer.allowedLinkTarget) else { return label }
            if let id = HTMLSanitizer.attachmentID(inReference: target) {
                let name = label.isEmpty ? NoteHTMLRenderer.escape(attachmentNames[id] ?? String(id.uuidString.prefix(8))) : label
                return "<a class=\"file\" href=\"\(target)\">📎 \(name)</a>"
            }
            return "<a href=\"\(HTMLSanitizer.escapeAttribute(target))\">\(label)</a>"
        }

        mutating func visitImage(_ image: Image) -> String {
            guard !sanitizer.isSuppressing else { return "" }
            // Only attachments are shown; a remote or any other image source is never put on the page.
            guard let id = image.source.flatMap(HTMLSanitizer.attachmentID(inReference:)) else { return "[Bild]" }
            return "<img src=\"\(HTMLSanitizer.imageScheme)://\(id.uuidString)\" alt=\"\(HTMLSanitizer.escapeAttribute(image.plainText))\">"
        }

        private mutating func wrap(_ tag: String, _ markup: Markup) -> String {
            let inner = children(of: markup)
            return sanitizer.isSuppressing ? "" : "<\(tag)>\(inner)</\(tag)>"
        }
    }
}
