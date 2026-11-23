import Foundation
import TagwerkCore

/// One safety copy, the state of the data before a restore replaced it.
struct SafetyCopy: Identifiable, Equatable {
    /// The file name, unique per minute.
    let id: String
    let createdAt: Date
    let bytes: Int
    /// Days until the copy is deleted (30 for a new one).
    let daysLeft: Int
    /// Whether the copy lies in the hidden folder of the backup folder, otherwise in the app documents of this iPhone.
    let isInBackupFolder: Bool

    var isEncrypted: Bool { id.hasSuffix("." + BackupRules.encryptedFileExtension) }
}

/// Where the safety copies live and how many stay (DS7c). Copies go into the hidden folder ".Sicherheitskopien" of the backup folder
/// the user chose (the Files app and Finder hide folders that start with a dot), so no iCloud container and no entitlement is
/// needed. Without a reachable backup folder they stay in `localDirectory`, as before, and nothing is deleted. With one, the newest
/// three stay and none longer than 30 days. The caller holds the security scope of the backup folder while the store works.
@MainActor
final class SafetyCopyStore {
    static let hiddenFolderName = ".Sicherheitskopien"

    private let localDirectory: URL
    private let hiddenDirectory: URL?
    private let now: () -> Date
    private let calendar: Calendar
    private let fileManager = FileManager.default

    /// `hiddenDirectory` is `<backup folder>/.Sicherheitskopien`, resolved from the backup folder bookmark; `nil` without a reachable
    /// backup folder, then copies keep today's behaviour in `localDirectory`.
    init(localDirectory: URL, hiddenDirectory: URL?, now: @escaping () -> Date, calendar: Calendar) {
        self.localDirectory = localDirectory
        self.hiddenDirectory = hiddenDirectory
        self.now = now
        self.calendar = calendar
    }

    var storesInBackupFolder: Bool { hiddenDirectory != nil }

    /// Writes a copy and prunes. The hidden folder comes first; when it cannot be written (folder gone, offline), the copy goes to
    /// `localDirectory` instead: a restore never goes ahead without a safety copy somewhere.
    @discardableResult
    func write(_ data: Data) throws -> SafetyCopy {
        let name = BackupRules.safetyCopyName(for: now(), calendar: calendar, encrypted: BackupCrypto.isEncrypted(data))
        var inBackupFolder = false
        if let hiddenDirectory, (try? writeFile(data, named: name, into: hiddenDirectory, protected: false)) != nil {
            inBackupFolder = true
        } else {
            try writeFile(data, named: name, into: localDirectory, protected: true)
        }
        prune()
        return entry(named: name, in: inBackupFolder ? hiddenDirectory : localDirectory, isInBackupFolder: inBackupFolder)
            ?? SafetyCopy(id: name, createdAt: now(), bytes: data.count, daysLeft: BackupRules.safetyCopyRetentionDays, isInBackupFolder: inBackupFolder)
    }

    /// All copies of both places, newest first; a name that is in both places is listed once, the hidden one.
    func list() -> [SafetyCopy] {
        var result: [String: SafetyCopy] = [:]
        for (directory, inBackupFolder) in places.reversed() {
            for name in names(in: directory) {
                if let copy = entry(named: name, in: directory, isInBackupFolder: inBackupFolder) { result[name] = copy }
            }
        }
        return result.values.sorted { $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt }
    }

    func data(of copy: SafetyCopy) throws -> Data {
        let directory = copy.isInBackupFolder ? hiddenDirectory : localDirectory
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: directory.appendingPathComponent(copy.id))
    }

    func delete(_ copy: SafetyCopy) {
        for (directory, _) in places { try? fileManager.removeItem(at: directory.appendingPathComponent(copy.id)) }
    }

    /// Removes what the rules name, from both places. Without a backup folder nothing is ever deleted: the copies stay where they
    /// are, as they did before, until the user deletes them in the list.
    func prune() {
        guard hiddenDirectory != nil else { return }
        let all = Set(places.flatMap { names(in: $0.directory) })
        for name in BackupRules.safetyCopiesToDelete(names: Array(all), now: now(), calendar: calendar) {
            for (directory, _) in places { try? fileManager.removeItem(at: directory.appendingPathComponent(name)) }
        }
    }

    /// Moves copies from the old visible folder "Dokumente/Sicherungen" once and removes the folder when it is empty. Does nothing
    /// without a hidden folder. A copy that already exists in the hidden folder is not overwritten.
    func adoptLegacyCopies(from directory: URL) {
        guard let hiddenDirectory else { return }
        for name in names(in: directory) {
            let source = directory.appendingPathComponent(name)
            let target = hiddenDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: target.path) {
                try? fileManager.removeItem(at: source)
                continue
            }
            guard let data = try? Data(contentsOf: source), (try? writeFile(data, named: name, into: hiddenDirectory, protected: false)) != nil else { continue }
            try? fileManager.removeItem(at: source)
        }
        if let rest = try? fileManager.contentsOfDirectory(atPath: directory.path), rest.isEmpty {
            try? fileManager.removeItem(at: directory)
        }
        prune()
    }

    // MARK: Files

    private var places: [(directory: URL, isInBackupFolder: Bool)] {
        (hiddenDirectory.map { [($0, true)] } ?? []) + [(localDirectory, false)]
    }

    private func names(in directory: URL) -> [String] {
        ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []).filter(BackupRules.isSafetyCopy)
    }

    private func entry(named name: String, in directory: URL?, isInBackupFolder: Bool) -> SafetyCopy? {
        guard let directory, let createdAt = BackupRules.safetyCopyDate(name, calendar: calendar) else { return nil }
        let size = (try? directory.appendingPathComponent(name).resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return SafetyCopy(id: name, createdAt: createdAt, bytes: size, daysLeft: BackupRules.safetyCopyDaysLeft(createdAt: createdAt, now: now()),
                          isInBackupFolder: isInBackupFolder)
    }

    private func writeFile(_ data: Data, named name: String, into directory: URL, protected: Bool) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name), options: protected ? [.atomic, .completeFileProtection] : [.atomic])
    }
}
