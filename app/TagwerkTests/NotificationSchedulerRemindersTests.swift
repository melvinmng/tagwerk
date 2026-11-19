import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Several reminders per entry and the rolling plan in the scheduler (plan P4, Task 7). All data is invented.
@MainActor
struct NotificationSchedulerRemindersTests {
    final class Clock { var now = testNow() }

    let container: ModelContainer
    let settings: AppSettings
    let overrides: ReminderOverrideStore
    let center = FakeNotificationCenter()
    let local = FakeTaskProvider(source: .local)
    let reminders = FakeTaskProvider(source: .reminders)
    let calendar = testCalendar()
    let clock = Clock()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        overrides = ReminderOverrideStore(context: container.mainContext)
    }

    private func makeScheduler(_ list: TaskListModel) -> NotificationScheduler {
        let clock = self.clock
        return NotificationScheduler(center: center, taskList: list, deadlineEvents: { _, _ in [] }, settings: settings,
                                     now: { clock.now }, calendar: calendar, locale: { Locale(identifier: "de_DE") },
                                     reminderOverrides: overrides)
    }

    private func loadedList(_ providers: [FakeTaskProvider]? = nil) async -> TaskListModel {
        let list = TaskListModel(providers: providers ?? [local, reminders])
        await list.reload()
        return list
    }

    private func due(_ day: Int, _ hour: Int = 12, minute: Int = 0) -> DueDate { DueDate(year: 2026, month: 11, day: day, hour: hour, minute: minute) }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func useThreeReminders() {
        var defaults = settings.reminderDefaults
        for kind in [ReminderKind.localTask, .githubIssue, .appleReminder] {
            defaults.set([.before(amount: 1, unit: .weeks), .before(amount: 1, unit: .days), .before(amount: 1, unit: .hours)],
                         for: kind, isAllDay: false)
        }
        settings.reminderDefaults = defaults
    }

    @Test func reschedule_replacesLegacyIDsWithIndexedOnes() async {
        center.seed("tagwerk.task.local:A", fireDate: testNow().addingTimeInterval(86_400))
        center.seed("tagwerk.event.klausur", fireDate: testNow().addingTimeInterval(86_400))
        local.tasks = [makeTask("A", source: .local, due: due(25))]
        await makeScheduler(await loadedList([local])).reschedule()
        #expect(center.pendingIDs == ["tagwerk.task.local:A#0"])
    }

    @Test func reschedule_keepsRoutineAndForeignPrefixes() async {
        center.seed("tagwerk.routine.morning", fireDate: nil)
        center.seed("tagwerk.routine.evening.X", fireDate: nil)
        center.seed("tagwerk.focus.timer", fireDate: testNow().addingTimeInterval(600))
        center.seed("other.reminder", fireDate: testNow().addingTimeInterval(600))
        local.tasks = [makeTask("A", source: .local, due: due(25))]
        await makeScheduler(await loadedList([local])).reschedule()
        #expect(center.pendingIDs == ["tagwerk.task.local:A#0", "tagwerk.routine.morning", "tagwerk.routine.evening.X",
                                      "tagwerk.focus.timer", "other.reminder"])
    }

    @Test func threeReminders_areScheduledWithIndexedIDs() async {
        useThreeReminders()
        local.tasks = [makeTask("A", source: .local, due: due(30))]
        await makeScheduler(await loadedList([local])).reschedule()
        #expect(center.pendingIDs == ["tagwerk.task.local:A#0", "tagwerk.task.local:A#1", "tagwerk.task.local:A#2"])
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == at(23, 12))
        #expect(center.pending["tagwerk.task.local:A#2"]?.fireDate == at(30, 11))
    }

    @Test func reschedule_overflow_reportsRefillDate() async {
        useThreeReminders()
        // 30 tasks × 3 reminders, one task per hour of the 30th: the budget holds 50 of the 90.
        local.tasks = (0..<30).map { makeTask("T\($0)", source: .local, due: DueDate(year: 2026, month: 12, day: 1 + $0 / 12, hour: 8 + $0 % 12)) }
        let scheduler = makeScheduler(await loadedList([local]))
        await scheduler.reschedule()
        #expect(center.pending.count == NotificationScheduler.limit)
        let latest = center.pending.values.compactMap(\.fireDate).max()
        #expect(latest != nil)
        #expect(scheduler.nextRefill == latest?.addingTimeInterval(-3600))
    }

    @Test func reschedule_everythingFits_hasNoRefillDate() async {
        local.tasks = [makeTask("A", source: .local, due: due(25))]
        let scheduler = makeScheduler(await loadedList([local]))
        await scheduler.reschedule()
        #expect(scheduler.nextRefill == nil)
    }

    @Test func reschedule_afterFirstFired_refillsNext() async {
        useThreeReminders()
        local.tasks = (0..<30).map { makeTask("T\($0)", source: .local, due: DueDate(year: 2026, month: 12, day: 1 + $0 / 12, hour: 8 + $0 % 12)) }
        let scheduler = makeScheduler(await loadedList([local]))
        await scheduler.reschedule()
        let before = center.pendingIDs
        // The earliest reminders fire (iOS removes delivered requests) and time passes.
        let firedFirst = center.pending.values.filter { ($0.fireDate ?? .distantFuture) <= at(25, 23) }.map(\.id)
        #expect(!firedFirst.isEmpty)
        for id in firedFirst { center.removePendingForTest(id) }
        clock.now = at(25, 23)
        await scheduler.reschedule()
        #expect(center.pending.count == NotificationScheduler.limit)
        #expect(center.pendingIDs.subtracting(before).count == firedFirst.count)
        #expect(Set(firedFirst).isDisjoint(with: center.pendingIDs))
    }

    @Test func appleReminderWithEventKitOverride_getsNoTagwerkNotification() async throws {
        var item = makeTask("Apple", source: .reminders, due: due(25))
        item.container = TaskContainer(id: "list", name: "Liste", colorHex: nil)
        reminders.tasks = [item]
        let scheduler = makeScheduler(await loadedList([reminders]))
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.task.reminders:Apple#0"])

        try overrides.save(ReminderOverride(itemKey: ReminderOverride.key(task: item.id), scope: .always, storage: .eventKit,
                                            offsets: [.before(amount: 1, unit: .days)]))
        await scheduler.reschedule()
        #expect(center.pending.isEmpty)

        try overrides.removeAll(itemKey: ReminderOverride.key(task: item.id))
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.task.reminders:Apple#0"])
    }

    @Test func tagwerkOverride_replacesTheDefaultReminders() async throws {
        let item = makeTask("A", source: .local, due: due(25))
        local.tasks = [item]
        try overrides.save(ReminderOverride(itemKey: ReminderOverride.key(task: item.id), scope: .always,
                                            offsets: [.at(daysBefore: 2, hour: 18, minute: 0)]))
        await makeScheduler(await loadedList([local])).reschedule()
        #expect(center.pending.count == 1)
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == at(23, 18))
    }

    @Test func quietHours_stillApplyToEveryOffset() async {
        settings.quietHoursEnabled = true
        settings.quietHoursStartsAtBedtime = false
        settings.quietStartMinutes = 22 * 60
        settings.quietEndMinutes = 7 * 60
        var defaults = settings.reminderDefaults
        for kind in [ReminderKind.localTask, .githubIssue, .appleReminder] {
            defaults.set([.at(daysBefore: 2, hour: 23, minute: 0), .before(amount: 1, unit: .days), .before(amount: 1, unit: .hours)],
                         for: kind, isAllDay: false)
        }
        settings.reminderDefaults = defaults
        // Due 25th at 06:00: 2 days before at 23:00 (night) and 1 day before (24th 06:00, night) both move to 07:00;
        // 1 hour before (05:00, night) moves to 07:00 as well, so only the first of them stays.
        local.tasks = [makeTask("A", source: .local, due: due(25, 6))]
        await makeScheduler(await loadedList([local])).reschedule()
        #expect(center.pending.values.compactMap(\.fireDate).sorted() == [at(24, 7), at(25, 7)])
    }

    @Test func backgroundRefresh_usesEarlierRefillDate() async {
        useThreeReminders()
        local.tasks = (0..<30).map { makeTask("T\($0)", source: .local, due: DueDate(year: 2026, month: 12, day: 1 + $0 / 12, hour: 8 + $0 % 12)) }
        let list = await loadedList([local])
        let scheduler = makeScheduler(list)
        var submitted: [Date] = []
        let refresh = BackgroundRefresh(
            prepare: { false }, reload: {}, reschedule: { await scheduler.reschedule() },
            submit: { submitted.append($0) }, now: { testNow() }, nextRefill: { scheduler.nextRefill })
        await refresh.run()
        #expect(submitted.first == testNow().addingTimeInterval(BackgroundRefresh.interval))
        // The plan reaches into December, so the refill date is further away than the usual interval: unchanged.
        #expect(scheduler.nextRefill.map { $0 > testNow().addingTimeInterval(BackgroundRefresh.interval) } == true)
        #expect(submitted.count == 1)

        // Closer plan: 60 tasks due within a day make the refill earlier than the interval.
        local.tasks = (0..<60).map { makeTask("N\($0)", source: .local, due: DueDate(year: 2026, month: 11, day: 18, hour: 11, minute: $0)) }
        await list.reload()
        submitted = []
        await refresh.run()
        let early = scheduler.nextRefill
        #expect(early.map { $0 < testNow().addingTimeInterval(BackgroundRefresh.interval) } == true)
        #expect(submitted.last == early)
    }
}
