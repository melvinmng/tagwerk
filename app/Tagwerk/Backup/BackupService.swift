import Foundation
import Observation
import SwiftData
import TagwerkCore

/// The data backup (#158): writes all own data into one JSON file, reads such a file back and, on request, writes a file into a
/// folder the user chose. Nothing here talks to a server. Secrets (Keychain: GitHub and ChatGPT sign-in) are not in the
/// database and never in the file.
@MainActor
@Observable
final class BackupService {
    /// The first lines of a file. Read on their own, so a file of a newer version is refused before its content is decoded.
    struct Header: Codable, Equatable {
        var format: String
        var schemaVersion: Int
        var appVersion: String
        /// ISO 8601, for people reading the file.
        var createdAt: String
        /// Whether journal and Bible Study content is in the file.
        var includesPrivateNotes: Bool
    }

    struct Envelope: Codable, Equatable {
        var format: String
        var schemaVersion: Int
        var appVersion: String
        var createdAt: String
        var includesPrivateNotes: Bool
        var entities: BackupEntities
    }

    /// A file that was read and checked, before anything is replaced.
    struct Inspection: Equatable {
        var header: Header
        var entities: BackupEntities
        var tasks: Int { entities.localTasks.count }
        var notes: Int { entities.notes.count }
        var habits: Int { entities.habits.count }
        var meals: Int { entities.meals.count }
    }

    enum BackupError: Error, Equatable {
        case notABackup
        case newerVersion(Int)
        case unreadable
        case noFolder
        case folderUnavailable
        case writeFailed
        case restoreFailed
    }

    /// What the last automatic run did, for the settings page.
    enum Outcome: Equatable {
        case notDue
        case disabled
        case written(String)
        case failed(BackupError)
    }

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let appVersion: String
    /// Runs after a restore, also after a failed one that put the old state back (the app files the notes into their folders).
    @ObservationIgnored private let afterRestore: @MainActor () -> Void
    /// The bytes of the notes' attachments; without it a backup holds none and a restore leaves them alone.
    @ObservationIgnored private let attachments: NoteAttachmentStore?
    /// Whether the device can check its owner (a passcode is set). A restore that brings locked notes turns the protection on
    /// only when it can; the settings of the lock are not part of a backup.
    @ObservationIgnored private let canProtectNotes: @MainActor () -> Bool

    init(context: ModelContext, settings: AppSettings, calendar: Calendar = .tagwerk, appVersion: String? = nil,
         now: @escaping () -> Date = Date.init, attachments: NoteAttachmentStore? = nil,
         canProtectNotes: @escaping @MainActor () -> Bool = { false }, afterRestore: @escaping @MainActor () -> Void = {}) {
        self.canProtectNotes = canProtectNotes
        self.afterRestore = afterRestore
        self.attachments = attachments
        self.context = context
        self.settings = settings
        self.calendar = calendar
        self.now = now
        self.appVersion = appVersion ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
    }

    /// Number and total size of the attachments a full backup holds (for the backup page).
    var attachmentSummary: (count: Int, bytes: Int)? { attachments?.summary }

    // MARK: Writing a backup

    var suggestedFileName: String { BackupRules.fileName(for: now(), calendar: calendar) }

