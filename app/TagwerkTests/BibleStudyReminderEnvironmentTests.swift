import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// "Heute nicht" on the Bible Study reminder, with the app environment behind it (BS7).
@MainActor
struct BibleStudyReminderEnvironmentTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "bible-reminder-\(UUID().uuidString)")

    @Test func skipBibleStudyToday_remembersTheDayAndDropsItsReminder() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let center = FakeNotificationCenter()
        // A pinned clock at noon: the real time could sit right before midnight, where the reminder below has passed
        // or "today" rolls over while the test runs.
        let now = Calendar.tagwerk.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        let environment = try AppEnvironment(modelContainer: container, notificationCenter: center, health: FakeHealthStore(),
                                             snapshotWriter: WidgetSnapshotWriter(directory: directory, reload: {}),
                                             routineClock: { now })
        let calendar = environment.planning.calendar
        let today = PlanDay(date: now, calendar: calendar)
        // A reminder at the last minute of every day: today's is still ahead of the pinned noon.
        environment.settings.bibleStudyReminderEnabled = true
        environment.settings.bibleStudyReminderTimes = [BibleStudyReminderTime(minutes: 23 * 60 + 59, weekdays: Set(1...7))]
        await environment.routineNotifications.reschedule()
        center.seed(BibleStudyReminders.identifier(day: today), fireDate: nil)

        await environment.skipBibleStudyToday()

        #expect(environment.settings.bibleStudySkippedDayKey == today.dayKey)
        #expect(!center.pendingIDs.contains(BibleStudyReminders.identifier(day: today)))
        // Tomorrow keeps its reminder: "Heute nicht" is for one day.
        #expect(center.pendingIDs.contains(BibleStudyReminders.identifier(day: today.adding(days: 1, calendar: calendar))))
    }
}
