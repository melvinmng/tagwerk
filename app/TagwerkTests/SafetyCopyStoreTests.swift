import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// The safety copies before a restore (DS7c): hidden in the backup folder, limited, listed. Two temporary folders stand for the
/// app documents and the backup folder. All data is invented.
@MainActor
struct SafetyCopyStoreTests {
    final class Clock { var now = testNow() }
    let clock = Clock()
    let calendar = testCalendar()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("safety-" + UUID().uuidString, isDirectory: true)
    var local: URL { root.appendingPathComponent("Sicherungen", isDirectory: true) }
    var backupFolder: URL { root.appendingPathComponent("Backup", isDirectory: true) }
    var hidden: URL { backupFolder.appendingPathComponent(SafetyCopyStore.hiddenFolderName, isDirectory: true) }

    init() throws {
        try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
    }

    private func store(withBackupFolder: Bool = true) -> SafetyCopyStore {
        let clock = self.clock
        return SafetyCopyStore(localDirectory: local, hiddenDirectory: withBackupFolder ? hidden : nil, now: { clock.now }, calendar: calendar)
    }

    private func names(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private func legacyFile(_ day: Int, month: Int = 11, bytes: Int = 10) throws -> String {
        let name = BackupRules.safetyCopyName(for: calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 8))!, calendar: calendar)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try Data(count: bytes).write(to: local.appendingPathComponent(name))
        return name
    }

    @Test func hiddenFolder_startsWithADot() {
        #expect(SafetyCopyStore.hiddenFolderName == ".Sicherheitskopien")
    }

    @Test func write_storesInTheHiddenFolderOnly() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let copy = try store().write(Data("backup".utf8))
        #expect(copy.isInBackupFolder && copy.daysLeft == 30 && copy.bytes == 6 && !copy.isEncrypted)
        #expect(names(in: hidden) == [copy.id])
        #expect(names(in: local).isEmpty)
        #expect(BackupRules.safetyCopyDate(copy.id, calendar: calendar) == clock.now)
        // The hidden folder is no own backup file, so the daily clean-up of the backup folder never sees it.
        #expect(names(in: backupFolder).filter(BackupRules.isOwnFile).isEmpty)
    }

    @Test func write_withoutBackupFolder_storesLocallyOnly() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let copy = try store(withBackupFolder: false).write(Data("backup".utf8))
        #expect(!copy.isInBackupFolder)
        #expect(names(in: local) == [copy.id])
        #expect(!FileManager.default.fileExists(atPath: hidden.path))
    }

    @Test func write_whenTheHiddenFolderCannotBeWritten_fallsBackToLocal() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        // A file where the hidden folder should be: creating the folder fails.
        try Data("x".utf8).write(to: hidden)
        let copy = try store().write(Data("backup".utf8))
        #expect(!copy.isInBackupFolder)
        #expect(names(in: local) == [copy.id])
    }

    @Test func write_marksAnEncryptedFileByItsExtension() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let material = BackupCrypto.KeyMaterial(key: Data(repeating: 1, count: 32), salt: Data(repeating: 2, count: 16), iterations: 1_000)
        let encrypted = try BackupCrypto.encrypt(Data("backup".utf8), with: material)
        let copy = try store().write(encrypted)
        #expect(copy.isEncrypted && copy.id.hasSuffix(".tagwerk"))
        #expect(try store().data(of: copy) == encrypted)
    }

    @Test func list_mergesBothPlacesWithoutDuplicates() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = try legacyFile(10)
        let both = try legacyFile(12)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try Data(count: 99).write(to: hidden.appendingPathComponent(both))
        clock.now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!
        let newest = try store().write(Data(count: 5))
        let listed = store().list()
        #expect(listed.map(\.id) == [newest.id, both, legacy])
        #expect(listed.map(\.isInBackupFolder) == [true, true, false])
        // The hidden one wins for a name that is in both places.
        #expect(listed[1].bytes == 99)
        #expect(listed.map(\.daysLeft) == [30, 22, 20])
    }

    @Test func prune_removesFromBoth() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        clock.now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!
        let oldLocal = try legacyFile(1)
        let oldBoth = try legacyFile(2)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try Data(count: 1).write(to: hidden.appendingPathComponent(oldBoth))
        for day in [14, 16, 18] {
            let name = BackupRules.safetyCopyName(for: calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 8))!, calendar: calendar)
            try Data(count: 1).write(to: hidden.appendingPathComponent(name))
        }
        store().prune()
        #expect(names(in: hidden).count == 3 && !names(in: hidden).contains(oldBoth))
        #expect(!names(in: local).contains(oldLocal) && !names(in: local).contains(oldBoth))
    }

    @Test func prune_dropsCopiesOlderThanThirtyDays() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        clock.now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 9))!
        let expired = try legacyFile(31, month: 10)
        let fresh = try legacyFile(29)
        store().prune()
        #expect(names(in: local) == [fresh] && !names(in: local).contains(expired))
    }

    @Test func prune_withoutBackupFolder_neverDeletes() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        clock.now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 9))!
        let names = [try legacyFile(1, month: 9), try legacyFile(31, month: 10), try legacyFile(10), try legacyFile(20), try legacyFile(29)]
        let store = store(withBackupFolder: false)
        store.prune()
        _ = try store.write(Data(count: 1))
        #expect(self.names(in: local).count == names.count + 1)
        #expect(store.list().count == names.count + 1)
    }

    @Test func delete_andDataOf_workInTheRightPlace() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let copy = try store().write(Data("hello".utf8))
        #expect(try store().data(of: copy) == Data("hello".utf8))
        store().delete(copy)
        #expect(store().list().isEmpty)
        #expect(throws: (any Error).self) { try store().data(of: copy) }
    }

    @Test func adoptLegacyCopies_movesAndCleansUp() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        clock.now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!
        let moved = try legacyFile(15, bytes: 7)
        let duplicate = try legacyFile(16, bytes: 7)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try Data(count: 3).write(to: hidden.appendingPathComponent(duplicate))
        store().adoptLegacyCopies(from: local)
        #expect(names(in: hidden) == [moved, duplicate].sorted())
        // The copy that was already in the hidden folder is not overwritten.
        #expect(try Data(contentsOf: hidden.appendingPathComponent(duplicate)).count == 3)
        #expect(try Data(contentsOf: hidden.appendingPathComponent(moved)).count == 7)
        #expect(!FileManager.default.fileExists(atPath: local.path))
    }

    @Test func adoptLegacyCopies_withoutBackupFolder_changesNothing() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        clock.now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!
        let name = try legacyFile(15)
        store(withBackupFolder: false).adoptLegacyCopies(from: local)
        #expect(names(in: local) == [name])
    }

    @Test func adoptLegacyCopies_leavesForeignFilesAlone() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        clock.now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!
        _ = try legacyFile(15)
        try Data("mine".utf8).write(to: local.appendingPathComponent("Notiz.txt"))
        store().adoptLegacyCopies(from: local)
        #expect(names(in: local) == ["Notiz.txt"])
    }
}
