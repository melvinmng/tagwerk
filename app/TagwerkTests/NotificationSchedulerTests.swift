import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct NotificationSchedulerTests {
    let container: ModelContainer
    let settings: AppSettings
    let center = FakeNotificationCenter()
    let github = FakeTaskProvider(source: .github)
    let local = FakeTaskProvider(source: .local)
    let reminders = FakeTaskProvider(source: .reminders)
    let calendar = testCalendar()
    var events: [CalendarEvent] = []
    var calendarAccess = true

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.deadlineCalendarIDs = ["deadlines"]
    }

    private func due(_ day: Int, _ hour: Int? = nil) -> DueDate { DueDate(year: 2026, month: 11, day: day, hour: hour) }

    private func makeScheduler(_ list: TaskListModel) -> NotificationScheduler {
        let events = self.events
        let access = calendarAccess
        return NotificationScheduler(center: center, taskList: list,
                                     deadlineEvents: { _, ids in access ? events.filter { ids.contains($0.calendarID) } : nil },
                                     settings: settings, now: { testNow() }, calendar: calendar)
    }

    private func loadedList(_ providers: [FakeTaskProvider]? = nil) async -> TaskListModel {
        let list = TaskListModel(providers: providers ?? [github, local, reminders])
        await list.reload()
        return list
    }

    private func event(_ id: String, day: Int, hour: Int) -> CalendarEvent {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        return CalendarEvent(id: id, externalID: nil, calendarID: "deadlines", title: id, start: start,
                             end: start.addingTimeInterval(3600), isAllDay: false, url: nil, isBusy: true, version: "1")
    }

    @Test func noAuthorization_schedulesNothing() async {
        center.status = .notDetermined
        local.tasks = [makeTask("A", source: .local, due: due(20))]
        let scheduler = makeScheduler(await loadedList())
        await scheduler.reschedule()
        #expect(center.pending.isEmpty)
        #expect(scheduler.authorization == .notDetermined)
    }

    @Test func schedulesGitHubAndLocal_notReminders() async {
        github.tasks = [makeTask("Issue", source: .github, due: due(20))]
        local.tasks = [makeTask("Lokal", source: .local, due: due(20, 9))]
        reminders.tasks = [makeTask("Erinnerung", source: .reminders, due: due(20))]
        let scheduler = makeScheduler(await loadedList())
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.task.github:Issue", "tagwerk.task.local:Lokal"])
    }

    @Test func completedTask_removesItsNotification() async {
        local.tasks = [makeTask("A", source: .local, due: due(20)), makeTask("B", source: .local, due: due(21))]
        let list = await loadedList()
        let scheduler = makeScheduler(list)
        await scheduler.reschedule()
        local.tasks.removeAll { $0.title == "A" }
        await list.reload()
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.task.local:B"])
    }

    @Test func dueChanged_replacesNotification() async {
        local.tasks = [makeTask("A", source: .local, due: due(20))]
        let list = await loadedList()
        let scheduler = makeScheduler(list)
        await scheduler.reschedule()
        local.tasks = [makeTask("A", source: .local, due: due(25))]
        await list.reload()
        await scheduler.reschedule()
        let expected = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 9))
        #expect(center.pending["tagwerk.task.local:A"]?.fireDate == expected)
    }

    @Test func leadTimeChanged_reschedulesAll() async {
        // A task with time: tasks without time remind at 09:00 regardless of the lead time.
        local.tasks = [makeTask("A", source: .local, due: due(20, 18))]
        let scheduler = makeScheduler(await loadedList())
        await scheduler.reschedule()
        settings.leadTimeMinutes = 60
        await scheduler.reschedule()
        let expected = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 17))
        #expect(center.pending["tagwerk.task.local:A"]?.fireDate == expected)
    }

    @Test mutating func deadlineSwitchOff_removesEventNotifications() async {
        events = [event("klausur", day: 20, hour: 10)]
        let scheduler = makeScheduler(await loadedList())
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.event.klausur"])
        settings.deadlineCalendarNotifications = false
        await scheduler.reschedule()
        #expect(center.pending.isEmpty)
    }

    @Test mutating func noCalendarAccess_keepsEventNotifications() async {
        center.seed("tagwerk.event.klausur", fireDate: testNow().addingTimeInterval(86_400))
        calendarAccess = false
        let scheduler = makeScheduler(await loadedList())
        await scheduler.reschedule()
        #expect(center.pendingIDs.contains("tagwerk.event.klausur"))
    }

    @Test func githubNotLoaded_keepsExistingGitHubNotifications() async {
        // A background launch before GitHub is registered: GitHub has no state at all.
        center.seed("tagwerk.task.github:Issue", fireDate: testNow().addingTimeInterval(86_400))
        local.tasks = [makeTask("Lokal", source: .local, due: due(20))]
        let scheduler = makeScheduler(await loadedList([local, reminders]))
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.task.github:Issue", "tagwerk.task.local:Lokal"])
    }

    @Test func githubFailed_keepsExistingGitHubNotifications() async {
        center.seed("tagwerk.task.github:Issue", fireDate: testNow().addingTimeInterval(86_400))
        github.readError = .failed("kaputt")
        let scheduler = makeScheduler(await loadedList())
        await scheduler.reschedule()
        #expect(center.pendingIDs.contains("tagwerk.task.github:Issue"))
    }

    @Test func githubOffline_replacesFromCache() async {
        center.seed("tagwerk.task.github:Alt", fireDate: testNow().addingTimeInterval(86_400))
        github.tasks = [makeTask("Neu", source: .github, due: due(20))]
        github.offlineSince = testNow()
        let scheduler = makeScheduler(await loadedList())
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.task.github:Neu"])
    }

    @Test func githubSignedOut_removesGitHubNotifications() async {
        github.tasks = [makeTask("Issue", source: .github, due: due(20))]
        let list = await loadedList()
        let scheduler = makeScheduler(list)
        await scheduler.reschedule()
        github.readError = .signedOut
        await list.reload()
        await scheduler.reschedule()
        #expect(center.pending.isEmpty)
    }

    @Test func githubVoluntarySignOut_removesGitHubNotifications() async {
        github.tasks = [makeTask("Issue", source: .github, due: due(20))]
        local.tasks = [makeTask("Lokal", source: .local, due: due(20))]
        let list = await loadedList()
        let scheduler = makeScheduler(list)
        await scheduler.reschedule()
        await list.unregister(.github)
        await scheduler.removeNotifications(of: .github)
        #expect(center.pendingIDs == ["tagwerk.task.local:Lokal"])
    }

    @Test func foreignPendingRequests_untouched() async {
        center.seed("other.request", fireDate: testNow().addingTimeInterval(60))
        let scheduler = makeScheduler(await loadedList())
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["other.request"])
    }

    @Test func overduePendingRequest_removed() async {
        center.seed("tagwerk.task.github:Alt", fireDate: nil)
        center.seed("tagwerk.event.vorbei", fireDate: testNow().addingTimeInterval(-60))
        let scheduler = makeScheduler(await loadedList([local]))
        await scheduler.reschedule()
        #expect(center.pending.isEmpty)
    }

    @Test func limit_countsKeptRequests() async {
        for index in 0..<10 {
            center.seed("tagwerk.task.github:K\(index)", fireDate: testNow().addingTimeInterval(86_400))
        }
        local.tasks = (0..<60).map { (minute: Int) in
            makeTask("L\(minute)", source: .local, due: DueDate(year: 2026, month: 11, day: 25, hour: 12, minute: minute))
        }
        let scheduler = makeScheduler(await loadedList([local]))
        await scheduler.reschedule()
        #expect(center.pending.count == 50)
        #expect(center.pendingIDs.contains("tagwerk.task.local:L39"))
        #expect(!center.pendingIDs.contains("tagwerk.task.local:L40"))
    }

    @Test func requestAuthorization_grantedReschedulesAtOnce() async {
        center.status = .notDetermined
        local.tasks = [makeTask("A", source: .local, due: due(20))]
        let scheduler = makeScheduler(await loadedList())
        let granted = await scheduler.requestAuthorization()
        #expect(granted)
        #expect(center.pendingIDs == ["tagwerk.task.local:A"])
    }

    @Test func pendingWithinMargin_kept() async {
        // Due 12:00 with 2 h lead time fires at 10:00, 30 s after "now" (09:59:30), inside the 60 s margin.
        center.seed("tagwerk.task.local:Gleich", fireDate: testNow())
        local.tasks = [makeTask("Gleich", source: .local, due: due(18, 12))]
        let scheduler = NotificationScheduler(center: center, taskList: await loadedList([local]),
                                              deadlineEvents: { _, _ in [] }, settings: settings,
                                              now: { testNow().addingTimeInterval(-30) }, calendar: calendar)
        await scheduler.reschedule()
        #expect(center.pendingIDs.contains("tagwerk.task.local:Gleich"))
        #expect(center.added.isEmpty)
    }

    @Test func pendingWithinMarginButMoved_removed() async {
        center.seed("tagwerk.task.local:Gleich", fireDate: testNow().addingTimeInterval(30))
        local.tasks = [makeTask("Gleich", source: .local, due: due(25))]
        let scheduler = makeScheduler(await loadedList([local]))
        await scheduler.reschedule()
        let expected = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 9))
        #expect(center.pending["tagwerk.task.local:Gleich"]?.fireDate == expected)
    }

    @Test func concurrentRuns_doNotReviveRemovedNotifications() async {
        local.tasks = [makeTask("A", source: .local, due: due(20))]
        let list = await loadedList([local])
        let scheduler = makeScheduler(list)
        center.addDelay = .milliseconds(100)
        let first = Task { await scheduler.reschedule() }
        await Task.yield()
        local.tasks = []
        await list.reload()
        await scheduler.reschedule()
        await first.value
        #expect(center.pending.isEmpty)
    }
}
