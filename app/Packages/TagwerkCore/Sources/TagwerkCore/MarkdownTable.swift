import Foundation
import Markdown

/// A table of a note as the Markdown text holds it, with the rules to find, write and change it. Pure rules, no UI.
///
/// Which tables exist is decided by the Markdown parser, the same one `NoteHTMLRenderer` uses: only a table that is a
/// direct child of the document counts (not one inside a quote, a list or a code fence). The renderer numbers exactly
/// these tables in document order, so index N of `blocks(in:)` is the table behind the link `tagwerk-table:N`.
public struct MarkdownTable: Sendable, Equatable {
    public enum Alignment: Sendable, Equatable { case none, left, center, right }

    /// The cells of the header row.
    public var header: [String]
    /// One alignment per column.
    public var alignments: [Alignment]
    /// The body rows; the header is not one of them.
    public var rows: [[String]]

    /// The editor opens tables up to this width; wider tables stay text.
    public static let maximumColumns = 8
    /// The scheme of the links of the rendered page: `tagwerk-table:<index>`. Only the renderer writes it; a link in the
    /// text cannot, because the scheme is not in `HTMLSanitizer.linkSchemes`.
    public static let scheme = "tagwerk-table"

    /// Rows and alignments are fitted to the width of the header, so the table is always rectangular.
    public init(header: [String], alignments: [Alignment] = [], rows: [[String]] = []) {
        let width = header.count
        self.header = header
        self.alignments = (0..<width).map { $0 < alignments.count ? alignments[$0] : .none }
        self.rows = rows.map { row in (0..<width).map { $0 < row.count ? row[$0] : "" } }
    }

    /// A new table: three columns, a header row and two empty rows.
    public static var empty: MarkdownTable {
        MarkdownTable(header: ["", "", ""], rows: [["", "", ""], ["", "", ""]])
    }

    public var columnCount: Int { header.count }

    // MARK: Finding

    /// The table blocks of a text in order, each with the range of lines it covers (1-based, inclusive). Tables inside
    /// fenced code, quotes and lists are skipped. The count and order match what `NoteHTMLRenderer` numbers.
    public static func blocks(in text: String) -> [(table: MarkdownTable, lines: ClosedRange<Int>)] {
        let document = Document(parsing: text, options: [.disableSmartOpts])
        var found: [ClosedRange<Int>] = []
        for child in document.children {
            guard let node = child as? Markdown.Table, let range = node.range else { continue }
            // The parser starts the range of a table that interrupts a paragraph at the first line of that paragraph, but its
            // end is right. The table is the header, the separator and one line per body row, counted back from the end.
            let last = range.upperBound.line
            let first = max(range.lowerBound.line, last - Array(node.body.rows).count - 1)
            found.append(first...max(first, last))
        }
        guard !found.isEmpty else { return [] }
        let spans = LineSpan.spans(of: text)
        return found.compactMap { range in
            // The parser's range may name a line beyond the text.
            let last = min(range.upperBound, spans.count)
            guard range.lowerBound < last else { return nil }
            let lines = (range.lowerBound...last).map { String(text[spans[$0 - 1].content]) }
            guard let table = parse(lines: lines) else { return nil }
            return (table, range.lowerBound...last)
        }
    }

    /// The index of the table block that contains the 1-based line, if any.
    public static func blockIndex(containingLine line: Int, in text: String) -> Int? {
        blocks(in: text).firstIndex { $0.lines.contains(line) }
    }

    /// The table number in a link of the rendered page ("tagwerk-table:2" → 2); anything else is no table link.
    public static func index(inLink url: String) -> Int? {
        let prefix = scheme + ":"
        guard url.lowercased().hasPrefix(prefix) else { return nil }
        let rest = url.dropFirst(prefix.count)
        guard !rest.isEmpty, rest.count <= 6, rest.allSatisfy(\.isASCII), rest.allSatisfy(\.isNumber) else { return nil }
        return Int(rest)
    }

    // MARK: Writing

    /// The Markdown of the table with padded columns; "|" in a cell is written as "\|", line breaks become spaces.
    public func markdown() -> String {
        let cells = ([header] + rows).map { $0.map(Self.escaped) }
        let widths = (0..<columnCount).map { column in
            max(3, cells.map { $0[column].count }.max() ?? 3)
        }
        func line(_ row: [String]) -> String {
            let padded = row.enumerated().map { column, cell in Self.pad(cell, to: widths[column], alignment: alignments[column]) }
            return "| " + padded.joined(separator: " | ") + " |"
        }
        let separator = alignments.enumerated().map { column, alignment -> String in
            let width = widths[column]
            switch alignment {
            case .none: return String(repeating: "-", count: width)
            case .left: return ":" + String(repeating: "-", count: width - 1)
            case .right: return String(repeating: "-", count: width - 1) + ":"
            case .center: return ":" + String(repeating: "-", count: width - 2) + ":"
            }
        }
        return ([line(cells[0]), "| " + separator.joined(separator: " | ") + " |"] + cells.dropFirst().map(line)).joined(separator: "\n")
    }

    /// The text with the table inserted at the character `offset` as a block of its own: a blank line separates it from the text
    /// before and after it, because a text line that follows a table directly would become a row of it. Returns the new text and
    /// the offset right behind the inserted block with its separators, where writing goes on.
    public static func inserting(_ table: MarkdownTable, into text: String, atOffset offset: Int) -> (text: String, cursorOffset: Int) {
        let at = text.index(text.startIndex, offsetBy: min(max(offset, 0), text.count))
        let before = text[..<at]
        let after = text[at...]
        let prefix: String
        if before.isEmpty || before.hasSuffix("\n\n") { prefix = "" } else if before.hasSuffix("\n") { prefix = "\n" } else { prefix = "\n\n" }
        let suffix: String
        if after.isEmpty { suffix = "\n" } else if after.hasPrefix("\n\n") { suffix = "" } else if after.hasPrefix("\n") { suffix = "\n" } else { suffix = "\n\n" }
        let inserted = prefix + table.markdown() + suffix
        return (String(before) + inserted + String(after), before.count + inserted.count)
    }

