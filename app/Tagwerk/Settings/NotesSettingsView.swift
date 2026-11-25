import SwiftUI
import TagwerkCore

/// Settings → Notizen: the order of the note lists, the lock of notes and private folders, and the import from Notion.
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
                    .foregroundStyle(.secondaryText)
            }
            lockSection
            Section {
                Button("Aus Notion importieren") { isImporting = true }
            } header: {
                Text("Import")
                    .foregroundStyle(.secondaryText)
            } footer: {
                Text("Liest einen entpackten Notion-Export. Nichts davon verlässt dein iPhone.")
                    .foregroundStyle(.secondaryText)
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

    // MARK: Lock

    private var lock: NoteLock { environment.noteLock }

    /// "Mit Face ID schützen" and its sibling for the private folders (NL1a).
    @ViewBuilder private var lockSection: some View {
        let enabled = Binding(get: { environment.settings.noteLockEnabled },
                              set: { value in Task { _ = await lock.setEnabled(value) } })
        let privateFolders = Binding(get: { environment.settings.noteLockPrivateFolders },
                                     set: { value in Task { _ = await lock.setLocksPrivateFolders(value) } })
        Section {
            Toggle(Self.protectTitle(lock.biometry), isOn: enabled)
                .disabled(!lock.canAuthenticate && !environment.settings.noteLockEnabled)
                .accessibilityIdentifier("notes.lock.enabled")
            Toggle("Private Ordner sperren", isOn: privateFolders)
                .disabled(!environment.settings.noteLockEnabled)
                .accessibilityIdentifier("notes.lock.privateFolders")
            NavigationLink {
                LockedNotesView()
            } label: {
                LabeledContent("Gesperrte Notizen", value: "\(environment.notes.lockedCount)")
            }
            .accessibilityIdentifier("notes.lock.list")
        } header: {
            Text("Sperre")
                .foregroundStyle(.secondaryText)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !lock.canAuthenticate {
                    Text("Richte zuerst einen Code für dein iPhone ein.").foregroundStyle(.secondaryText)
                } else {
                    Text("Gilt für gesperrte Notizen und private Ordner.").foregroundStyle(.secondaryText)
                }
                Text("Einmal entsperren öffnet alles Gesperrte, bis du Tagwerk verlässt. Private Ordner: \(privateFolderList).").foregroundStyle(.secondaryText)
            }
        }
        Section {
            Label("Verbirgt den Inhalt gesperrter Notizen und privater Ordner in Tagwerk.", systemImage: "eye.slash")
            Label("Bleibt auf dem iPhone: Gesperrte Notizen gehen nicht an ChatGPT. Entsperrt kann der Assistent sie lesen und ändern, bis du Tagwerk verlässt.", systemImage: "iphone")
            Label("Verschlüsselt nicht: Datenbank und Sicherung enthalten gesperrte Notizen im Klartext.", systemImage: "lock.open")
        } header: {
            Text("Was die Sperre tut")
                .foregroundStyle(.secondaryText)
        }
    }

    private var privateFolderList: String {
        NoteToolAccess.listText(NoteToolAccess(store: environment.notes).privateFolderNames())
    }

    /// The wording follows what the device offers first.
    static func protectTitle(_ biometry: DeviceBiometry) -> LocalizedStringKey {
        switch biometry {
        case .faceID: "Mit Face ID schützen"
        case .touchID: "Mit Touch ID schützen"
        case .opticID: "Mit Optic ID schützen"
        case .none: "Mit Gerätecode schützen"
        }
    }

    static func sortName(_ order: NoteSortOrder) -> String {
        switch order {
        case .modified: String(localized: "Bearbeitet")
        case .created: String(localized: "Erstellt")
        case .title: String(localized: "Titel")
        }
    }
}
