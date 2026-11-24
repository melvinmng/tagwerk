import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Quiet hours and the Focus filter in the scheduler (plan quiet-hours, #169). `now` is Wednesday 2026-11-18 10:00 unless
/// a test moves it.
@MainActor
struct NotificationSchedulerQuietHoursTests {
    let container: ModelContainer
    let settings: AppSettings
    let center = FakeNotificationCenter()
    let local = FakeTaskProvider(source: .local)
    let calendar = testCalendar()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.deadlineCalendarIDs = []
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func task(_ title: String, day: Int, hour: Int, minute: Int = 0) -> TaskItem {
        makeTask(title, source: .local, due: DueDate(year: 2026, month: 11, day: day, hour: hour, minute: minute))
    }

    private func scheduler(now: Date) async -> NotificationScheduler {
        let list = TaskListModel(providers: [local])
        await list.reload()
        return NotificationScheduler(center: center, taskList: list, deadlineEvents: { _, _ in [] }, settings: settings,
                                     now: { now }, calendar: calendar, locale: { Locale(identifier: "de_DE") })
    }

    private func enableQuietHours(coupledToBedtime: Bool = false) {
        settings.quietHoursEnabled = true
        settings.quietHoursStartsAtBedtime = coupledToBedtime
        settings.quietStartMinutes = 23 * 60
        settings.quietEndMinutes = 7 * 60
    }

    @Test func quietHoursOff_firesAtTheOriginalTime() async {
        // Due 01:00 with the default 2 h lead time: 23:00 the evening before.
        local.tasks = [task("A", day: 19, hour: 1)]
        await scheduler(now: testNow()).reschedule()
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == at(18, 23))
    }

    @Test func quietHoursOn_movesTheRequestToTheEnd_withTheOverdueText() async {
        enableQuietHours()
        local.tasks = [task("A", day: 19, hour: 1)]
        await scheduler(now: testNow()).reschedule()
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == at(19, 7))
        #expect(center.added.last?.body == "Seit heute, 01:00 fällig · local")
    }

    @Test func windowStartFollowsTheBedtime_whileCoupled() async {
        enableQuietHours(coupledToBedtime: true)
        settings.bedtimeMinutes = 22 * 60
        // Due 00:30, fires 22:30: inside 22:00-07:00, outside the default 23:00-07:00 only by half an hour.
        local.tasks = [task("A", day: 19, hour: 0, minute: 30)]
        await scheduler(now: testNow()).reschedule()
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == at(19, 7))
        settings.bedtimeMinutes = 23 * 60 + 30
        await scheduler(now: testNow()).reschedule()
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == at(18, 22, 30))
    }

    @Test func rescheduleDuringTheNight_keepsTheMovedRequest() async {
        enableQuietHours()
        local.tasks = [task("A", day: 19, hour: 1)]
        await scheduler(now: testNow()).reschedule()
        center.clearAdded()
        // 02:00: the original 23:00 is long past, but the request for 07:00 must survive any run.
        await scheduler(now: at(19, 2)).reschedule()
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == at(19, 7))
    }

    @Test func limitAndOrder_workWithMovedTimes() async {
        enableQuietHours()
        local.tasks = (0..<60).map { task("T\(String(format: "%02d", $0))", day: 19, hour: 1, minute: $0) }
        await scheduler(now: testNow()).reschedule()
        #expect(center.pending.count == NotificationScheduler.limit)
        #expect(center.pending.values.allSatisfy { $0.fireDate == at(19, 7) })
        // All share one time: the order falls back to the identifier, so the first 44 identifiers stay.
        #expect(center.pendingIDs.contains("tagwerk.task.local:T43#0"))
        #expect(!center.pendingIDs.contains("tagwerk.task.local:T44#0"))
    }

    // MARK: Focus filter

    @Test func focusActive_withoutQuietHours_holdsForFourHours() async {
        settings.focusQuietSince = at(18, 9)
        local.tasks = [task("A", day: 18, hour: 14)]  // fires 12:00
        await scheduler(now: testNow()).reschedule()
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == at(18, 13))
    }

    @Test func focusActive_withQuietHours_holdsForFourHours() async {
        enableQuietHours()
        settings.focusQuietSince = at(18, 9)
        local.tasks = [task("A", day: 18, hour: 14)]  // fires 12:00
        await scheduler(now: testNow()).reschedule()
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == at(18, 13))
    }

    @Test func focusActive_fallbackInsideQuietHours_movesToTheirEnd() async {
        enableQuietHours()
        settings.focusQuietSince = at(18, 20)
        local.tasks = [task("A", day: 18, hour: 23, minute: 30)]  // fires 21:30; four hours after 20:00 is 00:00
        await scheduler(now: at(18, 21)).reschedule()
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == at(19, 7))
    }

    @Test func focusEndsAfterTheFallback_deliversNothingTwice() async {
        enableQuietHours()
        settings.focusQuietSince = at(18, 9)
        local.tasks = [task("A", day: 18, hour: 14)]  // fires 12:00, held until 13:00
        await scheduler(now: testNow()).reschedule()
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == at(18, 13))
        // 13:00 passes and iOS delivers the held notification.
        center.removePendingForTest("tagwerk.task.local:A#0")
        // The end of the Focus is reported late, after the fallback target.
        let late = at(18, 17)
        settings.focusQuietState = FocusQuiet.applying(active: false, now: late, to: settings.focusQuietState,
                                                       quietHours: settings.quietHours, calendar: calendar)
        await scheduler(now: late).reschedule()
        #expect(center.pending.isEmpty)
        #expect(settings.focusQuietState == FocusQuiet.State())
    }

    @Test func focusEndsEarly_restoresTheOriginalTime() async {
        settings.focusQuietSince = at(18, 9)
        local.tasks = [task("A", day: 18, hour: 14)]
        await scheduler(now: testNow()).reschedule()
        settings.focusQuietState = FocusQuiet.applying(active: false, now: testNow(), to: settings.focusQuietState)
        await scheduler(now: testNow()).reschedule()
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == at(18, 12))
    }

    @Test func focusEnded_catchesUpWhatCameDueMeanwhile_once() async {
        local.tasks = [task("A", day: 18, hour: 13), task("B", day: 18, hour: 8)]  // fire 11:00 and 06:00
        settings.focusQuietState = FocusQuiet.State(since: nil, catchUpFrom: at(18, 9))
        let now = at(18, 13)
        let first = await scheduler(now: now)
        await first.reschedule()
        let catchUpMoment = now.addingTimeInterval(60)
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == catchUpMoment)
        #expect(center.pending["tagwerk.task.local:B#0"] == nil)  // came due before the Focus started
        #expect(center.added.last?.body == "Seit heute, 13:00 fällig · local")

        // A second run before the moment plans the same one; after it, nothing is planned again.
        await scheduler(now: now.addingTimeInterval(30)).reschedule()
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == catchUpMoment)
        center.removePendingForTest("tagwerk.task.local:A#0")  // delivered
        await scheduler(now: catchUpMoment.addingTimeInterval(5)).reschedule()
        #expect(center.pending.isEmpty)
        #expect(settings.focusQuietState == FocusQuiet.State())
    }

    @Test func secondFocusAfterTheCatchUpFired_doesNotReplayIt() async {
        local.tasks = [task("A", day: 18, hour: 11)]  // fires 09:00; an earlier Focus caught it up at 10:01
        settings.focusQuietState = FocusQuiet.State(since: nil, catchUpFrom: at(18, 8), catchUpAt: at(18, 10, 1))
        settings.focusQuietState = FocusQuiet.applying(active: true, now: at(18, 14), to: settings.focusQuietState,
                                                       quietHours: settings.quietHours, calendar: calendar)
        await scheduler(now: at(18, 14)).reschedule()
        settings.focusQuietState = FocusQuiet.applying(active: false, now: at(18, 15), to: settings.focusQuietState,
                                                       quietHours: settings.quietHours, calendar: calendar)
        await scheduler(now: at(18, 15)).reschedule()
        #expect(center.pending.isEmpty)
    }

    @Test func secondFocusRunningPastItsTarget_doesNotDeliverItsSpanTwice() async {
        // Focus A: 09:00 to 10:00, ended before its target. Its catch-up has no moment yet when Focus B starts half a minute
        // later (the run after the end of A is still busy loading). B never reports its end in time.
        local.tasks = [task("A", day: 18, hour: 11, minute: 30),  // fires 09:30, inside A
                       task("B", day: 18, hour: 13),  // fires 11:00, inside B
                       task("C", day: 18, hour: 18)]  // fires 16:00, after B
        settings.focusQuietSince = at(18, 9)
        settings.focusQuietState = FocusQuiet.applying(active: false, now: at(18, 10), to: settings.focusQuietState,
                                                       quietHours: settings.quietHours, calendar: calendar)
        let startOfB = at(18, 10).addingTimeInterval(30)
        settings.focusQuietState = FocusQuiet.applying(active: true, now: startOfB, to: settings.focusQuietState,
                                                       quietHours: settings.quietHours, calendar: calendar)
        await scheduler(now: startOfB).reschedule()
        let targetOfB = startOfB.addingTimeInterval(FocusQuiet.unreportedEndHold)
        #expect(center.pending["tagwerk.task.local:B#0"]?.fireDate == targetOfB)

        // The target passes and iOS delivers B.
        center.removePendingForTest("tagwerk.task.local:B#0")
        // The end of B is reported late.
        let late = at(18, 15)
        settings.focusQuietState = FocusQuiet.applying(active: false, now: late, to: settings.focusQuietState,
                                                       quietHours: settings.quietHours, calendar: calendar)
        await scheduler(now: late).reschedule()
        // A is caught up once; B was delivered at its target and stays out; C keeps its time.
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == late.addingTimeInterval(60))
        #expect(center.pending["tagwerk.task.local:B#0"] == nil)
        #expect(center.pending["tagwerk.task.local:C#0"]?.fireDate == at(18, 16))
    }

    @Test func staleFocusStart_isDropped() async {
        settings.focusQuietSince = at(16, 9)
        local.tasks = [task("A", day: 18, hour: 14)]
        await scheduler(now: testNow()).reschedule()
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == at(18, 12))
        #expect(settings.focusQuietSince == nil)
    }
}
