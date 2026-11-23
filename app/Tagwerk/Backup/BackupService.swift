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
        /// The numbers of the comparison sheet: notes of the daily routine apart from journal and Bible Study.
        var counts: Counts {
            let privateNotes = entities.notes.filter { !(NoteKind(rawValue: $0.kindRaw) ?? .free).isInDefaultBackup }.count
            return Counts(tasks: tasks, notes: notes - privateNotes, habits: habits, meals: meals, privateNotes: privateNotes)
        }
    }

    /// What a file or this device holds, for the comparison before a restore. `privateNotes` are journal and Bible Study notes,
    /// the only notes a file may leave out (switch "Tagebuch und Bible Study einschließen").
    struct Counts: Equatable {
        var tasks: Int
        var notes: Int
        var habits: Int
        var meals: Int
        var privateNotes: Int
    }

    enum BackupError: Error, Equatable {
        case notABackup
        case newerVersion(Int)
        case unreadable
        case noFolder
        case folderUnavailable
        case writeFailed
        case restoreFailed
        /// The file is encrypted and neither the key of this device nor a password is available.
        case passwordRequired
        case wrongPassword
        /// Encryption is on, but the key is not in the Keychain of this iPhone (for example after a transfer to another device).
        case keyMissing
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
    /// The key of the backup password; see `BackupKeyStore`.
    @ObservationIgnored private let keyStore: BackupKeyStore
    /// Where safety copies go when no backup folder is reachable: the app documents, as before.
    @ObservationIgnored private let localSafetyCopyDirectory: URL
    /// Whether the device can check its owner (a passcode is set). A restore that brings locked notes turns the protection on
    /// only when it can; the settings of the lock are not part of a backup.
    @ObservationIgnored private let canProtectNotes: @MainActor () -> Bool

    init(context: ModelContext, settings: AppSettings, calendar: Calendar = .tagwerk, appVersion: String? = nil,
         now: @escaping () -> Date = Date.init, attachments: NoteAttachmentStore? = nil, keyStore: BackupKeyStore = BackupKeyStore(),
         safetyCopyDirectory: URL = BackupService.safetyCopyDirectory, canProtectNotes: @escaping @MainActor () -> Bool = { false },
         afterRestore: @escaping @MainActor () -> Void = {}) {
        self.keyStore = keyStore
        self.localSafetyCopyDirectory = safetyCopyDirectory
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

    /// What is on this device right now, counted like `Inspection` counts a file.
    func currentCounts() -> Counts {
        let notes = (try? context.fetch(FetchDescriptor<NoteRecord>())) ?? []
        let privateNotes = notes.filter { !$0.kind.isInDefaultBackup }.count
        return Counts(tasks: (try? context.fetchCount(FetchDescriptor<LocalTask>())) ?? 0, notes: notes.count - privateNotes,
                      habits: (try? context.fetchCount(FetchDescriptor<HabitRecord>())) ?? 0,
                      meals: (try? context.fetchCount(FetchDescriptor<MealRecord>())) ?? 0, privateNotes: privateNotes)
    }

    // MARK: Writing a backup

    var suggestedFileName: String { BackupRules.fileName(for: now(), calendar: calendar, encrypted: settings.backupEncryptionEnabled) }

    /// Whether the key of the backup password is in the Keychain of this iPhone.
    var hasKey: Bool { keyStore.material() != nil }

    /// The password is set: the key goes into the Keychain and encryption is on from now on. Older files keep the password they
    /// were written with.
    func enableEncryption(with material: BackupCrypto.KeyMaterial) throws {
        try keyStore.save(material)
        settings.backupEncryptionEnabled = true
        if settings.lastBackupError == Self.message(for: .keyMissing) { settings.lastBackupError = nil }
        try? context.save()
    }

    /// Removes the key and switches encryption off; files that exist stay as they are.
    func disableEncryption() throws {
        try keyStore.remove()
        settings.backupEncryptionEnabled = false
        if settings.lastBackupError == Self.message(for: .keyMissing) { settings.lastBackupError = nil }
        try? context.save()
    }

    /// The key for new files: `nil` while encryption is off; throws `.keyMissing` when it is on but the key is gone. A backup is
    /// never written unencrypted while the user asked for encryption.
    private func writingKey() throws -> BackupCrypto.KeyMaterial? {
        guard settings.backupEncryptionEnabled else { return nil }
        guard let material = keyStore.material() else { throw BackupError.keyMissing }
        return material
    }

    /// JSON or, with encryption on, the encrypted file, with the name that goes with it.
    func makeBackupFile(includePrivate: Bool? = nil) throws -> (data: Data, fileName: String) {
        let key = try writingKey()
        let plain = try makeBackupData(includePrivate: includePrivate)
        guard let key else { return (plain, BackupRules.fileName(for: now(), calendar: calendar)) }
        return (try BackupCrypto.encrypt(plain, with: key), BackupRules.fileName(for: now(), calendar: calendar, encrypted: true))
    }

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

    /// Like `inspect`, for a file that may be encrypted. An encrypted file opens with the key of this device when its salt matches,
    /// otherwise with `password`; without either `.passwordRequired` is thrown. A wrong password throws `.wrongPassword`; nothing
    /// is decrypted into the store, replaced or written then.
    func inspectFile(_ data: Data, password: String? = nil) throws -> Inspection {
        guard BackupCrypto.isEncrypted(data) else { return try inspect(data) }
        guard let header = BackupCrypto.header(of: data) else { throw BackupError.unreadable }
        if let key = deviceKey(for: header) { return try inspectEncrypted(data, key: key) }
        guard let password, !password.isEmpty else { throw BackupError.passwordRequired }
        return try inspectEncrypted(data, key: BackupCrypto.deriveKey(password: password, salt: header.salt, iterations: header.iterations))
    }

    /// Like `inspectFile(_:password:)` for a typed password, but the slow key derivation runs off the main actor.
    func inspectFile(_ data: Data, typedPassword: String) async throws -> Inspection {
        guard BackupCrypto.isEncrypted(data), let header = BackupCrypto.header(of: data), deviceKey(for: header) == nil, !typedPassword.isEmpty else {
            return try inspectFile(data, password: typedPassword)
        }
        let key = await Task.detached(priority: .userInitiated) {
            BackupCrypto.deriveKey(password: typedPassword, salt: header.salt, iterations: header.iterations)
        }.value
        return try inspectEncrypted(data, key: key)
    }

    /// The key of this device when its salt and iteration count are the ones of the file.
    private func deviceKey(for header: (salt: Data, iterations: Int)) -> Data? {
        guard let material = keyStore.material(), material.salt == header.salt, material.iterations == header.iterations else { return nil }
        return material.key
    }

    private func inspectEncrypted(_ data: Data, key: Data) throws -> Inspection {
        do {
            return try inspect(try BackupCrypto.decrypt(data, key: key))
        } catch let error as BackupCrypto.CryptoError {
            switch error {
            case .wrongPassword: throw BackupError.wrongPassword
            case .unsupportedVersion(let version): throw BackupError.newerVersion(version)
            case .damaged, .passwordTooShort: throw BackupError.unreadable
            }
        }
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
            if let safetyCopy, let previous = try? inspectFile(safetyCopy) {
                try? previous.entities.restore(into: context, settings: settings, replacePrivate: true, attachments: attachments)
            }
            afterRestore()
            throw BackupError.restoreFailed
        }
    }

    /// The whole current state for a safety copy: journal and Bible Study included, encrypted while encryption is on. Throws
    /// `.keyMissing` when encryption is on but the key is gone: a copy is never written in plain text then.
    func makeSafetyCopyData() throws -> Data {
        let key = try writingKey()
        let data = try makeBackupData(includePrivate: true)
        return try key.map { try BackupCrypto.encrypt(data, with: $0) } ?? data
    }

    /// A copy of the current state in `directory`, made before a restore replaces anything.
    @discardableResult
    func writeSafetyCopy(into directory: URL) throws -> URL {
        let data = try makeSafetyCopyData()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(BackupRules.safetyCopyName(for: now(), calendar: calendar, encrypted: BackupCrypto.isEncrypted(data)))
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Writes the safety copy of the current state into the hidden folder of the backup folder (or, without one, the app documents)
    /// and returns its content, so a failed restore can put the previous state back.
    func saveSafetyCopy() throws -> Data {
        let data = try makeSafetyCopyData()
        _ = try withSafetyCopies { try $0.write(data) }
        return data
    }

    func safetyCopies() -> [SafetyCopy] {
        withSafetyCopies { store in
            store.prune()
            return store.list()
        }
    }

    func safetyCopyData(_ copy: SafetyCopy) throws -> Data {
        try withSafetyCopies { try $0.data(of: copy) }
    }

    func deleteSafetyCopy(_ copy: SafetyCopy) {
        withSafetyCopies { $0.delete(copy) }
    }

    /// Whether safety copies go into the backup folder right now (otherwise they stay on this iPhone).
    var safetyCopiesAreInBackupFolder: Bool {
        withSafetyCopies { $0.storesInBackupFolder }
    }

    /// Runs `body` with a store for the safety copies. The hidden folder is `.Sicherheitskopien` in the backup folder; its security
    /// scope is open while `body` runs. Copies of the old visible folder move over as soon as the backup folder is reachable.
    private func withSafetyCopies<T>(_ body: (SafetyCopyStore) throws -> T) rethrows -> T {
        var folder: URL?
        var scopedURL: URL?
        if let bookmark = settings.backupFolderBookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                // The scope is stopped on this URL even when the folder turns out to be gone.
                if url.startAccessingSecurityScopedResource() { scopedURL = url }
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue { folder = url }
            }
        }
        defer { scopedURL?.stopAccessingSecurityScopedResource() }
        let store = SafetyCopyStore(localDirectory: localSafetyCopyDirectory,
                                    hiddenDirectory: folder?.appendingPathComponent(SafetyCopyStore.hiddenFolderName, isDirectory: true),
                                    now: now, calendar: calendar)
        store.adoptLegacyCopies(from: localSafetyCopyDirectory)
        return try body(store)
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

    /// Own backup files in the chosen folder (only names that follow the pattern of `BackupRules.isOwnFile`): their number and
    /// total size. `nil` without a folder or when the folder cannot be read.
    func folderSummary() -> (count: Int, bytes: Int)? {
        guard let bookmark = settings.backupFolderBookmark else { return nil }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        let own = names.filter(BackupRules.isOwnFile)
        let bytes = own.reduce(0) { total, name in
            let size = (try? folder.appendingPathComponent(name).resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + size
        }
        return (own.count, bytes)
    }

    /// The status of the automatic backup for the card on the backup page.
    var status: BackupStatus {
        BackupStatus.status(autoEnabled: settings.autoBackupEnabled, hasFolder: settings.backupFolderBookmark != nil,
                            lastBackup: settings.lastAutoBackupAt, lastError: settings.lastBackupError, now: now())
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
        let (data, name) = try makeBackupFile()
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
        case .passwordRequired: String(localized: "Diese Sicherung ist mit einem Passwort verschlüsselt.")
        case .wrongPassword: String(localized: "Das Passwort stimmt nicht. Es wurde nichts geändert.")
        case .keyMissing: String(localized: "Passwort erneut eingeben: Der Schlüssel fehlt auf diesem iPhone. Öffne „Mit Passwort verschlüsseln“.")
        case .restoreFailed: String(localized: "Die Sicherung ließ sich nicht wiederherstellen. Der vorherige Stand wurde zurückgeholt; eine Kopie steht unter „Sicherheitskopien“ in der Datensicherung.")
        }
    }
}
