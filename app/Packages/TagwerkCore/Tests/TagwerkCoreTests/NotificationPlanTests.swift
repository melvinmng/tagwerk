import Foundation
import Testing
@testable import TagwerkCore

struct NotificationPlanTests {
    let calendar = makeCalendar()
    /// Wednesday, 18 Nov 2026, 08:00 in Berlin.
    var now: Date { instant(2026, 11, 18, 8, 0, in: calendar) }
    let rules = NotificationRules(leadTimeMinutes: 120, includesDeadlineCalendars: true)

    private func task(_ title: String, source: TaskSource, due: DueDate?, completed: Bool = false,
                      container: String = "Lokal") -> TaskItem {
        var item = makeItem(title, due: due, source: source)
        item.isCompleted = completed
        item.container = TaskContainer(id: container, name: container, colorHex: nil)
        return item
    }

    private func event(_ id: String, start: Date, end: Date? = nil, allDay: Bool = false, busy: Bool = true) -> CalendarEvent {
        CalendarEvent(id: id, externalID: nil, calendarID: "deadlines", title: "Termin \(id)", start: start,
                      end: end ?? start.addingTimeInterval(3600), isAllDay: allDay, url: nil, isBusy: busy, version: "1")
    }

    private func plan(_ tasks: [TaskItem], events: [CalendarEvent] = [], rules: NotificationRules? = nil) -> [PlannedNotification] {
        notificationPlan(tasks: tasks, deadlineEvents: events, rules: rules ?? self.rules, now: now, calendar: calendar)
    }

    @Test func completedAndUndatedTasks_excluded() {
        let due = DueDate(year: 2026, month: 11, day: 19, hour: 12)
        let result = plan([
            task("Erledigt", source: .local, due: due, completed: true),
            task("Ohne Datum", source: .github, due: nil),
            task("Offen", source: .github, due: due),
        ])
        #expect(result.map(\.title) == ["Offen"])
        #expect(result.first?.source == .github)
    }

    @Test func allSources_includedByDefault() {
        let due = DueDate(year: 2026, month: 11, day: 19, hour: 12)
        let result = plan([
            task("Erinnerung", source: .reminders, due: due, container: "Einkauf"),
            task("Issue", source: .github, due: due),
            task("Lokal", source: .local, due: due),
        ])
        #expect(Set(result.compactMap(\.source)) == [.reminders, .github, .local])
        #expect(result.first { $0.source == .reminders }?.body == "Fällig heute um 12:00 · Einkauf")
    }

    @Test func taskSources_limitTheSources() {
        var only = rules
        only.taskSources = [.local]
        let due = DueDate(year: 2026, month: 11, day: 19, hour: 12)
        let result = plan([task("Erinnerung", source: .reminders, due: due), task("Issue", source: .github, due: due),
                           task("Lokal", source: .local, due: due)], rules: only)
        #expect(result.map(\.title) == ["Lokal"])
    }

    @Test func githubDateOnly_firesAt9OnDueDayWithoutLeadTime() {
        let result = plan([task("Issue", source: .github, due: DueDate(year: 2026, month: 11, day: 19))])
        #expect(result.first?.fireDate == instant(2026, 11, 19, 9, 0, in: calendar))
    }

    @Test func localDateOnly_firesAt9OnDueDayWithoutLeadTime() {
        let result = plan([task("Lokal", source: .local, due: DueDate(year: 2026, month: 11, day: 19))])
        #expect(result.first?.fireDate == instant(2026, 11, 19, 9, 0, in: calendar))
    }

    @Test func dateOnlyToday_afterMorning_skipped() {
        // Due today without time; 09:00 has passed at 10:00, so there is nothing left to remind of.
        let tasks = [task("Heute", source: .local, due: DueDate(year: 2026, month: 11, day: 18))]
        let morning = notificationPlan(tasks: tasks, deadlineEvents: [], rules: rules, now: now, calendar: calendar)
        let late = notificationPlan(tasks: tasks, deadlineEvents: [], rules: rules,
                                    now: instant(2026, 11, 18, 10, 0, in: calendar), calendar: calendar)
        #expect(morning.first?.fireDate == instant(2026, 11, 18, 9, 0, in: calendar))
        #expect(late.isEmpty)
    }

    @Test func timedTask_firesAtDueMinusLeadTime() {
        let result = plan([task("Lokal", source: .local, due: DueDate(year: 2026, month: 11, day: 18, hour: 14, minute: 30))])
        #expect(result.first?.fireDate == instant(2026, 11, 18, 12, 30, in: calendar))
        #expect(result.first?.body == "Fällig heute um 14:30 · Lokal")
    }

    @Test func fireDateInPast_skipped() {
        // Due in one hour with two hours lead time: the moment to remind has passed.
        let result = plan([task("Bald", source: .local, due: DueDate(year: 2026, month: 11, day: 18, hour: 9))])
        #expect(result.isEmpty)
    }

    @Test func fireDateWithinMargin_skipped() {
        // Due 10:00, fires 08:00. 30 s before that is too close; 90 s before is fine.
        let tasks = [task("Knapp", source: .local, due: DueDate(year: 2026, month: 11, day: 18, hour: 10))]
        let tooClose = notificationPlan(tasks: tasks, deadlineEvents: [], rules: rules,
                                        now: now.addingTimeInterval(-30), calendar: calendar)
        let inTime = notificationPlan(tasks: tasks, deadlineEvents: [], rules: rules,
                                      now: now.addingTimeInterval(-90), calendar: calendar)
        #expect(tooClose.isEmpty)
        #expect(inTime.count == 1)
    }

