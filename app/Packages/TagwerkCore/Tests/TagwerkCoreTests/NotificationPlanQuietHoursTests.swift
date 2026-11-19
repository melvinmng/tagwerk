import Foundation
import Testing
@testable import TagwerkCore

/// Quiet hours and the Focus filter in `notificationPlan` (plan quiet-hours, #169). The tests of the plan without
/// them stay in `NotificationPlanTests`.
struct NotificationPlanQuietHoursTests {
    let calendar = makeCalendar()
    /// Wednesday, 18 Nov 2026, 08:00 in Berlin.
    var now: Date { at(18, 8, 0) }
    let night = QuietHours(startMinutes: 23 * 60, endMinutes: 7 * 60)

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { instant(2026, 11, day, hour, minute, in: calendar) }

    private func rules(leadTime: Int = 0, quietHours: QuietHours? = nil, hold: FocusHold? = nil, catchUp: Date? = nil,
                       limit: Int = 50) -> NotificationRules {
        NotificationRules(leadTimeMinutes: leadTime, includesDeadlineCalendars: true, limit: limit, quietHours: quietHours,
                          focusHold: hold, focusCatchUpFrom: catchUp)
    }

    private func task(_ title: String, day: Int, hour: Int? = nil, minute: Int = 0) -> TaskItem {
        makeItem(title, due: DueDate(year: 2026, month: 11, day: day, hour: hour, minute: hour == nil ? nil : minute))
    }

