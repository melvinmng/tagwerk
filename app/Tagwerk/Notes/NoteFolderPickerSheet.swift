import SwiftUI
import TagwerkCore

/// A sheet with the folder tree to pick a destination for notes or for a folder. `nil` stands for "Notizen".
struct NoteFolderPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: NoteStore
    let title: LocalizedStringKey
    /// A folder that is being moved: it and its subfolders are not offered, and levels that would be too deep stay disabled.
    let movingFolderID: UUID?
    let currentFolderID: UUID?
    let onPick: (UUID?) -> Void

    init(store: NoteStore, title: LocalizedStringKey, movingFolderID: UUID? = nil, currentFolderID: UUID? = nil,
         onPick: @escaping (UUID?) -> Void) {
        self.store = store
        self.title = title
        self.movingFolderID = movingFolderID
        self.currentFolderID = currentFolderID
        self.onPick = onPick
    }

    var body: some View {
        let infos = store.folders().map(\.info)
        // Folders that only the routines fill (Tagesstart, Tagesabschluss, Dream Log) are no destination for notes.
        // Moving a folder has its own rules (`validateMove`), so they stay visible there, disabled.
        let nodes = NoteFolderRules.tree(infos).flatMap(\.flattened)
            .filter { movingFolderID != nil || $0.folder.role?.acceptsOwnNotes ?? true }
        NavigationStack {
            List {
                row(name: String(localized: "Notizen"), id: nil, depth: 1, isEnabled: true, symbol: "note.text")
                ForEach(nodes) { node in
                    row(name: node.folder.name, id: node.id, depth: node.depth, isEnabled: isEnabled(node.id, infos: infos),
                        symbol: NotesFoldersView.symbol(for: node.folder.role))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func isEnabled(_ id: UUID, infos: [NoteFolderInfo]) -> Bool {
        guard let movingFolderID else { return true }
        return (try? NoteFolderRules.validateMove(movingFolderID, to: id, in: infos)) != nil
    }

    private func row(name: String, id: UUID?, depth: Int, isEnabled: Bool, symbol: String) -> some View {
        Button {
            onPick(id)
            dismiss()
        } label: {
            HStack {
                Label(name, systemImage: symbol)
                Spacer()
                if id == currentFolderID { Image(systemName: "checkmark").foregroundStyle(.secondary) }
            }
            .padding(.leading, CGFloat(depth - 1) * 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
        .disabled(!isEnabled)
    }
}
