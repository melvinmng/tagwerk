import SwiftUI
import TagwerkCore
import UniformTypeIdentifiers

/// Settings → Datensicherung: a status card on top, then back up into a file, restore from one, and the automatic backup into a
/// chosen folder.
struct BackupSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var document: BackupDocument?
    @State private var exportFileName = ""
    @State private var isExporting = false
    @State private var isChoosingFile = false
    @State private var isChoosingFolder = false
    @State private var pendingRestore: BackupService.Inspection?
    @State private var alertText: String?
    /// An encrypted file that needs a typed password, and the password field of the alert.
    @State private var fileAwaitingPassword: Data?
    @State private var typedPassword = ""
    /// The one-time question when the automatic backup is switched on without a password.
    @State private var isAskingForPassword = false
    @State private var isShowingEncryption = false
    /// Number and size of the own files in the backup folder; read when the page opens and after a backup.
    @State private var folderSummary: (count: Int, bytes: Int)?
    /// Number of safety copies, for the row; read when the page opens and after a restore.
    @State private var safetyCopyCount: Int?

    var body: some View {
        let service = environment.backup
        Form {
            statusSection(service)
            actionsSection(service)
            automaticSection(service)
            contentSection(service)
            safetyCopySection(service)
        }
        .navigationTitle("Datensicherung")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isShowingEncryption) { BackupEncryptionView() }
        .task { refreshFolderSummary(service) }
        .onChange(of: environment.settings.backupFolderBookmark) { refreshFolderSummary(service) }
        .onChange(of: environment.settings.lastAutoBackupAt) { refreshFolderSummary(service) }
        .onChange(of: environment.settings.autoBackupEnabled) { askForPasswordOnce() }
        .fileExporter(isPresented: $isExporting, document: document, contentType: document?.contentType ?? .json,
                      defaultFilename: exportFileName) { result in
            if case .failure = result { alertText = BackupService.message(for: .writeFailed) }
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.json, .tagwerkBackup]) { result in
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
        .alert("Passwort der Sicherung", isPresented: passwordBinding) {
            SecureField("Passwort", text: $typedPassword)
            Button("Öffnen") { openWithTypedPassword(service) }
            Button("Abbrechen", role: .cancel) { fileAwaitingPassword = nil; typedPassword = "" }
        } message: {
            Text("Diese Sicherung ist verschlüsselt. Gib das Passwort ein, mit dem sie gesichert wurde.")
        }
        .alert("Passwort festlegen?", isPresented: $isAskingForPassword) {
            Button("Passwort festlegen") { isShowingEncryption = true }
            Button("Ohne Passwort sichern", role: .cancel) {}
        } message: {
            Text("Die Sicherung enthält dein Tagebuch unverschlüsselt.")
        }
        .alert(alertText ?? "", isPresented: alertBinding) { Button("OK", role: .cancel) {} }
    }

    // MARK: Sections

    private func statusSection(_ service: BackupService) -> some View {
        Section {
            StatusCard(status: service.status, folderName: service.folderName, summary: folderSummary,
                       includesPrivate: environment.settings.backupIncludesPrivateNotes,
                       encrypted: environment.settings.backupEncryptionEnabled)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private func actionsSection(_ service: BackupService) -> some View {
        Section {
            Button { makeBackup(service) } label: { Label("Jetzt sichern", systemImage: "square.and.arrow.up") }
            Button { isChoosingFile = true } label: { Label("Wiederherstellen …", systemImage: "arrow.counterclockwise") }
        }
    }

    private func automaticSection(_ service: BackupService) -> some View {
        @Bindable var settings = environment.settings
        return Section {
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
    }

    private func contentSection(_ service: BackupService) -> some View {
        @Bindable var settings = environment.settings
        return Section {
            Toggle("Tagebuch und Bible Study einschließen", isOn: $settings.backupIncludesPrivateNotes)
            if environment.notes.lockedCount > 0 {
                LabeledContent("Gesperrte Notizen · \(environment.notes.lockedCount)",
                               value: Self.lockedNotesValue(encrypted: settings.backupEncryptionEnabled))
            }
            NavigationLink { BackupEncryptionView() } label: {
                LabeledContent("Mit Passwort verschlüsseln",
                               value: settings.backupEncryptionEnabled ? String(localized: "Ein") : String(localized: "Aus"))
            }
            NavigationLink { BackupCoverageView() } label: { Text("Was wird gesichert?") }
            if let text = Self.attachmentsText(service.attachmentSummary) {
                LabeledContent("Anhänge in Notizen", value: text)
            }
        } header: {
            Text("Inhalt")
        } footer: {
            Text(contentFooter(encrypted: settings.backupEncryptionEnabled))
        }
    }

    /// The footer of "Inhalt"; with locked notes in a file that is not encrypted it adds that the lock does not protect the file.
    private func contentFooter(encrypted: Bool) -> String {
        var text = String(localized: "Gilt für „Jetzt sichern“ und die automatische Sicherung. Ohne diese Inhalte bleiben beim Wiederherstellen vorhandene Einträge in Tagebuch und Bible Study erhalten.")
        if environment.notes.lockedCount > 0, !encrypted {
            text += " " + String(localized: "Die Sperre schützt vor Mitlesen in Tagwerk, nicht die Sicherungsdatei. Bewahre die Datei an einem geschützten Ort auf.")
        }
        return text
    }

    private func safetyCopySection(_ service: BackupService) -> some View {
        Section {
            NavigationLink {
                SafetyCopiesView(onRestore: { data in open(data, password: nil, service: service) })
            } label: {
                LabeledContent("Sicherheitskopien", value: safetyCopyCount.map { "\($0)" } ?? "")
            }
        } header: {
            Text("Vor dem Wiederherstellen")
        } footer: {
            Text("Vor jedem Wiederherstellen legt Tagwerk eine Kopie des bisherigen Stands an. Sie liegt verborgen im Sicherungsordner, sonst nur auf diesem iPhone.")
        }
    }

    private func refreshFolderSummary(_ service: BackupService) {
        folderSummary = service.folderSummary()
        safetyCopyCount = service.safetyCopies().count
    }

    /// Switching the automatic backup on without a password asks once whether to set one; the question never comes back.
    private func askForPasswordOnce() {
        let settings = environment.settings
        guard settings.autoBackupEnabled, !settings.backupEncryptionEnabled, !settings.backupPlainHintShown,
              settings.backupIncludesPrivateNotes else { return }
        settings.backupPlainHintShown = true
        isAskingForPassword = true
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
            let file = try service.makeBackupFile()
            document = BackupDocument(data: file.data, encrypted: BackupCrypto.isEncrypted(file.data))
            exportFileName = file.fileName
            isExporting = true
        } catch let error as BackupService.BackupError {
            alertText = BackupService.message(for: error)
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
        open(data, password: nil, service: service)
    }

    /// Decodes the file. An encrypted file from another device asks for its password; a wrong one changes nothing.
    private func open(_ data: Data, password: String?, service: BackupService) {
        do {
            pendingRestore = try service.inspectFile(data, password: password)
            fileAwaitingPassword = nil
        } catch BackupService.BackupError.passwordRequired {
            fileAwaitingPassword = data
        } catch let error as BackupService.BackupError {
            fileAwaitingPassword = nil
            alertText = BackupService.message(for: error)
        } catch {
            fileAwaitingPassword = nil
            alertText = BackupService.message(for: .unreadable)
        }
    }

    private func openWithTypedPassword(_ service: BackupService) {
        guard let data = fileAwaitingPassword else { return }
        let password = typedPassword
        typedPassword = ""
        // The alert closes at once; it comes back only when the file still needs a password (nothing else holds it open while the
        // slow key derivation runs).
        fileAwaitingPassword = nil
        Task {
            do {
                pendingRestore = try await service.inspectFile(data, typedPassword: password)
            } catch let error as BackupService.BackupError {
                alertText = BackupService.message(for: error)
            } catch {
                alertText = BackupService.message(for: .unreadable)
            }
        }
    }

    /// A copy of the current state goes into the app documents first, then the data is replaced.
    private func restore(_ service: BackupService) {
        guard let inspection = pendingRestore else { return }
        pendingRestore = nil
        let safetyCopy: Data
        do {
            safetyCopy = try service.saveSafetyCopy()
        } catch BackupService.BackupError.keyMissing {
            alertText = BackupService.message(for: .keyMissing) + " " + String(localized: "Es wurde nichts ersetzt.")
            return
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
            refreshFolderSummary(service)
            alertText = String(localized: "Wiederhergestellt. Eine Kopie des vorherigen Stands steht unter „Sicherheitskopien“ in der Datensicherung.")
        }
    }

    // MARK: Texts

    static func lastBackupText(_ date: Date?) -> String {
        date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? String(localized: "Noch keine")
    }

    private var restoreBinding: Binding<Bool> {
        Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })
    }

    private var passwordBinding: Binding<Bool> {
        Binding(get: { fileAwaitingPassword != nil }, set: { if !$0 { typedPassword = "" } })
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
    var encrypted = false
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
            Text(BackupStatusText.detail(status, folderName: folderName, summary: summary, includesPrivate: includesPrivate, encrypted: encrypted))
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
