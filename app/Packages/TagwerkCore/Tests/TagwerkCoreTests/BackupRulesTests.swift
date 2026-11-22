import Foundation
import Testing
@testable import TagwerkCore

struct BackupRulesTests {
    private let calendar = makeCalendar()

    @Test func fileName_followsTheDateInTheCalendarsTimeZone() {
        #expect(BackupRules.fileName(for: instant(2026, 11, 19, 14, 23), calendar: calendar) == "Tagwerk-Sicherung-2026-11-19-1423.json")
        #expect(BackupRules.fileName(for: instant(2026, 1, 2, 3, 4), calendar: calendar) == "Tagwerk-Sicherung-2026-01-02-0304.json")
    }

    @Test func ownFiles_matchTheNamePatternExactly() {
        #expect(BackupRules.isOwnFile("Tagwerk-Sicherung-2026-11-19-1423.json"))
        #expect(BackupRules.isOwnFile(BackupRules.fileName(for: .now, calendar: calendar)))
        for name in ["Tagwerk-Sicherung-2026-11-19-1423.json.bak", "Tagwerk-Sicherung-2026-11-19.json", "meine-Datei.json",
                     "Tagwerk-Sicherung-2026-11-19-1423 (1).json", "xTagwerk-Sicherung-2026-11-19-1423.json", "Tagwerk.json", ""] {
            #expect(!BackupRules.isOwnFile(name), "\(name)")
        }
    }

    @Test func safetyCopy_isNeverAnOwnFile() {
        let name = BackupRules.safetyCopyName(for: instant(2026, 11, 19, 14, 23), calendar: calendar)
        #expect(name == "Tagwerk-Vor-Wiederherstellung-2026-11-19-1423.json")
        #expect(!BackupRules.isOwnFile(name))
    }

    @Test func filesToDelete_keepsTheNewestSevenOwnFilesOnly() {
        var names = (1...10).map { "Tagwerk-Sicherung-2026-11-\(String(format: "%02d", $0))-0800.json" }
        names += ["Notizen.txt", "Tagwerk-Sicherung-2026-11-05-0800.json.bak", "Tagwerk-Vor-Wiederherstellung-2026-11-01-0800.json"]
        let doomed = BackupRules.filesToDelete(names: names.shuffled())
        #expect(doomed == ["Tagwerk-Sicherung-2026-11-03-0800.json", "Tagwerk-Sicherung-2026-11-02-0800.json", "Tagwerk-Sicherung-2026-11-01-0800.json"])
        #expect(BackupRules.filesToDelete(names: Array(names.prefix(7))).isEmpty)
        #expect(BackupRules.filesToDelete(names: names, keeping: 0).count == 10)
        #expect(BackupRules.filesToDelete(names: []).isEmpty)
    }

    @Test func fileName_encryptedExtension() {
        let date = instant(2026, 11, 19, 14, 23)
        #expect(BackupRules.fileName(for: date, calendar: calendar, encrypted: true) == "Tagwerk-Sicherung-2026-11-19-1423.tagwerk")
        #expect(BackupRules.fileName(for: date, calendar: calendar, encrypted: false) == BackupRules.fileName(for: date, calendar: calendar))
        #expect(BackupRules.safetyCopyName(for: date, calendar: calendar, encrypted: true) == "Tagwerk-Vor-Wiederherstellung-2026-11-19-1423.tagwerk")
    }

    @Test func isOwnFile_bothExtensions() {
        #expect(BackupRules.isOwnFile("Tagwerk-Sicherung-2026-11-19-1423.tagwerk"))
        #expect(BackupRules.isOwnFile("Tagwerk-Sicherung-2026-11-19-1423.json"))
        for name in ["Tagwerk-Sicherung-2026-11-19-1423.tagwerk.bak", "Tagwerk-Sicherung-2026-11-19-1423.txt", "Tagwerk-Sicherung-2026-11-19-1423.TAGWERK"] {
            #expect(!BackupRules.isOwnFile(name), "\(name)")
        }
    }

    @Test func filesToDelete_keepsNewestSevenAcrossBoth() {
        var names = (1...5).map { "Tagwerk-Sicherung-2026-11-\(String(format: "%02d", $0))-0800.json" }
        names += (6...10).map { "Tagwerk-Sicherung-2026-11-\(String(format: "%02d", $0))-0800.tagwerk" }
        let doomed = BackupRules.filesToDelete(names: names.shuffled())
        #expect(doomed == ["Tagwerk-Sicherung-2026-11-03-0800.json", "Tagwerk-Sicherung-2026-11-02-0800.json", "Tagwerk-Sicherung-2026-11-01-0800.json"])
    }

    @Test func isOwnFile_safetyCopyNeverMatches() {
        for encrypted in [false, true] {
            #expect(!BackupRules.isOwnFile(BackupRules.safetyCopyName(for: instant(2026, 11, 19, 14, 23), calendar: calendar, encrypted: encrypted)))
        }
    }