    @Test func timedDeadlineEvent_firesAtStartMinusLeadTime() {
        let result = plan([], events: [event("klausur", start: instant(2026, 11, 20, 10, 0, in: calendar))])
        #expect(result.first?.fireDate == instant(2026, 11, 20, 8, 0, in: calendar))
        #expect(result.first?.body == "Deadline heute um 10:00")
        #expect(result.first?.target == .event(id: "klausur", day: PlanDay(year: 2026, month: 11, day: 20)))
        #expect(result.first?.source == nil)
    }

    @Test func allDayDeadlineEvent_firesPreviousDayAt18() {
        let start = instant(2026, 11, 20, 0, 0, in: calendar)
        let result = plan([], events: [event("abgabe", start: start, end: instant(2026, 11, 22, 0, 0, in: calendar), allDay: true)])
        #expect(result.first?.fireDate == instant(2026, 11, 19, 18, 0, in: calendar))
        #expect(result.first?.body == "Deadline morgen, ganztägig")
    }

    @Test func allDayFreeEvent_included() {
        let start = instant(2026, 11, 20, 0, 0, in: calendar)
        let result = plan([], events: [event("frei", start: start, allDay: true, busy: false)])
        #expect(result.count == 1)
    }

    @Test func deadlineCalendarsSwitchOff_excludesEvents() {
        var off = rules
        off.includesDeadlineCalendars = false
        let result = plan([], events: [event("klausur", start: instant(2026, 11, 20, 10, 0, in: calendar))], rules: off)
        #expect(result.isEmpty)
    }

    @Test func limit_keepsEarliestFifty() {
        let tasks = Array(0..<60).reversed().map { (minute: Int) in
            task("T\(minute)", source: .local, due: DueDate(year: 2026, month: 12, day: 1, hour: 10, minute: minute))
        }
        let result = plan(tasks)
        #expect(result.count == 50)
        #expect(result.first?.title == "T0")
        #expect(result.last?.title == "T49")
    }

    @Test func identifiers_areStable() {
        let due = DueDate(year: 2026, month: 11, day: 19)
        let first = plan([task("Alt", source: .github, due: due)])
        var renamed = task("Alt", source: .github, due: due)
        renamed.title = "Neu"
        let second = plan([renamed])
        #expect(first.first?.id == "tagwerk.task.github:Alt")
        #expect(first.first?.id == second.first?.id)
        let events = plan([], events: [event("e1", start: instant(2026, 11, 20, 10, 0, in: calendar))])
        #expect(events.first?.id == "tagwerk.event.e1")
    }

    @Test func dateOnlyBody_hasNoTime() {
        let result = plan([task("Issue", source: .github, due: DueDate(year: 2026, month: 11, day: 18), container: "beispiel/webshop")])
        #expect(result.first?.body == "Fällig heute · beispiel/webshop")
    }

    @Test func body_usesRelativeDayOfFireDate() {
        var long = rules
        long.leadTimeMinutes = 48 * 60
        let result = notificationPlan(
            tasks: [
                task("Morgen", source: .local, due: DueDate(year: 2026, month: 11, day: 21, hour: 9)),
                task("Später", source: .github, due: DueDate(year: 2026, month: 11, day: 22), container: "beispiel/webshop"),
            ],
            deadlineEvents: [event("d", start: instant(2026, 11, 22, 10, 0, in: calendar))],
            rules: long, now: now, calendar: calendar)
        let bodies = Dictionary(uniqueKeysWithValues: result.map { ($0.title, $0.body) })
        // Fires on Thursday 19 Nov at 09:00; the task is due on Saturday.
        #expect(bodies["Morgen"] == "Fällig am Sa., 21.11. um 09:00 · Lokal")
        // Without time it fires on the due day itself, independent of the lead time.
        #expect(bodies["Später"] == "Fällig heute · beispiel/webshop")
        #expect(bodies["Termin d"] == "Deadline am So., 22.11. um 10:00")
    }

    @Test func relativeDay_tomorrow() {
        var long = rules
        long.leadTimeMinutes = 24 * 60
        let result = plan([task("Morgen", source: .local, due: DueDate(year: 2026, month: 11, day: 20, hour: 9))], rules: long)
        #expect(result.first?.body == "Fällig morgen um 09:00 · Lokal")
    }

    @Test func emptyTitle_usesPlaceholder() {
        let result = plan([task("", source: .local, due: DueDate(year: 2026, month: 11, day: 19))])
        #expect(result.first?.title == "Ohne Titel")
    }

    @Test func dstChange_keepsWallClockTime() {
        // Summer time ends in Berlin on 25 Oct 2026; the due date on the 26th still fires at 09:00 local time.
        let october = instant(2026, 10, 20, 8, 0, in: calendar)
        let result = notificationPlan(tasks: [task("Herbst", source: .local, due: DueDate(year: 2026, month: 10, day: 26))],
                                      deadlineEvents: [], rules: rules, now: october, calendar: calendar)
        let parts = calendar.dateComponents([.hour, .minute], from: result.first!.fireDate)
        #expect(parts.hour == 9)
        #expect(parts.minute == 0)
    }
}