    private func event(_ id: String, start: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, externalID: nil, calendarID: "deadlines", title: "Termin \(id)", start: start,
                      end: start.addingTimeInterval(3600), isAllDay: allDay, url: nil, isBusy: true, version: "1")
    }

    private func plan(_ tasks: [TaskItem] = [], events: [CalendarEvent] = [], rules: NotificationRules, now: Date? = nil)
        -> [PlannedNotification] {
        notificationPlan(tasks: tasks, deadlineEvents: events, rules: rules, now: now ?? self.now, calendar: calendar,
                         locale: Locale(identifier: "de_DE"))
    }

    // MARK: Off

    @Test func withoutQuietHours_nothingMoves() {
        let tasks = [task("A", day: 18, hour: 23, minute: 30), task("B", day: 19, hour: 2)]
        let result = plan(tasks, rules: rules())
        #expect(result.map(\.fireDate) == [at(18, 23, 30), at(19, 2)])
        #expect(result.first?.body == "Fällig heute um 23:30 · Lokal")
    }

    // MARK: Tasks

    @Test func taskInTheWindow_firesAtTheEnd_andSaysItWasDue() {
        let result = plan([task("A", day: 18, hour: 23, minute: 30)], rules: rules(quietHours: night))
        #expect(result.map(\.fireDate) == [at(19, 7)])
        #expect(result.first?.body == "War fällig gestern um 23:30 · Lokal")
    }

    @Test func taskDueAfterTheEnd_isMovedButNotOverdue() {
        // Fires at 06:00 with two hours of lead time, is due at 08:00: it fires at 07:00 and is still ahead.
        let result = plan([task("A", day: 19, hour: 8)], rules: rules(leadTime: 120, quietHours: night))
        #expect(result.map(\.fireDate) == [at(19, 7)])
        #expect(result.first?.body == "Fällig heute um 08:00 · Lokal")
    }

    @Test func taskDueInsideTheWindow_afterMidnight_isOverdueToday() {
        let result = plan([task("A", day: 19, hour: 1)], rules: rules(quietHours: night))
        #expect(result.map(\.fireDate) == [at(19, 7)])
        #expect(result.first?.body == "War fällig heute um 01:00 · Lokal")
    }

    @Test func fireAtTheEnd_isNotMoved() {
        let result = plan([task("A", day: 19, hour: 9)], rules: rules(leadTime: 120, quietHours: night))
        #expect(result.map(\.fireDate) == [at(19, 7)])
        #expect(result.first?.body == "Fällig heute um 09:00 · Lokal")
    }

    @Test func dateOnlyTask_movedWithinItsDay_staysDue() {
        // The morning reminder at 09:00 falls into a window from 08:00 to 10:00.
        let morning = QuietHours(startMinutes: 8 * 60, endMinutes: 10 * 60)
        let result = plan([task("A", day: 19)], rules: rules(quietHours: morning))
        #expect(result.map(\.fireDate) == [at(19, 10)])
        #expect(result.first?.body == "Fällig heute · Lokal")
    }

    @Test func dateOnlyTask_movedIntoTheNextDay_isOverdue() {
        // A window from 08:30 to midnight pushes the 09:00 reminder of 19 Nov to 00:00 of 20 Nov.
        let day = QuietHours(startMinutes: 8 * 60 + 30, endMinutes: 0)
        let result = plan([task("A", day: 19)], rules: rules(quietHours: day))
        #expect(result.map(\.fireDate) == [at(20, 0)])
        #expect(result.first?.body == "War fällig gestern · Lokal")
    }

    @Test func overdueTextTwoDaysBack_namesTheDate() {
        // 23:30 on 18 Nov, moved by a window that ends only on 20 Nov 07:00 is not possible with daily windows;
        // the Focus hold can reach that far.
        let hold = FocusHold(from: at(18, 8), until: at(20, 7))
        let result = plan([task("A", day: 18, hour: 12)], rules: rules(hold: hold))
        #expect(result.first?.fireDate == at(20, 7))
        #expect(result.first?.body == "War fällig am Mi., 18.11. um 12:00 · Lokal")
    }

    // MARK: Events

    @Test func timedEvent_inTheWindow_firesAtTheEnd() {
        let result = plan(events: [event("klausur", start: at(19, 2))], rules: rules(leadTime: 120, quietHours: night))
        #expect(result.map(\.fireDate) == [at(19, 7)])
        #expect(result.first?.body == "Deadline war heute um 02:00")
    }

    @Test func timedEvent_startingAfterTheEnd_keepsTheNormalText() {
        let result = plan(events: [event("klausur", start: at(19, 8, 30))], rules: rules(leadTime: 120, quietHours: night))
        #expect(result.map(\.fireDate) == [at(19, 7)])
        #expect(result.first?.body == "Deadline heute um 08:30")
    }

    @Test func allDayEvent_firesInsideTheWindow_isMoved() {
        // Reminder at 18:00 the evening before; a window from 17:00 to 19:00 moves it to 19:00, the event is still ahead.
        let evening = QuietHours(startMinutes: 17 * 60, endMinutes: 19 * 60)
        let result = plan(events: [event("abgabe", start: at(20, 0), allDay: true)], rules: rules(quietHours: evening))
        #expect(result.map(\.fireDate) == [at(19, 19)])
        #expect(result.first?.body == "Deadline morgen, ganztägig")
    }

    @Test func allDayEvent_movedIntoTheEventDay_isNotOverdueYet() {
        let overnight = QuietHours(startMinutes: 17 * 60, endMinutes: 7 * 60)
        let result = plan(events: [event("abgabe", start: at(20, 0), allDay: true)], rules: rules(quietHours: overnight))
        #expect(result.map(\.fireDate) == [at(20, 7)])
        #expect(result.first?.body == "Deadline heute, ganztägig")
    }

    // MARK: Order, limit, guard

    @Test func shiftedNotifications_keepTheirOrderById_andTheLimitAppliesAfterwards() {
        let tasks = [task("B", day: 18, hour: 23, minute: 30), task("A", day: 19, hour: 2), task("C", day: 18, hour: 12),
                     task("D", day: 19, hour: 7, minute: 30)]
        let all = plan(tasks, rules: rules(quietHours: night))
        #expect(all.map(\.title) == ["C", "A", "B", "D"])
        #expect(all.map(\.fireDate) == [at(18, 12), at(19, 7), at(19, 7), at(19, 7, 30)])
        // Without the shift D would come before B and be kept by a limit of three.
        let limited = plan(tasks, rules: rules(quietHours: night, limit: 3))
        #expect(limited.map(\.title) == ["C", "A", "B"])
    }

    @Test func notificationDuringTheNight_whoseOriginalTimeIsPast_isStillPlannedForTheMorning() {
        // 02:00: the original 23:30 is behind us, but the moved notification at 07:00 has not fired yet.
        let result = plan([task("A", day: 18, hour: 23, minute: 30)], rules: rules(quietHours: night), now: at(19, 2))
        #expect(result.map(\.fireDate) == [at(19, 7)])
        // Without quiet hours it is simply gone.
        #expect(plan([task("A", day: 18, hour: 23, minute: 30)], rules: rules(), now: at(19, 2)).isEmpty)
    }

    @Test func notificationOutsideTheWindow_whoseTimeIsPast_staysGone() {
        let result = plan([task("A", day: 18, hour: 12)], rules: rules(quietHours: night), now: at(18, 13))
        #expect(result.isEmpty)
    }

    @Test func oldNotification_movedToAnEndThatIsPast_staysGone() {
        let result = plan([task("A", day: 16, hour: 23, minute: 30)], rules: rules(quietHours: night), now: at(19, 2))
        #expect(result.isEmpty)
    }

    @Test func movedNotification_respectsTheMinimumDelay() {
        // At 06:59:30 the end is 30 seconds away: closer than the margin of a minute.
        let nearEnd = at(19, 6, 59).addingTimeInterval(30)
        var margin = rules(quietHours: night)
        margin.minimumDelay = 60
        #expect(plan([task("A", day: 19, hour: 1)], rules: margin, now: nearEnd).isEmpty)
        margin.minimumDelay = 0
        #expect(plan([task("A", day: 19, hour: 1)], rules: margin, now: nearEnd).map(\.fireDate) == [at(19, 7)])
    }

    @Test func daylightSaving_movedFireDateIsLocalSeven() {
        let before = instant(2026, 3, 28, 12, 0, in: calendar)
        let due = DueDate(year: 2026, month: 3, day: 28, hour: 23, minute: 30)
        let result = notificationPlan(tasks: [makeItem("A", due: due)], deadlineEvents: [], rules: rules(quietHours: night),
                                      now: before, calendar: calendar, locale: Locale(identifier: "de_DE"))
        #expect(result.map(\.fireDate) == [instant(2026, 3, 29, 7, 0, in: calendar)])
    }

    // MARK: Focus filter

    @Test func focusHold_movesWhatFiresInsideIt_andLeavesTheRest() {
        let hold = FocusHold(from: at(18, 8), until: at(19, 7))
        let tasks = [task("Heute", day: 18, hour: 14), task("Morgen", day: 19, hour: 12), task("Vorher", day: 18, hour: 7, minute: 30)]
        let result = plan(tasks, rules: rules(hold: hold))
        #expect(result.map(\.title) == ["Heute", "Morgen"])
        #expect(result.map(\.fireDate) == [at(19, 7), at(19, 12)])
        #expect(result.first?.body == "War fällig gestern um 14:00 · Lokal")
    }

    @Test func focusHold_endingInsideTheQuietHours_isMovedOnToTheirEnd() {
        let hold = FocusHold(from: at(18, 8), until: at(18, 23, 30))
        let result = plan([task("A", day: 18, hour: 14)], rules: rules(quietHours: night, hold: hold))
        #expect(result.map(\.fireDate) == [at(19, 7)])
    }

    @Test func focusCatchUp_firesWhatCameDueWhileHeld() {
        let later = at(18, 12)
        let tasks = [task("Gehalten", day: 18, hour: 10), task("Davor", day: 18, hour: 8, minute: 30), task("Später", day: 18, hour: 15)]
        var catchUp = rules(catchUp: at(18, 9))
        catchUp.minimumDelay = NotificationRules.defaultMinimumDelay
        let result = plan(tasks, rules: catchUp, now: later)
        #expect(result.map(\.title) == ["Gehalten", "Später"])
        #expect(result.first?.fireDate == later.addingTimeInterval(60))
        #expect(result.first?.body == "War fällig heute um 10:00 · Lokal")
    }

    @Test func focusCatchUp_withSchedulerMargin_staysAMinuteAhead() {
        // The scheduler plans without a margin (minimumDelay 0) and drops anything closer than a minute.
        var catchUp = rules(catchUp: at(18, 9))
        catchUp.minimumDelay = 0
        let result = plan([task("A", day: 18, hour: 10)], rules: catchUp, now: at(18, 12))
        #expect(result.first?.fireDate == at(18, 12).addingTimeInterval(NotificationRules.defaultMinimumDelay))
    }

    @Test func focusCatchUp_insideTheQuietHours_waitsForTheEnd() {
        let result = plan([task("A", day: 18, hour: 22)], rules: rules(quietHours: night, catchUp: at(18, 20)), now: at(18, 23, 30))
        #expect(result.map(\.fireDate) == [at(19, 7)])
    }
}
