import SwiftUI
import TagwerkCore

/// A checkbox line of a Bible Study note that is about to become a task (BS5b).
struct CheckboxTaskDraft: Identifiable, Equatable {
    /// Position among all checkboxes of the note (`MarkdownText.checkboxTitle(at:in:)`).
    let index: Int
    let title: String
    var id: Int { index }
}

extension NoteEditorView {
    /// The menu of a long press on the page: the scan and drawing menus, and in a Bible Study note the menu of a checkbox line
    /// ("Als Aufgabe anlegen", "Abhaken"). The press lands on the box (`tagwerk-toggle:<index>`) or on the text of the line
    /// (`tagwerk-edit:<line>`).
    func pageMenu(for url: URL) -> UIMenu? {
        if let menu = attachmentMenu(for: url) { return menu }
        guard store.note(id: noteID)?.kind == .bibleStudy, let index = checkboxIndex(of: url),
              let title = MarkdownText.checkboxTitle(at: index, in: text) else { return nil }
        var actions: [UIAction] = []
        if !hasTaskMarker(at: index) {
            actions.append(UIAction(title: String(localized: "Als Aufgabe anlegen"), image: UIImage(systemName: "plus.circle")) { _ in
                checkboxTask = CheckboxTaskDraft(index: index, title: title)
            })
        }
        let isChecked = MarkdownText.isCheckboxChecked(at: index, in: text) ?? false
        actions.append(UIAction(title: isChecked ? String(localized: "Haken entfernen") : String(localized: "Abhaken"),
                                image: UIImage(systemName: isChecked ? "circle" : "checkmark.circle")) { _ in
            toggleCheckbox(index)
        })
        return UIMenu(children: actions)
    }

    /// The checkbox line at the cursor as a task draft ("Als Aufgabe" of the bar above the keyboard, #307); `nil` while the cursor
    /// stands in no checkbox line, in a line that is a task already, or without a cursor.
    func checkboxDraftAtCursor() -> CheckboxTaskDraft? {
        guard case .selection(let range)? = selection?.indices else { return nil }
        let offset = text.distance(from: text.startIndex, to: range.lowerBound)
        let line = text.prefix(offset).filter(\.isNewline).count + 1
        guard let index = MarkdownText.checkboxIndex(atLine: line, in: text), !hasTaskMarker(at: index),
              let title = MarkdownText.checkboxTitle(at: index, in: text), !title.isEmpty else { return nil }
        return CheckboxTaskDraft(index: index, title: title)
    }

    /// "Als Aufgabe" of the bar: saves the text first, so the line the draft points at is the one in the store, and asks for the task.
    func createTaskAtCursor() {
        guard let draft = checkboxDraftAtCursor() else { return }
        saveText()
        checkboxTask = draft
    }

    /// The task was created: the line gets the marker, saved like every other write of this page. A text that changed meanwhile
    /// and no longer has this title at the position is left alone.
    func markCheckboxAsTask(_ draft: CheckboxTaskDraft) {
        guard MarkdownText.checkboxTitle(at: draft.index, in: text) == draft.title else { return }
        text = MarkdownText.markingCheckboxAsTask(at: draft.index, in: text)
        saveText()
    }

    private func checkboxIndex(of url: URL) -> Int? {
        if url.scheme?.lowercased() == NoteHTMLRenderer.toggleScheme {
            return Int(url.absoluteString.dropFirst(NoteHTMLRenderer.toggleScheme.count + 1))
        }
        if let line = NoteEditTarget.parse(url.absoluteString)?.line { return MarkdownText.checkboxIndex(atLine: line, in: text) }
        return nil
    }

    /// Whether marking the line would change nothing, because it already ends with the marker.
    private func hasTaskMarker(at index: Int) -> Bool {
        MarkdownText.markingCheckboxAsTask(at: index, in: text) == text
    }
}

/// "Als Aufgabe anlegen" on a checkbox line: first the hint that the title leaves the private note, then the sheet "Neue Aufgabe"
/// with the title. Nothing is created without the sheet's own button, and the line is marked only after the task exists.
struct CheckboxTaskModifier: ViewModifier {
    @Binding var draft: CheckboxTaskDraft?
    let model: TaskListModel
    let onCreated: (CheckboxTaskDraft) -> Void
    @State private var creating: CheckboxTaskDraft?

    func body(content: Content) -> some View {
        content
            .alert("Als Aufgabe anlegen", isPresented: Binding(get: { draft != nil }, set: { if !$0 { draft = nil } }), presenting: draft) { item in
                Button("Weiter") { creating = item }
                Button("Abbrechen", role: .cancel) {}
            } message: { _ in
                Text("Der Titel wird eine normale Aufgabe und ist dann nicht mehr privat (Erinnerungen, Assistent).")
            }
            .sheet(item: $creating) { item in
                NewTaskSheet(model: model, prefilledTitle: item.title, onCreated: { onCreated(item) })
            }
    }
}

extension View {
    func checkboxTask(_ draft: Binding<CheckboxTaskDraft?>, model: TaskListModel, onCreated: @escaping (CheckboxTaskDraft) -> Void) -> some View {
        modifier(CheckboxTaskModifier(draft: draft, model: model, onCreated: onCreated))
    }
}
