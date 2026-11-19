import Foundation
import RemindersKit
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

    private func makeScheduler(_ list: TaskListModel, locale: @escaping () -> Locale = { Locale(identifier: "de_DE") })
        -> NotificationScheduler {
        let events = self.events
        let access = calendarAccess
        return NotificationScheduler(center: center, taskList: list,
                                     deadlineEvents: { _, ids in access ? events.filter { ids.contains($0.calendarID) } : nil },
                                     settings: settings, now: { testNow() }, calendar: calendar, locale: locale)
    }

    /// The text of the last request added for `id`.
    private func lastAdded(_ id: String) -> PlannedNotification? { center.added.last { $0.id == id } }

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

    @Test func shoppingItems_getNoNotification() async {
        let store = InMemoryReminderStore(
            lists: [ListInfo(id: "uni", title: "Uni", colorHex: nil, kind: .calDAV),
                    ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV)],
            records: [ReminderRecord(id: "milk", title: "Milch", notes: nil, due: due(20), ekPriority: 0, isCompleted: false,
                                     listID: "shop", lastModified: nil),
                      ReminderRecord(id: "essay", title: "Abgabe", notes: nil, due: due(20), ekPriority: 0, isCompleted: false,
                                     listID: "uni", lastModified: nil)])
        let provider = RemindersTaskProvider(store: store, selectedListIDs: { nil }, excludedListID: { "shop" })
        let list = TaskListModel(providers: [provider])
        await list.reload()
        let scheduler = makeScheduler(list)
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.task.reminders:essay#0"])
    }

    @Test func schedulesAllSources_byDefault() async {
        github.tasks = [makeTask("Issue", source: .github, due: due(20))]
        local.tasks = [makeTask("Lokal", source: .local, due: due(20, 12))]
        reminders.tasks = [makeTask("Erinnerung", source: .reminders, due: due(20))]
        let scheduler = makeScheduler(await loadedList())
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.task.github:Issue#0", "tagwerk.task.local:Lokal#0", "tagwerk.task.reminders:Erinnerung#0"])
    }

    @Test func sourceSwitchOff_removesOnlyItsNotifications() async {
        github.tasks = [makeTask("Issue", source: .github, due: due(20))]
        local.tasks = [makeTask("Lokal", source: .local, due: due(20, 12))]
        reminders.tasks = [makeTask("Erinnerung", source: .reminders, due: due(20))]
        let scheduler = makeScheduler(await loadedList())
        await scheduler.reschedule()
        settings.githubTaskNotifications = false
        settings.reminderTaskNotifications = false
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.task.local:Lokal#0"])
        settings.localTaskNotifications = false
        await scheduler.reschedule()
        #expect(center.pending.isEmpty)
    }

    @Test func sourceSwitchOff_removesNotificationsAlsoWhenSourceNotLoaded() async {
        // Switched off while GitHub is not registered yet: its pending requests go anyway.
        center.seed("tagwerk.task.github:Issue", fireDate: testNow().addingTimeInterval(86_400))
        settings.githubTaskNotifications = false
        let scheduler = makeScheduler(await loadedList([local, reminders]))
        await scheduler.reschedule()
        #expect(center.pending.isEmpty)
    }

    @Test func completedTask_removesItsNotification() async {
        local.tasks = [makeTask("A", source: .local, due: due(20)), makeTask("B", source: .local, due: due(21))]
        let list = await loadedList()
        let scheduler = makeScheduler(list)
        await scheduler.reschedule()
        local.tasks.removeAll { $0.title == "A" }
        await list.reload()
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.task.local:B#0"])
    }

    @Test func handOver_removesPendingNotification() async {
        var issue = makeTask("Login", source: .github, due: due(20))
        issue.assignees = ["octo"]
        github.tasks = [issue]
        github.viewerLogin = "octo"
        let list = await loadedList()
        let scheduler = makeScheduler(list)
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.task.github:Login#0"])

        issue.assignees = ["lea-m"]
        list.didSave(issue)
        await scheduler.reschedule()
        #expect(center.pendingIDs.isEmpty)
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
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == expected)
    }

    @Test func leadTimeChanged_reschedulesAll() async {
        // A task with time: tasks without time remind at 09:00 regardless of the lead time.
        local.tasks = [makeTask("A", source: .local, due: due(20, 18))]
        let scheduler = makeScheduler(await loadedList())
        await scheduler.reschedule()
        settings.leadTimeMinutes = 60
        await scheduler.reschedule()
        let expected = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 17))
        #expect(center.pending["tagwerk.task.local:A#0"]?.fireDate == expected)
    }

    @Test mutating func deadlineSwitchOff_removesEventNotifications() async {
        events = [event("klausur", day: 20, hour: 10)]
        let scheduler = makeScheduler(await loadedList())
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.event.klausur#0"])
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
        #expect(center.pendingIDs == ["tagwerk.task.github:Issue", "tagwerk.task.local:Lokal#0"])
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
        #expect(center.pendingIDs == ["tagwerk.task.github:Neu#0"])
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
        #expect(center.pendingIDs == ["tagwerk.task.local:Lokal#0"])
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
        #expect(center.pendingIDs.contains("tagwerk.task.local:L39#0"))
        #expect(!center.pendingIDs.contains("tagwerk.task.local:L40#0"))
    }

    @Test func requestAuthorization_grantedReschedulesAtOnce() async {
        center.status = .notDetermined
        local.tasks = [makeTask("A", source: .local, due: due(20))]
        let scheduler = makeScheduler(await loadedList())
        let granted = await scheduler.requestAuthorization()
        #expect(granted)
        #expect(center.pendingIDs == ["tagwerk.task.local:A#0"])
    }

    @Test func pendingWithinMargin_kept() async {
        // Due 12:00 with 2 h lead time fires at 10:00, 30 s after "now" (09:59:30), inside the 60 s margin.
        center.seed("tagwerk.task.local:Gleich#0", fireDate: testNow())
        local.tasks = [makeTask("Gleich", source: .local, due: due(18, 12))]
        let scheduler = NotificationScheduler(center: center, taskList: await loadedList([local]),
                                              deadlineEvents: { _, _ in [] }, settings: settings,
                                              now: { testNow().addingTimeInterval(-30) }, calendar: calendar)
        await scheduler.reschedule()
        #expect(center.pendingIDs.contains("tagwerk.task.local:Gleich#0"))
        #expect(center.added.isEmpty)
    }

    @Test func pendingWithinMarginButMoved_removed() async {
        center.seed("tagwerk.task.local:Gleich#0", fireDate: testNow().addingTimeInterval(30))
        local.tasks = [makeTask("Gleich", source: .local, due: due(25))]
        let scheduler = makeScheduler(await loadedList([local]))
        await scheduler.reschedule()
        let expected = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 9))
        #expect(center.pending["tagwerk.task.local:Gleich#0"]?.fireDate == expected)
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

    // MARK: Language

    final class LocaleBox { var locale = Locale(identifier: "de_DE") }

    @Test func languageSwitch_replansLoadedSources_andKeepsUnloadedOnes() async {
        center.seed("tagwerk.task.github:Issue", fireDate: testNow().addingTimeInterval(86_400))
        local.tasks = [makeTask("Lokal", source: .local, due: due(20))]
        let box = LocaleBox()
        let scheduler = makeScheduler(await loadedList([local, reminders]), locale: { box.locale })

        await scheduler.reschedule()
        #expect(lastAdded("tagwerk.task.local:Lokal#0")?.body.hasPrefix("Fällig ") == true)

        box.locale = Locale(identifier: "en_US")
        center.clearAdded()
        await scheduler.reschedule()
        // The loaded sources are replaced in English; the unloaded GitHub request stays untouched and unrecorded.
        #expect(lastAdded("tagwerk.task.local:Lokal#0")?.body.hasPrefix("Due ") == true)
        #expect(center.pendingIDs == ["tagwerk.task.github:Issue", "tagwerk.task.local:Lokal#0"])
        #expect(!center.added.contains { $0.id.hasPrefix("tagwerk.task.github:") })
    }

    @Test func languageSwitch_replansASourceOnceItLoads() async {
        center.seed("tagwerk.task.github:Issue", fireDate: testNow().addingTimeInterval(86_400))
        github.tasks = [makeTask("Issue", source: .github, due: due(20))]
        local.tasks = [makeTask("Lokal", source: .local, due: due(20))]
        let box = LocaleBox()
        box.locale = Locale(identifier: "en_US")
        let list = await loadedList([local])
        let scheduler = makeScheduler(list, locale: { box.locale })
        await scheduler.reschedule()

        // GitHub registers and loads later: its old request is replaced by one in the new language.
        let loaded = await loadedList([github, local])
        let later = makeScheduler(loaded, locale: { box.locale })
        await later.reschedule()
        #expect(lastAdded("tagwerk.task.github:Issue#0")?.body.hasPrefix("Due ") == true)
    }

    @Test mutating func languageSwitch_replansDeadlineEventsOnlyWithCalendarAccess() async {
        events = [event("Abgabe", day: 20, hour: 14)]
        let box = LocaleBox()
        let withAccess = makeScheduler(await loadedList([local]), locale: { box.locale })
        await withAccess.reschedule()

        calendarAccess = false
        box.locale = Locale(identifier: "en_US")
        center.clearAdded()
        let withoutAccess = makeScheduler(await loadedList([local]), locale: { box.locale })
        await withoutAccess.reschedule()
        #expect(center.pendingIDs.contains("tagwerk.event.Abgabe#0"))
        #expect(center.added.isEmpty)
    }

    // MARK: Marked deadline events (plan deadline-marking, Task 8)

    final class MarkBox { var ids: Set<String> = [] }

    private func timetableEvent(_ id: String, day: Int, hour: Int, calendarID: String = "timetable") -> CalendarEvent {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        return CalendarEvent(id: id, externalID: nil, calendarID: calendarID, title: "Klausur Statistik", start: start,
                             end: start.addingTimeInterval(7200), isAllDay: false, url: nil, isBusy: true, version: "1")
    }

    private func makeMarkedScheduler(_ list: TaskListModel, marks: MarkBox) -> NotificationScheduler {
        let events = self.events
        return NotificationScheduler(
            center: center, taskList: list,
            deadlineEvents: { _, ids in events.filter { ids.contains($0.calendarID) } },
            markedDeadlines: MarkedDeadlineSource(calendarIDs: { ["timetable"] },
                                                  markedIDs: { events in Set(events.map(\.id)).intersection(marks.ids) }),
            settings: settings, now: { testNow() }, calendar: calendar, locale: { Locale(identifier: "de_DE") })
    }

    @Test mutating func markedEventGetsNotificationWithoutAnyDeadlineCalendar() async {
        settings.deadlineCalendarIDs = nil
        events = [timetableEvent("exam", day: 20, hour: 10), timetableEvent("lecture", day: 20, hour: 14)]
        let marks = MarkBox()
        marks.ids = ["exam"]
        let scheduler = makeMarkedScheduler(await loadedList([local]), marks: marks)
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.event.exam#0"])
        #expect(lastAdded("tagwerk.event.exam#0")?.title == "Klausur Statistik")
    }

    @Test mutating func switchOffRemovesMarkedEventNotifications() async {
        events = [timetableEvent("exam", day: 20, hour: 10)]
        let marks = MarkBox()
        marks.ids = ["exam"]
        let scheduler = makeMarkedScheduler(await loadedList([local]), marks: marks)
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.event.exam#0"])
        settings.deadlineCalendarNotifications = false
        await scheduler.reschedule()
        #expect(center.pending.isEmpty)
    }

    @Test mutating func unmarkRemovesPendingNotification() async {
        events = [timetableEvent("exam", day: 20, hour: 10)]
        let marks = MarkBox()
        marks.ids = ["exam"]
        let scheduler = makeMarkedScheduler(await loadedList([local]), marks: marks)
        await scheduler.reschedule()
        marks.ids = []
        await scheduler.reschedule()
        #expect(center.pending.isEmpty)
    }

    @Test mutating func eventInDeadlineCalendarAndMarkedNotifiesOnce() async {
        events = [timetableEvent("exam", day: 20, hour: 10, calendarID: "deadlines")]
        let marks = MarkBox()
        marks.ids = ["exam"]
        let scheduler = makeMarkedScheduler(await loadedList([local]), marks: marks)
        await scheduler.reschedule()
        #expect(center.pendingIDs == ["tagwerk.event.exam#0"])
        #expect(center.added.filter { $0.id == "tagwerk.event.exam#0" }.count == 1)
    }


    @Test func routineRequests_areNeitherCountedNorRemoved() async {
        let routineIDs = (0..<5).map { "tagwerk.routine.evening.\($0)" }
        routineIDs.forEach { center.seed($0, fireDate: nil) }
        local.tasks = (0..<60).map { makeTask("T\($0)", source: .local, due: due(20 + $0 % 5, 12)) }
        let scheduler = makeScheduler(await loadedList([local]))
        await scheduler.reschedule()
        #expect(center.added.count == 50)
        #expect(Set(routineIDs).isSubset(of: center.pendingIDs))
    }
}
