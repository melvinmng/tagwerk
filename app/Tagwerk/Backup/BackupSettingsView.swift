import SwiftUI
import TagwerkCore
import UniformTypeIdentifiers

/// Settings → Datensicherung: back up into a file, restore from one, and the automatic backup into a chosen folder.
struct BackupSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var document: BackupDocument?
    @State private var isExporting = false
    @State private var isChoosingFile = false
    @State private var isChoosingFolder = false
    @State private var pendingRestore: BackupService.Inspection?
    @State private var alertText: String?

    var body: some View {
        @Bindable var settings = environment.settings
        let service = environment.backup
        Form {
            Section {
                Button { makeBackup(service) } label: { Label("Jetzt sichern", systemImage: "square.and.arrow.up") }
                Button { isChoosingFile = true } label: { Label("Wiederherstellen …", systemImage: "arrow.counterclockwise") }
                if let text = Self.attachmentsText(service.attachmentSummary) {
                    LabeledContent("Anhänge in Notizen", value: text)
                }
            } footer: {
                Text("Die Sicherung ist eine einzelne Datei mit allen eigenen Daten, auch den Bildern und Dateien in Notizen. Sie ist nicht verschlüsselt und liegt dort, wo du sie speicherst, zum Beispiel in iCloud Drive. Anmeldedaten für GitHub und ChatGPT sind nie darin.")
            }

            if environment.notes.lockedCount > 0 {
                Section {
                    LabeledContent("Gesperrte Notizen · \(environment.notes.lockedCount)", value: Self.lockedNotesValue(encrypted: false))
                } footer: {
                    Text("Die Sperre schützt vor Mitlesen in Tagwerk, nicht die Sicherungsdatei. Bewahre die Datei an einem geschützten Ort auf.")
                }
            }

            Section {
                Toggle("Tagebuch und Bible Study einschließen", isOn: $settings.backupIncludesPrivateNotes)
            } footer: {
                Text("Gilt für „Jetzt sichern“ und die automatische Sicherung. Ohne diese Inhalte bleiben beim Wiederherstellen vorhandene Einträge in Tagebuch und Bible Study erhalten.")
            }

            Section {
                Toggle("Automatisch sichern", isOn: $settings.autoBackupEnabled)
                Button { isChoosingFolder = true } label: {
                    LabeledContent("Sicherungsordner", value: service.folderName ?? String(localized: "Nicht gewählt"))
                }
                .tint(.primary)
                LabeledContent("Letzte Sicherung", value: Self.lastBackupText(settings.lastAutoBackupAt))
                if let error = settings.lastBackupError {
                    Text(error).font(.footnote).foregroundStyle(.redText)
                }
            } header: {
                Text("Automatische Sicherung")
            } footer: {
                Text("Wähle einen Ordner, zum Beispiel in iCloud Drive. Beim Wechsel in den Hintergrund sichert Tagwerk, wenn die letzte Sicherung älter als 24 Stunden ist. Die letzten \(BackupRules.keptFiles) Dateien bleiben, ältere mit dem Namen „Tagwerk-Sicherung-…“ werden gelöscht. Andere Dateien im Ordner rührt Tagwerk nicht an.")
            }

            Section {
                EmptyView()
            } footer: {
                Text("Nicht gesichert: der Chatverlauf mit dem Assistenten und Zwischenspeicher, die Tagwerk neu lädt. Beim Wiederherstellen werden alle gesicherten Daten ersetzt. Angaben, die an dieses Gerät gebunden sind (Kalender, Erinnerungslisten, Einkaufsliste), werden übernommen; fehlen sie auf dem Gerät, verhält sich Tagwerk wie bei einer fehlenden Liste.")
            }
        }
        .navigationTitle("Datensicherung")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $isExporting, document: document, contentType: .json, defaultFilename: service.suggestedFileName) { result in
            if case .failure = result { alertText = BackupService.message(for: .writeFailed) }
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { inspect(url, service: service) }
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            do { try service.chooseFolder(url) } catch { alertText = BackupService.message(for: .folderUnavailable) }
        }
        .confirmationDialog("Alle Daten durch die Sicherung ersetzen?", isPresented: restoreBinding, titleVisibility: .visible) {
            Button("Wiederherstellen", role: .destructive) { restore(service) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            if let pendingRestore { Text(Self.summary(pendingRestore)) }
        }
        .alert(alertText ?? "", isPresented: alertBinding) { Button("OK", role: .cancel) {} }
    }

    /// The value of the row "Gesperrte Notizen": the file holds them as plain text unless the backup is encrypted.
    static func lockedNotesValue(encrypted: Bool) -> String {
        encrypted ? String(localized: "enthalten") : String(localized: "in der Datei unverschlüsselt enthalten")
    }

    /// "12 · 34 MB"; `nil` without attachments, so the row only shows when it matters for the file size.
    static func attachmentsText(_ summary: (count: Int, bytes: Int)?) -> String? {
        guard let summary, summary.count > 0 else { return nil }
        let size = summary.bytes.formatted(.byteCount(style: .file))
        return "\(summary.count) · \(size)"
    }

    // MARK: Actions

    private func makeBackup(_ service: BackupService) {
        do {
            document = BackupDocument(data: try service.makeBackupData())
            isExporting = true
        } catch {
            alertText = BackupService.message(for: .writeFailed)
        }
    }

    /// Reads the chosen file and asks before anything is replaced.
    private func inspect(_ url: URL, service: BackupService) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            alertText = BackupService.message(for: .unreadable)
            return
        }
        do {
            pendingRestore = try service.inspect(data)
        } catch let error as BackupService.BackupError {
            alertText = BackupService.message(for: error)
        } catch {
            alertText = BackupService.message(for: .unreadable)
        }
    }

    /// A copy of the current state goes into the app documents first, then the data is replaced.
    private func restore(_ service: BackupService) {
        guard let inspection = pendingRestore else { return }
        pendingRestore = nil
        let safetyCopy: Data
        do {
            let url = try service.writeSafetyCopy(into: BackupService.safetyCopyDirectory)
            safetyCopy = try Data(contentsOf: url)
        } catch {
            alertText = String(localized: "Die Kopie des bisherigen Stands ließ sich nicht schreiben. Es wurde nichts ersetzt.")
            return
        }
        do {
            try service.restore(inspection, recoveringFrom: safetyCopy)
        } catch {
            Task {
                await environment.reloadAfterRestore()
                alertText = BackupService.message(for: .restoreFailed)
            }
            return
        }
        Task {
            await environment.reloadAfterRestore()
            alertText = String(localized: "Wiederhergestellt. Eine Kopie des vorherigen Stands liegt im Ordner „Sicherungen“ in den Dokumenten von Tagwerk.")
        }
    }

    // MARK: Texts

    /// "Sicherung vom 19.11.2026: 12 Aufgaben, 5 Notizen, 3 Gewohnheiten, 2 Mahlzeiten."
    static func summary(_ inspection: BackupService.Inspection) -> String {
        let created = ISO8601DateFormatter().date(from: inspection.header.createdAt)
            .map { $0.formatted(date: .abbreviated, time: .shortened) } ?? inspection.header.createdAt
        let counts = String(localized: "\(inspection.tasks) Aufgaben, \(inspection.notes) Notizen, \(inspection.habits) Gewohnheiten, \(inspection.meals) Mahlzeiten")
        let privateText = inspection.header.includesPrivateNotes
            ? String(localized: "Mit Tagebuch und Bible Study.") : String(localized: "Ohne Tagebuch und Bible Study.")
        return String(localized: "Sicherung vom \(created): \(counts). \(privateText) Das ersetzt die gesicherten Daten auf diesem iPhone.")
    }

    static func lastBackupText(_ date: Date?) -> String {
        date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? String(localized: "Noch keine")
    }

    private var restoreBinding: Binding<Bool> {
        Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })
    }
}
