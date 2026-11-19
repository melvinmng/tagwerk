import Foundation
import Observation
import TagwerkCore

/// What an import reads from the unpacked Notion export: the journal "Tagebuch mit Gott" or the Bible Study notes.
enum NotionImportTarget: Hashable {
    case journal
}

/// Reads the folder of an unpacked Notion export, shows what an import would do and then stores it. Only a folder is read
/// (there is no ZIP reader); the text of the files never leaves the device.
@MainActor
@Observable
final class NotionImportModel {
    struct Preview: Equatable {
        var plan: NotionJournalPlan
        var counts: NotionImportPreview
    }

    enum Phase: Equatable {
        case idle
        case reading
        case preview(Preview)
        case done(NoteStore.ImportResult)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    @ObservationIgnored private let store: NoteStore
    @ObservationIgnored private let calendar: Calendar

    init(store: NoteStore, calendar: Calendar) {
        self.store = store
        self.calendar = calendar
    }

    /// Reads the chosen folder and builds the preview. `url` comes from the file importer; its security scope is opened here.
    func load(folder url: URL) async {
        phase = .reading
        let calendar = self.calendar
        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<NotionJournalPlan, NotionExportReader.ReadError> in
            do {
                let files = try NotionExportReader.readFiles(in: url)
                return .success(NotionExportParser.journalPlan(in: files, calendar: calendar))
            } catch let error as NotionExportReader.ReadError {
                return .failure(error)
            } catch {
                return .failure(.unreadable)
            }
        }.value
        switch outcome {
        case .failure(let error):
            phase = .failed(Self.message(for: error))
        case .success(let plan):
            guard plan.foundCount > 0 else {
                phase = .failed(String(localized: "Im gewählten Ordner wurden keine Einträge von „Tagebuch mit Gott“ gefunden. Wähle den entpackten Export (den Ordner mit den .md- und .csv-Dateien)."))
                return
            }
            let counts = NotionImportPlanner.preview(entries: plan.entries, existingDayKeys: store.journalDayKeys,
                                                    importedIDs: store.importedSourceIDs)
            phase = .preview(Preview(plan: plan, counts: counts))
        }
    }

    func runImport() {
        guard case .preview(let preview) = phase else { return }
        phase = .done(store.importJournal(preview.plan.entries))
    }

    func reset() { phase = .idle }

    static func message(for error: NotionExportReader.ReadError) -> String {
        switch error {
        case .unreadable: String(localized: "Der Ordner lässt sich nicht lesen.")
        case .tooManyFiles: String(localized: "Der Ordner enthält zu viele Dateien für einen Import.")
        case .zipSelected: String(localized: "Das ist eine ZIP-Datei. Entpacke den Export zuerst in der Dateien-App und wähle den entpackten Ordner.")
        }
    }
}

/// Reads the `.md` and `.csv` files of an export folder, including its subfolders.
enum NotionExportReader {
    enum ReadError: Error { case unreadable, tooManyFiles, zipSelected }

    static let maximumFiles = 20_000
    static let maximumFileBytes = 2_000_000

    /// Reads all Markdown and CSV files below `folder` as UTF-8 text. Files that cannot be read as text are skipped.
    nonisolated static func readFiles(in folder: URL) throws -> [NotionExportFile] {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        if folder.pathExtension.lowercased() == "zip" { throw ReadError.zipSelected }
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                              options: [.skipsHiddenFiles]) else { throw ReadError.unreadable }
        var files: [NotionExportFile] = []
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > maximumFiles { throw ReadError.tooManyFiles }
            let ext = url.pathExtension.lowercased()
            guard ext == "md" || ext == "csv" else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, (values?.fileSize ?? 0) <= maximumFileBytes,
                  let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { continue }
            files.append(NotionExportFile(name: url.lastPathComponent, content: text))
        }
        return files
    }
}