    private func copyName(_ day: Int, month: Int = 11, hour: Int = 8, encrypted: Bool = false) -> String {
        BackupRules.safetyCopyName(for: instant(2026, month, day, hour), calendar: calendar, encrypted: encrypted)
    }

    @Test func safetyCopiesToDelete_keepsNewestThree() {
        let now = instant(2026, 11, 20, 12)
        let names = [copyName(10), copyName(12, encrypted: true), copyName(14), copyName(16), copyName(18)]
        #expect(BackupRules.safetyCopiesToDelete(names: names.shuffled(), now: now, calendar: calendar) == [copyName(12, encrypted: true), copyName(10)])
        #expect(BackupRules.safetyCopiesToDelete(names: Array(names.suffix(3)), now: now, calendar: calendar).isEmpty)
        #expect(BackupRules.safetyCopiesToDelete(names: [], now: now, calendar: calendar).isEmpty)
    }

    @Test func safetyCopiesToDelete_dropsOlderThanThirtyDays() {
        let now = instant(2026, 11, 30, 8)
        // Exactly 30 days old is due; 29 days and 23 hours is not.
        let thirtyDays = copyName(31, month: 10)
        let almostThirty = BackupRules.safetyCopyName(for: instant(2026, 10, 31, 9), calendar: calendar)
        let names = [copyName(29), almostThirty, thirtyDays, copyName(1, month: 9)]
        #expect(BackupRules.safetyCopiesToDelete(names: names, now: now, calendar: calendar) == [thirtyDays, copyName(1, month: 9)])
    }

    @Test func safetyCopiesToDelete_neverListsOtherFiles() {
        let now = instant(2026, 11, 20, 12)
        let names = ["Notizen.txt", "Tagwerk-Sicherung-2020-01-01-0800.json", "Tagwerk-Vor-Wiederherstellung-2020-01-01-0800.json.bak", copyName(19)]
        #expect(BackupRules.safetyCopiesToDelete(names: names, now: now, calendar: calendar).isEmpty)
    }

    @Test func safetyCopyDate_followsTheTimeZoneOfTheCalendar() {
        #expect(BackupRules.safetyCopyDate(copyName(19, hour: 14), calendar: calendar) == instant(2026, 11, 19, 14))
        #expect(BackupRules.safetyCopyDate("Tagwerk-Sicherung-2026-11-19-1400.json", calendar: calendar) == nil)
        #expect(BackupRules.safetyCopyDate("Tagwerk-Vor-Wiederherstellung-2026-11-19-2561.json", calendar: calendar) == nil)
        #expect(BackupRules.isSafetyCopy(copyName(19, encrypted: true)) && !BackupRules.isOwnFile(copyName(19, encrypted: true)))
    }

    @Test func safetyCopyDaysLeft_countsDownFromThirty() {
        let created = instant(2026, 11, 1, 8)
        #expect(BackupRules.safetyCopyDaysLeft(createdAt: created, now: created) == 30)
        #expect(BackupRules.safetyCopyDaysLeft(createdAt: created, now: created.addingTimeInterval(18 * 86_400)) == 12)
        #expect(BackupRules.safetyCopyDaysLeft(createdAt: created, now: created.addingTimeInterval(30 * 86_400)) == 0)
        #expect(BackupRules.safetyCopyDaysLeft(createdAt: created, now: created.addingTimeInterval(-3600)) == 30)
    }

    @Test func isDue_afterADayOrWithoutABackup() {
        let now = instant(2026, 11, 19, 12)
        #expect(BackupRules.isDue(lastBackup: nil, now: now))
        #expect(!BackupRules.isDue(lastBackup: now.addingTimeInterval(-3600), now: now))
        #expect(!BackupRules.isDue(lastBackup: now.addingTimeInterval(-86_399), now: now))
        #expect(BackupRules.isDue(lastBackup: now.addingTimeInterval(-86_400), now: now))
        // A last backup in the future (clock set back) must not block backups for good.
        #expect(BackupRules.isDue(lastBackup: now.addingTimeInterval(3600), now: now))
    }

    @Test func compatibility_refusesForeignFilesAndNewerVersions() {
        #expect(BackupRules.compatibility(format: "tagwerk-backup", schemaVersion: 1) == .readable)
        #expect(BackupRules.compatibility(format: "tagwerk-backup", schemaVersion: 2) == .readable)
        #expect(BackupRules.compatibility(format: "tagwerk-backup", schemaVersion: 0) == .readable)
        #expect(BackupRules.compatibility(format: "tagwerk-backup", schemaVersion: 3) == .newerVersion(3))
        #expect(BackupRules.compatibility(format: "something-else", schemaVersion: 1) == .notABackup)
    }
}
