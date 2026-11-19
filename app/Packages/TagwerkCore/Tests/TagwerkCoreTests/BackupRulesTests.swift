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
