import SwiftUI
import TagwerkCore

/// Settings → Notizen: the order of the note lists and the import from Notion.
struct NotesSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                Picker("Sortieren nach", selection: $settings.noteSortOrder) {
                    ForEach(NoteSortOrder.allCases, id: \.self) { Text(Self.sortName($0)).tag($0) }
                }
            } footer: {
                Text("Angeheftete Notizen stehen immer oben. Die Wahl gilt für alle Ordner.")
            }
            Section {
                NavigationLink("Aus Notion importieren") { NotionImportView() }
            } header: {
                Text("Import")
            } footer: {
                Text("Liest einen entpackten Notion-Export. Nichts davon verlässt dein iPhone.")
            }
        }
        .navigationTitle("Notizen")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func sortName(_ order: NoteSortOrder) -> String {
        switch order {
        case .modified: String(localized: "Bearbeitet")
        case .created: String(localized: "Erstellt")
        case .title: String(localized: "Titel")
        }
    }
}
