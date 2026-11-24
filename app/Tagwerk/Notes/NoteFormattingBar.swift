import SwiftUI
import TagwerkCore

/// The bar above the keyboard of the note editor: heading, bold, italic, list, checkbox, the insert menu and the
/// button that closes the keyboard. It scrolls sideways when the text size leaves no room for all of them.
struct NoteFormattingBar: View {
    let onFormat: (MarkdownFormatting.Action) -> Void
    let onHideKeyboard: () -> Void
    /// The insert menu; `nil` when the note has no attachment store.
    let attachments: AnyView?
    /// The cursor is in a table: the button for the table editor takes the place of the insert menu.
    var isInTable = false
    var onTable: () -> Void = {}
    /// "Als Aufgabe" (Bible Study notes only; `nil` shows no button): turns the checkbox line at the cursor into a task. Enabled
    /// only while the cursor stands in a checkbox line that is not a task yet.
    var onTask: (() -> Void)?
    var canCreateTask = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                button(.heading, symbol: "textformat.size", label: "Überschrift")
                button(.bold, symbol: "bold", label: "Fettschrift")
                button(.italic, symbol: "italic", label: "Kursiv")
                button(.list, symbol: "list.bullet", label: "Liste")
                button(.checkbox, symbol: "checklist", label: "Checkbox")
                if let onTask {
                    Button(action: onTask) {
                        Label("Als Aufgabe", systemImage: "plus.circle")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(!canCreateTask)
                    .accessibilityIdentifier(AccessibilityID.NoteEditor.checkboxTaskButton)
                }
                if isInTable {
                    Button(action: onTable) {
                        Image(systemName: "tablecells").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Tabelle bearbeiten")
                    .accessibilityIdentifier(AccessibilityID.NoteEditor.tableButton)
                } else if let attachments {
                    attachments.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                Button(action: onHideKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Tastatur ausblenden")
                .accessibilityIdentifier(AccessibilityID.Common.hideKeyboard)
            }
            .padding(.horizontal, 8)
        }
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        // A tap on the bar must not close the keyboard: the window-wide dismissal skips this area.
        .keepsKeyboardOnTap()
    }

    private func button(_ action: MarkdownFormatting.Action, symbol: String, label: LocalizedStringKey) -> some View {
        Button { onFormat(action) } label: {
            Image(systemName: symbol).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}
