import Foundation
import Testing
@testable import TagwerkCore

/// Several reminders per task and deadline (plan P4, Task 4).
struct NotificationPlanMultipleTests {
    let calendar = makeCalendar()
    /// Wednesday, 18 Nov 2026, 08:00 in Berlin.
    var now: Date { at(18, 8, 0) }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { instant(2026, 11, day, hour, minute, in: calendar) }

    private func task(_ title: String, day: Int, hour: Int? = nil, source: TaskSource = .local) -> TaskItem {
        makeItem(title, due: DueDate(year: 2026, month: 11, day: day, hour: hour, minute: hour == nil ? nil : 0), source: source)
    }

    private func event(_ id: String, start: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, externalID: nil, calendarID: "deadlines", title: "Termin \(id)", start: start,
                      end: start.addingTimeInterval(3600), isAllDay: allDay, url: nil, isBusy: true, version: "1")
    }

    private func rules(_ defaults: ReminderDefaults? = nil, overrides: [String: [ReminderOverride]] = [:],
                       seriesKey: [String: String] = [:], limit: Int = 50, quietHours: QuietHours? = nil,
                       lead: Int = 120) -> NotificationRules {
        NotificationRules(leadTimeMinutes: lead, includesDeadlineCalendars: true, limit: limit, minimumDelay: 0,
                          quietHours: quietHours, defaults: defaults, overrides: overrides, seriesKey: seriesKey)
    }

    private func result(_ tasks: [TaskItem] = [], events: [CalendarEvent] = [], rules: NotificationRules) -> NotificationPlanResult {
        notificationPlanResult(tasks: tasks, deadlineEvents: events, rules: rules, now: now, calendar: calendar,
                               locale: Locale(identifier: "de_DE"))
    }

    private func defaults(task: [ReminderOffset] = [], taskAllDay: [ReminderOffset] = [], deadline: [ReminderOffset] = [],
                          deadlineAllDay: [ReminderOffset] = []) -> ReminderDefaults {
        ReminderDefaults(timed: [.task: task, .deadline: deadline], allDay: [.task: taskAllDay, .deadline: deadlineAllDay])
    }

    @Test func migratedDefaults_planSameFireDatesAsLegacyRules() {
        let tasks = [task("Timed", day: 20, hour: 12), task("DateOnly", day: 21), task("Github", day: 22, hour: 9, source: .github),
                     task("Late", day: 19, hour: 7)]
        let events = [event("A", start: at(21, 10), allDay: true), event("B", start: at(20, 15))]
        for lead in [15, 60, 120, 1440, 2880] {
            let legacy = notificationPlan(tasks: tasks, deadlineEvents: events, rules: rules(lead: lead), now: now, calendar: calendar)
            let migrated = notificationPlan(tasks: tasks, deadlineEvents: events,
                                            rules: rules(.legacy(leadTimeMinutes: lead), lead: lead), now: now, calendar: calendar)
            #expect(legacy == migrated)
            #expect(!legacy.isEmpty)
        }
        // The fixed dates of the old rules: lead time before a timed due moment, 9:00 on the day, 18:00 on the evening before.
        let plan = notificationPlan(tasks: tasks, deadlineEvents: events, rules: rules(lead: 120), now: now, calendar: calendar)
        let dates = Dictionary(uniqueKeysWithValues: plan.map { ($0.title, $0.fireDate) })
        #expect(dates["Timed"] == at(20, 10))
        #expect(dates["DateOnly"] == at(21, 9))
        #expect(dates["Termin A"] == at(20, 18))
        #expect(dates["Termin B"] == at(20, 13))
    }

    @Test func threeOffsets_yieldThreeNotificationsWithIndexedIDs() {
        let three = defaults(task: [.before(amount: 1, unit: .hours), .before(amount: 1, unit: .weeks), .before(amount: 1, unit: .days)])
        let item = task("Plan", day: 27, hour: 12)
        let plan = result([item], rules: rules(three)).notifications
        // Indexes follow the sorted list: 1 week = #0, 1 day = #1, 1 hour = #2.
        #expect(plan.map(\.id) == [PlannedNotification.identifier(for: item.id, index: 0), PlannedNotification.identifier(for: item.id, index: 1),
                                   PlannedNotification.identifier(for: item.id, index: 2)])
        #expect(plan.map(\.fireDate) == [at(20, 12), at(26, 12), at(27, 11)])
        #expect(plan.allSatisfy { $0.id.contains("#") && PlannedNotification.isBudgeted($0.id) })
    }

    @Test func deadlines_getIndexedIDsToo() {
        let two = defaults(deadline: [.before(amount: 1, unit: .days), .before(amount: 1, unit: .hours)])
        let plan = result(events: [event("E", start: at(25, 15))], rules: rules(two)).notifications
        #expect(plan.map(\.id) == [PlannedNotification.identifier(forEvent: "E", index: 0), PlannedNotification.identifier(forEvent: "E", index: 1)])
        #expect(plan.map(\.fireDate) == [at(24, 15), at(25, 14)])
    }

    @Test func eventKitOverride_suppressesTagwerkNotifications() {
        let item = task("Apple", day: 25, hour: 12, source: .reminders)
        let key = ReminderOverride.key(task: item.id)
        let override = ReminderOverride(itemKey: key, scope: .always, storage: .eventKit, offsets: [.before(amount: 1, unit: .days)])
        #expect(result([item], rules: rules(overrides: [key: [override]])).notifications.isEmpty)
        let own = ReminderOverride(itemKey: key, scope: .always, storage: .tagwerk, offsets: [.before(amount: 1, unit: .days)])
        #expect(result([item], rules: rules(overrides: [key: [own]])).notifications.map(\.fireDate) == [at(24, 12)])
    }

    @Test func tagwerkOverride_replacesTheDefault() {
        let item = task("Own", day: 25, hour: 12)
        let key = ReminderOverride.key(task: item.id)
        let override = ReminderOverride(itemKey: key, scope: .always,
                                        offsets: [.at(daysBefore: 2, hour: 18, minute: 0), .before(amount: 30, unit: .minutes)])
        let plan = result([item], rules: rules(overrides: [key: [override]])).notifications
        #expect(plan.map(\.fireDate) == [at(23, 18), at(25, 11, 30)])
    }

    @Test func limit_keepsEarliestAcrossEntries() {
        let three = defaults(task: [.before(amount: 2, unit: .days), .before(amount: 1, unit: .days), .before(amount: 1, unit: .hours)])
        // Task n is due on day 21 + n % 9 at the given hour; 30 tasks × 3 reminders = 90 wanted.
        let tasks = (0..<30).map { task("T\($0)", day: 21 + $0 % 9, hour: 8 + $0 % 12) }
        let full = result(tasks, rules: rules(three, limit: 1000))
        let limited = result(tasks, rules: rules(three, limit: 50))
        #expect(full.notifications.count == 90)
        #expect(limited.notifications.count == 50)
        #expect(limited.omittedCount == 40)
        #expect(limited.notifications == Array(full.notifications.prefix(50)))
    }

    @Test func quietHours_collapseSameMinuteOfOneEntry() {
        // 23:00-07:00: every reminder in the night moves to 07:00; one entry keeps only the first of them.
        let night = QuietHours(startMinutes: 23 * 60, endMinutes: 7 * 60)
        let three = defaults(task: [.before(amount: 4, unit: .hours), .before(amount: 3, unit: .hours), .before(amount: 1, unit: .hours)])
        let item = task("Early", day: 25, hour: 4)
        let plan = result([item], rules: rules(three, quietHours: night)).notifications
        #expect(plan.count == 1)
        #expect(plan.first?.fireDate == at(25, 7))
        #expect(plan.first?.id == PlannedNotification.identifier(for: item.id, index: 0))
    }

    @Test func quietHours_keepRemindersOfDifferentEntriesApart() {
        let night = QuietHours(startMinutes: 23 * 60, endMinutes: 7 * 60)
        let one = defaults(task: [.before(amount: 1, unit: .hours)])
        let plan = result([task("A", day: 25, hour: 4), task("B", day: 25, hour: 5)], rules: rules(one, quietHours: night)).notifications
        #expect(plan.count == 2)
    }

    @Test func pastOffsets_areSkipped_laterOnesKept() {
        let three = defaults(task: [.before(amount: 1, unit: .weeks), .before(amount: 1, unit: .days), .before(amount: 1, unit: .hours)])
        // Due tomorrow at 07:00: 1 week and 1 day before are past (now is 08:00 on the 18th), 1 hour before is not.
        let item = task("Soon", day: 19, hour: 7)
        let plan = result([item], rules: rules(three)).notifications
        #expect(plan.map(\.fireDate) == [at(19, 6)])
        // The surviving reminder keeps its index, so it does not change when the earlier ones have fired.
        #expect(plan.first?.id == PlannedNotification.identifier(for: item.id, index: 2))
    }

    @Test func deadlineSeries_onlyThisOccurrenceOverride() {
        let ids = ["S|100", "S|200", "S|300"]
        let events = [event(ids[0], start: at(20, 10)), event(ids[1], start: at(27, 10)), event(ids[2], start: at(30, 10))]
        let key = ReminderOverride.key(deadlineSeries: "S")
        let override = ReminderOverride(itemKey: key, scope: .occurrence(ids[1]), offsets: [.before(amount: 3, unit: .days)])
        let plan = result(events: events, rules: rules(overrides: [key: [override]], seriesKey: Dictionary(uniqueKeysWithValues: ids.map { ($0, "S") })))
            .notifications
        let byEvent = Dictionary(uniqueKeysWithValues: plan.map { ($0.id, $0.fireDate) })
        #expect(byEvent[PlannedNotification.identifier(forEvent: ids[0])] == at(20, 8))
        #expect(byEvent[PlannedNotification.identifier(forEvent: ids[1])] == at(24, 10))
        #expect(byEvent[PlannedNotification.identifier(forEvent: ids[2])] == at(30, 8))
    }

    @Test func deadlineSeries_allFollowingOverride() {
        let ids = ["S|100", "S|200", "S|300"]
        let events = [event(ids[0], start: at(20, 10)), event(ids[1], start: at(27, 10)), event(ids[2], start: at(30, 10))]
        let key = ReminderOverride.key(deadlineSeries: "S")
        let override = ReminderOverride(itemKey: key, scope: .seriesFrom(PlanDay(year: 2026, month: 11, day: 27)),
                                        offsets: [.before(amount: 1, unit: .days)])
        let plan = result(events: events, rules: rules(overrides: [key: [override]], seriesKey: Dictionary(uniqueKeysWithValues: ids.map { ($0, "S") })))
            .notifications
        let byEvent = Dictionary(uniqueKeysWithValues: plan.map { ($0.id, $0.fireDate) })
        #expect(byEvent[PlannedNotification.identifier(forEvent: ids[0])] == at(20, 8))
        #expect(byEvent[PlannedNotification.identifier(forEvent: ids[1])] == at(26, 10))
        #expect(byEvent[PlannedNotification.identifier(forEvent: ids[2])] == at(29, 10))
    }

    @Test func allDayDeadline_atDaysBeforeKeepsWallClockAcrossDaylightSaving() {
        // Berlin ends daylight saving time on 25 Oct 2026: an all-day deadline on the 26th with "2 days before at 18:00".
        let start = instant(2026, 10, 26, 0, 0, in: calendar)
        let list = defaults(deadlineAllDay: [.at(daysBefore: 2, hour: 18, minute: 0)])
        let plan = notificationPlan(tasks: [], deadlineEvents: [event("D", start: start, allDay: true)], rules: rules(list),
                                    now: instant(2026, 10, 1, 8, 0, in: calendar), calendar: calendar)
        #expect(plan.map(\.fireDate) == [instant(2026, 10, 24, 18, 0, in: calendar)])
    }

    @Test func isBudgeted_ignoresRoutineAndOtherPrefixes() {
        #expect(PlannedNotification.isBudgeted("tagwerk.task.local:A#0"))
        #expect(PlannedNotification.isBudgeted("tagwerk.task.github:o/r#4#1"))
        #expect(PlannedNotification.isBudgeted("tagwerk.event.abc|100#0"))
        #expect(!PlannedNotification.isBudgeted("tagwerk.routine.morning"))
        #expect(!PlannedNotification.isBudgeted("tagwerk.routine.evening.X"))
        #expect(!PlannedNotification.isBudgeted("tagwerk.focus.timer"))
        #expect(!PlannedNotification.isBudgeted("other.task.local:A"))
    }
}
