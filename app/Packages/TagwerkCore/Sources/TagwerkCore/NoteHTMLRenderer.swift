import Foundation
import Markdown

/// What the page needs to know about an attachment of the note.
public struct NoteAttachmentDisplay: Sendable, Equatable {
    /// `scan` is a PDF with a preview of its first page; `pages` is its number of pages.
    public enum Kind: Sendable, Equatable { case image, file, scan(pages: Int) }
    public var name: String
    /// "1,2 MB", already formatted by the app.
    public var detail: String
    public var kind: Kind

    public init(name: String, detail: String = "", kind: Kind = .file) {
        self.name = name
        self.detail = detail
        self.kind = kind
    }
}

/// Turns the Markdown of a note into the HTML page that the note view shows. The page runs without JavaScript;
/// everything that could load or run something is handled here and again by the view (see `contentSecurityPolicy`).
public enum NoteHTMLRenderer {
    /// What the page may load: nothing but the images of the note's attachments, and its own inline styles.
    public static let contentSecurityPolicy =
        "default-src 'none'; img-src \(HTMLSanitizer.imageScheme):; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"

    /// The scheme of the links that flip a checkbox: `tagwerk-toggle:<index>`. Only this renderer writes it; links in
    /// the text cannot, because the scheme is not in `HTMLSanitizer.linkSchemes`.
    public static let toggleScheme = "tagwerk-toggle"

    public struct RenderOptions: Sendable, Equatable {
        /// The attachments of the note by ID: names links without a label and turns file references into chips.
        public var attachments: [UUID: NoteAttachmentDisplay] = [:]
        /// Wraps the text of the page in links that open the editor at that source line.
        public var editLinks = false
        /// Wraps the text of every table cell in a link `tagwerk-table:<index>` that opens the table editor. The index is the
        /// position among `MarkdownTable.blocks(in:)`; tables inside quotes and lists have no link.
        public var tableLinks = false

        public init(attachments: [UUID: NoteAttachmentDisplay] = [:], editLinks: Bool = false, tableLinks: Bool = false) {
            self.attachments = attachments
            self.editLinks = editLinks
            self.tableLinks = tableLinks
        }
    }

    /// The HTML of the note body.
    public static func html(markdown: String, options: RenderOptions) -> String {
        // Smart punctuation stays off: a note shows exactly what was typed.
        let document = Document(parsing: markdown, options: [.disableSmartOpts])
        var visitor = BodyVisitor(options: options)
        var output = visitor.visit(document)
        // A tap below the text writes at the end of the note. The empty link is only a touch target: it stays out of the
        // accessibility tree (the action "Bearbeiten" is the way in for VoiceOver).
        if options.editLinks { output += "<a class=\"e tail\" href=\"\(NoteEditTarget.scheme):\(NoteEditTarget.endToken)\" aria-hidden=\"true\" tabindex=\"-1\"></a>\n" }
        return output
    }

