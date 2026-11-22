import SwiftUI
import TagwerkCore

/// What the table editor works on: the table of the note with this number among its tables, or a new one (`index` is `nil`).
struct TableSession: Identifiable {
    let id = UUID()
    let index: Int?
    let table: MarkdownTable
}

/// A table of a note that has more columns than the editor opens; the hint offers the text instead.
struct WideTableHint: Identifiable {
    let id = UUID()
    /// The first line of the table in the note, where "Im Text bearbeiten" puts the cursor.
    let firstLine: Int
}

/// The state of the table editor: the table, the cell with the cursor and what can be done to it there.
@MainActor @Observable
final class TableEditorModel {
    var table: MarkdownTable
    /// The cell with the cursor; row 0 is the header, the body rows follow.
    var focus: (row: Int, column: Int)

    init(table: MarkdownTable) {
        self.table = table
        focus = (0, 0)
    }

    var rowCount: Int { table.rows.count + 1 }
    var canDeleteRow: Bool { focus.row > 0 }
    var canDeleteColumn: Bool { table.columnCount > 1 }
    var canAddColumn: Bool { table.columnCount < MarkdownTable.maximumColumns }
    var canInsertRowAbove: Bool { focus.row > 0 }
    var canMoveRowUp: Bool { focus.row > 1 }
    var canMoveRowDown: Bool { focus.row > 0 && focus.row < table.rows.count }

    func text(row: Int, column: Int) -> String {
        guard column >= 0, column < table.columnCount else { return "" }
        if row == 0 { return table.header[column] }
        guard table.rows.indices.contains(row - 1) else { return "" }
        return table.rows[row - 1][column]
    }

    func setText(_ text: String, row: Int, column: Int) {
        guard column >= 0, column < table.columnCount else { return }
        if row == 0 {
            table.header[column] = text
        } else if table.rows.indices.contains(row - 1) {
            table.rows[row - 1][column] = text
        }
    }

    /// "Weiter": the next cell, a new row after the last cell.
    func advance() {
        if focus.column < table.columnCount - 1 {
            focus.column += 1
        } else if focus.row < table.rows.count {
            focus = (focus.row + 1, 0)
        } else {
            table.insertRow(at: table.rows.count)
            focus = (table.rows.count, 0)
        }
    }

    /// "＋ Zeile": a row behind the last one.
    func addRow() {
        table.insertRow(at: table.rows.count)
        focus = (table.rows.count, focus.column)
    }

    /// "＋ Spalte": a column behind the last one; nothing at the limit.
    func addColumn() {
        guard canAddColumn else { return }
        table.insertColumn(at: table.columnCount)
        focus = (focus.row, table.columnCount - 1)
    }

    func insertRowAbove() {
        guard canInsertRowAbove else { return }
        table.insertRow(at: focus.row - 1)
    }

    func insertColumnLeft() {
        guard canAddColumn else { return }
        table.insertColumn(at: focus.column)
    }

    func moveRowUp() {
        guard canMoveRowUp else { return }
        table.moveRow(from: focus.row - 1, to: focus.row - 2)
        focus.row -= 1
    }

    func moveRowDown() {
        guard canMoveRowDown else { return }
        table.moveRow(from: focus.row - 1, to: focus.row)
        focus.row += 1
    }

    func setAlignment(_ alignment: MarkdownTable.Alignment) {
        table.setAlignment(alignment, column: focus.column)
    }

    var alignmentOfFocusedColumn: MarkdownTable.Alignment {
        table.alignments.indices.contains(focus.column) ? table.alignments[focus.column] : .none
    }

    func deleteRow() {
        guard canDeleteRow else { return }
        table.removeRow(at: focus.row - 1)
        focus.row = min(focus.row, table.rows.count)
    }

    func deleteColumn() {
        guard canDeleteColumn else { return }
        table.removeColumn(at: focus.column)
        focus.column = min(focus.column, table.columnCount - 1)
    }
}

/// The table of a note as a grid of text fields in a sheet. "Fertig" gives the table back; the note holds it as Markdown text.
/// The columns share the width down to 96 pt each, wider tables scroll sideways.
struct TableEditorSheet: View {
    let onCancel: () -> Void
    let onDone: (MarkdownTable) -> Void

    @State private var model: TableEditorModel
    @FocusState private var focusedCell: Cell?

    private struct Cell: Hashable {
        let row: Int
        let column: Int
    }

    /// The narrowest a column gets, in points.
    static let minimumColumnWidth: CGFloat = 96

