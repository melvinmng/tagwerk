import Foundation
import Observation
import TagwerkCore

/// What an import reads from the unpacked Notion export: the journal "Tagebuch mit Gott" or the Bible Study notes.
enum NotionImportTarget: Hashable, CaseIterable {
    case journal
    case bibleStudy
}

/// Reads the folder of an unpacked Notion export, shows what an import would do and then stores it. Only a folder is read
/// (there is no ZIP reader); the text of the files never leaves the device.
@MainActor
@Observable
final class NotionImportModel {
    /// What was found, ready to be stored.
    enum Payload: Equatable {
        case journal(NotionJournalPlan)
        case bibleStudy([NotionBibleNote])
    }

    struct Preview: Equatable {
        var payload: Payload
        var counts: NotionImportPreview
        var foundCount: Int
        var firstDay: PlanDay?
        var lastDay: PlanDay?
        /// Journal: pages without a usable date. Bible Study: pages whose title is not a book.
        var leftOutTitles: [String]

        var isBibleStudy: Bool {
            if case .bibleStudy = payload { return true }
            return false
        }
    }

    struct Summary: Equatable {
        var created = 0
        var appended = 0
        var skipped = 0
        var leftOutTitles: [String] = []
    }

    enum Phase: Equatable {
        case idle
        case reading
        case preview(Preview)
        case done(Summary)
        case failed(String)
    }

    var target: NotionImportTarget = .journal
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
        let target = self.target
        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<Payload, NotionExportReader.ReadError> in
            do {
                let files = try NotionExportReader.readFiles(in: url)
                switch target {
                case .journal:
                    return .success(.journal(NotionExportParser.journalPlan(in: files, calendar: calendar)))
                case .bibleStudy:
                    let sections = BibleStudyTemplate.importSections(locale: Locale(identifier: "de_DE"))
                    return .success(.bibleStudy(NotionExportParser.bibleStudyNotes(in: files, sections: sections)))
                }
            } catch let error as NotionExportReader.ReadError {
                return .failure(error)
            } catch {
                return .failure(.unreadable)
            }
        }.value
        switch outcome {
        case .failure(let error):
            phase = .failed(Self.message(for: error))
        case .success(let payload):
            phase = makePreview(payload, target: target)
        }
    }

    private func makePreview(_ payload: Payload, target: NotionImportTarget) -> Phase {
        let imported = store.importedSourceIDs
        switch payload {
        case .journal(let plan):
            guard plan.foundCount > 0 else {
                return .failed(String(localized: "Im gewählten Ordner wurden keine Einträge von „Tagebuch mit Gott“ gefunden. Wähle den entpackten Export (den Ordner mit den .md- und .csv-Dateien)."))
            }
            let counts = NotionImportPlanner.preview(entries: plan.entries, existingDayKeys: store.journalDayKeys, importedIDs: imported)
            return .preview(Preview(payload: payload, counts: counts, foundCount: plan.foundCount, firstDay: plan.firstDay,
                                    lastDay: plan.lastDay, leftOutTitles: plan.skipped.map(\.title)))
        case .bibleStudy(let pages):
            guard !pages.isEmpty else {
                return .failed(String(localized: "Im gewählten Ordner wurden keine Seiten von „Bible Studies“ gefunden. Wähle den entpackten Export (den Ordner mit den .md- und .csv-Dateien)."))
            }
            let existing = Set(store.notes(.all).filter { $0.kind == .bibleStudy }.compactMap(\.bookKey))
            let result = NotionImportPlanner.biblePreview(pages: pages, existingBookKeys: existing, importedIDs: imported)
            return .preview(Preview(payload: payload, counts: result.preview, foundCount: pages.count, firstDay: nil, lastDay: nil,
                                    leftOutTitles: result.unmatched))
        }
    }

    func runImport() {
        guard case .preview(let preview) = phase else { return }
        switch preview.payload {
        case .journal(let plan):
            let result = store.importJournal(plan.entries)
            phase = .done(Summary(created: result.created, appended: result.appended, skipped: result.skipped,
                                  leftOutTitles: plan.skipped.map(\.title)))
        case .bibleStudy(let pages):
            let result = store.importBibleNotes(pages)
            phase = .done(Summary(created: result.created, appended: result.appended, skipped: result.skipped,
                                  leftOutTitles: result.unmatched))
        }
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