    /// Kept for existing callers; forwards to `html(markdown:options:)`. `attachmentNames` names the attachments.
    public static func html(markdown: String, attachmentNames: [UUID: String] = [:]) -> String {
        html(markdown: markdown, options: RenderOptions(attachments: attachmentNames.mapValues { NoteAttachmentDisplay(name: $0) }))
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
        body { margin: 0; padding: 4px 18px 24px; color: var(--text); background: transparent; word-wrap: break-word;
               font: \(String(format: "%.2f", 17 * scale))px/1.45 -apple-system, system-ui, sans-serif; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.2; margin: 1.1em 0 .4em; }
        h1 { font-size: 1.41em; font-weight: 700; } h2 { font-size: 1em; font-weight: 600; }
        h3, h4, h5, h6 { font-size: 1em; font-weight: 600; }
        p { margin: .5em 0; }
        ul, ol { padding-left: 1.4em; margin: .4em 0; }
        li > p { margin: .15em 0; }
        li.task { list-style: none; margin-left: -1.4em; }
        li.done { color: var(--muted); }
        a { color: var(--accent); text-decoration: none; }
        a.e { color: inherit; text-decoration: none; -webkit-touch-callout: none; }
        a.e.block { display: block; }
        a.e.tail { display: block; min-height: 50vh; }
        a.img { display: inline-block; max-width: 100%; }
        a.task-box { display: inline-flex; min-width:44px; min-height:44px; align-items: center; justify-content: center;
                     vertical-align: top; margin: calc((1.45em - 44px) / 2) calc(.4em + (1.1em - 44px) / 2) calc((1.45em - 44px) / 2) calc((1.1em - 44px) / 2); }
        a.task-box .box { display: flex; align-items: center; justify-content: center; box-sizing: border-box; width: 1.1em; height: 1.1em;
                          border: 2px solid var(--muted); border-radius: .3em; font-size: 1em; line-height: 1; color: #fff; }
        a.task-box[aria-checked="true"] .box { background: var(--accent); border-color: var(--accent); font-size: .8em; font-weight: 700; }
        a.file { display: inline-block; padding: .1em .6em; border: 1px solid var(--line); border-radius: 1em; }
        a.chip { display: inline-flex; align-items: center; gap: .5em; min-height:44px; box-sizing: border-box; padding: 0 .8em; margin: .2em .4em .2em 0; max-width: 100%;
                 background: var(--code); border: 1px solid var(--line); border-radius: 10px; color: var(--text); }
        a.chip::before { content: "▤"; }
        a.chip .name { min-width: 0; overflow-wrap: anywhere; }
        a.chip .detail { color: var(--muted); font-size: .85em; }
        a.scan { display: flex; align-items: center; gap: .8em; min-height: 44px; box-sizing: border-box; max-width: 100%; margin: .3em 0; padding: .5em;
                 background: var(--code); border: 1px solid var(--line); border-radius: 10px; color: var(--text); }
        a.scan img { flex: none; width: 64px; max-height: none; border-radius: 4px; border: 1px solid var(--line); background: #fff; }
        a.scan .meta { display: flex; flex-direction: column; min-width: 0; }
        a.scan .name { font-weight: 600; overflow-wrap: anywhere; }
        a.scan .detail { color: var(--muted); font-size: .85em; }
        blockquote { margin: .6em 0; padding: 0 0 0 .9em; border-left: 3px solid var(--line); color: var(--muted); }
        code { font: .9em ui-monospace, Menlo, monospace; background: var(--code); border-radius: 4px; padding: .05em .3em; }
        pre { background: var(--code); border-radius: 8px; padding: .6em .8em; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        hr { border: 0; border-top: 1px solid var(--line); margin: 1em 0; }
        div.table { margin: .6em 0; overflow-x: auto; padding-right: 16px;
                    -webkit-mask-image: linear-gradient(to right, #000 calc(100% - 16px), transparent);
                    mask-image: linear-gradient(to right, #000 calc(100% - 16px), transparent); }
        table { border-collapse: collapse; }
        th, td { border: 1px solid var(--line); padding: .3em .6em; vertical-align: top; max-width: 200pt; white-space: normal; }
        th { background: var(--code); font-weight: 600; }
        a.t { color: inherit; -webkit-touch-callout: none; }
        td.right, th.right { text-align: right; } td.center, th.center { text-align: center; }
        img { max-width:100%; max-height:40vh; width: auto; height: auto; object-fit:contain; border-radius: 8px; }
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

        let options: RenderOptions
        /// The checkboxes are numbered in document order, like `MarkdownText.togglingCheckbox` counts them.
        var checkboxIndex = 0
        var sanitizer = HTMLSanitizer()
        /// Greater than zero inside a real link: no other link there (no anchor inside an anchor).
        var anchorDepth = 0
        /// Inside a table: no edit link there; a table is edited in its own sheet.
        var insideTable = false
        /// The number of the next table that gets a link; tables are numbered in document order like `MarkdownTable.blocks`.
        var tableIndex = 0
        /// The link number of the table whose cells are being written, `nil` without links.
        var tableLink: Int?

        init(options: RenderOptions) { self.options = options }

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
            let block = "<pre><code>\(NoteHTMLRenderer.escape(codeBlock.code))</code></pre>"
            guard let line = firstContentLine(of: codeBlock), canLinkForEditing else { return block + "\n" }
            return "<a class=\"e block\" href=\"\(NoteEditTarget.scheme):\(line)\">\(block)</a>\n"
        }

        /// The source line of the first line of code: after the opening fence of a fenced block, the first line of an
        /// indented one. The number of lines the block spans against the lines of its code tells the two apart.
        private func firstContentLine(of codeBlock: CodeBlock) -> Int? {
            guard let range = codeBlock.range else { return nil }
            let codeLines = codeBlock.code.isEmpty ? 0 : codeBlock.code.split(separator: "\n", omittingEmptySubsequences: false).count - (codeBlock.code.hasSuffix("\n") ? 1 : 0)
            let spannedLines = range.upperBound.line - range.lowerBound.line + 1
            return spannedLines > codeLines ? range.lowerBound.line + 1 : range.lowerBound.line
        }

        /// Whether the next piece of text may become an edit link.
        private var canLinkForEditing: Bool { options.editLinks && anchorDepth == 0 && !insideTable && !sanitizer.isSuppressing }

        /// The link of a piece of a table cell: it opens the table editor.
        private func tableLinked(_ html: String) -> String {
            guard let index = tableLink, anchorDepth == 0, !sanitizer.isSuppressing, !html.isEmpty else { return html }
            return "<a class=\"t\" href=\"\(MarkdownTable.scheme):\(index)\">\(html)</a>"
        }

        /// Wraps an inline piece in the edit link of the source line of `markup`, or in the table link inside a table.
        private func editLinked(_ html: String, for markup: Markup) -> String {
            if insideTable { return tableLinked(html) }
            guard canLinkForEditing, !html.isEmpty, let line = markup.range?.lowerBound.line else { return html }
            return "<a class=\"e\" href=\"\(NoteEditTarget.scheme):\(line)\">\(html)</a>"
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
                + "aria-checked=\"\(isChecked)\"><span class=\"box\">\(isChecked ? "✓" : "")</span></a>"
            return "<li class=\"task\(isChecked ? " done" : "")\">\(box)\(content(of: item))</li>\n"
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
            // Only a table that stands on its own is numbered, as `MarkdownTable.blocks(in:)` finds it.
            let isBlock = table.parent is Document
            if isBlock {
                if options.tableLinks { tableLink = tableIndex }
                tableIndex += 1
            }
            insideTable = true
            defer { insideTable = false; tableLink = nil }
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
                    // An empty cell still needs something to tap.
                    if inner.isEmpty { inner = tableLinked("&nbsp;") }
                    output += "<\(tag)\(cssClass)>\(inner)</\(tag)>"
                }
                return output + "</tr>\n"
            }
            var output = "<div class=\"table\">\n<table>\n<thead>\n\(row(table.head.cells, tag: "th"))</thead>\n<tbody>\n"
            for bodyRow in table.body.rows { output += row(bodyRow.cells, tag: "td") }
            return output + "</tbody>\n</table>\n</div>\n"
        }

        // Inlines

        mutating func visitText(_ text: Text) -> String {
            sanitizer.isSuppressing ? "" : editLinked(NoteHTMLRenderer.escape(text.string), for: text)
        }

        // A single line break in a note is a line break on the page.
        mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { sanitizer.isSuppressing ? "" : "<br>\n" }

        mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { sanitizer.isSuppressing ? "" : "<br>\n" }

        mutating func visitEmphasis(_ emphasis: Emphasis) -> String { wrap("em", emphasis) }

        mutating func visitStrong(_ strong: Strong) -> String { wrap("strong", strong) }

        mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String { wrap("del", strikethrough) }

        mutating func visitInlineCode(_ code: InlineCode) -> String {
            sanitizer.isSuppressing ? "" : editLinked("<code>\(NoteHTMLRenderer.escape(code.code))</code>", for: code)
        }

        mutating func visitInlineHTML(_ html: InlineHTML) -> String { sanitizer.feed(html.rawHTML) }

        mutating func visitLink(_ link: Link) -> String {
            anchorDepth += 1
            let label = children(of: link)
            anchorDepth -= 1
            guard !sanitizer.isSuppressing else { return "" }
            guard let target = link.destination.flatMap(HTMLSanitizer.allowedLinkTarget) else { return label }
            if let id = HTMLSanitizer.attachmentID(inReference: target) {
                let display = options.attachments[id]
                let name = label.isEmpty ? NoteHTMLRenderer.escape(display?.name ?? String(id.uuidString.prefix(8))) : label
                if let display, case .scan(let pages) = display.kind {
                    // A scan: the first page as a preview, the name and what the app says about it (pages, size, recognition).
                    let detail = display.detail.isEmpty ? "" : "<span class=\"detail\">\(NoteHTMLRenderer.escape(display.detail))</span>"
                    return "<a class=\"scan\" href=\"\(target)\" data-pages=\"\(pages)\"><img src=\"\(HTMLSanitizer.imageScheme)://\(id.uuidString)\" alt=\"\">"
                        + "<span class=\"meta\"><span class=\"name\">\(name)</span>\(detail)</span></a>"
                }
                if let display, display.kind == .file {
                    let detail = display.detail.isEmpty ? "" : "<span class=\"detail\">\(NoteHTMLRenderer.escape(display.detail))</span>"
                    return "<a class=\"chip\" href=\"\(target)\"><span class=\"name\">\(name)</span>\(detail)</a>"
                }
                return "<a class=\"file\" href=\"\(target)\">📎 \(name)</a>"
            }
            return "<a href=\"\(HTMLSanitizer.escapeAttribute(target))\">\(label)</a>"
        }

        mutating func visitImage(_ image: Image) -> String {
            guard !sanitizer.isSuppressing else { return "" }
            // Only attachments are shown; a remote or any other image source is never put on the page.
            guard let id = image.source.flatMap(HTMLSanitizer.attachmentID(inReference:)) else { return "[Bild]" }
            let picture = "<img src=\"\(HTMLSanitizer.imageScheme)://\(id.uuidString)\" alt=\"\(HTMLSanitizer.escapeAttribute(image.plainText))\">"
            if insideTable { return tableLinked(picture) }
            // A tap opens the picture large (Quick Look); it never starts writing.
            return anchorDepth == 0 ? "<a class=\"img\" href=\"\(MarkdownText.attachmentScheme):\(id.uuidString)\">\(picture)</a>" : picture
        }

        private mutating func wrap(_ tag: String, _ markup: Markup) -> String {
            let inner = children(of: markup)
            return sanitizer.isSuppressing ? "" : "<\(tag)>\(inner)</\(tag)>"
        }
    }
}
