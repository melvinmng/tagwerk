import SwiftUI
import TagwerkCore

/// Settings → Notizen: the order of the note lists and the import from Notion.
struct NotesSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isImporting = false

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                Picker("Sortieren nach", selection: $settings.noteSortOrder) {
                    ForEach(NoteSortOrder.allCases, id: \.self) { Text(Self.sortName($0)).tag($0) }
                }
                Picker("Richtung", selection: $settings.noteSortAscending) {
                    let names = NotesListView.directionNames(for: settings.noteSortOrder)
                    Text(names.standard).tag(false)
                    Text(names.reversed).tag(true)
                }
                Toggle("Nach Datum gruppieren", isOn: $settings.noteGroupsByDate)
                    .disabled(settings.noteSortOrder == .title)
            } footer: {
                Text("Angeheftete Notizen stehen immer oben. Die Wahl gilt für alle Ordner. Die Tagesstart- und Tagesabschluss-Einträge und das Dream Log bleiben nach Tag sortiert.")
            }
            Section {
                Button("Aus Notion importieren") { isImporting = true }
            } header: {
                Text("Import")
            } footer: {
                Text("Liest einen entpackten Notion-Export. Nichts davon verlässt dein iPhone.")
            }
        }
        .navigationTitle("Notizen")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isImporting) {
            NotionImportView(onShowFolder: showImportedFolder)
        }
    }

    /// After "Zum Tagebuch" / "Zu Bible Study": the list of the folder in the tab "Aufgaben".
    private func showImportedFolder(_ target: NotionImportTarget) {
        let store = environment.notes
        let folder = target == .journal ? store.ensureJournalFolder() : store.folder(role: .bibleStudy)
        if let folder { environment.showNotes(.folder(folder.id)) }
    }

    static func sortName(_ order: NoteSortOrder) -> String {
        switch order {
        case .modified: String(localized: "Bearbeitet")
        case .created: String(localized: "Erstellt")
        case .title: String(localized: "Titel")
        }
    }
}
