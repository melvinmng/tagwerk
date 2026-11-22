import Testing
import TagwerkCore
@testable import Tagwerk

/// The state of the table editor: where the cursor goes and what can be done in which cell.
@MainActor
struct TableEditorModelTests {
    private func model(columns: Int = 2, rows: Int = 2) -> TableEditorModel {
        let header = (1...columns).map { "H\($0)" }
        let body = (1...max(rows, 1)).prefix(rows).map { row in (1...columns).map { "r\(row)c\($0)" } }
        return TableEditorModel(table: MarkdownTable(header: header, rows: Array(body)))
    }

    @Test func advance_movesThroughCellsAndAddsRow() {
        let model = model(columns: 2, rows: 1)
        #expect(model.focus == (0, 0))
        model.advance()
        #expect(model.focus == (0, 1))
        // The end of a row: the first cell of the next one.
        model.advance()
        #expect(model.focus == (1, 0))
        model.advance()
        #expect(model.focus == (1, 1))
        // After the last cell: a new row.
        model.advance()
        #expect(model.focus == (2, 0))
        #expect(model.table.rows.count == 2 && model.table.rows[1] == ["", ""])
    }

    @Test func canDeleteRow_falseOnHeader() {
        let model = model()
        #expect(!model.canDeleteRow)
        model.deleteRow()
        #expect(model.table.rows.count == 2)
        model.focus = (1, 0)
        #expect(model.canDeleteRow)
        model.deleteRow()
        #expect(model.table.rows.count == 1)
        #expect(model.focus.row == 1)
    }

    @Test func canAddColumn_falseAtEight() {
        let model = model(columns: 7)
        #expect(model.canAddColumn)
        model.addColumn()
        #expect(model.table.columnCount == 8 && model.focus == (0, 7))
        #expect(!model.canAddColumn)
        model.addColumn()
        model.insertColumnLeft()
        #expect(model.table.columnCount == 8)
    }

    @Test func canDeleteColumn_falseWithOneColumnLeft() {
        let model = model(columns: 2)
        #expect(model.canDeleteColumn)
        model.focus = (0, 1)
        model.deleteColumn()
        #expect(model.table.columnCount == 1 && model.focus == (0, 0))
        #expect(!model.canDeleteColumn)
        model.deleteColumn()
        #expect(model.table.columnCount == 1)
    }

    @Test func rowActions_followTheRowOfTheCursor() {
        let model = model(columns: 1, rows: 3)
        // The header can be neither moved nor have a row inserted above it.
        #expect(!model.canInsertRowAbove && !model.canMoveRowUp && !model.canMoveRowDown)
        model.focus = (1, 0)
        #expect(model.canInsertRowAbove && !model.canMoveRowUp && model.canMoveRowDown)
        model.moveRowDown()
        #expect(model.table.rows == [["r2c1"], ["r1c1"], ["r3c1"]] && model.focus.row == 2)
        model.moveRowUp()
        #expect(model.table.rows == [["r1c1"], ["r2c1"], ["r3c1"]] && model.focus.row == 1)
        model.focus = (3, 0)
        #expect(!model.canMoveRowDown)
        model.insertRowAbove()
        #expect(model.table.rows == [["r1c1"], ["r2c1"], [""], ["r3c1"]])
    }

    @Test func cellText_readsAndWritesHeaderAndBody() {
        let model = model()
        #expect(model.text(row: 0, column: 1) == "H2" && model.text(row: 2, column: 0) == "r2c1")
        model.setText("Neu", row: 0, column: 0)
        model.setText("Wert", row: 1, column: 1)
        #expect(model.table.header[0] == "Neu" && model.table.rows[0][1] == "Wert")
        // A cell that does not exist reads as empty and ignores writes.
        #expect(model.text(row: 9, column: 0) == "" && model.text(row: 0, column: 9) == "")
        model.setText("x", row: 9, column: 0)
        #expect(model.table == model.table)
    }

    @Test func alignment_isThatOfTheColumnOfTheCursor() {
        let model = model()
        model.focus = (1, 1)
        #expect(model.alignmentOfFocusedColumn == .none)
        model.setAlignment(.right)
        #expect(model.alignmentOfFocusedColumn == .right && model.table.alignments == [.none, .right])
    }

    @Test func columnWidth_sharesTheWidthDownToTheMinimum() {
        #expect(TableEditorSheet.columnWidth(columns: 3, available: 392) == 120)
        #expect(TableEditorSheet.columnWidth(columns: 8, available: 392) == TableEditorSheet.minimumColumnWidth)
        #expect(TableEditorSheet.columnWidth(columns: 1, available: 0) == TableEditorSheet.minimumColumnWidth)
    }
}
