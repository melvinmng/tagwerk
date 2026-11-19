import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Per-entry reminder lists and the default reminders in the settings (plan P4, Task 6). All data is invented.
@MainActor
struct ReminderOverrideStoreTests {
    let container: ModelContainer
    let store: ReminderOverrideStore
    let taskKey = ReminderOverride.key(task: TaskID(source: .github, rawValue: "owner/repo#7"))

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = ReminderOverrideStore(context: container.mainContext, now: { testNow() })
    }

    private func recordCount() -> Int { (try? container.mainContext.fetchCount(FetchDescriptor<ReminderOverrideRecord>())) ?? -1 }

    @Test func save_thenRead_roundTrips() throws {
        let due = DueDate(year: 2026, month: 11, day: 20, hour: 10)
        let day = PlanDay(year: 2026, month: 11, day: 27)
        let all: [ReminderOverride] = [
            ReminderOverride(itemKey: taskKey, scope: .always, storage: .eventKit, offsets: [.before(amount: 1, unit: .days)]),
            ReminderOverride(itemKey: taskKey, scope: .onlyDue(due), offsets: [.at(daysBefore: 1, hour: 18, minute: 0)]),
            ReminderOverride(itemKey: "deadline:S", scope: .occurrence("S|200"), offsets: []),
            ReminderOverride(itemKey: "deadline:S", scope: .seriesFrom(day), offsets: [.before(amount: 2, unit: .weeks)]),
        ]
        for override in all { try store.save(override) }
        let read = store.overrides()
        #expect(Set(read[taskKey] ?? []) == Set(all.filter { $0.itemKey == taskKey }))
        #expect(Set(read["deadline:S"] ?? []) == Set(all.filter { $0.itemKey == "deadline:S" }))
    }

    @Test func save_sameScope_replacesTheList() throws {
        try store.save(ReminderOverride(itemKey: taskKey, scope: .always, offsets: [.before(amount: 1, unit: .days)]))
        try store.save(ReminderOverride(itemKey: taskKey, scope: .always, offsets: [.before(amount: 3, unit: .days)]))
        #expect(recordCount() == 1)
        #expect(store.overrides(for: taskKey).first?.offsets == [.before(amount: 3, unit: .days)])
    }

    @Test func reading_neverInserts() {
        _ = store.overrides()
        _ = store.overrides(for: taskKey)
        #expect(recordCount() == 0)
    }

    @Test func remove_dropsOnlyThatScope_andRemoveAll_dropsTheEntry() throws {
        try store.save(ReminderOverride(itemKey: taskKey, scope: .always, offsets: []))
        try store.save(ReminderOverride(itemKey: taskKey, scope: .occurrence("x"), offsets: []))
        try store.save(ReminderOverride(itemKey: "task:other", scope: .always, offsets: []))
        try store.remove(itemKey: taskKey, scope: .occurrence("x"))
        #expect(store.overrides(for: taskKey).map(\.scope) == [.always])
        try store.removeAll(itemKey: taskKey)
        #expect(store.overrides(for: taskKey).isEmpty)
        #expect(store.overrides(for: "task:other").count == 1)
    }

    @Test func changes_raiseTheRevision() throws {
        let start = store.revision
        try store.save(ReminderOverride(itemKey: taskKey, scope: .always, offsets: []))
        try store.remove(itemKey: taskKey, scope: .always)
        #expect(store.revision == start + 2)
        try store.remove(itemKey: taskKey, scope: .always)
        #expect(store.revision == start + 2)
    }

    @Test func staleOnlyDueOverrides_areRemoved() throws {
        let today = PlanDay(year: 2026, month: 11, day: 19)
        try store.save(ReminderOverride(itemKey: taskKey, scope: .onlyDue(DueDate(year: 2026, month: 11, day: 12, hour: 9)), offsets: []))
        try store.save(ReminderOverride(itemKey: taskKey, scope: .onlyDue(DueDate(year: 2026, month: 11, day: 19, hour: 9)), offsets: []))
        try store.save(ReminderOverride(itemKey: taskKey, scope: .always, offsets: []))
        #expect(store.removeStaleOnlyDue(today: today) == 1)
        #expect(Set(store.overrides(for: taskKey).map(\.scope)) == [.always, .onlyDue(DueDate(year: 2026, month: 11, day: 19, hour: 9))])
    }

    @Test func unreadableRecords_areIgnored() throws {
        try store.save(ReminderOverride(itemKey: taskKey, scope: .always, offsets: [.before(amount: 1, unit: .days)]))
        let record = try #require(try container.mainContext.fetch(FetchDescriptor<ReminderOverrideRecord>()).first)
        record.offsetsData = Data("broken".utf8)
        #expect(store.overrides().isEmpty)
    }

    @Test func deletingLocalTask_removesItsOverride() async throws {
        let provider = LocalTaskProvider(context: container.mainContext)
        let task = try await provider.create(TaskDraft(title: "Abgabe", due: DueDate(year: 2026, month: 11, day: 25, hour: 12)))
        let other = try await provider.create(TaskDraft(title: "Anderes", due: DueDate(year: 2026, month: 11, day: 26, hour: 12)))
        try store.save(ReminderOverride(itemKey: ReminderOverride.key(task: task.id), scope: .always, offsets: []))
        try store.save(ReminderOverride(itemKey: ReminderOverride.key(task: other.id), scope: .always, offsets: []))
        try await provider.delete(task.id, expectedVersion: nil)
        #expect(store.overrides(for: ReminderOverride.key(task: task.id)).isEmpty)
        #expect(store.overrides(for: ReminderOverride.key(task: other.id)).count == 1)
    }

    @Test func settings_reminderDefaults_followTheLeadTimeUntilChanged() throws {
        let settings = try AppSettings.current(in: container.mainContext)
        settings.leadTimeMinutes = 60
        #expect(settings.reminderDefaultsData == nil)
        #expect(settings.reminderDefaults == .legacy(leadTimeMinutes: 60))
        var changed = settings.reminderDefaults
        changed.set([.before(amount: 1, unit: .weeks)], for: .task, isAllDay: false)
        settings.reminderDefaults = changed
        settings.leadTimeMinutes = 240
        #expect(settings.reminderDefaults.offsets(for: .task, isAllDay: false) == [.before(amount: 1, unit: .weeks)])
    }
}
