import SwiftUI
import TagwerkCore
import UniformTypeIdentifiers

/// Settings → Datensicherung: a status card on top, then back up into a file, restore from one, and the automatic backup into a
/// chosen folder.
struct BackupSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var document: BackupDocument?
    @State private var isExporting = false
    @State private var isChoosingFile = false
    @State private var isChoosingFolder = false
    @State private var pendingRestore: BackupService.Inspection?
    @State private var alertText: String?
    /// Number and size of the own files in the backup folder; read when the page opens and after a backup.
    @State private var folderSummary: (count: Int, bytes: Int)?

    var body: some View {
        @Bindable var settings = environment.settings
        let service = environment.backup
        let status = service.status
        Form {
            Section {
                StatusCard(status: status, folderName: service.folderName, summary: folderSummary,
                           includesPrivate: settings.backupIncludesPrivateNotes)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                Button { makeBackup(service) } label: { Label("Jetzt sichern", systemImage: "square.and.arrow.up") }
                Button { isChoosingFile = true } label: { Label("Wiederherstellen …", systemImage: "arrow.counterclockwise") }
            }

            Section {
                Toggle(isOn: $settings.autoBackupEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatisch sichern")
                        Text("Täglich beim Verlassen der App, die letzten \(BackupRules.keptFiles) bleiben")
                            .font(.footnote).foregroundStyle(.secondaryText)
                    }
                }
                Button { isChoosingFolder = true } label: {
                    LabeledContent("Sicherungsordner", value: service.folderName ?? String(localized: "Nicht gewählt"))
                }
                .tint(.primary)
            } header: {
                Text("Automatisch")
            } footer: {
                Text("Andere Dateien im Ordner rührt Tagwerk nicht an. Gelöscht werden nur ältere Dateien mit dem Namen „Tagwerk-Sicherung-…“.")
            }

            Section {
                Toggle("Tagebuch und Bible Study einschließen", isOn: $settings.backupIncludesPrivateNotes)
                NavigationLink { BackupCoverageView() } label: { Text("Was wird gesichert?") }
                if let text = Self.attachmentsText(service.attachmentSummary) {
                    LabeledContent("Anhänge in Notizen", value: text)
                }
            } header: {
                Text("Inhalt")
            } footer: {
                Text("Gilt für „Jetzt sichern“ und die automatische Sicherung. Ohne diese Inhalte bleiben beim Wiederherstellen vorhandene Einträge in Tagebuch und Bible Study erhalten. Die Sicherung ist nicht verschlüsselt und liegt dort, wo du sie speicherst.")
            }

            Section {
                EmptyView()
            } header: {
                Text("Vor dem Wiederherstellen")
            } footer: {
                Text("Vor jedem Wiederherstellen legt Tagwerk eine Kopie des bisherigen Stands im Ordner „Sicherungen“ in den Dokumenten von Tagwerk an (Dateien-App › Auf meinem iPhone › Tagwerk).")
            }
        }
        .navigationTitle("Datensicherung")
        .navigationBarTitleDisplayMode(.inline)
        .task { refreshFolderSummary(service) }
        .onChange(of: settings.backupFolderBookmark) { refreshFolderSummary(service) }
        .onChange(of: settings.lastAutoBackupAt) { refreshFolderSummary(service) }
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
        .sheet(isPresented: restoreBinding) {
            if let pendingRestore {
                RestoreComparisonSheet(inspection: pendingRestore, device: service.currentCounts(),
                                       onReplace: { restore(service) }, onCancel: { self.pendingRestore = nil })
                    .presentationDetents([.large])
            }
        }
        .alert(alertText ?? "", isPresented: alertBinding) { Button("OK", role: .cancel) {} }
    }

    private func refreshFolderSummary(_ service: BackupService) {
        folderSummary = service.folderSummary()
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

/// The card on top of the page: whether, when, where to and with which content the backup ran. The warning state is orange and
/// carries a symbol and text, never colour alone.
private struct StatusCard: View {
    let status: BackupStatus
    let folderName: String?
    let summary: (count: Int, bytes: Int)?
    let includesPrivate: Bool
    private let now = Date()

    var body: some View {
        let calendar = Calendar.tagwerk
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(BackupStatusText.headline(status))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(status.isWarning ? Color.orangeText : status == .off ? Color.secondaryText : Color.greenText)
            } icon: {
                Image(systemName: symbolName).foregroundStyle(status.isWarning ? Color.orange : status == .off ? Color.secondaryText : Color.green)
            }
            if let title = BackupStatusText.title(status, now: now, calendar: calendar) {
                Text(title).font(.title3.weight(.semibold))
            }
            Text(BackupStatusText.detail(status, folderName: folderName, summary: summary, includesPrivate: includesPrivate))
                .font(.footnote).foregroundStyle(.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(status.isWarning ? Color.orange.opacity(0.14) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("backup.statusCard")
    }

    private var symbolName: String {
        switch status {
        case .backedUp: "checkmark.circle.fill"
        case .off: "pause.circle"
        case .overdue, .folderMissing, .failed: "exclamationmark.triangle.fill"
        }
    }
}
