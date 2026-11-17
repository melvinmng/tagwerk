import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct PlanningModelTests {
    let container: ModelContainer
    let settings: AppSettings
    let calendarStore = FakeCalendarStore()
    let accessStore = FakeAccessStore()
    let local: FakeTaskProvider
    let github: FakeTaskProvider
    let taskList: TaskListModel
    let planStore: PlanStore
    let blocks: BlockPlanner
    let calendar = testCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 18)  // Wednesday

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.planCalendarID = "plan"
        settings.bufferMinutes = 0
        local = FakeTaskProvider(source: .local, tasks: [
            makeTask("Fahrrad", source: .local),
            makeTask("Abgabe", source: .local, due: DueDate(year: 2026, month: 11, day: 19)),
        ])
        github = FakeTaskProvider(source: .github, tasks: [makeTask("Login", source: .github)])
        taskList = TaskListModel(providers: [local, github], now: testNow, calendar: calendar)
        planStore = PlanStore(context: container.mainContext)
        blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                              settings: settings, calendar: calendar)
    }

    private func model() async -> PlanningModel {
        await taskList.reload()
        let model = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: accessStore,
                                  planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                  blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                  now: testNow, calendar: calendar)
        await model.reload()
        return model
    }

    private func id(_ title: String, _ source: TaskSource = .local) -> TaskID { TaskID(source: source, rawValue: title) }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func reload_week_hasSevenDaysMondayFirst() async {
        let model = await model()
        model.scope = .week
        await model.reload()
        #expect(model.days.count == 7)
        #expect(model.days.first?.day == PlanDay(year: 2026, month: 11, day: 16))
        #expect(model.days.last?.day == PlanDay(year: 2026, month: 11, day: 22))
        #expect(model.days.last?.capacity.isDayOff == true)
    }

    @Test func reload_month_coversFullWeeks() async {
        let model = await model()
        model.scope = .month
        await model.reload()
        #expect(model.days.first?.day == PlanDay(year: 2026, month: 10, day: 26))
        #expect(model.days.last?.day == PlanDay(year: 2026, month: 12, day: 6))
        #expect(model.days.count % 7 == 0)
    }

    @Test func capacity_defaultMinutesForTasksWithoutEstimate() async {
        planStore.assign(id("Fahrrad"), to: today)
        let model = await model()
        let day = model.days.first { $0.day == today }
        #expect(day?.capacity.plannedMinutes == 30)
        #expect(day?.capacity.estimatedCount == 1)
        #expect(day?.capacity.availableMinutes == 480)
    }

    @Test func capacity_countsLinkedEventAsPlannedNotBusy() async {
        calendarStore.storedEvents = [CalendarEvent(id: "e", externalID: nil, calendarID: "work", title: "Fahrrad",
                                                    start: at(18, 10), end: at(18, 11), isAllDay: false, url: nil,
                                                    isBusy: true, version: "1")]
        let model = await model()
        let day = model.days.first { $0.day == today }
        #expect(day?.capacity.availableMinutes == 480)
        #expect(day?.capacity.plannedMinutes == 60)
        #expect(day?.links["e"] == id("Fahrrad"))
    }

    @Test func capacity_unlinkedEventIsBusy() async {
        calendarStore.storedEvents = [CalendarEvent(id: "e", externalID: nil, calendarID: "work", title: "Vorlesung",
                                                    start: at(18, 10), end: at(18, 11), isAllDay: false, url: nil,
                                                    isBusy: true, version: "1")]
        let model = await model()
        #expect(model.days.first { $0.day == today }?.capacity.availableMinutes == 420)
    }

    @Test func unplanned_excludesAssignedAndCompleted() async {
        planStore.assign(id("Fahrrad"), to: today)
        let model = await model()
        #expect(Set(model.unplanned.map(\.title)) == ["Abgabe", "Login"])
    }

    @Test func overdue_showPastOpenAssignments() async {
        planStore.assign(id("Fahrrad"), to: PlanDay(year: 2026, month: 11, day: 16))
        let model = await model()
        #expect(model.overdue.map(\.title) == ["Fahrrad"])
    }

    @Test func dueToday_appearsAndCountsAsLoad() async throws {
        local.tasks.append(makeTask("Heute fällig", source: .local, due: DueDate(year: 2026, month: 11, day: 18)))
        let model = await model()
        let day = try #require(model.days.first)
        #expect(day.dueToday.map(\.title) == ["Heute fällig"])
        #expect(day.capacity.plannedMinutes == 30)
    }

    @Test func dueToday_withAssignmentElsewhere_notShown() async throws {
        local.tasks.append(makeTask("Heute fällig", source: .local, due: DueDate(year: 2026, month: 11, day: 18)))
        planStore.assign(id("Heute fällig"), to: PlanDay(year: 2026, month: 11, day: 20))
        let model = await model()
        #expect(try #require(model.days.first).dueToday.isEmpty)
    }

    @Test func dueToday_onlyOnToday() async throws {
        let model = await model()
        model.anchor = PlanDay(year: 2026, month: 11, day: 19)
        await model.reload()
        #expect(try #require(model.days.first).dueToday.isEmpty)  // "Abgabe" is due on the 19th, but that is not today
    }

    @Test func overdue_includesPastDueWithoutAssignment_notCounted() async throws {
        local.tasks.append(makeTask("Vergessen", source: .local, due: DueDate(year: 2026, month: 11, day: 15)))
        let model = await model()
        #expect(model.overdue.map(\.title) == ["Vergessen"])
        #expect(try #require(model.days.first).capacity.plannedMinutes == 0)
    }

    @Test func overdue_afterAssignToday_movesIntoAssigned() async throws {
        local.tasks.append(makeTask("Vergessen", source: .local, due: DueDate(year: 2026, month: 11, day: 15)))
        let model = await model()
        await model.assign(id("Vergessen"), to: today)
        #expect(model.overdue.isEmpty)
        #expect(try #require(model.days.first).assigned.map(\.title) == ["Vergessen"])
    }

    @Test func recurringReminderDueToday_countsOnceViaEffort() async throws {
        accessStore.openRecords = [ReminderRecord(id: "k", title: "Training", notes: nil, due: DueDate(year: 2026, month: 11, day: 18),
                                                  ekPriority: 0, isCompleted: false, listID: "l", lastModified: nil,
                                                  recurrence: Recurrence(rule: .daily(interval: 1), start: today, end: nil, count: nil))]
        accessStore.accessState = .fullAccess
        let reminders = FakeTaskProvider(source: .reminders, tasks: [makeTask("k", source: .reminders, due: DueDate(year: 2026, month: 11, day: 18))])
        await taskList.register(reminders)
        let model = await model()
        let day = try #require(model.days.first)
        #expect(day.dueToday.map(\.id.rawValue) == ["k"])
        #expect(day.capacity.plannedMinutes == 0)
    }

    @Test func assign_afterDue_marksPastDue() async {
        let model = await model()
        model.scope = .week
        await model.assign(id("Abgabe"), to: PlanDay(year: 2026, month: 11, day: 20))
        let day = model.days.first { $0.day == PlanDay(year: 2026, month: 11, day: 20) }
        #expect(day?.isPastDue.contains(id("Abgabe")) == true)
        #expect(local.appliedEdits.isEmpty)
    }

    @Test func assign_withFutureBlocks_asksAndMoves() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        let block = try blocks.createBlock(for: task, start: at(19, 14), minutes: 60)
        await model.assign(task.id, to: PlanDay(year: 2026, month: 11, day: 24))
        #expect(model.pendingBlockDecision?.taskID == task.id)
        await model.resolveBlocks(move: true)
        #expect(calendarStore.event(id: block.id)?.start == at(24, 14))
        #expect(planStore.assignment(for: task.id) == PlanDay(year: 2026, month: 11, day: 24))
        #expect(model.pendingBlockDecision == nil)
    }

    @Test func dayOverride_changesCapacity() async {
        let model = await model()
        model.setDayOverride(.hours(WorkHours(startMinutes: 540, endMinutes: 1200)), on: today)
        await model.reload()
        #expect(model.days.first { $0.day == today }?.capacity.availableMinutes == 600)
    }

    @Test func prune_keepsAssignmentsOfSourcesNotLoaded() async {
        planStore.assign(id("Login", .github), to: today)
        github.offlineSince = testNow()
        github.tasks = []  // offline cache empty: the issue is not listed
        _ = await model()
        #expect(planStore.assignment(for: id("Login", .github)) == today)
    }

    @Test func prune_removesAssignmentsOfCompletedTasks() async {
        planStore.assign(id("Fahrrad"), to: today)
        local.tasks.removeAll { $0.title == "Fahrrad" }
        _ = await model()
        #expect(planStore.assignment(for: id("Fahrrad")) == nil)
    }

    @Test func dayView_ordersRowsByTime_withLunch() async {
        calendarStore.storedEvents = [
            CalendarEvent(id: "late", externalID: nil, calendarID: "work", title: "Team-Meeting", start: at(18, 15), end: at(18, 16),
                          isAllDay: false, url: nil, isBusy: true, version: "1"),
            CalendarEvent(id: "early", externalID: nil, calendarID: "work", title: "Vorlesung", start: at(18, 9), end: at(18, 10, 30),
                          isAllDay: false, url: nil, isBusy: true, version: "1"),
            CalendarEvent(id: "allday", externalID: nil, calendarID: "work", title: "Projektwoche", start: at(18, 0), end: at(19, 0),
                          isAllDay: true, url: nil, isBusy: true, version: "1"),
        ]
        let model = await model()
        let day = try! #require(model.days.first)
        let rows = model.timeline(for: day)
        #expect(rows.map(\.label) == ["Vorlesung", "Mittagspause", "Team-Meeting"])
        #expect(model.allDayEvents(for: day).map(\.title) == ["Projektwoche"])
    }

    @Test func dayView_upcomingDeadlines_nextFourteenDays() async {
        local.tasks.append(TaskItem(id: id("Klausurvorbereitung"), title: "Klausurvorbereitung", notes: nil,
                                    due: DueDate(year: 2026, month: 11, day: 30), priority: .p1, estimateMinutes: nil,
                                    isCompleted: false, container: TaskContainer(id: "local", name: "Lokal", colorHex: nil),
                                    url: nil, version: "1", editableFields: []))
        local.tasks.append(TaskItem(id: id("Später"), title: "Später", notes: nil,
                                    due: DueDate(year: 2026, month: 12, day: 15), priority: .p1, estimateMinutes: nil,
                                    isCompleted: false, container: TaskContainer(id: "local", name: "Lokal", colorHex: nil),
                                    url: nil, version: "1", editableFields: []))
        let model = await model()
        #expect(model.upcomingDeadlines.map(\.title) == ["Klausurvorbereitung"])
    }

    @Test func deadlineCalendarEvent_isDeadline_notAllDayEvent() async throws {
        settings.deadlineCalendarIDs = ["uni"]
        calendarStore.storedEvents = [
            CalendarEvent(id: "anmeldung", externalID: nil, calendarID: "uni", title: "Anmeldung Abschlussarbeit",
                          start: at(18, 0), end: at(19, 0), isAllDay: true, url: nil, isBusy: true, version: "1"),
            CalendarEvent(id: "frei", externalID: nil, calendarID: "work", title: "Projektwoche",
                          start: at(18, 0), end: at(19, 0), isAllDay: true, url: nil, isBusy: true, version: "1"),
        ]
        let model = await model()
        let day = try #require(model.days.first)
        #expect(model.allDayEvents(for: day).map(\.title) == ["Projektwoche"])
        #expect(day.deadlines.map(\.title) == ["Anmeldung Abschlussarbeit"])
        #expect(model.upcomingDeadlines.map(\.title) == ["Anmeldung Abschlussarbeit"])
    }

    @Test func timedDeadlineEvent_staysInTimelineAndConsumesTime() async throws {
        settings.deadlineCalendarIDs = ["uni"]
        calendarStore.storedEvents = [CalendarEvent(id: "klausur", externalID: nil, calendarID: "uni", title: "Klausur",
                                                    start: at(18, 10), end: at(18, 12), isAllDay: false, url: nil,
                                                    isBusy: true, version: "1")]
        let model = await model()
        let day = try #require(model.days.first)
        #expect(model.timeline(for: day).map(\.label).contains("Klausur"))
        #expect(day.capacity.availableMinutes == 360)
        #expect(day.deadlines.map(\.title) == ["Klausur"])
    }

    @Test func upcomingDeadlines_followTheShownDay() async {
        settings.deadlineCalendarIDs = ["uni"]
        calendarStore.storedEvents = [CalendarEvent(id: "anmeldung", externalID: nil, calendarID: "uni", title: "Anmeldung",
                                                    start: date(2027, 1, 18), end: date(2027, 1, 19), isAllDay: true,
                                                    url: nil, isBusy: true, version: "1")]
        let model = await model()
        #expect(model.upcomingDeadlines.isEmpty)
        model.anchor = PlanDay(year: 2027, month: 1, day: 18)
        await model.reload()
        #expect(model.upcomingDeadlines.map(\.title) == ["Anmeldung"])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func createBlock_fromDayView_writesEventAndAssigns() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        await model.createBlock(for: task, start: at(18, 14), minutes: 45)
        #expect(calendarStore.storedEvents.count == 1)
        #expect(model.days.first?.blocks.count == 1)
        #expect(model.days.first?.capacity.plannedMinutes == 45)
    }

    @Test func createBlock_removesTaskFromPlannedWithoutTime() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        await model.createBlock(for: task, start: at(18, 14), minutes: 45)
        #expect(model.days.first?.assigned.contains { $0.id == task.id } == false)
    }

    @Test func recurringItems_listEffortOfTheDay() async {
        accessStore.openRecords = [ReminderRecord(id: "k", title: "Karteikarten", notes: nil, due: DueDate(year: 2026, month: 11, day: 16),
                                                  ekPriority: 0, isCompleted: false, listID: "l", lastModified: nil,
                                                  recurrence: Recurrence(rule: .daily(interval: 1), start: PlanDay(year: 2026, month: 11, day: 16),
                                                                         end: nil, count: nil))]
        accessStore.accessState = .fullAccess
        RecurringEffortStore(context: container.mainContext).setForAll(180, reminderID: "k", from: PlanDay(year: 2026, month: 11, day: 1))
        let model = await model()
        #expect(model.days.first?.recurring == [RecurringItem(reminderID: "k", title: "Karteikarten", minutes: 180)])
        #expect(model.days.first?.capacity.availableMinutes == 300)
    }

    @Test func recurringItem_onlyForRecurringReminders_withCurrentEffort() async throws {
        accessStore.openRecords = [
            ReminderRecord(id: "k", title: "Karteikarten", notes: nil, due: DueDate(year: 2026, month: 11, day: 18),
                           ekPriority: 0, isCompleted: false, listID: "l", lastModified: nil,
                           recurrence: Recurrence(rule: .daily(interval: 1), start: PlanDay(year: 2026, month: 11, day: 18),
                                                  end: nil, count: nil)),
            ReminderRecord(id: "e", title: "Einmalig", notes: nil, due: nil, ekPriority: 0, isCompleted: false,
                           listID: "l", lastModified: nil),
        ]
        accessStore.accessState = .fullAccess
        let model = await model()
        func reminder(_ raw: String, _ title: String) -> TaskItem {
            TaskItem(id: TaskID(source: .reminders, rawValue: raw), title: title, notes: nil, due: nil, priority: nil,
                     estimateMinutes: nil, isCompleted: false, container: TaskContainer(id: "l", name: "Liste", colorHex: nil),
                     url: nil, version: "1", editableFields: [])
        }
        let recurring = reminder("k", "Karteikarten")
        let once = reminder("e", "Einmalig")
        #expect(model.recurringItem(for: recurring, on: today) == RecurringItem(reminderID: "k", title: "Karteikarten", minutes: 0))
        #expect(model.recurringItem(for: once, on: today) == nil)
        await model.setRecurringEffort(45, reminderID: "k", day: today, forAll: true)
        #expect(model.recurringItem(for: recurring, on: today)?.minutes == 45)
    }

    @Test func dayPlan_today_hasRemaining_otherDaysNot() async {
        let model = await model()
        model.scope = .week
        await model.reload()
        #expect(model.days.first { $0.day == today }?.capacity.remainingMinutes == 420)  // 10:00–18:00 minus lunch
        #expect(model.days.first { $0.day == today.adding(days: 1, calendar: calendar) }?.capacity.remainingMinutes == nil)
    }

    @Test func dayPlan_pastDay_isPast() async {
        let model = await model()
        model.scope = .week
        await model.reload()
        #expect(model.days.first { $0.day == PlanDay(year: 2026, month: 11, day: 16) }?.isPast == true)
        #expect(model.days.first { $0.day == today }?.isPast == false)
    }

    @Test func remaining_countsOnlyBlockPartAfterNow() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        await model.createBlock(for: task, start: at(18, 9), minutes: 120)
        #expect(model.days.first?.capacity.remainingMinutes == 360)
    }

    private func recurringTraining() {
        accessStore.openRecords = [ReminderRecord(id: "k", title: "Training", notes: nil, due: DueDate(year: 2026, month: 11, day: 18),
                                                  ekPriority: 0, isCompleted: false, listID: "l", lastModified: nil,
                                                  recurrence: Recurrence(rule: .daily(interval: 1), start: today, end: nil, count: nil))]
        accessStore.accessState = .fullAccess
        RecurringEffortStore(context: container.mainContext).setForAll(60, reminderID: "k", from: today)
    }

    @Test func completingRecurringToday_freesItsEffort() async {
        recurringTraining()
        let model = await model()
        #expect(model.days.first?.capacity.remainingMinutes == 360)
        await model.didChangeCompletion(TaskID(source: .reminders, rawValue: "k"), isCompleted: true)
        #expect(model.days.first?.capacity.remainingMinutes == 420)
        #expect(model.days.first?.recurring.first?.isDone == true)
        await model.didChangeCompletion(TaskID(source: .reminders, rawValue: "k"), isCompleted: false)
        #expect(model.days.first?.capacity.remainingMinutes == 360)
    }

    @Test func completingNonRecurring_doesNotMarkOccurrence() async {
        recurringTraining()
        let model = await model()
        await model.didChangeCompletion(id("Fahrrad"), isCompleted: true)
        #expect(model.efforts.isDone(reminderID: "Fahrrad", day: today) == false)
        #expect(model.days.first?.capacity.remainingMinutes == 360)
    }

    @Test func duplicateEvents_showOnce_capacityUnchanged() async throws {
        calendarStore.storedEvents = ["work", "shared"].map { calendarID in
            CalendarEvent(id: "seminar-\(calendarID)", externalID: nil, calendarID: calendarID, title: "Seminar",
                          start: at(18, 14), end: at(18, 15), isAllDay: false, url: nil, isBusy: true, version: "1")
        }
        let model = await model()
        let day = try #require(model.days.first)
        #expect(model.timeline(for: day).filter { $0.label == "Seminar" }.count == 1)
        #expect(day.events.first?.mergedCalendarIDs == ["shared"])
        #expect(day.capacity.availableMinutes == 420)
        settings.mergeDuplicateEvents = false
        await model.reload()
        #expect(model.timeline(for: try #require(model.days.first)).filter { $0.label == "Seminar" }.count == 2)
    }

    private func draft(_ event: CalendarEvent, title: String? = nil, start: Date? = nil, end: Date? = nil) -> EventDraft {
        EventDraft(title: title ?? event.title, start: start ?? event.start, end: end ?? event.end, isAllDay: event.isAllDay,
                   calendarID: event.calendarID, notes: nil, location: nil, url: event.url)
    }

    @Test func updateEvent_changesTitleAndTime() async throws {
        calendarStore.storedEvents = [CalendarEvent(id: "e", externalID: nil, calendarID: "work", title: "Seminar",
                                                    start: at(18, 14), end: at(18, 15), isAllDay: false, url: nil,
                                                    isBusy: true, version: "1")]
        let model = await model()
        let event = try #require(calendarStore.event(id: "e"))
        await model.updateEvent(event, with: draft(event, title: "Kolloquium", start: at(18, 16), end: at(18, 17)), span: .thisEvent)
        #expect(calendarStore.event(id: "e")?.title == "Kolloquium")
        #expect(calendarStore.event(id: "e")?.start == at(18, 16))
        #expect(model.lastError == nil)
    }

    @Test func updateEvent_staleVersion_conflictNoChange() async throws {
        calendarStore.storedEvents = [CalendarEvent(id: "e", externalID: nil, calendarID: "work", title: "Seminar",
                                                    start: at(18, 14), end: at(18, 15), isAllDay: false, url: nil,
                                                    isBusy: true, version: "1")]
        let model = await model()
        var stale = try #require(calendarStore.event(id: "e"))
        stale.version = "0"
        await model.updateEvent(stale, with: draft(stale, title: "Neu"), span: .thisEvent)
        #expect(calendarStore.event(id: "e")?.title == "Seminar")
        #expect(model.lastError != nil)
    }

    @Test func deleteEvent_readOnly_errorAndUnchanged() async throws {
        var holiday = CalendarEvent(id: "h", externalID: nil, calendarID: "holidays", title: "Feiertag",
                                    start: at(18, 0), end: at(19, 0), isAllDay: true, url: nil, isBusy: false, version: "1")
        holiday.isEditable = false
        calendarStore.storedEvents = [holiday]
        let model = await model()
        await model.deleteEvent(holiday, span: .thisEvent)
        #expect(calendarStore.event(id: "h") != nil)
        #expect(model.lastError != nil)
    }

    @Test func createEvent_defaultsToPlanCalendar() async throws {
        let model = await model()
        #expect(model.defaultEventCalendarID == "plan")
        let created = await model.createEvent(EventDraft(title: "Lernen", start: at(18, 16), end: at(18, 17), isAllDay: false,
                                                         calendarID: try #require(model.defaultEventCalendarID),
                                                         notes: nil, location: nil, url: nil))
        #expect(created?.calendarID == "plan")
        #expect(calendarStore.storedEvents.count == 1)
    }

    @Test func updateRecurring_thisEvent_onlyOccurrence() async throws {
        calendarStore.storedEvents = [18, 19, 20].map { day in
            var event = CalendarEvent(id: "sport|\(Int(at(day, 18).timeIntervalSince1970))", externalID: nil, calendarID: "work",
                                      title: "Sport", start: at(day, 18), end: at(day, 19), isAllDay: false, url: nil,
                                      isBusy: true, version: "1")
            event.isRecurring = true
            return event
        }
        let model = await model()
        let second = calendarStore.storedEvents[1]
        await model.updateEvent(second, with: draft(second, start: at(19, 19), end: at(19, 20)), span: .thisEvent)
        #expect(calendarStore.storedEvents.map(\.start) == [at(18, 18), at(19, 19), at(20, 18)])
        let first = calendarStore.storedEvents[0]
        await model.updateEvent(first, with: draft(first, title: "Lauf"), span: .futureEvents)
        #expect(calendarStore.storedEvents.map(\.title) == ["Lauf", "Lauf", "Lauf"])
    }

    @Test func moveBlock_changesEventAndAssignment() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        let block = try blocks.createBlock(for: task, start: at(18, 14), minutes: 60)
        await model.moveBlock(block, toStartMinutes: 16 * 60 + 8, on: PlanDay(year: 2026, month: 11, day: 19))
        #expect(calendarStore.event(id: block.id)?.start == at(19, 16, 15))
        #expect(calendarStore.event(id: block.id)?.end == at(19, 17, 15))
        #expect(planStore.assignment(for: task.id) == PlanDay(year: 2026, month: 11, day: 19))
    }

    @Test func moveBlock_lateStartIsClampedToTheDay() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        let block = try blocks.createBlock(for: task, start: at(18, 14), minutes: 60)
        await model.moveBlock(block, toStartMinutes: 23 * 60 + 30, on: today)
        #expect(calendarStore.event(id: block.id)?.start == at(18, 23))
    }

    @Test func resizeBlock_keepsStart() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        let block = try blocks.createBlock(for: task, start: at(18, 14), minutes: 60)
        await model.resizeBlock(block, minutes: 95)
        #expect(calendarStore.event(id: block.id)?.start == at(18, 14))
        #expect(calendarStore.event(id: block.id)?.end == at(18, 15, 30))
    }

    @Test func deleteBlock_removesEvent_assignmentStays() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        let block = try blocks.createBlock(for: task, start: at(18, 14), minutes: 60)
        await model.deleteBlock(block)
        #expect(calendarStore.event(id: block.id) == nil)
        #expect(planStore.assignment(for: task.id) == today)
    }

    @Test func moveBlock_conflict_setsLastError() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        var block = try blocks.createBlock(for: task, start: at(18, 14), minutes: 60)
        block.version = "stale"
        await model.moveBlock(block, toStartMinutes: 15 * 60, on: today)
        #expect(model.lastError != nil)
        #expect(calendarStore.event(id: block.id)?.start == at(18, 14))
    }

    @Test func gaps_today_startFromNowAndSkipBlocks() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        await model.createBlock(for: task, start: at(18, 14), minutes: 60)
        #expect(model.gaps(for: try #require(model.days.first)) == [600..<720, 780..<840, 900..<1080])
    }

    @Test func step_day_week_month() async {
        let model = await model()
        model.step(1)
        #expect(model.anchor == PlanDay(year: 2026, month: 11, day: 19))
        model.scope = .week
        model.step(-1)
        #expect(model.anchor == PlanDay(year: 2026, month: 11, day: 12))
        model.scope = .month
        model.step(1)
        #expect(model.anchor == PlanDay(year: 2026, month: 12, day: 12))
    }

    @Test func timelineWithGaps_insertsFreeStretchesInOrder() async throws {
        calendarStore.storedEvents = [CalendarEvent(id: "e", externalID: nil, calendarID: "work", title: "Vorlesung",
                                                    start: at(18, 14), end: at(18, 15), isAllDay: false, url: nil,
                                                    isBusy: true, version: "1")]
        let model = await model()
        let rows = model.timelineWithGaps(for: try #require(model.days.first))
        #expect(rows.map(\.label) == ["frei", "Mittagspause", "frei", "Vorlesung", "frei"])
    }

    @Test func dropTask_intoGap_createsBlockWithEstimate() async throws {
        let model = await model()
        await model.dropTask(key: id("Fahrrad").key, atMinutes: 13 * 60, on: today)
        let block = try #require(calendarStore.storedEvents.first)
        #expect(block.start == at(18, 13))
        #expect(block.end == at(18, 13, 30))  // no estimate: default duration
        #expect(planStore.assignment(for: id("Fahrrad")) == today)
    }

    @Test func assign_withMoveBlocksFlag_movesWithoutPendingDecision() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        let block = try blocks.createBlock(for: task, start: at(19, 14), minutes: 60)
        await model.assign(task.id, to: PlanDay(year: 2026, month: 11, day: 24), moveBlocks: true)
        #expect(model.pendingBlockDecision == nil)
        #expect(calendarStore.event(id: block.id)?.start == at(24, 14))
    }

    @Test func applyPlanning_changesBlocksDeletesAndAdds() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        let first = try blocks.createBlock(for: task, start: at(19, 9), minutes: 60)
        let second = try blocks.createBlock(for: task, start: at(19, 14), minutes: 60)
        var edit = model.plannedEdit(for: task)
        #expect(edit.blocks.count == 2)
        edit.blocks[0].start = at(19, 16)
        edit.blocks[0].minutes = 90
        edit.blocks[1].isDeleted = true
        edit.newBlocks = [PlannedEdit.NewBlock(start: at(20, 10), minutes: 30)]
        await model.applyPlanning(edit, for: task)
        #expect(calendarStore.event(id: first.id)?.start == at(19, 16))
        #expect(calendarStore.event(id: first.id)?.end == at(19, 17, 30))
        #expect(calendarStore.event(id: second.id) == nil)
        #expect(calendarStore.storedEvents.contains { $0.start == at(20, 10) })
    }

    @Test func applyPlanning_unchanged_writesNothing() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        let block = try blocks.createBlock(for: task, start: at(19, 9), minutes: 60)
        await model.applyPlanning(model.plannedEdit(for: task), for: task)
        #expect(calendarStore.event(id: block.id)?.version == block.version)
    }

    @Test func unplannedSections_dueInRangeFirst_thenOthers() async {
        local.tasks.append(makeTask("Später fällig", source: .local, due: DueDate(year: 2026, month: 12, day: 3)))
        let model = await model()
        model.scope = .week
        await model.reload()
        let sections = model.unplannedSections(search: "")
        #expect(sections.dueInRange.map(\.title) == ["Abgabe"])
        #expect(sections.other.map(\.title) == ["Später fällig", "Fahrrad", "Login"])
    }

    @Test func unplannedSections_searchFiltersBoth() async {
        let model = await model()
        model.scope = .week
        await model.reload()
        let sections = model.unplannedSections(search: "fahr")
        #expect(sections.dueInRange.isEmpty)
        #expect(sections.other.map(\.title) == ["Fahrrad"])
    }

    @Test func monthSelection_defaultsToTodayInMonth_elseFirst() async {
        let model = await model()
        model.scope = .month
        #expect(model.monthSelection == today)
        model.selectedDay = PlanDay(year: 2026, month: 11, day: 25)
        #expect(model.monthSelection == PlanDay(year: 2026, month: 11, day: 25))
        model.step(1)
        #expect(model.monthSelection == PlanDay(year: 2026, month: 12, day: 1))
    }

    @Test func planToday_assignsAllWithoutWritingSource() async {
        let model = await model()
        await model.planToday([id("Fahrrad"), id("Abgabe")])
        #expect(planStore.assignment(for: id("Fahrrad")) == today)
        #expect(planStore.assignment(for: id("Abgabe")) == today)
        #expect(local.appliedEdits.isEmpty)
    }

    @Test func plannedMinutes_usesEstimateOrDefault() async {
        local.tasks.append(TaskItem(id: id("Lesen"), title: "Lesen", notes: nil, due: nil, priority: nil, estimateMinutes: 90,
                                    isCompleted: false, container: TaskContainer(id: "local", name: "Lokal", colorHex: nil),
                                    url: nil, version: "1", editableFields: []))
        let model = await model()
        #expect(model.plannedMinutes(for: [id("Fahrrad"), id("Lesen")]) == 120)
    }

    @Test func planMany_assignsAll_movesBlocksWithoutAsking() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        let block = try blocks.createBlock(for: task, start: at(19, 14), minutes: 60)
        await model.plan([id("Fahrrad"), id("Abgabe")], to: PlanDay(year: 2026, month: 11, day: 23))
        #expect(planStore.assignment(for: id("Fahrrad")) == PlanDay(year: 2026, month: 11, day: 23))
        #expect(planStore.assignment(for: id("Abgabe")) == PlanDay(year: 2026, month: 11, day: 23))
        #expect(model.pendingBlockDecision == nil)
        #expect(calendarStore.event(id: block.id)?.start == at(23, 14))
    }

    @Test func planToday_taskWithFutureBlocks_movesThemToo() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        let block = try blocks.createBlock(for: task, start: at(20, 14), minutes: 60)
        await model.planToday([task.id])
        #expect(planStore.assignment(for: task.id) == today)
        #expect(calendarStore.event(id: block.id)?.start == at(18, 14))
    }

    @Test func duplicateOfLinkedEvent_isNotCountedTwice() async throws {
        calendarStore.storedEvents = ["work", "shared"].map { calendarID in
            CalendarEvent(id: "fahrrad-\(calendarID)", externalID: nil, calendarID: calendarID, title: "Seminar",
                          start: at(18, 14), end: at(18, 15), isAllDay: false, url: nil, isBusy: true, version: "1")
        }
        let model = await model()
        await model.link(eventID: "fahrrad-work", to: id("Fahrrad"))
        let day = try #require(model.days.first)
        #expect(day.capacity.availableMinutes == 480)  // the copy is not busy time
        #expect(day.capacity.plannedMinutes == 60)
    }

    @Test func canEditAsBlock_onlyOwnWritableBlocks() async throws {
        var foreign = CalendarEvent(id: "f", externalID: nil, calendarID: "work", title: "Fahrrad", start: at(18, 14),
                                    end: at(18, 15), isAllDay: false, url: nil, isBusy: true, version: "1")
        foreign.isEditable = false
        calendarStore.storedEvents = [foreign]
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        let own = try blocks.createBlock(for: task, start: at(18, 16), minutes: 60)
        await model.reload()
        #expect(model.canEditAsBlock(own))
        #expect(!model.canEditAsBlock(foreign))
    }

    @Test func resizeBlockStart_keepsEnd() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        let block = try blocks.createBlock(for: task, start: at(18, 14), minutes: 60)
        await model.resizeBlockStart(block, toStartMinutes: 13 * 60 + 28)
        #expect(calendarStore.event(id: block.id)?.start == at(18, 13, 30))
        #expect(calendarStore.event(id: block.id)?.end == at(18, 15))
        let moved = try #require(calendarStore.event(id: block.id))
        await model.resizeBlockStart(moved, toStartMinutes: 15 * 60)  // past the end: keeps at least 15 min
        #expect(calendarStore.event(id: block.id)?.start == at(18, 14, 45))
    }

    @Test func suggestedBlockMinutes_estimateMinusExistingBlocks() async throws {
        local.tasks.append(TaskItem(id: id("Lesen"), title: "Lesen", notes: nil, due: nil, priority: nil, estimateMinutes: 150,
                                    isCompleted: false, container: TaskContainer(id: "local", name: "Lokal", colorHex: nil),
                                    url: nil, version: "1", editableFields: []))
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Lesen" })
        #expect(model.suggestedBlockMinutes(for: task) == 150)
        _ = try blocks.createBlock(for: task, start: at(19, 9), minutes: 60)
        #expect(model.suggestedBlockMinutes(for: task) == 90)
        _ = try blocks.createBlock(for: task, start: at(19, 14), minutes: 120)
        #expect(model.suggestedBlockMinutes(for: task) == 150)  // fully blocked: the estimate again
        let noEstimate = try #require(taskList.items.first { $0.title == "Fahrrad" })
        #expect(model.suggestedBlockMinutes(for: noEstimate) == 30)  // default duration
    }

    @Test func lunchOfOneDay_changesCapacityAndTimeline() async throws {
        let model = await model()
        await model.setLunch(startMinutes: 13 * 60 + 7, minutes: 30, on: today)
        let day = try #require(model.days.first)
        #expect(model.lunch(on: today) == 780..<810)
        #expect(day.capacity.availableMinutes == 510)
        #expect(model.timeline(for: day).contains { $0 == .lunch(startMinutes: 780, minutes: 30) })
        #expect(model.lunch(on: today.adding(days: 1, calendar: calendar)) == 720..<780)
        await model.applyLunchToAllDays(from: today)
        #expect(settings.lunchStartMinutes == 780)
        #expect(settings.lunchDurationMinutes == 30)
        #expect(!model.hasOwnLunch(on: today))
    }

    @Test func removeLunch_onlyThisDay() async throws {
        let model = await model()
        await model.removeLunch(on: today)
        #expect(model.lunch(on: today) == nil)
        #expect(try #require(model.days.first).capacity.availableMinutes == 540)
        await model.resetLunch(on: today)
        #expect(model.lunch(on: today) == 720..<780)
    }

    @Test func freeMark_releasesBusyTime() async throws {
        calendarStore.storedEvents = [CalendarEvent(id: "e", externalID: nil, calendarID: "work", title: "Vorlesung",
                                                    start: at(18, 10), end: at(18, 11), isAllDay: false, url: nil,
                                                    isBusy: true, version: "1")]
        let model = await model()
        #expect(try #require(model.days.first).capacity.availableMinutes == 420)
        await model.setFree([try #require(calendarStore.event(id: "e"))], free: true, series: false)
        #expect(try #require(model.days.first).capacity.availableMinutes == 480)
        #expect(try #require(model.days.first).events.first?.isBusy == false)
    }

    @Test func freeMark_seriesFromThisOccurrenceOn() async throws {
        calendarStore.storedEvents = [18, 19].map { day in
            var event = CalendarEvent(id: "kurs|\(Int(at(day, 10).timeIntervalSince1970))", externalID: nil, calendarID: "work",
                                      title: "Kurs", start: at(day, 10), end: at(day, 11), isAllDay: false, url: nil,
                                      isBusy: true, version: "1")
            event.isRecurring = true
            return event
        }
        let model = await model()
        model.scope = .week
        await model.reload()
        let first = try #require(model.days.first { $0.day == today }?.events.first)
        await model.setFree([first], free: true, series: true)
        #expect(model.days.first { $0.day == today.adding(days: 1, calendar: calendar) }?.events.first?.isBusy == false)
    }

    @Test func placeholderMerge_acceptedHidesPlaceholder() async throws {
        calendarStore.storedEvents = [
            CalendarEvent(id: "real", externalID: nil, calendarID: "uni", title: "Vorlesung", start: at(18, 10), end: at(18, 11),
                          isAllDay: false, url: nil, isBusy: true, version: "1"),
            CalendarEvent(id: "busy", externalID: nil, calendarID: "work", title: "Busy", start: at(18, 10), end: at(18, 11),
                          isAllDay: false, url: nil, isBusy: true, version: "1"),
        ]
        let model = await model()
        let suggestion = try #require(model.mergeSuggestions.first)
        #expect(suggestion.placeholderID == "busy")
        await model.decideMerge(suggestion, merge: true, always: false)
        #expect(model.mergeSuggestions.isEmpty)
        #expect(try #require(model.days.first).events.map(\.id) == ["real"])
    }

    @Test func placeholderMerge_dismissedStaysSeparate() async throws {
        calendarStore.storedEvents = [
            CalendarEvent(id: "real", externalID: nil, calendarID: "uni", title: "Vorlesung", start: at(18, 10), end: at(18, 11),
                          isAllDay: false, url: nil, isBusy: true, version: "1"),
            CalendarEvent(id: "busy", externalID: nil, calendarID: "work", title: "Busy", start: at(18, 10), end: at(18, 11),
                          isAllDay: false, url: nil, isBusy: true, version: "1"),
        ]
        let model = await model()
        await model.decideMerge(try #require(model.mergeSuggestions.first), merge: false, always: true)
        #expect(model.mergeSuggestions.isEmpty)
        #expect(try #require(model.days.first).events.count == 2)
    }

    @Test func setTime_foreignWritableEvent_snapsAndKeepsFields() async throws {
        var seminar = CalendarEvent(id: "s", externalID: nil, calendarID: "work", title: "Seminar", start: at(18, 10),
                                    end: at(18, 11), isAllDay: false, url: nil, isBusy: true, version: "1")
        seminar.notes = "Raum 2.14"
        calendarStore.storedEvents = [seminar]
        let model = await model()
        await model.setTime(of: seminar, startMinutes: 14 * 60 + 8, endMinutes: 15 * 60 + 53, span: .thisEvent)
        let moved = try #require(calendarStore.event(id: "s"))
        #expect(moved.start == at(18, 14, 15))
        #expect(moved.end == at(18, 16))
        #expect(moved.notes == "Raum 2.14")
    }

    @Test func setTime_keepsAtLeastQuarterHour() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        let block = try blocks.createBlock(for: task, start: at(18, 14), minutes: 60)
        await model.setTime(of: block, startMinutes: 14 * 60, endMinutes: 14 * 60 + 3, span: .thisEvent)
        #expect(calendarStore.event(id: block.id)?.end == at(18, 14, 15))
    }

    @Test func canDrag_onlyWritableTimedEvents() async throws {
        var invitation = CalendarEvent(id: "i", externalID: nil, calendarID: "work", title: "Runde", start: at(18, 10),
                                       end: at(18, 11), isAllDay: false, url: nil, isBusy: true, version: "1")
        invitation.isInvitation = true
        let own = CalendarEvent(id: "o", externalID: nil, calendarID: "work", title: "Lernen", start: at(18, 10),
                                end: at(18, 11), isAllDay: false, url: nil, isBusy: true, version: "1")
        let model = await model()
        #expect(model.canDrag(own))
        #expect(!model.canDrag(invitation))
    }

    @Test func duration_padsMinutes() {
        #expect(CapacityText.duration(125) == "2 h 05")
        #expect(CapacityText.duration(45) == "45 min")
        #expect(CapacityText.duration(120) == "2 h")
    }

    @Test func planDay_forTodayTomorrowWeekend_matchesRescheduleDates() async {
        let model = await model()
        #expect(model.planDay(for: .today) == today)
        #expect(model.planDay(for: .tomorrow) == PlanDay(year: 2026, month: 11, day: 19))
        #expect(model.planDay(for: .weekend) == PlanDay(year: 2026, month: 11, day: 21))
        #expect(model.planDay(for: .nextMonday) == PlanDay(year: 2026, month: 11, day: 23))
    }

    @Test func contextMenu_einplanen_doesNotWriteSource() async {
        let model = await model()
        await model.plan(id("Abgabe"), option: .tomorrow)
        #expect(planStore.assignment(for: id("Abgabe")) == PlanDay(year: 2026, month: 11, day: 19))
        #expect(local.appliedEdits.isEmpty)
    }

    @Test func eventDetail_linkManually_showsInDay() async {
        calendarStore.storedEvents = [CalendarEvent(id: "e", externalID: nil, calendarID: "work", title: "Arbeitsblock",
                                                    start: at(18, 14), end: at(18, 15), isAllDay: false, url: nil,
                                                    isBusy: true, version: "1")]
        let model = await model()
        #expect(model.days.first?.links["e"] == nil)
        await model.link(eventID: "e", to: id("Fahrrad"))
        #expect(model.days.first?.links["e"] == id("Fahrrad"))
        #expect(model.linkOrigin(eventID: "e") == .manual)
        await model.unlink(eventID: "e")
        #expect(model.days.first?.links["e"] == nil)
    }

    @Test func recurringEffort_setForDayAndForAll() async {
        let model = await model()
        await model.setRecurringEffort(60, reminderID: "k", day: today, forAll: false)
        #expect(model.efforts.minutes(for: "k", on: today) == 60)
        #expect(model.efforts.minutes(for: "k", on: today.adding(days: 1, calendar: calendar)) == nil)
        await model.setRecurringEffort(120, reminderID: "k", day: today, forAll: true)
        #expect(model.efforts.minutes(for: "k", on: today.adding(days: 1, calendar: calendar)) == 120)
    }

    @Test func plannedInfo_forEditor() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        _ = try blocks.createBlock(for: task, start: at(19, 9), minutes: 30)
        let info = model.plannedInfo(for: task.id)
        #expect(info.day == PlanDay(year: 2026, month: 11, day: 19))
        #expect(info.blocks.count == 1)
    }
}