    /// The text with the block at `index` replaced; everything outside the block is untouched, the line break style of the
    /// block is kept. An index without a block changes nothing.
    public static func replacing(blockAt index: Int, with table: MarkdownTable, in text: String) -> String {
        let all = blocks(in: text)
        guard all.indices.contains(index) else { return text }
        let lines = all[index].lines
        let spans = LineSpan.spans(of: text)
        guard lines.upperBound <= spans.count else { return text }
        let first = spans[lines.lowerBound - 1]
        let lineBreak = first.terminator.isEmpty ? "\n" : String(text[first.terminator])
        let range = first.content.lowerBound..<spans[lines.upperBound - 1].content.upperBound
        var result = text
        result.replaceSubrange(range, with: table.markdown().replacingOccurrences(of: "\n", with: lineBreak))
        return result
    }

    // MARK: Editing

    /// Inserts an empty body row; `index` counts body rows and is clamped to the table.
    public mutating func insertRow(at index: Int) {
        rows.insert(Array(repeating: "", count: columnCount), at: min(max(index, 0), rows.count))
    }

    /// Inserts an empty column; does nothing at `maximumColumns`.
    public mutating func insertColumn(at index: Int) {
        guard columnCount < Self.maximumColumns else { return }
        let position = min(max(index, 0), columnCount)
        header.insert("", at: position)
        alignments.insert(.none, at: position)
        for row in rows.indices { rows[row].insert("", at: position) }
    }

    /// Removes a body row; the header is never one. An index without a row changes nothing.
    public mutating func removeRow(at index: Int) {
        guard rows.indices.contains(index) else { return }
        rows.remove(at: index)
    }

    /// Removes a column; does nothing when one column is left.
    public mutating func removeColumn(at index: Int) {
        guard columnCount > 1, header.indices.contains(index) else { return }
        header.remove(at: index)
        alignments.remove(at: index)
        for row in rows.indices { rows[row].remove(at: index) }
    }

    /// Moves a body row; `to` is the position the row has afterwards.
    public mutating func moveRow(from: Int, to: Int) {
        guard rows.indices.contains(from), rows.indices.contains(to), from != to else { return }
        rows.insert(rows.remove(at: from), at: to)
    }

    public mutating func setAlignment(_ alignment: Alignment, column: Int) {
        guard alignments.indices.contains(column) else { return }
        alignments[column] = alignment
    }

    // MARK: Parsing

    /// Reads a table from its source lines: header, separator, rows. The cells keep their inline Markdown as it stands.
    private static func parse(lines: [String]) -> MarkdownTable? {
        guard lines.count >= 2 else { return nil }
        let header = cells(of: lines[0])
        guard !header.isEmpty else { return nil }
        let alignments = cells(of: lines[1]).map { cell -> Alignment in
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): .center
            case (true, false): .left
            case (false, true): .right
            default: .none
            }
        }
        return MarkdownTable(header: header, alignments: alignments, rows: lines.dropFirst(2).map(cells(of:)))
    }

    /// The trimmed cells of one table line. A pipe is a separator unless a backslash escapes it; "\|" becomes "|".
    private static func cells(of line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var segments: [String] = []
        var current = ""
        var characters = trimmed.makeIterator()
        var pending = characters.next()
        while let character = pending {
            pending = characters.next()
            if character == "\\", pending == "|" {
                current.append("|")
                pending = characters.next()
            } else if character == "|" {
                segments.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        segments.append(current)
        if trimmed.hasPrefix("|") { segments.removeFirst() }
        if trimmed.count > 1, segments.count > 0, trimmed.hasSuffix("|"), segments.last?.isEmpty == true { segments.removeLast() }
        return segments.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func escaped(_ cell: String) -> String {
        var flat = ""
        var characters = cell.makeIterator()
        while let character = characters.next() {
            switch character {
            case "\n", "\r", "\r\n": flat.append(" ")
            case "|": flat.append("\\|")
            default: flat.append(character)
            }
        }
        return flat.trimmingCharacters(in: .whitespaces)
    }

    private static func pad(_ cell: String, to width: Int, alignment: Alignment) -> String {
        let gap = max(width - cell.count, 0)
        switch alignment {
        case .right: return String(repeating: " ", count: gap) + cell
        case .center: return String(repeating: " ", count: gap / 2) + cell + String(repeating: " ", count: gap - gap / 2)
        default: return cell + String(repeating: " ", count: gap)
        }
    }
}

/// The lines of a text the way the Markdown parser counts them: "\n", "\r" and "\r\n" end a line.
private struct LineSpan {
    var content: Range<String.Index>
    var terminator: Range<String.Index>

    static func spans(of text: String) -> [LineSpan] {
        var result: [LineSpan] = []
        var start = text.startIndex
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            let character = text[index]
            if character == "\n" || character == "\r" || character == "\r\n" {
                result.append(LineSpan(content: start..<index, terminator: index..<next))
                start = next
            }
            index = next
        }
        result.append(LineSpan(content: start..<text.endIndex, terminator: text.endIndex..<text.endIndex))
        return result
    }
}
