import SwiftUI
import TagwerkCore

/// Settings → Datensicherung → "Sicherheitskopien": the copies Tagwerk made before a restore (DS7c). They are hidden in the
/// backup folder, so this list is the place to find them again.
struct SafetyCopiesView: View {
    @Environment(AppEnvironment.self) private var environment
    /// Opens the content of a copy in the comparison before a restore; the page that owns the restore flow handles it.
    let onRestore: (Data) -> Void
    @State private var copies: [SafetyCopy] = []
    @State private var isInBackupFolder = false
    @State private var document: BackupDocument?
    @State private var exportFileName = ""
    @State private var isExporting = false
    @State private var copyToDelete: SafetyCopy?
    @State private var alertText: String?

    var body: some View {
        let service = environment.backup
        List {
            Section {
                if copies.isEmpty {
                    Text("Noch keine Sicherheitskopien.").foregroundStyle(.secondaryText)
                }
                ForEach(copies) { copy in
                    row(copy, service: service)
                }
            } header: {
                Text(headerText).textCase(nil)
            } footer: {
                Text(locationText)
            }
        }
        .navigationTitle("Sicherheitskopien")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload(service) }
        .fileExporter(isPresented: $isExporting, document: document, contentType: document?.contentType ?? .json,
                      defaultFilename: exportFileName) { result in
            if case .failure = result { alertText = BackupService.message(for: .writeFailed) }
        }
        .confirmationDialog("Sicherheitskopie löschen?", isPresented: deleteBinding, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let copyToDelete { service.deleteSafetyCopy(copyToDelete) }
                copyToDelete = nil
                reload(service)
            }
            Button("Abbrechen", role: .cancel) { copyToDelete = nil }
        } message: {
            Text("Dieser Stand lässt sich danach nicht mehr zurückholen.")
        }
        .alert(alertText ?? "", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func row(_ copy: SafetyCopy, service: BackupService) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(copy.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text(detail(copy)).font(.footnote).foregroundStyle(.secondaryText)
            }
            Spacer(minLength: 8)
            Menu {
                Button { restore(copy, service: service) } label: { Label("Diesen Stand zurückholen", systemImage: "arrow.counterclockwise") }
                Button { export(copy, service: service) } label: { Label("Als Datei sichern", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { copyToDelete = copy } label: { Label("Löschen", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Aktionen für die Kopie vom \(copy.createdAt.formatted(date: .abbreviated, time: .shortened))"))
        }
        .accessibilityElement(children: .contain)
    }

    private var headerText: String {
        isInBackupFolder
            ? String(localized: "Vor jedem Wiederherstellen legt Tagwerk eine Kopie des bisherigen Stands an. Die letzten \(BackupRules.keptSafetyCopies) bleiben, höchstens \(BackupRules.safetyCopyRetentionDays) Tage. Sie enthalten immer auch Tagebuch und Bible Study.")
            : String(localized: "Vor jedem Wiederherstellen legt Tagwerk eine Kopie des bisherigen Stands an. Sie bleiben, bis du sie löschst, und enthalten immer auch Tagebuch und Bible Study.")
    }

    private func detail(_ copy: SafetyCopy) -> String {
        var parts = [String(localized: "Stand vor dem Wiederherstellen"), copy.bytes.formatted(.byteCount(style: .file))]
        // Only copies in the backup folder expire; the others stay until they are deleted here.
        if copy.isInBackupFolder { parts.append(String(localized: "Verbleibende Tage: \(copy.daysLeft)")) }
        if copy.isEncrypted { parts.append(String(localized: "verschlüsselt")) }
        return parts.joined(separator: " · ")
    }

    private var locationText: String {
        isInBackupFolder
            ? String(localized: "Die Kopien liegen verborgen im Sicherungsordner, im Unterordner „.Sicherheitskopien“. Die Dateien-App zeigt ihn nicht an.")
            : String(localized: "Kein Sicherungsordner gewählt. Die Kopien liegen nur auf diesem iPhone.")
    }

    // MARK: Actions

    private func reload(_ service: BackupService) {
        isInBackupFolder = service.safetyCopiesAreInBackupFolder
        copies = service.safetyCopies()
    }

    private func restore(_ copy: SafetyCopy, service: BackupService) {
        do {
            onRestore(try service.safetyCopyData(copy))
        } catch {
            alertText = String(localized: "Die Sicherheitskopie ließ sich nicht lesen. Der Sicherungsordner ist vielleicht nicht erreichbar.")
        }
    }

    private func export(_ copy: SafetyCopy, service: BackupService) {
        do {
            document = BackupDocument(data: try service.safetyCopyData(copy), encrypted: copy.isEncrypted)
            exportFileName = copy.id
            isExporting = true
        } catch {
            alertText = String(localized: "Die Sicherheitskopie ließ sich nicht lesen. Der Sicherungsordner ist vielleicht nicht erreichbar.")
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { copyToDelete != nil }, set: { if !$0 { copyToDelete = nil } })
    }
}