    init(table: MarkdownTable, onCancel: @escaping () -> Void, onDone: @escaping (MarkdownTable) -> Void) {
        self.onCancel = onCancel
        self.onDone = onDone
        _model = State(initialValue: TableEditorModel(table: table))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let columnWidth = Self.columnWidth(columns: model.table.columnCount, available: proxy.size.width)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        ScrollView(.horizontal) { grid(columnWidth: columnWidth) }
                        Text("Die erste Zeile ist die Kopfzeile. In der Notiz steht die Tabelle als Markdown-Text.")
                            .font(.footnote).foregroundStyle(.secondaryText).padding(.horizontal, 16)
                    }
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Tabelle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { onDone(model.table) }.accessibilityIdentifier(AccessibilityID.NoteEditor.tableDone)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bar }
            .onAppear { focusedCell = Cell(row: model.focus.row, column: model.focus.column) }
            // The model moves the cursor (Weiter, a new row); a tap on a cell moves it the other way.
            .onChange(of: Cell(row: model.focus.row, column: model.focus.column)) { _, cell in
                if focusedCell != cell { focusedCell = cell }
            }
            .onChange(of: focusedCell) { _, cell in
                if let cell { model.focus = (cell.row, cell.column) }
            }
        }
    }

    /// The width of a column: the columns share the available width, but none gets narrower than the minimum.
    static func columnWidth(columns: Int, available: CGFloat) -> CGFloat {
        max(minimumColumnWidth, (available - 32) / CGFloat(max(columns, 1)))
    }

    private func grid(columnWidth: CGFloat) -> some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<model.rowCount, id: \.self) { row in
                GridRow {
                    ForEach(0..<model.table.columnCount, id: \.self) { column in
                        cell(row: row, column: column).frame(width: columnWidth)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func cell(row: Int, column: Int) -> some View {
        let binding = Binding(get: { model.text(row: row, column: column) }, set: { model.setText($0, row: row, column: column) })
        return TextField("", text: binding)
            .font(row == 0 ? .body.weight(.semibold) : .body)
            .multilineTextAlignment(Self.textAlignment(model.table.alignments.indices.contains(column) ? model.table.alignments[column] : .none))
            .focused($focusedCell, equals: Cell(row: row, column: column))
            .submitLabel(.next)
            .onSubmit { model.advance() }
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .background(row == 0 ? Color(.secondarySystemFill) : Color.clear)
            .overlay(Rectangle().stroke(Color(.separator), lineWidth: 0.5))
            .accessibilityLabel(row == 0 ? String(localized: "Kopfzeile, Spalte \(column + 1)") : String(localized: "Zeile \(row), Spalte \(column + 1)"))
    }

    static func textAlignment(_ alignment: MarkdownTable.Alignment) -> TextAlignment {
        switch alignment {
        case .center: .center
        case .right: .trailing
        default: .leading
        }
    }

    // MARK: Bar above the keyboard

    /// The buttons fit side by side at the usual text sizes, with "Weiter" at the right; at larger sizes the bar scrolls sideways
    /// like the bar of the note editor instead of clipping its buttons.
    private var bar: some View {
        ViewThatFits(in: .horizontal) {
            barContent(fillsWidth: true)
            ScrollView(.horizontal, showsIndicators: false) { barContent(fillsWidth: false) }
        }
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func barContent(fillsWidth: Bool) -> some View {
        HStack(spacing: 0) {
            Button { model.addRow() } label: { Label("Zeile", systemImage: "plus").frame(minHeight: 44).padding(.horizontal, 8).contentShape(Rectangle()) }
            Button { model.addColumn() } label: { Label("Spalte", systemImage: "plus").frame(minHeight: 44).padding(.horizontal, 8).contentShape(Rectangle()) }
                .disabled(!model.canAddColumn)
            Menu {
                Button { model.insertRowAbove() } label: { Label("Zeile darüber einfügen", systemImage: "arrow.up.to.line") }
                    .disabled(!model.canInsertRowAbove)
                Button { model.insertColumnLeft() } label: { Label("Spalte links einfügen", systemImage: "arrow.left.to.line") }
                    .disabled(!model.canAddColumn)
                Button { model.moveRowUp() } label: { Label("Zeile nach oben", systemImage: "arrow.up") }.disabled(!model.canMoveRowUp)
                Button { model.moveRowDown() } label: { Label("Zeile nach unten", systemImage: "arrow.down") }.disabled(!model.canMoveRowDown)
                Menu("Ausrichtung") {
                    Picker("Ausrichtung", selection: Binding(get: { model.alignmentOfFocusedColumn }, set: { model.setAlignment($0) })) {
                        Text("Links").tag(MarkdownTable.Alignment.left)
                        Text("Zentriert").tag(MarkdownTable.Alignment.center)
                        Text("Rechts").tag(MarkdownTable.Alignment.right)
                        Text("Keine").tag(MarkdownTable.Alignment.none)
                    }
                }
                Button(role: .destructive) { model.deleteRow() } label: { Label("Zeile löschen", systemImage: "trash") }.disabled(!model.canDeleteRow)
                Button(role: .destructive) { model.deleteColumn() } label: { Label("Spalte löschen", systemImage: "trash") }.disabled(!model.canDeleteColumn)
            } label: {
                Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Mehr")
            if fillsWidth { Spacer(minLength: 0) }
            Button { model.advance() } label: { Label("Weiter", systemImage: "arrow.right.to.line").frame(minHeight: 44).padding(.horizontal, 8).contentShape(Rectangle()) }
        }
        .padding(.horizontal, 8)
    }
}
