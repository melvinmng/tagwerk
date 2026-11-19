import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The habit rows follow writes of the stores behind the routine sources, without a reload of the tab.
@MainActor
struct HabitSourceUpdatesTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "habit-sources-\(UUID().uuidString)")

    private func make() throws -> AppEnvironment {
        let container = try ModelContainerFactory.make(inMemory: true)
        let environment = try AppEnvironment(modelContainer: container, notificationCenter: FakeNotificationCenter(),
                                             health: FakeHealthStore(), snapshotWriter: WidgetSnapshotWriter(directory: directory, reload: {}))
        environment.settings.setupCompleted = true
        return environment
    }

    /// Lets the observation task run until `condition` holds (at most about two seconds).
    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func journalBibleStudyAndWrapUp_refreshTheRowsAfterAWrite() async throws {
        let environment = try make()
        let habits = environment.habits
        let today = habits.today
        for (index, source) in [HabitSource.journal, .bibleStudy, .eveningClosed].enumerated() {
            habits.save(Habit(name: "Quelle \(source.rawValue)", symbol: "book", order: index, source: source, start: today))
        }
        environment.startHabitSourceUpdates()
        await settle { habits.rows.count == 3 }
        #expect(habits.rows.count == 3 && habits.rows.allSatisfy { !$0.isFulfilled })

        let entry = environment.notes.openJournalEntry(dayKey: today.dayKey, locale: Locale(identifier: "de_DE"))
        environment.notes.updateText(entry.id, text: entry.text + "Heute war ein guter Tag.")
        await settle { habits.rows.first { $0.habit.source == .journal }?.isFulfilled == true }
        #expect(habits.rows.first { $0.habit.source == .journal }?.isFulfilled == true)

        let book = try #require(BibleBooks.book(number: 45))
        let started = environment.notes.startSession(book: book, passage: "3,21-31", dayKey: today.dayKey, dateText: "19.11.2026")
        environment.notes.completeSession(started.session.id)
        await settle { habits.rows.first { $0.habit.source == .bibleStudy }?.isFulfilled == true }
        #expect(habits.rows.first { $0.habit.source == .bibleStudy }?.isFulfilled == true)

        environment.routineStore.update(today) { $0.closeCompletedAt = .now }
        await settle { habits.rows.first { $0.habit.source == .eveningClosed }?.isFulfilled == true }
        #expect(habits.rows.first { $0.habit.source == .eveningClosed }?.isFulfilled == true)
        #expect(habits.todayCounter == HabitCounter(done: 3, total: 3))
    }
}