    /// The whole backup as JSON. `includePrivate` defaults to the setting "Tagebuch und Bible Study einschließen".
    func makeBackupData(includePrivate: Bool? = nil) throws -> Data {
        let includePrivate = includePrivate ?? settings.backupIncludesPrivateNotes
        let envelope = Envelope(format: BackupRules.format, schemaVersion: BackupRules.schemaVersion, appVersion: appVersion,
                                createdAt: ISO8601DateFormatter().string(from: now()), includesPrivateNotes: includePrivate,
                                entities: BackupEntities(collecting: context, settings: settings, includePrivate: includePrivate,
                                                         attachments: attachments))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    // MARK: Reading a backup

    /// Checks a file and decodes it. Nothing is changed. Throws `.notABackup` for other files and `.newerVersion` for files that a
    /// newer version of the app wrote.
    func inspect(_ data: Data) throws -> Inspection {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else { throw BackupError.notABackup }
        switch BackupRules.compatibility(format: header.format, schemaVersion: header.schemaVersion) {
        case .notABackup: throw BackupError.notABackup
        case .newerVersion(let version): throw BackupError.newerVersion(version)
        case .readable: break
        }
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { throw BackupError.unreadable }
        return Inspection(header: header, entities: envelope.entities)
    }

    /// Replaces the data of everything in the file. Call `writeSafetyCopy` first and pass its content as `safetyCopy`:
    /// the replacement saves twice (old unique keys must be gone first), so a failure after the first save would leave
    /// the store without data. In that case the previous state comes back from the safety copy and `.restoreFailed` is thrown.
    func restore(_ inspection: Inspection, recoveringFrom safetyCopy: Data? = nil) throws {
        do {
            try inspection.entities.restore(into: context, settings: settings, replacePrivate: inspection.header.includesPrivateNotes,
                                              attachments: attachments)
            // Locked notes on a device without the protection would be open until the switch is found: the safe state is on.
            if inspection.entities.notes.contains(where: { $0.isLocked == true }), canProtectNotes() {
                settings.noteLockEnabled = true
                try? context.save()
            }
            afterRestore()
        } catch {
            context.rollback()
            if let safetyCopy, let previous = try? inspect(safetyCopy) {
                try? previous.entities.restore(into: context, settings: settings, replacePrivate: true, attachments: attachments)
            }
            afterRestore()
            throw BackupError.restoreFailed
        }
    }

    /// A copy of the current state in `directory` (the app documents), made before a restore replaces anything. It always holds
    /// everything, journal and Bible Study included.
    @discardableResult
    func writeSafetyCopy(into directory: URL) throws -> URL {
        let data = try makeBackupData(includePrivate: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(BackupRules.safetyCopyName(for: now(), calendar: calendar))
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// The folder for safety copies: "Sicherungen" in the app documents.
    static var safetyCopyDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Sicherungen", isDirectory: true)
    }

    // MARK: Automatic backup

    /// Remembers the folder the user picked, as a bookmark that survives restarts.
    func chooseFolder(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        settings.backupFolderBookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        settings.lastBackupError = nil
        try? context.save()
    }

    var folderName: String? {
        guard let bookmark = settings.backupFolderBookmark else { return nil }
        var stale = false
        return (try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))?.lastPathComponent
    }

    func clearFolder() {
        settings.backupFolderBookmark = nil
        settings.lastBackupError = nil
        try? context.save()
    }

    /// Writes a backup into the chosen folder when the switch is on and the last one is a day old, then removes the files beyond
    /// the newest seven (only files with the own name pattern). Errors land in `settings.lastBackupError` and block nothing.
    @discardableResult
    func runAutomaticBackupIfDue() -> Outcome {
        guard settings.autoBackupEnabled else { return .disabled }
        guard BackupRules.isDue(lastBackup: settings.lastAutoBackupAt, now: now()) else { return .notDue }
        return runAutomaticBackup()
    }

    @discardableResult
    func runAutomaticBackup() -> Outcome {
        do {
            let name = try writeToChosenFolder()
            settings.lastAutoBackupAt = now()
            settings.lastBackupError = nil
            try? context.save()
            return .written(name)
        } catch let error as BackupError {
            settings.lastBackupError = Self.message(for: error)
            try? context.save()
            return .failed(error)
        } catch {
            settings.lastBackupError = Self.message(for: .writeFailed)
            try? context.save()
            return .failed(.writeFailed)
        }
    }

    private func writeToChosenFolder() throws -> String {
        guard let bookmark = settings.backupFolderBookmark else { throw BackupError.noFolder }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            throw BackupError.folderUnavailable
        }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let data = try makeBackupData()
        let name = suggestedFileName
        do {
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        } catch {
            throw BackupError.writeFailed
        }
        if stale, let fresh = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            settings.backupFolderBookmark = fresh
        }
        // Only files with the own name pattern are ever removed.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for old in BackupRules.filesToDelete(names: names) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(old))
        }
        return name
    }

    // MARK: Texts

    static func message(for error: BackupError) -> String {
        switch error {
        case .notABackup: String(localized: "Das ist keine Tagwerk-Sicherung.")
        case .newerVersion: String(localized: "Diese Sicherung stammt aus einer neueren Version von Tagwerk. Aktualisiere die App und versuche es noch einmal.")
        case .unreadable: String(localized: "Die Sicherung lässt sich nicht lesen.")
        case .noFolder: String(localized: "Wähle zuerst einen Ordner für die automatische Sicherung.")
        case .folderUnavailable: String(localized: "Der gewählte Ordner ist nicht mehr erreichbar. Wähle ihn neu.")
        case .writeFailed: String(localized: "Die Sicherung ließ sich nicht schreiben. Prüfe den Ordner und den freien Speicher.")
        case .restoreFailed: String(localized: "Die Sicherung ließ sich nicht wiederherstellen. Der vorherige Stand wurde zurückgeholt; eine Kopie liegt im Ordner „Sicherungen“ in den Dokumenten von Tagwerk.")
        }
    }
}
