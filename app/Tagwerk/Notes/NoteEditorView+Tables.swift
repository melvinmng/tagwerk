import SwiftUI
import TagwerkCore

/// The tables of the note editor: which table the cursor is in, opening the grid sheet and writing the table back.
extension NoteEditorView {
    /// The number of the table the cursor is in (among the tables of the note), `nil` outside tables. A text without a "|" has
    /// no table, which spares the parse on most keystrokes.
    var tableIndexAtCursor: Int? {
        guard mode == .edit, text.contains("|"), case .selection(let range)? = selection?.indices else { return nil }
        let offset = text.distance(from: text.startIndex, to: range.lowerBound)
        return MarkdownTable.blockIndex(containingLine: NoteEditTarget.line(atOffset: offset, in: text), in: text)
    }

    /// Opens the table with this number in the grid sheet. A table with more columns than the grid takes gets a hint and the
    /// way to the text instead.
    func openTable(at index: Int) {
        let blocks = MarkdownTable.blocks(in: text)
        guard blocks.indices.contains(index) else { return }
        let block = blocks[index]
        if block.table.columnCount > MarkdownTable.maximumColumns {
            inserts.wideTable = WideTableHint(firstLine: block.lines.lowerBound)
        } else {
            inserts.tableSession = TableSession(index: index, table: block.table)
        }
    }

    func openTableAtCursor() {
        if let index = tableIndexAtCursor { openTable(at: index) }
    }

    /// "Tabelle" of the insert menu: the grid sheet with a new table of three columns. It goes into the note with "Fertig";
    /// "Abbrechen" leaves the note as it is.
    func startNewTable() {
        inserts.tableSession = TableSession(index: nil, table: .empty)
    }

    /// The grid sheet is done. A new table is inserted at the cursor as a block of its own; an edited one replaces its block
    /// and nothing else of the text. An own save of the page, like every other write.
    func finishTable(_ session: TableSession, table: MarkdownTable) {
        guard let index = session.index else {
            insertTable(table)
            return
        }
        // The text may have changed behind the sheet (a change from outside): the table is not written over something else.
        let blocks = MarkdownTable.blocks(in: text)
        guard blocks.indices.contains(index), blocks[index].table == session.table else {
            failureText = String(localized: "Die Notiz hat sich geändert. Die Tabelle wurde nicht übernommen.")
            return
        }
        guard table != session.table else { return }
        let updated = MarkdownTable.replacing(blockAt: index, with: table, in: text)
        let lastLine = MarkdownTable.blocks(in: updated).indices.contains(index) ? MarkdownTable.blocks(in: updated)[index].lines.upperBound : nil
        text = updated
        if mode == .edit, let lastLine {
            // The cursor of the old text means nothing in the new one: it goes to the end of the table.
            let offset = NoteEditTarget.offset(endOfLine: lastLine, in: updated)
            selection = TextSelection(insertionPoint: updated.index(updated.startIndex, offsetBy: offset))
        }
        saveText()
        refreshShareURLs()
    }

    private func insertTable(_ table: MarkdownTable) {
        var offset = text.count
        if case .selection(let range)? = selection?.indices { offset = text.distance(from: text.startIndex, to: range.lowerBound) }
        let result = MarkdownTable.inserting(table, into: text, atOffset: offset)
        text = result.text
        selection = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: result.cursorOffset))
        mode = .edit
        saveText()
        refreshShareURLs()
        // The text field exists only after this update; focusing it then brings up the keyboard at the cursor.
        Task { @MainActor in isTextFocused = true }
    }
}
