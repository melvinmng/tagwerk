import Foundation
import Testing
@testable import TagwerkCore

struct BackupStatusTests {
    private let now = instant(2026, 11, 20, 12)

    private func status(auto: Bool = true, folder: Bool = true, last: Date? = nil, error: String? = nil) -> BackupStatus {
        BackupStatus.status(autoEnabled: auto, hasFolder: folder, lastBackup: last, lastError: error, now: now)
    }

    @Test func status_off() {
        #expect(status(auto: false, last: now) == .off)
        #expect(!status(auto: false).isWarning)
    }

    @Test func status_backedUpToday() {
        let last = now.addingTimeInterval(-3600)
        #expect(status(last: last) == .backedUp(at: last))
        #expect(!status(last: last).isWarning)
        // Still fine just before the second interval has passed.
        #expect(status(last: now.addingTimeInterval(-2 * 86_400 + 1)) == .backedUp(at: now.addingTimeInterval(-2 * 86_400 + 1)))
    }

    @Test func status_overdueAfterTwoDays() {
        let last = now.addingTimeInterval(-3 * 86_400 - 3600)
        #expect(status(last: last) == .overdue(since: last, days: 3))
        #expect(status(last: last).isWarning)
        let exactlyTwo = now.addingTimeInterval(-2 * 86_400)
        #expect(status(last: exactlyTwo) == .overdue(since: exactlyTwo, days: 2))
    }

    @Test func status_neverBackedUp() {
        #expect(status(last: nil) == .overdue(since: nil, days: 0))
        #expect(status(last: nil).isWarning)
    }

    @Test func status_folderMissing() {
        #expect(status(folder: false, last: now) == .folderMissing)
        #expect(status(folder: false).isWarning)
    }

    @Test func status_errorWins() {
        #expect(status(last: now, error: "Disk full") == .failed(message: "Disk full"))
        #expect(status(last: nil, error: "Disk full") == .failed(message: "Disk full"))
        #expect(status(last: now, error: "Disk full").isWarning)
        // Switching the automatic backup off hides an old error.
        #expect(status(auto: false, error: "Disk full") == .off)
    }

    @Test func status_clockSetBack_countsAsBackedUp() {
        let last = now.addingTimeInterval(3600)
        #expect(status(last: last) == .backedUp(at: last))
    }
}
