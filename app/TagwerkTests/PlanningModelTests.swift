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

    @Test func resolveEvent_readsTheDayOfTheHitFromReadableCalendars() async {
        let model = await model()
        let start = at(20, 9)
        let stored = CalendarEvent(id: "abc#cal|1", externalID: nil, calendarID: "cal", title: "Klausur", start: start,
                                   end: start.addingTimeInterval(3600), isAllDay: false, url: nil, isBusy: true, version: "7")
        let hidden = CalendarEvent(id: "x#other|1", externalID: nil, calendarID: "other", title: "Klausur", start: start,
                                   end: start.addingTimeInterval(3600), isAllDay: false, url: nil, isBusy: true, version: "7")
        calendarStore.storedEvents = [stored, hidden]
        settings.selectedCalendarIDs = ["cal"]
        let hit = CalendarEvent(id: "abc|1", externalID: nil, calendarID: "cal", title: "Klausur", start: start,
                                end: start.addingTimeInterval(3600), isAllDay: false, url: nil, isBusy: true, version: "7")
        #expect(model.resolveEvent(matching: hit)?.id == "abc#cal|1")
        var changed = hit
        changed.start = at(20, 15)
        #expect(model.resolveEvent(matching: changed) == nil)
        var elsewhere = hit
        elsewhere.calendarID = "other"
        #expect(model.resolveEvent(matching: elsewhere) == nil)   // "other" is not a readable calendar
    }

    @Test func didHandOver_removesDayAndFutureBlocks_keepsPastBlocks() async throws {
        let model = await model()
        let issue = github.tasks[0]
        let past = try blocks.createBlock(for: issue, start: at(17, 9), minutes: 60)
        _ = try blocks.createBlock(for: issue, start: at(19, 9), minutes: 60)
        planStore.assign(issue.id, to: PlanDay(year: 2026, month: 11, day: 19))

        await model.didHandOver(issue.id)

        #expect(planStore.assignment(for: issue.id) == nil)
        #expect(calendarStore.storedEvents.map(\.id) == [past.id])
        #expect(model.lastError == nil)
    }

    @Test func futureBlockCount_countsFromNow() async throws {
        let model = await model()
        let issue = github.tasks[0]
        // Earlier today (before 10:00) counts for the editor's "Geplant" section, but is not deleted on hand-over.
        _ = try blocks.createBlock(for: issue, start: at(18, 8), minutes: 60)
        _ = try blocks.createBlock(for: issue, start: at(18, 14), minutes: 60)
        _ = try blocks.createBlock(for: issue, start: at(19, 9), minutes: 60)

        #expect(model.futureBlockCount(for: issue.id) == 2)
        #expect(model.plannedInfo(for: issue.id).blocks.count == 3)
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
        #expect(day?.capacity.untimedMinutes == 30)
        #expect(day?.capacity.untimedCount == 1)
        #expect(day?.capacity.plannedMinutes == 0)
        #expect(day?.capacity.freeMinutes == 480)
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

    @Test func planInput_matchesCapacity() async {
        settings.bufferMinutes = 10
        planStore.assign(id("Fahrrad"), to: today)
        calendarStore.storedEvents = [
            CalendarEvent(id: "busy", externalID: nil, calendarID: "work", title: "Vorlesung",
                          start: at(18, 10), end: at(18, 11), isAllDay: false, url: nil, isBusy: true, version: "1"),
            CalendarEvent(id: "linked", externalID: nil, calendarID: "work", title: "Login",
                          start: at(18, 14), end: at(18, 15), isAllDay: false, url: nil, isBusy: true, version: "1"),
        ]
        blocks.links.link(eventID: "linked", to: id("Login", .github))
        let model = await model()
        let day = try? #require(model.days.first { $0.day == today })
        let input = try? #require(day?.planInput)
        #expect(input?.availableMinutes == day?.capacity.availableMinutes)
        // The load for the AI checks keeps the tasks without a time; the capacity of the day does not.
        #expect(input?.plannedMinutes == (day?.capacity.plannedMinutes ?? 0) + (day?.capacity.untimedMinutes ?? 0))
        #expect(input?.busy == [600..<660])
        #expect(input?.blocks == [840..<900])
        #expect(input?.countedTaskMinutes == ["local:Fahrrad": 30])
    }

    @Test func capacity_unlinkedEventIsBusy() async {
        calendarStore.storedEvents = [CalendarEvent(id: "e", externalID: nil, calendarID: "work", title: "Vorlesung",
                                                    start: at(18, 10), end: at(18, 11), isAllDay: false, url: nil,
                                                    isBusy: true, version: "1")]
        let model = await model()
        #expect(model.days.first { $0.day == today }?.capacity.availableMinutes == 420)
    }

    @Test func unplanned_includesLeftoversFromPastDays() async {
        planStore.assign(id("Fahrrad"), to: PlanDay(year: 2026, month: 11, day: 16))
        planStore.assign(id("Abgabe"), to: today)
        let model = await model()
        model.scope = .week
        await model.reload()
        #expect(Set(model.unplanned.map(\.title)) == ["Fahrrad", "Login"])
        #expect(model.unplannedSections(search: "Fahr").other.map(\.title) == ["Fahrrad"])
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

    @Test func dueToday_appearsAndCountsAsUntimedEffort() async throws {
        local.tasks.append(makeTask("Heute fällig", source: .local, due: DueDate(year: 2026, month: 11, day: 18)))
        let model = await model()
        let day = try #require(model.days.first)
        #expect(day.openToday.map(\.title) == ["Heute fällig"])
        #expect(day.capacity.untimedMinutes == 30)
        #expect(day.capacity.plannedMinutes == 0)
    }

    @Test func openToday_staleAssignment_dueToday_isOpenNotOverdue() async throws {
        local.tasks.append(makeTask("Verschoben", source: .local, due: DueDate(year: 2026, month: 11, day: 18)))
        planStore.assign(id("Verschoben"), to: PlanDay(year: 2026, month: 11, day: 16))
        let model = await model()
        #expect(try #require(model.days.first).openToday.map(\.title) == ["Verschoben"])
        #expect(model.overdue.isEmpty)
    }

    @Test func overdue_recurringPastDue_isOverdue() async throws {
        let reminders = FakeTaskProvider(source: .reminders,
                                         tasks: [makeTask("k", source: .reminders, due: DueDate(year: 2026, month: 11, day: 16))])
        await taskList.register(reminders)
        let model = await model()
        #expect(model.overdue.map(\.id.rawValue) == ["k"])
    }

    @Test func dueToday_withAssignmentElsewhere_notShown() async throws {
        local.tasks.append(makeTask("Heute fällig", source: .local, due: DueDate(year: 2026, month: 11, day: 18)))
        planStore.assign(id("Heute fällig"), to: PlanDay(year: 2026, month: 11, day: 20))
        let model = await model()
        #expect(try #require(model.days.first).openToday.isEmpty)
    }

    // MARK: Planning tomorrow (plan-tomorrow, step 2)

    private let tomorrow = PlanDay(year: 2026, month: 11, day: 19)

    /// A model whose clock reads `now` (default: Wednesday 10:00); `clock` lets a test move the time.
    private func model(at hour: Int, _ minute: Int = 0, day: Int = 18) async -> PlanningModel {
        let now = at(day, hour, minute)
        await taskList.reload()
        let model = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: accessStore,
                                  planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                  blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                  now: { now }, calendar: calendar)
        await model.reload()
        return model
    }

    @Test func futureDay_listsTasksDueThatDay_andCountsTheirUntimedEffort() async throws {
        let model = await model()
        model.anchor = tomorrow
        await model.reload()
        let day = try #require(model.days.first)
        #expect(day.openToday.map(\.title) == ["Abgabe"])  // due on the 19th, no estimate: 30 min
        #expect(day.capacity.untimedMinutes == 30)
    }

    @Test func futureDay_dueTaskAssignedToAnotherFutureDay_notListedTwice() async throws {
        planStore.assign(id("Abgabe"), to: PlanDay(year: 2026, month: 11, day: 20))
        let model = await model()
        model.scope = .week
        await model.reload()
        let thursday = try #require(model.days.first { $0.day == tomorrow })
        let friday = try #require(model.days.first { $0.day == PlanDay(year: 2026, month: 11, day: 20) })
        #expect(thursday.openToday.isEmpty)
        #expect(thursday.capacity.untimedMinutes == 0)
        #expect(friday.assigned.map(\.title) == ["Abgabe"])
        #expect(friday.capacity.untimedMinutes == 30)
    }

    @Test func futureDay_dueTaskAssignedToToday_countsOnlyToday() async throws {
        planStore.assign(id("Abgabe"), to: today)
        let model = await model()
        model.scope = .week
        await model.reload()
        #expect(try #require(model.days.first { $0.day == tomorrow }).openToday.isEmpty)
        #expect(try #require(model.days.first { $0.day == today }).capacity.untimedMinutes == 30)
    }

    @Test func week_countsTasksDueOnFutureDaysAsUntimedEffort() async throws {
        // Due on the day counts as untimed effort in week and month too; it takes no free time.
        let model = await model()
        model.scope = .week
        await model.reload()
        let tomorrowCapacity = try #require(model.days.first { $0.day == tomorrow }).capacity
        #expect(tomorrowCapacity.untimedMinutes == 30)
        #expect(tomorrowCapacity.plannedMinutes == 0)
    }

    @Test func isTodayOver_afterWorkEnd_andOnDayOff() async {
        #expect(await model().isTodayOver == false)  // Wednesday 10:00
        #expect(await model(at: 18, 0).isTodayOver == true)  // work ends at 18:00
        #expect(await model(at: 10, 0, day: 21).isTodayOver == true)  // Saturday
        planStore.setOverride(.hours(WorkHours(startMinutes: 540, endMinutes: 1200)), on: today)
        #expect(await model(at: 18, 40).isTodayOver == false)  // longer day until 20:00
    }

    @Test func leftFromToday_onlyWhenTodayIsOver_withoutFutureBlocks() async throws {
        local.tasks.append(makeTask("Heute fällig", source: .local, due: DueDate(year: 2026, month: 11, day: 18)))
        local.tasks.append(makeTask("Später", source: .local, due: DueDate(year: 2026, month: 11, day: 18)))
        local.tasks.append(makeTask("Mit Block", source: .local))
        planStore.assign(id("Fahrrad"), to: today)
        planStore.assign(id("Später"), to: PlanDay(year: 2026, month: 11, day: 20))
        await taskList.reload()
        let task = try #require(taskList.items.first { $0.title == "Mit Block" })
        _ = try blocks.createBlock(for: task, start: at(19, 9), minutes: 60)
        planStore.assign(id("Mit Block"), to: today)

        #expect(await model().leftFromToday.isEmpty)  // 10:00: today still has work time
        let evening = await model(at: 18, 40)
        #expect(Set(evening.leftFromToday.map(\.title)) == ["Fahrrad", "Heute fällig"])
    }

    @Test func openFromToday_isFilledBeforeTodayIsOver_leftFromTodayStaysEmpty() async {
        planStore.assign(id("Fahrrad"), to: today)
        let morning = await model()
        #expect(morning.openFromToday.map(\.title) == ["Fahrrad"])
        #expect(morning.leftFromToday.isEmpty)
        let evening = await model(at: 18, 40)
        #expect(evening.openFromToday.map(\.title) == evening.leftFromToday.map(\.title))
    }

    @Test func showsLeftoverLine_followsTheRuleOfTheCard() async {
        planStore.assign(id("Fahrrad"), to: today)
        // Working hours are 9:00 to 18:00: the row appears from 16:00 on, or at any time when the day is overbooked.
        #expect(await !model(at: 10).showsLeftoverLine(overbooked: false))
        #expect(await model(at: 10).showsLeftoverLine(overbooked: true))
        #expect(await !model(at: 15, 59).showsLeftoverLine(overbooked: false))
        #expect(await model(at: 16).showsLeftoverLine(overbooked: false))
        #expect(await model(at: 18, 40).showsLeftoverLine(overbooked: false))
    }

    @Test func showsLeftoverLine_withoutOpenTasks_isFalse() async {
        #expect(await !model(at: 17).showsLeftoverLine(overbooked: true))
    }

    @Test func nextPlanDay_skipsDaysOff_withinFiveDays() async {
        #expect(await model(at: 18, 40).nextPlanDay == tomorrow)
        // Friday evening: Saturday and Sunday are off.
        #expect(await model(at: 18, 40, day: 20).nextPlanDay == PlanDay(year: 2026, month: 11, day: 23))
        for offset in 1...5 { planStore.setOverride(.off, on: today.adding(days: offset, calendar: calendar)) }
        #expect(await model(at: 18, 40).nextPlanDay == nil)
    }

    @Test func eveningEntry_onlyOnTodayAfterWorkEnd_withFreeTimeAndLeftovers() async throws {
        planStore.assign(id("Fahrrad"), to: today)
        #expect(await model().eveningEntry == nil)
        let model = await model(at: 18, 40)
        let entry = try #require(model.eveningEntry)
        #expect(entry.day == tomorrow)
        #expect(entry.freeMinutes == 480)  // "Abgabe" due tomorrow (30 min, no time block) takes no free time
        #expect(entry.leftCount == 1)
        model.anchor = tomorrow
        await model.reload()
        #expect(model.eveningEntry == nil)
    }

    @Test func midnight_reloadUsesTheNewToday() async throws {
        planStore.assign(id("Fahrrad"), to: today)
        var now = at(18, 23, 50)
        await taskList.reload()
        let model = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: accessStore,
                                  planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                  blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                  now: { now }, calendar: calendar)
        model.anchor = tomorrow
        await model.reload()
        #expect(model.leftFromToday.map(\.title) == ["Fahrrad"])
        now = at(19, 0, 10)
        await model.reload()
        #expect(model.today == tomorrow)
        #expect(model.leftFromToday.isEmpty)  // a new day with work time ahead
        #expect(model.overdue.map(\.title) == ["Fahrrad"])  // planned for yesterday
    }

    @Test func freeAfterAccepting_subtractsTheSuggestedBlocks() {
        // Mockup MP2: 5 h free, 4 h suggested as blocks; tasks without a time block take no free time, so 1 h remains.
        let suggestions = [("a", 75), ("b", 45), ("c", 30), ("d", 90)].map { key, minutes in
            PlanSuggestion(id: UUID(), kind: .block, taskKey: key, title: key, day: tomorrow, startMinutes: 540,
                           minutes: minutes, reason: "r")
        }
        let move = PlanSuggestion(id: UUID(), kind: .move, taskKey: "e", title: "e", day: tomorrow, startMinutes: nil,
                                  minutes: nil, reason: "r")
        let free = PlanningModel.freeAfterAccepting(free: 300, suggestions: suggestions + [move])
        #expect(free == 60)
        #expect(PlanningModel.freeAfterAccepting(free: 30, suggestions: suggestions) == 0)
    }

    @Test func leftoverTargetCapacity_ignoresTasksWithoutTime() async {
        // "Abgabe" is due tomorrow and has no time block: it takes no free time of the target day.
        let capacity = await model().leftoverTargetCapacity(on: tomorrow)
        #expect(capacity.freeMinutes == 480)
        #expect(!capacity.isDayOff)
    }

    @Test func overdue_shownTodayAndTomorrow_notLater() async {
        let model = await model()
        #expect(model.showsOverdue(on: today))
        #expect(model.showsOverdue(on: tomorrow))
        #expect(!model.showsOverdue(on: PlanDay(year: 2026, month: 11, day: 20)))
        #expect(!model.showsOverdue(on: PlanDay(year: 2026, month: 11, day: 17)))
    }

    @Test func leftovers_onlyOnNextPlanDay_onceTodayIsOver() async {
        planStore.assign(id("Fahrrad"), to: today)
        #expect(await model().leftovers(on: tomorrow).isEmpty)
        let evening = await model(at: 18, 40)
        #expect(evening.leftovers(on: tomorrow).map(\.title) == ["Fahrrad"])
        #expect(evening.leftovers(on: PlanDay(year: 2026, month: 11, day: 20)).isEmpty)
        #expect(evening.leftovers(on: today).isEmpty)
    }

    @Test func assignFromPanel_usesShownDay() async throws {
        let model = await model()
        model.anchor = tomorrow
        await model.reload()
        await model.commitToShownDay(id("Abgabe"))
        #expect(planStore.assignment(for: id("Abgabe")) == tomorrow)
    }

    @Test func moveTasks_movesAll_andUndoRestoresEach() async throws {
        planStore.assign(id("Fahrrad"), to: today)
        planStore.assign(id("Login", .github), to: today)
        let model = await model(at: 18, 40)
        await model.moveTasks([id("Fahrrad"), id("Login", .github)], to: tomorrow)
        #expect(planStore.assignment(for: id("Fahrrad")) == tomorrow)
        #expect(planStore.assignment(for: id("Login", .github)) == tomorrow)
        #expect(model.lastMoveGroup?.count == 2)
        #expect(model.lastMove == nil)
        await model.undoMoveGroup()
        #expect(planStore.assignment(for: id("Fahrrad")) == today)
        #expect(planStore.assignment(for: id("Login", .github)) == today)
        #expect(model.lastMoveGroup == nil)
    }

    @Test func placeInFreeBlocks_createsBlocksAndPlansTheDays() async throws {
        planStore.assign(id("Fahrrad"), to: today)
        let model = await model(at: 18, 40)
        let outcome = await model.placeInFreeBlocks([id("Fahrrad"), id("Abgabe")])
        #expect(outcome == PlanningModel.LeftoverOutcome(placed: 2, late: 0, unplaced: 0))
        #expect(calendarStore.storedEvents.count == 2)
        // The task due tomorrow lands tomorrow; nothing overlaps.
        #expect(planStore.assignment(for: id("Abgabe")) == tomorrow)
        let spans = calendarStore.storedEvents.map { $0.start..<$0.end }
        #expect(!spans[0].overlaps(spans[1]))
        #expect(model.lastMoveGroup?.count == 2)
        #expect(model.lastMoveGroup?.allSatisfy { $0.createdBlockIDs.count == 1 } == true)
    }

    @Test func placeInFreeBlocks_undoDeletesTheNewBlocksAndRestoresTheDay() async throws {
        planStore.assign(id("Fahrrad"), to: today)
        let model = await model(at: 18, 40)
        _ = await model.placeInFreeBlocks([id("Fahrrad")])
        #expect(calendarStore.storedEvents.count == 1)
        #expect(planStore.assignment(for: id("Fahrrad")) != today)
        await model.undoMoveGroup()
        #expect(calendarStore.storedEvents.isEmpty)
        #expect(planStore.assignment(for: id("Fahrrad")) == today)
        #expect(model.lastMoveGroup == nil)
    }

    @Test func placeInFreeBlocks_reportsUnplacedTasks() async throws {
        planStore.assign(id("Fahrrad"), to: today)
        // A block longer than any working day fits nowhere.
        settings.defaultTaskMinutes = 900
        let model = await model(at: 18, 40)
        let outcome = await model.placeInFreeBlocks([id("Fahrrad")])
        #expect(outcome == PlanningModel.LeftoverOutcome(placed: 0, late: 0, unplaced: 1, unplacedTaskIDs: [id("Fahrrad")]))
        #expect(calendarStore.storedEvents.isEmpty)
        #expect(model.lastMoveGroup == nil)
        #expect(planStore.assignment(for: id("Fahrrad")) == today)
    }

    @Test func moveTasks_undo_stillWorks() async throws {
        // The existing way "Alle auf morgen" does not create blocks and takes none back.
        planStore.assign(id("Fahrrad"), to: today)
        let model = await model(at: 18, 40)
        await model.moveTasks([id("Fahrrad")], to: tomorrow)
        #expect(model.lastMoveGroup?.first?.createdBlockIDs.isEmpty == true)
        await model.undoMoveGroup()
        #expect(planStore.assignment(for: id("Fahrrad")) == today)
        #expect(calendarStore.storedEvents.isEmpty)
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
        #expect(day.openToday.map(\.id.rawValue) == ["k"])
        #expect(day.capacity.plannedMinutes == 0)
    }

    @Test func recurringReminderInShoppingList_isIgnored() async {
        func daily(_ id: String, list: String) -> ReminderRecord {
            ReminderRecord(id: id, title: id, notes: nil, due: DueDate(year: 2026, month: 11, day: 18), ekPriority: 0,
                           isCompleted: false, listID: list, lastModified: nil,
                           recurrence: Recurrence(rule: .daily(interval: 1), start: today, end: nil, count: nil))
        }
        accessStore.accessState = .fullAccess
        accessStore.openRecords = [daily("shop-1", list: "shop"), daily("uni-1", list: "uni")]
        settings.shoppingListID = "shop"
        let model = await model()
        #expect(model.recurringTaskIDs == [TaskID(source: .reminders, rawValue: "uni-1")])
    }

    private func addTask(_ title: String, estimate: Int?) {
        local.tasks.append(TaskItem(id: id(title), title: title, notes: nil, due: nil, priority: nil, estimateMinutes: estimate,
                                    isCompleted: false, container: TaskContainer(id: "local", name: "Lokal", colorHex: nil),
                                    url: nil, version: "1", editableFields: []))
    }

    @Test func toSchedule_listsTasksWithBlocksBelowEstimate() async throws {
        addTask("Lesen", estimate: 180)
        addTask("Fertig", estimate: 60)
        await taskList.reload()
        let lesen = try #require(taskList.items.first { $0.title == "Lesen" })
        let fertig = try #require(taskList.items.first { $0.title == "Fertig" })
        _ = try blocks.createBlock(for: lesen, start: at(17, 9), minutes: 60)
        _ = try blocks.createBlock(for: fertig, start: at(18, 14), minutes: 60)
        let model = await model()
        #expect(model.toSchedule.map(\.title) == ["Lesen"])
        #expect(model.sessionProgress[lesen.id] == PlanningModel.SessionProgress(blocked: 60, estimate: 180))
        #expect(model.sessionProgress[lesen.id]?.remaining == 120)
    }

    @Test func recurringTask_countsOnlyBlocksOfTheCurrentPeriod() async throws {
        accessStore.openRecords = [ReminderRecord(id: "k", title: "Training", notes: nil, due: DueDate(year: 2026, month: 11, day: 18),
                                                  ekPriority: 0, isCompleted: false, listID: "l", lastModified: nil,
                                                  recurrence: Recurrence(rule: .daily(interval: 1), start: PlanDay(year: 2026, month: 11, day: 10),
                                                                         end: nil, count: nil))]
        accessStore.accessState = .fullAccess
        let reminders = FakeTaskProvider(source: .reminders, tasks: [makeTask("k", source: .reminders, due: DueDate(year: 2026, month: 11, day: 18))])
        await taskList.register(reminders)
        RecurringEffortStore(context: container.mainContext).setForAll(60, task: TaskID(source: .reminders, rawValue: "k"), from: PlanDay(year: 2026, month: 11, day: 10))
        let task = try #require(taskList.items.first { $0.id.source == .reminders })
        _ = try blocks.createBlock(for: task, start: at(17, 9), minutes: 60)
        var model = await model()
        #expect(model.toSchedule.isEmpty)  // yesterday's session belongs to yesterday's occurrence
        _ = try blocks.createBlock(for: task, start: at(18, 15), minutes: 30)
        model = await self.model()
        #expect(model.toSchedule.map(\.id) == [task.id])
        #expect(model.sessionProgress[task.id]?.remaining == 30)
    }

    /// A daily recurring reminder "Blumen" (due today) with the given recurring effort; returns the task.
    private func addDailyReminder(effort: Int?) async throws -> TaskItem {
        accessStore.openRecords = [ReminderRecord(id: "b", title: "Blumen", notes: nil, due: DueDate(year: 2026, month: 11, day: 18),
                                                  ekPriority: 0, isCompleted: false, listID: "l", lastModified: nil,
                                                  recurrence: Recurrence(rule: .daily(interval: 1), start: PlanDay(year: 2026, month: 11, day: 10),
                                                                         end: nil, count: nil))]
        accessStore.accessState = .fullAccess
        let reminders = FakeTaskProvider(source: .reminders, tasks: [makeTask("b", source: .reminders, due: DueDate(year: 2026, month: 11, day: 18))])
        await taskList.register(reminders)
        if let effort {
            RecurringEffortStore(context: container.mainContext).setForAll(effort, task: TaskID(source: .reminders, rawValue: "b"), from: PlanDay(year: 2026, month: 11, day: 10))
        }
        return try #require(taskList.items.first { $0.id.source == .reminders })
    }

    // MARK: Changing the recurrence (plan 2026-11-18)

    /// A recurring reminder "s" with `rule` from `start` (= due date) and 30 minutes of recurring effort.
    private func addSeries(_ rule: RecurrenceRule, start: PlanDay) async throws -> TaskItem {
        let due = DueDate(year: start.year, month: start.month, day: start.day)
        accessStore.openRecords = [ReminderRecord(id: "s", title: "Serie", notes: nil, due: due, ekPriority: 0, isCompleted: false,
                                                  listID: "l", lastModified: nil,
                                                  recurrence: Recurrence(rule: rule, start: start, end: nil, count: nil))]
        accessStore.accessState = .fullAccess
        await taskList.register(FakeTaskProvider(source: .reminders, tasks: [makeTask("s", source: .reminders, due: due)]))
        RecurringEffortStore(context: container.mainContext).setForAll(30, task: TaskID(source: .reminders, rawValue: "s"), from: PlanDay(year: 2026, month: 11, day: 16))
        return try #require(taskList.items.first { $0.id.source == .reminders })
    }

    private func reservedDays(_ model: PlanningModel) -> [Int] {
        model.days.filter { $0.recurring.contains { $0.taskID.rawValue == "s" && $0.minutes == 30 } }.map(\.day.day)
    }

    @Test func ruleChange_reservesOnNewDays() async throws {
        _ = try await addSeries(.weekly(interval: 1, weekdays: [5]), start: PlanDay(year: 2026, month: 11, day: 19))
        let model = await model()
        model.scope = .week
        await model.reload()
        #expect(reservedDays(model) == [19])
        // Saved as "every month on the 3rd Wednesday" from Wednesday, 18 November.
        accessStore.openRecords[0].due = DueDate(year: 2026, month: 11, day: 18)
        accessStore.openRecords[0].recurrence = Recurrence(rule: .monthlyWeekday(interval: 1, ordinal: 3, weekday: 4), start: today,
                                                           end: nil, count: nil)
        await model.reload()
        #expect(reservedDays(model) == [18])
    }

    @Test func removingRule_dropsReservedEffort() async throws {
        let task = try await addSeries(.daily(interval: 1), start: today)
        let model = await model()
        #expect(reservedDays(model) == [18])
        accessStore.openRecords[0].recurrence = nil
        await model.reload()
        #expect(reservedDays(model).isEmpty)
        #expect(model.recurringItem(for: task, on: today) == nil)
    }

    /// A block prepares the occurrence of the current rule on or after its day; it is off the series when the
    /// new rule no longer has that occurrence (device test: the old window rule almost never asked).
    @Test func blocksOffSeries_flagsBlockWhoseOccurrenceDisappears() async throws {
        // Weekly on Thursday from 19 November; Thursday 26 November is the occurrence.
        let task = try await addSeries(.weekly(interval: 1, weekdays: [5]), start: PlanDay(year: 2026, month: 11, day: 19))
        let onThursday = try blocks.createBlock(for: task, start: at(26, 9), minutes: 60)
        let model = await model()
        // Mockup example: every 2 weeks on Monday and Thursday from 30 November no longer has 26 November.
        let changed = Recurrence(rule: .weekly(interval: 2, weekdays: [2, 5]), start: PlanDay(year: 2026, month: 11, day: 30),
                                 end: nil, count: nil)
        #expect(model.blocksOffSeries(for: task, recurrence: changed).map(\.id) == [onThursday.id])
    }

    @Test func blocksOffSeries_keepsBlockPreparingAnOccurrenceThatStays() async throws {
        let task = try await addSeries(.weekly(interval: 1, weekdays: [5]), start: PlanDay(year: 2026, month: 11, day: 19))
        // Tuesday's block is work on Thursday 26 November, which the new rule keeps.
        _ = try blocks.createBlock(for: task, start: at(24, 9), minutes: 60)
        let model = await model()
        let withMonday = Recurrence(rule: .weekly(interval: 1, weekdays: [2, 5]), start: PlanDay(year: 2026, month: 11, day: 19),
                                    end: nil, count: nil)
        #expect(model.blocksOffSeries(for: task, recurrence: withMonday).isEmpty)
        #expect(model.blocksOffSeries(for: task, recurrence: Recurrence(rule: .unsupported, start: today, end: nil, count: nil)).isEmpty)
    }

    @Test func blocksOffSeries_flagsBlockAfterNewEnd() async throws {
        let task = try await addSeries(.daily(interval: 1), start: today)
        let before = try blocks.createBlock(for: task, start: at(20, 9), minutes: 60)
        let after = try blocks.createBlock(for: task, start: at(25, 9), minutes: 60)
        let model = await model()
        let ending = Recurrence(rule: .daily(interval: 1), start: today, end: PlanDay(year: 2026, month: 11, day: 22), count: nil)
        #expect(model.blocksOffSeries(for: task, recurrence: ending).map(\.id) == [after.id])
        _ = before
    }

    @Test func dropTask_recurringReminder_usesRecurringEffort() async throws {
        let task = try await addDailyReminder(effort: 15)
        #expect(task.estimateMinutes == nil)
        let model = await model()
        await model.dropTask(key: task.id.key, atMinutes: 13 * 60, on: today)
        let block = try #require(calendarStore.storedEvents.first)
        #expect(block.start == at(18, 13))
        #expect(block.end == at(18, 13, 15))
    }

    @Test func suggestedBlockMinutes_recurringReminder_usesEffortOfTheDay() async throws {
        let task = try await addDailyReminder(effort: 15)
        let tomorrow = today.adding(days: 1, calendar: calendar)
        RecurringEffortStore(context: container.mainContext).setForDay(45, task: TaskID(source: .reminders, rawValue: "b"), day: tomorrow)
        let model = await model()
        #expect(model.suggestedBlockMinutes(for: task, on: today) == 15)
        #expect(model.suggestedBlockMinutes(for: task, on: tomorrow) == 45)
    }

    @Test func suggestedBlockMinutes_recurring_ignoresBlocksOfOtherOccurrences() async throws {
        let task = try await addDailyReminder(effort: 15)
        let tomorrow = today.adding(days: 1, calendar: calendar)
        _ = try blocks.createBlock(for: task, start: at(17, 9), minutes: 15)
        _ = try blocks.createBlock(for: task, start: at(19, 9), minutes: 15)
        let model = await model()
        #expect(model.suggestedBlockMinutes(for: task, on: today) == 15)  // yesterday and tomorrow are other occurrences
        _ = try blocks.createBlock(for: task, start: at(18, 9), minutes: 15)
        let reloaded = await self.model()
        #expect(reloaded.suggestedBlockMinutes(for: task, on: today.adding(days: 2, calendar: calendar)) == 15)
        #expect(reloaded.suggestedBlockMinutes(for: task, on: tomorrow) == 30)  // tomorrow's occurrence is planned: default
    }

    @Test func suggestedBlockMinutes_recurring_subtractsBlocksOfTheSameOccurrence() async throws {
        let task = try await addDailyReminder(effort: 60)
        _ = try blocks.createBlock(for: task, start: at(18, 9), minutes: 30)
        let model = await model()
        #expect(model.suggestedBlockMinutes(for: task, on: today) == 30)
    }

    @Test func suggestedBlockMinutes_recurringWithoutEffort_usesDefault() async throws {
        let task = try await addDailyReminder(effort: nil)
        let model = await model()
        #expect(model.suggestedBlockMinutes(for: task, on: today) == 30)
    }

    @Test func duplicateBlock_recurring_usesRemainingRecurringEffort() async throws {
        let task = try await addDailyReminder(effort: 60)
        let block = try blocks.createBlock(for: task, start: at(18, 14), minutes: 30)
        let model = await model()
        let original = try #require(calendarStore.event(id: block.id))
        #expect(model.duplicateTarget(for: original)?.count == 30)
    }

    @Test func duplicateBlock_goesToNextFreeSlotWithRemainingTime() async throws {
        addTask("Lesen", estimate: 180)
        await taskList.reload()
        let lesen = try #require(taskList.items.first { $0.title == "Lesen" })
        let block = try blocks.createBlock(for: lesen, start: at(18, 14), minutes: 60)
        let model = await model()
        let original = try #require(calendarStore.event(id: block.id))
        #expect(model.duplicateTarget(for: original) == 900..<1020)
        await model.duplicateBlock(original)
        let copies = calendarStore.storedEvents.filter { $0.id != block.id }
        #expect(copies.map(\.start) == [at(18, 15)])
        #expect(copies.first?.end == at(18, 17))
        #expect(model.lastDuplicate != nil)
        await model.undoDuplicate()
        #expect(calendarStore.storedEvents.map(\.id) == [block.id])
    }

    @Test func duplicateBlock_fullyPlanned_usesDefaultDuration_andBuffer() async throws {
        settings.bufferMinutes = 10
        settings.defaultTaskMinutes = 30
        addTask("Kurz", estimate: 60)
        await taskList.reload()
        let task = try #require(taskList.items.first { $0.title == "Kurz" })
        let block = try blocks.createBlock(for: task, start: at(18, 14), minutes: 60)
        let model = await model()
        let original = try #require(calendarStore.event(id: block.id))
        // Estimate used up by the first block → 30 min; 10 min distance to the original (ends 15:00).
        #expect(model.duplicateTarget(for: original) == 910..<940)
    }

    @Test func moveTask_takesOnlyBlocksOfTheOriginDay() async throws {
        addTask("Lesen", estimate: 180)
        await taskList.reload()
        let lesen = try #require(taskList.items.first { $0.title == "Lesen" })
        let onOrigin = try blocks.createBlock(for: lesen, start: at(19, 9), minutes: 60)
        let elsewhere = try blocks.createBlock(for: lesen, start: at(20, 9), minutes: 60)
        planStore.assign(lesen.id, to: PlanDay(year: 2026, month: 11, day: 19))
        let model = await model()
        model.scope = .week
        await model.reload()

        await model.moveTask(lesen.id, to: PlanDay(year: 2026, month: 11, day: 23))

        #expect(planStore.assignment(for: lesen.id) == PlanDay(year: 2026, month: 11, day: 23))
        #expect(calendarStore.event(id: onOrigin.id)?.start == at(23, 9))
        #expect(calendarStore.event(id: elsewhere.id)?.start == at(20, 9))
        #expect(model.lastMove?.movedBlocks == 1)
        #expect(model.pendingBlockDecision == nil)

        await model.undoMove()
        #expect(planStore.assignment(for: lesen.id) == PlanDay(year: 2026, month: 11, day: 19))
        #expect(calendarStore.event(id: onOrigin.id)?.start == at(19, 9))
    }

    @Test func moveTask_occupiedTime_usesNextFreeSlot() async throws {
        addTask("Lesen", estimate: 60)
        await taskList.reload()
        let lesen = try #require(taskList.items.first { $0.title == "Lesen" })
        let block = try blocks.createBlock(for: lesen, start: at(19, 9), minutes: 60)
        planStore.assign(lesen.id, to: PlanDay(year: 2026, month: 11, day: 19))
        calendarStore.storedEvents.append(CalendarEvent(id: "busy", externalID: nil, calendarID: "work", title: "Termin",
                                                        start: at(20, 9), end: at(20, 10), isAllDay: false, url: nil,
                                                        isBusy: true, version: "1"))
        let model = await model()
        model.scope = .week
        await model.reload()

        await model.moveTask(lesen.id, to: PlanDay(year: 2026, month: 11, day: 20))

        #expect(calendarStore.event(id: block.id)?.start == at(20, 10))
    }

    @Test func stepSelectedDay_crossesIntoNextMonth() async {
        let model = await model()
        model.scope = .month
        model.selectedDay = PlanDay(year: 2026, month: 11, day: 30)
        model.stepSelectedDay(1)
        #expect(model.monthSelection == PlanDay(year: 2026, month: 12, day: 1))
        #expect(model.anchor.month == 12)
        model.stepSelectedDay(-1)
        #expect(model.monthSelection == PlanDay(year: 2026, month: 11, day: 30))
        #expect(model.anchor.month == 11)
    }

    @Test func recurringReminderWithBlock_countsItsTimeOnce() async throws {
        accessStore.openRecords = [ReminderRecord(id: "k", title: "Training", notes: nil, due: DueDate(year: 2026, month: 11, day: 18),
                                                  ekPriority: 0, isCompleted: false, listID: "l", lastModified: nil,
                                                  recurrence: Recurrence(rule: .daily(interval: 1), start: PlanDay(year: 2026, month: 11, day: 10),
                                                                         end: nil, count: nil))]
        accessStore.accessState = .fullAccess
        let reminders = FakeTaskProvider(source: .reminders, tasks: [makeTask("k", source: .reminders, due: DueDate(year: 2026, month: 11, day: 18))])
        await taskList.register(reminders)
        RecurringEffortStore(context: container.mainContext).setForAll(120, task: TaskID(source: .reminders, rawValue: "k"), from: PlanDay(year: 2026, month: 11, day: 10))
        let task = try #require(taskList.items.first { $0.id.source == .reminders })
        _ = try blocks.createBlock(for: task, start: at(18, 14), minutes: 120)
        let model = await model()
        let day = try #require(model.days.first)
        // 480 working minutes; the 120 reserved are covered by the block, which counts as planned.
        #expect(day.capacity.availableMinutes == 480)
        #expect(day.capacity.plannedMinutes == 120)
    }

    // MARK: Day capacity (issue #260)

    private let tuesday = PlanDay(year: 2026, month: 11, day: 24)

    private func event(_ id: String, _ title: String, day: Int = 24, _ from: (Int, Int), _ to: (Int, Int), allDay: Bool = false,
                       busy: Bool = true) -> CalendarEvent {
        CalendarEvent(id: id, externalID: nil, calendarID: "work", title: title, start: at(day, from.0, from.1),
                      end: at(day, to.0, to.1), isAllDay: allDay, url: nil, isBusy: busy, version: "1")
    }

    /// A daily recurring reminder with `effort` minutes reserved from the 10th on.
    private func addDailyReminder(_ title: String, effort: Int) async throws -> TaskItem {
        accessStore.openRecords = [ReminderRecord(id: title, title: title, notes: nil, due: DueDate(year: 2026, month: 11, day: 18),
                                                  ekPriority: 0, isCompleted: false, listID: "l", lastModified: nil,
                                                  recurrence: Recurrence(rule: .daily(interval: 1), start: PlanDay(year: 2026, month: 11, day: 10),
                                                                         end: nil, count: nil))]
        accessStore.accessState = .fullAccess
        await taskList.register(FakeTaskProvider(source: .reminders, tasks: [makeTask(title, source: .reminders, due: DueDate(year: 2026, month: 11, day: 18))]))
        RecurringEffortStore(context: container.mainContext).setForAll(effort, task: TaskID(source: .reminders, rawValue: title),
                                                                       from: PlanDay(year: 2026, month: 11, day: 10))
        return try #require(taskList.items.first { $0.id.source == .reminders })
    }

    private func monthDay(_ model: PlanningModel, _ day: PlanDay) async throws -> DayPlan {
        model.scope = .month
        await model.reload()
        return try #require(model.days.first { $0.day == day })
    }

    /// Tue 24 Nov as reported: all-day "Away" and a birthday, "Selbststudium" 8–18 free, "Away" 12–13 busy, "RT" 18:30–22
    /// free, lunch 12–13, hours 9–18, and a recurring task "Karteikarten" with 4 h reserved effort but no time block.
    @Test func capacity_reportedDay_isEightHoursFreeOfEight() async throws {
        settings.bufferMinutes = 10
        calendarStore.storedEvents = [
            event("a1", "Away", (0, 0), (23, 59), allDay: true),
            event("a2", "Oma Bärbel's 66th Birthday", (0, 0), (23, 59), allDay: true),
            event("s", "Selbststudium", (8, 0), (18, 0), busy: false),
            event("a3", "Away", (12, 0), (13, 0)),
            event("rt", "RT Young Generation", (18, 30), (22, 0), busy: false),
        ]
        _ = try await addDailyReminder("Karteikarten", effort: 240)
        let day = try await monthDay(await model(), tuesday)
        #expect(day.recurring.map(\.minutes) == [240])
        #expect(day.capacity.availableMinutes == 480)
        #expect(day.capacity.plannedMinutes == 0)
        #expect(day.capacity.freeMinutes == 480)
        #expect(CapacityText.summary(day.capacity) == "8 h frei von 8 h")
    }

    @Test func capacity_overlappingBlocks_countOnce() async throws {
        await taskList.reload()
        let first = try #require(taskList.items.first { $0.title == "Fahrrad" })
        let second = try #require(taskList.items.first { $0.title == "Abgabe" })
        _ = try blocks.createBlock(for: first, start: at(24, 10), minutes: 60)
        _ = try blocks.createBlock(for: second, start: at(24, 10, 30), minutes: 60)
        let day = try await monthDay(await model(), tuesday)
        #expect(day.capacity.plannedMinutes == 90)
    }

    @Test func capacity_blockAfterWork_usesNoFreeTime() async throws {
        await taskList.reload()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        _ = try blocks.createBlock(for: task, start: at(24, 19), minutes: 60)
        let day = try await monthDay(await model(), tuesday)
        #expect(day.capacity.freeMinutes == 480)
        #expect(day.capacity.breakdown.outsideBlockMinutes == 60)
    }

    @Test func capacity_recurringReminder_countsOnlyItsBlock() async throws {
        let task = try await addDailyReminder("Karteikarten", effort: 240)
        _ = try blocks.createBlock(for: task, start: at(24, 14), minutes: 90)
        let day = try await monthDay(await model(), tuesday)
        #expect(day.capacity.availableMinutes == 480)
        #expect(day.capacity.plannedMinutes == 90)
    }

    @Test func freedMinutes_matchesTheCardAfterwards() async throws {
        settings.bufferMinutes = 10
        calendarStore.storedEvents = [event("e1", "Vorlesung", (10, 0), (11, 0)), event("e2", "Seminar", (10, 30), (11, 30))]
        let model = await model()
        let day = try await monthDay(model, tuesday)
        #expect(day.capacity.availableMinutes == 480 - 110)
        let both = model.freedMinutes(of: day.events, in: day)
        #expect(both == 110)
        await model.setFree(day.events, free: true, series: false)
        let after = try await monthDay(model, tuesday)
        #expect(after.capacity.freeMinutes - day.capacity.freeMinutes == both)
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
        RecurringEffortStore(context: container.mainContext).setForAll(180, task: TaskID(source: .reminders, rawValue: "k"), from: PlanDay(year: 2026, month: 11, day: 1))
        let model = await model()
        #expect(model.days.first?.recurring == [RecurringItem(taskID: TaskID(source: .reminders, rawValue: "k"), title: "Karteikarten", minutes: 180)])
        // The reserved effort is no load: it takes no time until a time block is booked (decision KA3).
        #expect(model.days.first?.capacity.availableMinutes == 480)
        #expect(model.days.first?.capacity.plannedMinutes == 0)
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
        #expect(model.recurringItem(for: recurring, on: today) == RecurringItem(taskID: TaskID(source: .reminders, rawValue: "k"), title: "Karteikarten", minutes: 0))
        #expect(model.recurringItem(for: once, on: today) == nil)
        await model.setRecurringEffort(45, task: TaskID(source: .reminders, rawValue: "k"), day: today, forAll: true)
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
        RecurringEffortStore(context: container.mainContext).setForAll(60, task: TaskID(source: .reminders, rawValue: "k"), from: today)
    }

    @Test func completingRecurringToday_marksTheOccurrenceAndKeepsTheCapacity() async {
        recurringTraining()
        let model = await model()
        #expect(model.days.first?.capacity.remainingMinutes == 420)
        await model.didChangeCompletion(TaskID(source: .reminders, rawValue: "k"), isCompleted: true)
        #expect(model.days.first?.capacity.remainingMinutes == 420)
        #expect(model.days.first?.recurring.first?.isDone == true)
        await model.didChangeCompletion(TaskID(source: .reminders, rawValue: "k"), isCompleted: false)
        #expect(model.days.first?.capacity.remainingMinutes == 420)
        #expect(model.days.first?.recurring.first?.isDone == false)
    }

    @Test func completingNonRecurring_doesNotMarkOccurrence() async {
        recurringTraining()
        let model = await model()
        await model.didChangeCompletion(id("Fahrrad"), isCompleted: true)
        #expect(model.efforts.isDone(task: id("Fahrrad"), day: today) == false)
        #expect(model.days.first?.recurring.first?.isDone == false)
    }

    // MARK: Recurring local tasks (plan 2026-11-18, stage 2)

    /// A local "Lesen" every day from today with an estimate that must not count on top of the series effort.
    private func recurringLocalReading(effort: Int? = 60) -> TaskID {
        var task = makeTask("Lesen", source: .local, due: DueDate(year: 2026, month: 11, day: 18))
        task.estimateMinutes = 120
        task.recurrence = Recurrence(rule: .daily(interval: 1), start: today, end: nil, count: nil)
        local.tasks.append(task)
        if let effort { RecurringEffortStore(context: container.mainContext).setForAll(effort, task: task.id, from: today) }
        return task.id
    }

    @Test func recurringLocalTask_reservesEffortLikeReminder() async throws {
        let reading = recurringLocalReading()
        let model = await model()
        #expect(model.recurringTaskIDs == [reading])
        #expect(model.days.first?.recurring == [RecurringItem(taskID: reading, title: "Lesen", minutes: 60)])
        #expect(model.days.first?.capacity.remainingMinutes == 420)
        let task = try #require(taskList.items.first { $0.id == reading })
        #expect(model.recurringItem(for: task, on: today) == RecurringItem(taskID: reading, title: "Lesen", minutes: 60))
        #expect(model.effortMinutes(of: task) == 60)
    }

    /// The series effort replaces the estimate: due today, the task does not add its estimate as load.
    @Test func recurringLocalTask_countsOnlyThroughItsEffort() async {
        _ = recurringLocalReading(effort: nil)
        let model = await model()
        #expect(model.days.first?.capacity.plannedMinutes == 0)
        #expect(model.days.first?.capacity.remainingMinutes == 420)
    }

    @Test func recurringLocalTask_effortReachesFollowingOccurrences() async {
        let reading = recurringLocalReading()
        let model = await model()
        model.scope = .week
        await model.reload()
        #expect(model.days.filter { $0.recurring.contains { $0.taskID == reading } }.map(\.day.day) == [18, 19, 20, 21, 22])
    }

    @Test func completingRecurringLocalToday_marksTheOccurrence() async {
        let reading = recurringLocalReading()
        let model = await model()
        await model.didChangeCompletion(reading, isCompleted: true)
        #expect(model.efforts.isDone(task: reading, day: today))
        #expect(model.days.first?.capacity.remainingMinutes == 420)
        await model.didChangeCompletion(reading, isCompleted: false)
        #expect(model.efforts.isDone(task: reading, day: today) == false)
        #expect(model.days.first?.capacity.remainingMinutes == 420)
    }

    @Test func recurringLocalTask_settingEffortUsesTaskKey() async throws {
        let reading = recurringLocalReading(effort: nil)
        let model = await model()
        await model.setRecurringEffort(45, task: reading, day: today, forAll: true)
        #expect(model.efforts.minutes(for: reading, on: today) == 45)
        #expect(model.efforts.minutes(for: TaskID(source: .reminders, rawValue: "Lesen"), on: today) == nil)
    }

    /// A task that just got its rule is a series before the planning reloads (editor, "Aufwand ändern …").
    @Test func recurringItem_followsTheTaskBeforeReload() async throws {
        let model = await model()
        let reading = recurringLocalReading()
        await taskList.reload()
        let task = try #require(taskList.items.first { $0.id == reading })
        #expect(model.recurringItem(for: task, on: today) == RecurringItem(taskID: reading, title: "Lesen", minutes: 60))
    }

    /// A reminder listed by the task list with its rule and read from Reminders counts once.
    @Test func recurringReminderInTaskList_countsOnce() async {
        recurringTraining()
        var listed = makeTask("k", source: .reminders, due: DueDate(year: 2026, month: 11, day: 18))
        listed.recurrence = Recurrence(rule: .daily(interval: 1), start: today, end: nil, count: nil)
        await taskList.register(FakeTaskProvider(source: .reminders, tasks: [listed]))
        let model = await model()
        #expect(model.days.first?.recurring.count == 1)
        #expect(model.days.first?.capacity.remainingMinutes == 420)
    }

    /// Blocks count against the occurrence of the series (daily: the same day), not against the last 60 days.
    @Test func recurringLocalTask_blocksCountForTheirOccurrence() async throws {
        let reading = recurringLocalReading()
        let model = await model()
        let task = try #require(taskList.items.first { $0.id == reading })
        await model.createBlock(for: task, start: at(17, 14), minutes: 30)
        await model.createBlock(for: task, start: at(18, 14), minutes: 45)
        #expect(model.blockedMinutes(of: reading) == 45)
    }

    @Test func duplicateEvents_shownBothUntilAnswered_thenOnce() async throws {
        calendarStore.storedEvents = ["work", "shared"].map { calendarID in
            CalendarEvent(id: "seminar-\(calendarID)", externalID: nil, calendarID: calendarID, title: "Seminar",
                          start: at(18, 14), end: at(18, 15), isAllDay: false, url: nil, isBusy: true, version: "1")
        }
        let model = await model()
        #expect(model.timeline(for: try #require(model.days.first)).filter { $0.label == "Seminar" }.count == 2)
        let suggestion = try #require(model.mergeSuggestions.first)
        await model.decideMerge(suggestion, merge: true, always: false)
        let day = try #require(model.days.first)
        #expect(model.timeline(for: day).filter { $0.label == "Seminar" }.count == 1)
        #expect(day.events.first?.mergedCalendarIDs.count == 1)
        #expect(day.capacity.availableMinutes == 420)
        await model.showSeparately(try #require(day.events.first))
        #expect(model.timeline(for: try #require(model.days.first)).filter { $0.label == "Seminar" }.count == 2)
        #expect(model.mergeSuggestions.isEmpty)  // answered with "Getrennt"
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

    @Test func newEvent_prefillsEventDefaults() async {
        let model = await model()
        // Events have no default reminders until the user sets some (A3).
        #expect(model.defaultEventReminders(isAllDay: false).isEmpty)
        var defaults = settings.reminderDefaults
        defaults.set([.before(amount: 15, unit: .minutes)], for: .event, isAllDay: false)
        defaults.set([.at(daysBefore: 1, hour: 18, minute: 0)], for: .event, isAllDay: true)
        settings.reminderDefaults = defaults
        #expect(model.defaultEventReminders(isAllDay: false) == [.before(amount: 15, unit: .minutes)])
        #expect(model.defaultEventReminders(isAllDay: true) == [.at(daysBefore: 1, hour: 18, minute: 0)])
    }

    @Test func createEvent_passesTheAlarmsToTheStore() async throws {
        let model = await model()
        let created = await model.createEvent(EventDraft(title: "Lernen", start: at(18, 16), end: at(18, 17), isAllDay: false,
                                                         calendarID: "plan", notes: nil, location: nil, url: nil,
                                                         alarms: [.before(amount: 1, unit: .days)]))
        #expect(model.alarms(ofEvent: try #require(created).id) == [.before(amount: 1, unit: .days)])
    }

    @Test func updateEvent_passesAlarmsWithSpan() async throws {
        calendarStore.storedEvents = [18, 19, 20].map { day in
            var event = CalendarEvent(id: "sport|\(Int(at(day, 18).timeIntervalSince1970))", externalID: nil, calendarID: "work",
                                      title: "Sport", start: at(day, 18), end: at(day, 19), isAllDay: false, url: nil,
                                      isBusy: true, version: "1")
            event.isRecurring = true
            return event
        }
        let model = await model()
        let second = calendarStore.storedEvents[1]
        var change = draft(second)
        change.alarms = [.at(daysBefore: 1, hour: 18, minute: 0)]
        await model.updateEvent(second, with: change, span: .futureEvents)
        #expect(calendarStore.updateSpans == [.futureEvents])
        #expect(model.alarms(ofEvent: calendarStore.storedEvents[0].id).isEmpty)
        #expect(model.alarms(ofEvent: calendarStore.storedEvents[1].id) == [.at(daysBefore: 1, hour: 18, minute: 0)])
        #expect(model.alarms(ofEvent: calendarStore.storedEvents[2].id) == [.at(daysBefore: 1, hour: 18, minute: 0)])
        // A draft without alarms leaves them as they are.
        await model.updateEvent(second, with: draft(second, title: "Lauf"), span: .thisEvent)
        #expect(model.alarms(ofEvent: second.id) == [.at(daysBefore: 1, hour: 18, minute: 0)])
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
        #expect(sections.other.map(\.title) == ["Später fällig", "Login", "Fahrrad"])  // due, then source order
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
        #expect(model.suggestedBlockMinutes(for: task) == 30)  // fully blocked: the default duration
        let noEstimate = try #require(taskList.items.first { $0.title == "Fahrrad" })
        #expect(model.suggestedBlockMinutes(for: noEstimate) == 30)  // default duration
    }

    @Test func suggestedBlockMinutes_longEstimate_cappedByLargestFreeSlotFromNow() async throws {
        local.tasks.append(TaskItem(id: id("Thesis"), title: "Thesis", notes: nil, due: nil, priority: nil, estimateMinutes: 600,
                                    isCompleted: false, container: TaskContainer(id: "local", name: "Lokal", colorHex: nil),
                                    url: nil, version: "1", editableFields: []))
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Thesis" })
        // Today from 10:00: 10–12 and 13–18 are free (lunch 12–13) → largest slot 300 min.
        #expect(model.suggestedBlockMinutes(for: task, on: today) == 300)
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

    @Test func timelessTasks_onlyTasksPlannedForTheDay_inTaskOrder() async throws {
        local.tasks.append(TaskItem(id: id("Wichtig"), title: "Wichtig", notes: nil, due: DueDate(year: 2026, month: 11, day: 20),
                                    priority: .p1, estimateMinutes: nil, isCompleted: false,
                                    container: TaskContainer(id: "local", name: "Lokal", colorHex: nil), url: nil, version: "1",
                                    editableFields: []))
        local.tasks.append(makeTask("Heute fällig", source: .local, due: DueDate(year: 2026, month: 11, day: 18)))
        planStore.assign(id("Fahrrad"), to: today)
        planStore.assign(id("Wichtig"), to: today)
        let model = await model()
        let day = try #require(model.days.first)
        #expect(model.timelessTasks(for: day).map(\.title) == ["Wichtig", "Fahrrad"])  // due first, none last
        #expect(day.openToday.map(\.title) == ["Heute fällig"])
    }

    @Test func timelessTasks_otherDay_onlyAssigned() async throws {
        planStore.assign(id("Fahrrad"), to: PlanDay(year: 2026, month: 11, day: 19))
        let model = await model()
        model.anchor = PlanDay(year: 2026, month: 11, day: 19)
        await model.reload()
        #expect(model.timelessTasks(for: try #require(model.days.first)).map(\.title) == ["Fahrrad"])
    }

    private func placeholderPair() -> [CalendarEvent] {
        [CalendarEvent(id: "real", externalID: nil, calendarID: "uni", title: "Vorlesung", start: at(18, 10), end: at(18, 11),
                       isAllDay: false, url: nil, isBusy: true, version: "1"),
         CalendarEvent(id: "busy", externalID: nil, calendarID: "work", title: "Busy", start: at(18, 10), end: at(18, 11),
                       isAllDay: false, url: nil, isBusy: true, version: "1")]
    }

    @Test func mergingOff_alsoIgnoresPlaceholderDecisions() async throws {
        calendarStore.storedEvents = placeholderPair()
        let model = await model()
        await model.decideMerge(try #require(model.mergeSuggestions.first), merge: true, always: true)
        #expect(try #require(model.days.first).events.count == 1)
        settings.mergeDuplicateEvents = false
        await model.reload()
        #expect(try #require(model.days.first).events.count == 2)
        #expect(model.mergeSuggestions.isEmpty)
    }

    @Test func resetMergeDecisions_showsPlaceholdersAgain() async throws {
        calendarStore.storedEvents = placeholderPair()
        let model = await model()
        await model.decideMerge(try #require(model.mergeSuggestions.first), merge: true, always: true)
        await model.resetMergeDecisions()
        #expect(try #require(model.days.first).events.count == 2)
        #expect(model.mergeSuggestions.count == 1)
    }

    @Test func deadlineCalendarEvents_areNeverMerged() async throws {
        settings.deadlineCalendarIDs = ["uni"]
        calendarStore.storedEvents = ["kurs", "uni"].map { calendarID in
            CalendarEvent(id: "e-\(calendarID)", externalID: nil, calendarID: calendarID, title: "Seminar", start: at(18, 0),
                          end: at(19, 0), isAllDay: true, url: nil, isBusy: true, version: "1")
        }
        let model = await model()
        let day = try #require(model.days.first)
        #expect(model.allDayEvents(for: day).map(\.calendarID) == ["kurs"])
    }

    @Test func calendarDiagnostics_countReadShownHidden() async throws {
        calendarStore.calendars = [ListInfo(id: "uni", title: "Kurs", colorHex: nil, kind: .subscription),
                                   ListInfo(id: "work", title: "Arbeit", colorHex: nil, kind: .calDAV),
                                   ListInfo(id: "other", title: "Anderes", colorHex: nil, kind: .local)]
        settings.selectedCalendarIDs = ["uni", "work"]
        calendarStore.storedEvents = placeholderPair() + [
            CalendarEvent(id: "x", externalID: nil, calendarID: "other", title: "Sport", start: at(18, 15), end: at(18, 16),
                          isAllDay: false, url: nil, isBusy: true, version: "1")]
        let model = await model()
        await model.decideMerge(try #require(model.mergeSuggestions.first), merge: true, always: false)
        let rows = model.calendarDiagnostics()
        let uni = try #require(rows.first { $0.calendarID == "uni" })
        let work = try #require(rows.first { $0.calendarID == "work" })
        let other = try #require(rows.first { $0.calendarID == "other" })
        #expect(uni.isRead && uni.events == 1 && uni.shown == 1)
        #expect(work.isRead && work.events == 1 && work.shown == 0 && work.hiddenByPlaceholderDecision == 1)
        #expect(!other.isRead && other.events == 1 && other.shown == 0)
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
        await model.setRecurringEffort(60, task: TaskID(source: .reminders, rawValue: "k"), day: today, forAll: false)
        #expect(model.efforts.minutes(for: TaskID(source: .reminders, rawValue: "k"), on: today) == 60)
        #expect(model.efforts.minutes(for: TaskID(source: .reminders, rawValue: "k"), on: today.adding(days: 1, calendar: calendar)) == nil)
        await model.setRecurringEffort(120, task: TaskID(source: .reminders, rawValue: "k"), day: today, forAll: true)
        #expect(model.efforts.minutes(for: TaskID(source: .reminders, rawValue: "k"), on: today.adding(days: 1, calendar: calendar)) == 120)
    }

    @Test func plannedInfo_forEditor() async throws {
        let model = await model()
        let task = try #require(taskList.items.first { $0.title == "Fahrrad" })
        _ = try blocks.createBlock(for: task, start: at(19, 9), minutes: 30)
        let info = model.plannedInfo(for: task.id)
        #expect(info.day == PlanDay(year: 2026, month: 11, day: 19))
        #expect(info.blocks.count == 1)
    }

    // MARK: Deadline marks and preparation (plan deadline-marking, Tasks 5 and 10)

    private func timetableEvent(_ id: String, _ title: String, start: Date, minutes: Int = 120, calendarID: String = "timetable",
                                externalID: String? = nil, allDay: Bool = false, recurring: Bool = false) -> CalendarEvent {
        var event = CalendarEvent(id: id, externalID: externalID, calendarID: calendarID, title: title, start: start,
                                  end: allDay ? start.addingTimeInterval(86_400) : start.addingTimeInterval(TimeInterval(minutes * 60)),
                                  isAllDay: allDay, url: nil, isBusy: true, version: "1")
        event.isEditable = calendarID != "timetable"
        event.isRecurring = recurring
        return event
    }

    private func useTimetable() {
        calendarStore.calendars += [ListInfo(id: "timetable", title: "Stundenplan", colorHex: nil, kind: .subscription),
                                    ListInfo(id: "work", title: "Privat", colorHex: nil, kind: .calDAV)]
    }

    @Test func markedTimetableEventShowsInDaysAndUpcomingDeadlines() async throws {
        useTimetable()
        let exam = timetableEvent("exam", "Klausur Statistik", start: at(27, 10))
        calendarStore.storedEvents = [exam]
        let model = await model()
        #expect(model.upcomingDeadlines.isEmpty)
        await model.markDeadline(exam, series: false)
        let deadline = try #require(model.upcomingDeadlines.first)
        #expect(deadline.kind == .markedEvent)
        #expect(deadline.eventID == "exam")
        #expect(deadline.calendarID == "timetable")
        #expect(model.isDeadlineEvent(exam))
        model.anchor = PlanDay(year: 2026, month: 11, day: 27)
        await model.reload()
        #expect(try #require(model.days.first).deadlines.map(\.title) == ["Klausur Statistik"])
        #expect(model.deadlineEventIDs == ["exam"])
    }

    @Test func markedAllDayEventLeavesAllDayRow() async throws {
        useTimetable()
        let submission = timetableEvent("essay", "Abgabe Essay", start: at(18, 0), calendarID: "work", allDay: true)
        calendarStore.storedEvents = [submission]
        let model = await model()
        #expect(model.allDayEvents(for: try #require(model.days.first)).map(\.id) == ["essay"])
        await model.markDeadline(submission, series: false)
        let day = try #require(model.days.first)
        #expect(model.allDayEvents(for: day).isEmpty)
        #expect(day.deadlines.map(\.title) == ["Abgabe Essay"])
    }

    @Test func markedTimedEventStillCountsAsBusy() async throws {
        useTimetable()
        let exam = timetableEvent("exam", "Klausur", start: at(18, 10))
        calendarStore.storedEvents = [exam]
        let model = await model()
        await model.markDeadline(exam, series: false)
        let day = try #require(model.days.first)
        #expect(day.capacity.availableMinutes == 360)
        #expect(model.timeline(for: day).map(\.label) == ["Klausur", "Mittagspause"])
    }

    @Test func markOnReadOnlyCalendarWritesNothingToTheCalendar() async throws {
        useTimetable()
        let exam = timetableEvent("exam", "Klausur Statistik", start: at(27, 10))
        let lecture = timetableEvent("lecture|1", "Vorlesung", start: at(23, 8), recurring: true)
        calendarStore.storedEvents = [exam, lecture]
        let before = calendarStore.storedEvents
        let model = await model()
        await model.markDeadline(exam, series: false)
        let deadline = try #require(model.upcomingDeadlines.first)
        await model.linkPreparation(lecture, to: deadline, series: true)
        await model.unmarkDeadline(exam)
        #expect(calendarStore.storedEvents == before)
        #expect(model.lastError == nil)
    }

    @Test func movedMarkedEventIsFollowed() async throws {
        useTimetable()
        calendarStore.storedEvents = [timetableEvent("exam", "Klausur Statistik", start: at(27, 10), externalID: "ext-exam")]
        let model = await model()
        await model.markDeadline(calendarStore.storedEvents[0], series: false)
        calendarStore.storedEvents = [timetableEvent("exam-2", "Klausur Statistik", start: at(30, 10), externalID: "ext-exam")]
        await model.reload()
        #expect(model.upcomingDeadlines.map(\.eventID) == ["exam-2"])
        #expect(model.orphanedMarks.isEmpty)
    }

    @Test func deletedMarkedEventIsReportedNotDropped() async throws {
        useTimetable()
        let exam = timetableEvent("exam", "Klausur Statistik", start: at(27, 10))
        calendarStore.storedEvents = [exam]
        let model = await model()
        await model.markDeadline(exam, series: false)
        calendarStore.storedEvents = []
        await model.reload()
        #expect(model.orphanedMarks.map(\.title) == ["Klausur Statistik"])
        #expect(model.orphanedMarks.first?.candidate == nil)
        #expect(model.deadlineMarks.marks().count == 1)
        await model.removeOrphanedMark(try #require(model.orphanedMarks.first))
        #expect(model.deadlineMarks.marks().isEmpty)
        #expect(model.orphanedMarks.isEmpty)
    }

    @Test func retitledMarkedEventIsOfferedAsCandidate() async throws {
        useTimetable()
        let exam = timetableEvent("exam", "Klausur Statistik", start: at(27, 10))
        calendarStore.storedEvents = [exam]
        let model = await model()
        await model.markDeadline(exam, series: false)
        let moved = timetableEvent("exam-9", "Klausur Statistik", start: at(30, 10))
        calendarStore.storedEvents = [moved]
        await model.reload()
        let orphan = try #require(model.orphanedMarks.first)
        #expect(orphan.candidate == moved)
        #expect(model.upcomingDeadlines.isEmpty)
        await model.adoptCandidate(orphan)
        #expect(model.orphanedMarks.isEmpty)
        #expect(model.upcomingDeadlines.map(\.eventID) == ["exam-9"])
    }

    @Test func missingMarkCanBeReassignedToAnotherEvent() async throws {
        useTimetable()
        let exam = timetableEvent("exam", "Klausur Statistik", start: at(27, 10))
        calendarStore.storedEvents = [exam]
        let model = await model()
        await model.markDeadline(exam, series: false)
        let replacement = timetableEvent("retake", "Nachklausur", start: at(28, 9))
        let far = timetableEvent("far", "Seminar", start: at(30, 9, 0).addingTimeInterval(40 * 86_400))
        calendarStore.storedEvents = [replacement, far]
        await model.reload()
        let orphan = try #require(model.orphanedMarks.first)
        #expect(orphan.candidate == nil)
        #expect(model.reassignCandidates(for: orphan).map(\.id) == ["retake"])
        await model.reassignMark(orphan, to: replacement)
        #expect(model.orphanedMarks.isEmpty)
        #expect(model.upcomingDeadlines.map(\.eventID) == ["retake"])
    }

    @Test func withoutCalendarAccessMarksStayUntouched() async throws {
        useTimetable()
        let exam = timetableEvent("exam", "Klausur Statistik", start: at(27, 10))
        calendarStore.storedEvents = [exam]
        let model = await model()
        await model.markDeadline(exam, series: false)
        calendarStore.calendars = []
        calendarStore.storedEvents = []
        await model.reload()
        #expect(model.orphanedMarks.isEmpty)
        #expect(model.deadlineMarks.marks().map(\.eventKey) == ["exam"])
    }

    @Test func markingASeriesMarksEveryOccurrence() async throws {
        useTimetable()
        let first = timetableEvent("course|1", "Kolloquium", start: at(19, 14), calendarID: "work", recurring: true)
        let second = timetableEvent("course|2", "Kolloquium", start: at(26, 14), calendarID: "work", recurring: true)
        calendarStore.storedEvents = [first, second]
        let model = await model()
        await model.markDeadline(first, series: true)
        #expect(model.upcomingDeadlines.map(\.eventID) == ["course|1", "course|2"])
        await model.unmarkDeadline(second)
        #expect(model.upcomingDeadlines.isEmpty)
    }

    @Test func preparationSumsLinkedEventsBeforeDeadline() async throws {
        useTimetable()
        let exam = timetableEvent("exam", "Klausur Statistik", start: at(27, 10))
        let group = timetableEvent("group", "Lerngruppe Statistik", start: at(19, 16), calendarID: "work")
        let lecture1 = timetableEvent("lecture|1", "Vorlesung Statistik", start: at(23, 8, 15), minutes: 90, recurring: true)
        let lecture2 = timetableEvent("lecture|2", "Vorlesung Statistik", start: at(30, 8, 15), minutes: 90, recurring: true)
        let past = timetableEvent("past", "Lernblock", start: at(17, 14), calendarID: "work")
        calendarStore.storedEvents = [exam, group, lecture1, lecture2, past]
        let model = await model()
        await model.markDeadline(exam, series: false)
        let deadline = try #require(model.upcomingDeadlines.first)
        #expect(model.preparationCandidates(for: deadline).map(\.id) == ["group", "lecture|1"])
        await model.linkPreparation(group, to: deadline, series: false)
        await model.linkPreparation(lecture1, to: deadline, series: true)
        await model.linkPreparation(past, to: deadline, series: false)
        #expect(model.preparation[deadline.preparationKey] == PreparationSummary(minutes: 210, count: 2))
        #expect(model.preparationEvents(for: deadline).map(\.id) == ["past", "group", "lecture|1"])
        // Preparation has no effect on capacity: the group still counts as busy on its day.
        model.anchor = PlanDay(year: 2026, month: 11, day: 19)
        await model.reload()
        #expect(try #require(model.days.first).capacity.availableMinutes == 360)
        #expect(model.preparationTarget(forEventID: "group")?.deadlineKey == "event:exam")
        #expect(model.preparationTarget(forEventID: "group")?.title == "Klausur Statistik")
    }

    @Test func preparationCanBelongToPriorityOneTasks() async throws {
        useTimetable()
        local.tasks.append(TaskItem(id: id("Angebot"), title: "Angebot", notes: nil, due: DueDate(year: 2026, month: 11, day: 20),
                                    priority: .p1, estimateMinutes: nil, isCompleted: false,
                                    container: TaskContainer(id: "local", name: "Lokal", colorHex: nil), url: nil, version: "1",
                                    editableFields: []))
        let block = timetableEvent("focus", "Fokuszeit", start: at(19, 9), calendarID: "work")
        calendarStore.storedEvents = [block]
        let model = await model()
        let deadline = try #require(model.upcomingDeadlines.first)
        #expect(model.linkableDeadlines(for: block).map(\.title) == ["Angebot"])
        await model.linkPreparation(block, to: deadline, series: false)
        #expect(model.preparation["task:local:Angebot"] == PreparationSummary(minutes: 120, count: 1))
    }

    @Test func unmarkingWithLinksReportsTheirCount() async throws {
        useTimetable()
        let exam = timetableEvent("exam", "Klausur Statistik", start: at(27, 10))
        let group = timetableEvent("group", "Lerngruppe", start: at(19, 16), calendarID: "work")
        calendarStore.storedEvents = [exam, group]
        let model = await model()
        await model.markDeadline(exam, series: false)
        await model.linkPreparation(group, to: try #require(model.upcomingDeadlines.first), series: false)
        #expect(model.preparationLinkCount(forDeadlineEvent: exam) == 1)
        await model.unmarkDeadline(exam)
        #expect(model.deadlineMarks.allLinks().isEmpty)
    }

    @Test func markedEventIsNeverHiddenByMerge() async throws {
        useTimetable()
        let real = timetableEvent("real", "Klausur", start: at(18, 10), calendarID: "work")
        let placeholder = timetableEvent("busy", "Busy", start: at(18, 10))
        calendarStore.storedEvents = [real, placeholder]
        let model = await model()
        #expect(model.mergeSuggestions.count == 1)
        await model.markDeadline(placeholder, series: false)
        #expect(model.mergeSuggestions.isEmpty)
    }

    @Test func deadlineEventLinkedToTaskIsNotABlock() async throws {
        settings.deadlineCalendarIDs = ["uni"]
        calendarStore.storedEvents = [CalendarEvent(id: "klausur", externalID: nil, calendarID: "uni", title: "Klausur",
                                                    start: at(18, 10), end: at(18, 12), isAllDay: false, url: nil,
                                                    isBusy: true, version: "1")]
        blocks.links.link(eventID: "klausur", to: id("Fahrrad"))
        let model = await model()
        let day = try #require(model.days.first)
        #expect(day.blocks.isEmpty)
        #expect(day.events.map(\.id) == ["klausur"])
        #expect(day.capacity.availableMinutes == 360)
        #expect(day.capacity.plannedMinutes == 0)
        #expect(model.linkedTask(eventID: "klausur")?.title == "Fahrrad")
    }

    @Test func keywordSuggestionOffersExamsUntilAnsweredOrMarked() async throws {
        useTimetable()
        let exam = timetableEvent("exam", "Klausur Statistik", start: at(27, 10))
        let essay = timetableEvent("essay", "Abgabe Essay", start: at(24, 12), calendarID: "work")
        calendarStore.storedEvents = [exam, essay, timetableEvent("lecture", "Vorlesung", start: at(19, 8))]
        let model = await model()
        #expect(model.deadlineSuggestions.map(\.id) == ["essay", "exam"])
        await model.dismissDeadlineSuggestion(essay)
        #expect(model.deadlineSuggestions.map(\.id) == ["exam"])
        await model.markDeadline(exam, series: false)
        #expect(model.deadlineSuggestions.isEmpty)
    }

    #if DEBUG
    @Test func identifierSamplesListUpToFiveEventsPerCalendar() async throws {
        useTimetable()
        calendarStore.storedEvents = (0..<7).map { index in
            timetableEvent("t\(index)", "Vorlesung", start: at(19, 8 + index), minutes: 30, externalID: "ext-\(index)")
        }
        let model = await model()
        let sample = try #require(model.eventIdentifierSamples().first { $0.calendarID == "timetable" })
        #expect(sample.calendarTitle == "Stundenplan")
        #expect(sample.events.map(\.id) == ["t0", "t1", "t2", "t3", "t4"])
        #expect(sample.events.first?.externalID == "ext-0")
    }
    #endif

    @Test func keywordSuggestionSkipsTimeBlocksAndLinkedEvents() async throws {
        useTimetable()
        _ = try blocks.createBlock(for: makeTask("Abgabe Hausarbeit", source: .local), start: at(19, 9), minutes: 60)
        let linked = timetableEvent("linked", "Abgabe Bericht", start: at(20, 9), calendarID: "work")
        let prep = timetableEvent("prep", "Abgabe vorbereiten", start: at(21, 9), calendarID: "work")
        calendarStore.storedEvents += [linked, prep]
        blocks.links.link(eventID: "linked", to: id("Fahrrad"))
        let model = await model()
        #expect(model.deadlineSuggestions.isEmpty)
    }

    @Test func removingASeriesMarkAlwaysAsks() async throws {
        useTimetable()
        let first = timetableEvent("course|1", "Kolloquium", start: at(19, 14), calendarID: "work", recurring: true)
        let single = timetableEvent("exam", "Klausur", start: at(27, 10))
        calendarStore.storedEvents = [first, single]
        let model = await model()
        await model.markDeadline(first, series: true)
        await model.markDeadline(single, series: false)
        #expect(model.needsUnmarkConfirmation(first))
        #expect(model.isSeriesMark(first))
        #expect(!model.needsUnmarkConfirmation(single))
    }

    @Test func markingAndUnmarkingReportsAChange() async throws {
        useTimetable()
        let exam = timetableEvent("exam", "Klausur", start: at(27, 10))
        calendarStore.storedEvents = [exam]
        let model = await model()
        var changes = 0
        model.onDeadlinesChanged = { changes += 1 }
        await model.markDeadline(exam, series: false)
        await model.unmarkDeadline(exam)
        #expect(changes == 2)
    }

    // MARK: Neighbour pages

    @Test func neighbourPlans_dayScope_holdsPreviousAndNextDay() async {
        let model = await model()
        await model.loadNeighbours()
        #expect(Set(model.neighbourPlans.keys) == [today.adding(days: -1, calendar: calendar), today.adding(days: 1, calendar: calendar)])
        #expect(model.days.map(\.day) == [today])
    }

    @Test func neighbourPlans_weekScope_holdsSevenDaysEach() async {
        let model = await model()
        model.scope = .week
        await model.reload()
        await model.loadNeighbours()
        let thisMonday = PlanDay(year: 2026, month: 11, day: 16)
        let expected = (-7...(-1)).map { thisMonday.adding(days: $0, calendar: calendar) }
            + (7...13).map { thisMonday.adding(days: $0, calendar: calendar) }
        #expect(Set(model.neighbourPlans.keys) == Set(expected))
        #expect(model.neighbourPlans.count == 14)
    }

    @Test func neighbourPlans_monthScope_isEmpty() async {
        let model = await model()
        model.scope = .month
        await model.reload()
        await model.loadNeighbours()
        #expect(model.neighbourPlans.isEmpty)
    }

    @Test func neighbourPlans_dayScope_carryTheStoredSuggestionsOfTheirDay() async {
        let store = SuggestionStore(context: container.mainContext)
        let tomorrow = today.adding(days: 1, calendar: calendar)
        let block = PlanSuggestion(id: UUID(), kind: .block, taskKey: "local:Fahrrad", title: "Fahrrad", day: tomorrow,
                                   startMinutes: 14 * 60, minutes: 60, reason: "r")
        store.replace(with: SuggestionBatch(id: UUID(), scope: .day, days: [tomorrow], createdAt: testNow(), suggestions: [block],
                                            unscheduled: [], risks: [], estimates: [:]))
        await taskList.reload()
        let model = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: accessStore,
                                  planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                  blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                  suggestions: store, now: testNow, calendar: calendar)
        model.anchor = tomorrow
        await model.reload()
        #expect(model.days.first?.suggestions.count == 1)
        // From today, tomorrow is the next page: its plan and its batches show the stored suggestion, like the page will.
        model.anchor = today
        await model.reload()
        await model.loadNeighbours()
        #expect(model.neighbourPlans[tomorrow]?.suggestions.count == 1)
        #expect(model.neighbourExtras[tomorrow]?.suggestionBatches.count == 1)
        #expect(model.neighbourPlans[today.adding(days: -1, calendar: calendar)]?.suggestions.isEmpty == true)
    }

    @Test func neighbourExtras_dayScope_holdTheDeadlinesFromThatDayOn() async {
        settings.deadlineCalendarIDs = ["uni"]
        // 14 days after today: inside the 14-day deadline window of tomorrow, outside the one of today.
        let start = today.adding(days: 14, calendar: calendar).startDate(in: calendar).addingTimeInterval(10 * 3600)
        calendarStore.storedEvents = [timetableEvent("exam", "Klausur", start: start, calendarID: "uni")]
        let model = await model()
        await model.loadNeighbours()
        let tomorrow = today.adding(days: 1, calendar: calendar)
        #expect(model.upcomingDeadlines.isEmpty)
        #expect(model.neighbourExtras[tomorrow]?.upcomingDeadlines.map(\.title) == ["Klausur"])
        #expect(model.neighbourExtras[today.adding(days: -1, calendar: calendar)]?.upcomingDeadlines.isEmpty == true)
    }

    @Test func neighbourExtras_dayScope_markTheDeadlineEventsOfThatDay() async {
        settings.deadlineCalendarIDs = ["uni"]
        let tomorrow = today.adding(days: 1, calendar: calendar)
        let start = tomorrow.startDate(in: calendar).addingTimeInterval(9 * 3600)
        calendarStore.storedEvents = [timetableEvent("exam", "Klausur", start: start, calendarID: "uni")]
        let model = await model()
        await model.loadNeighbours()
        // The shown day has no such event; the page of tomorrow knows it before it is shown.
        #expect(model.deadlineEventIDs.isEmpty)
        #expect(model.neighbourExtras[tomorrow]?.deadlineEventIDs == ["exam"])
        model.step(1)
        #expect(model.deadlineEventIDs == ["exam"])
    }

    @Test func step_withLoadedNeighbour_showsTheNewDayBeforeAnyReload() async {
        settings.deadlineCalendarIDs = ["uni"]
        let start = today.adding(days: 14, calendar: calendar).startDate(in: calendar).addingTimeInterval(10 * 3600)
        calendarStore.storedEvents = [timetableEvent("exam", "Klausur", start: start, calendarID: "uni")]
        let model = await model()
        await model.loadNeighbours()
        let tomorrow = today.adding(days: 1, calendar: calendar)
        // No await: the page change itself carries the plan and the deadline card of the new day.
        model.step(1)
        #expect(model.anchor == tomorrow)
        #expect(model.days.map(\.day) == [tomorrow])
        #expect(model.upcomingDeadlines.map(\.title) == ["Klausur"])
        // The reload that follows shows the same.
        await model.reload()
        #expect(model.days.map(\.day) == [tomorrow])
        #expect(model.upcomingDeadlines.map(\.title) == ["Klausur"])
    }

    @Test func step_keepsTheLeftDayAsNeighbourOfTheNewOne() async {
        let model = await model()
        await model.loadNeighbours()
        model.step(1)
        #expect(model.neighbourPlans[today] != nil)
        #expect(model.neighbourExtras[today] != nil)
        model.step(-1)
        #expect(model.days.map(\.day) == [today])
    }

    @Test func step_withoutLoadedNeighbour_keepsTheShownDayUntilReload() async {
        let model = await model()
        model.step(1)
        #expect(!model.adoptCachedPage())
        #expect(model.days.map(\.day) == [today])
        await model.reload()
        #expect(model.days.map(\.day) == [today.adding(days: 1, calendar: calendar)])
    }

    @Test func neighbourPlans_followTheShownDayAfterReload() async {
        let model = await model()
        model.anchor = today.adding(days: 3, calendar: calendar)
        await model.reload()
        await model.loadNeighbours()
        #expect(model.neighbourPlans[today.adding(days: 2, calendar: calendar)] != nil)
        #expect(model.neighbourPlans[today.adding(days: 4, calendar: calendar)] != nil)
        #expect(model.neighbourPlans[today.adding(days: -1, calendar: calendar)] == nil)
    }

    // MARK: Travel time (#168)

    private func travelModel(_ estimator: FakeTravelEstimator = FakeTravelEstimator(), home: String? = "Musterstraße 1, Berlin",
                             enabled: Bool = true, serviceClock: (() -> Date)? = nil) async -> (PlanningModel, FakeTravelEstimator) {
        settings.homeAddress = home
        // As after the settings check: a home address that Apple Maps found carries its coordinates (Berlin).
        settings.homeLatitude = home == nil ? nil : 52.52
        settings.homeLongitude = home == nil ? nil : 13.405
        settings.travelTimeEnabled = enabled
        await taskList.reload()
        let service = TravelTimeService(estimator: estimator, cacheURL: nil, now: serviceClock ?? testNow)
        let model = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: accessStore,
                                  planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                  blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                  now: testNow, calendar: calendar, travelTimes: service)
        await model.reload()
        return (model, estimator)
    }

    /// A meeting today from `start` for one hour; testNow is 10:00.
    private func meeting(_ id: String = "m1", hour: Int = 14, minute: Int = 0, location: String? = "Büro, Berlin") -> CalendarEvent {
        var event = CalendarEvent(id: id, externalID: nil, calendarID: "work", title: id, start: at(18, hour, minute),
                                  end: at(18, hour + 1, minute), isAllDay: false, url: nil, isBusy: true, version: "1")
        event.location = location
        return event
    }

    @Test func travel_addsSegmentBeforeEventWithLocation() async throws {
        calendarStore.storedEvents = [meeting()]
        let (model, estimator) = await travelModel()
        #expect(model.days.first?.travel.isEmpty == true)
        #expect(await model.refreshTravelTimes())
        let segment = try #require(model.days.first?.travel.first)
        #expect(segment.eventID == "m1")
        #expect(segment.range == 815..<840)
        #expect(segment.origin == .home)
        #expect(estimator.tripCalls == ["Musterstraße 1, Berlin>Büro, Berlin>automobile"])
    }

    @Test func travel_reducesCapacity() async throws {
        calendarStore.storedEvents = [meeting()]
        let (model, _) = await travelModel()
        let before = try #require(model.days.first?.capacity)
        await model.refreshTravelTimes()
        let after = try #require(model.days.first?.capacity)
        #expect(before.availableMinutes - after.availableMinutes == 25)
        #expect((before.remainingMinutes ?? 0) - (after.remainingMinutes ?? 0) == 25)
    }

    @Test func freedMinutes_includesTheTripOfTheFreedEvent() async throws {
        calendarStore.storedEvents = [meeting()]
        let (model, _) = await travelModel()
        await model.refreshTravelTimes()
        let day = try #require(model.days.first)
        #expect(day.travel.count == 1)
        // The meeting 14:00–15:00 and its trip of 25 minutes.
        let freed = model.freedMinutes(of: day.events, in: day)
        #expect(freed == 85)
        await model.setFree(day.events, free: true, series: false)
        await model.refreshTravelTimes()
        let after = try #require(model.days.first)
        #expect(after.travel.isEmpty)
        #expect(after.capacity.freeMinutes - day.capacity.freeMinutes == freed)
    }

    @Test func travel_disabledSetting_addsNothing() async {
        calendarStore.storedEvents = [meeting()]
        let (model, estimator) = await travelModel(enabled: false)
        #expect(await model.refreshTravelTimes() == false)
        #expect(model.days.first?.travel.isEmpty == true)
        #expect(estimator.tripCalls.isEmpty)
        #expect(estimator.geocodeCalls.isEmpty)
    }

    @Test func travel_monthScope_doesNotFetch() async {
        calendarStore.storedEvents = [meeting()]
        let (model, estimator) = await travelModel()
        model.scope = .month
        await model.reload()
        #expect(await model.refreshTravelTimes() == false)
        #expect(estimator.tripCalls.isEmpty)
    }

    @Test func travel_withoutHome_firstEventHasNoSegment() async {
        calendarStore.storedEvents = [meeting()]
        let (model, estimator) = await travelModel(home: nil)
        #expect(await model.refreshTravelTimes() == false)
        #expect(model.days.first?.travel.isEmpty == true)
        #expect(estimator.tripCalls.isEmpty)
    }

    @Test func travel_locationFarFromHome_hasNoSegment() async {
        // "Bibliothek" resolves to Munich while home is in Berlin: no absurd trip, no blocked capacity.
        calendarStore.storedEvents = [meeting(location: "Bibliothek")]
        let estimator = FakeTravelEstimator()
        estimator.locations = ["Bibliothek": TravelCoordinate(latitude: 48.137, longitude: 11.575)]
        let (model, _) = await travelModel(estimator)
        let before = model.days.first?.capacity
        #expect(await model.refreshTravelTimes() == false)
        #expect(model.days.first?.travel.isEmpty == true)
        #expect(model.days.first?.capacity == before)
        #expect(estimator.tripCalls.isEmpty)
    }

    @Test func travel_onlineLocation_hasNoSegment() async {
        calendarStore.storedEvents = [meeting(location: "Zoom")]
        let (model, estimator) = await travelModel()
        #expect(await model.refreshTravelTimes() == false)
        #expect(model.days.first?.travel.isEmpty == true)
        #expect(estimator.tripCalls.isEmpty)
    }

    @Test func travel_placeNotFound_keepsCapacityLikeWithoutTravel() async throws {
        calendarStore.storedEvents = [meeting()]
        let estimator = FakeTravelEstimator()
        estimator.failingTexts = ["Büro, Berlin"]
        let (model, _) = await travelModel(estimator)
        let before = try #require(model.days.first?.capacity)
        #expect(await model.refreshTravelTimes() == false)
        #expect(model.days.first?.capacity == before)
        #expect(model.days.first?.travel.isEmpty == true)
    }

    // MARK: Travel time without network (F2)

    @Test func travel_withoutNetwork_showsAProvisionalBlockThatCounts() async throws {
        calendarStore.storedEvents = [meeting()]
        let estimator = FakeTravelEstimator()
        estimator.isOffline = true
        let (model, _) = await travelModel(estimator)
        let before = try #require(model.days.first?.capacity)
        #expect(await model.refreshTravelTimes())
        let segment = try #require(model.days.first?.travel.first)
        #expect(segment.source == .provisional)
        #expect(segment.minutes == 30)
        #expect(segment.range == 810..<840)
        let after = try #require(model.days.first?.capacity)
        #expect(before.availableMinutes - after.availableMinutes == 30)
        let input = try #require(model.days.first?.planInput)
        #expect(input.busy.contains(810..<840))
        #expect(input.events.contains { $0.travel && $0.title == "Fahrzeit" })
        // The same failure again neither reloads nor asks again right away.
        let calls = estimator.tripCalls.count + estimator.geocodeCalls.count
        #expect(await model.refreshTravelTimes() == false)
        #expect(estimator.tripCalls.count + estimator.geocodeCalls.count == calls)
        #expect(model.days.first?.travel.count == 1)
    }

    @Test func travel_estimateIsReplacedWhenTheNetworkIsBack() async throws {
        calendarStore.storedEvents = [meeting()]
        final class Clock: @unchecked Sendable { var now = testNow() }
        let clock = Clock()
        let estimator = FakeTravelEstimator()
        estimator.isOffline = true
        let (model, _) = await travelModel(estimator, serviceClock: { clock.now })
        #expect(await model.refreshTravelTimes())
        #expect(model.days.first?.travel.first?.source == .provisional)
        estimator.isOffline = false
        clock.now = clock.now.addingTimeInterval(TravelTimeService.transientRetryInterval + 1)
        #expect(await model.refreshTravelTimes())
        let segment = try #require(model.days.first?.travel.first)
        #expect(segment.source == .automatic)
        #expect(segment.minutes == 25)
    }

    // MARK: Manual travel time (F2)

    @Test func manualTravelTime_none_removesTheBlockAndIsNotAsked() async throws {
        calendarStore.storedEvents = [meeting()]
        let (model, estimator) = await travelModel()
        let event = try #require(model.days.first?.events.first)
        await model.setTravelOverride(.none, for: event, series: false)
        #expect(await model.refreshTravelTimes() == false)
        #expect(model.days.first?.travel.isEmpty == true)
        #expect(estimator.tripCalls.isEmpty)
        #expect(estimator.geocodeCalls.isEmpty)
    }

    @Test func manualTravelTime_fixed_winsOverTheAutomaticValueAndCounts() async throws {
        calendarStore.storedEvents = [meeting()]
        let (model, _) = await travelModel()
        await model.refreshTravelTimes()
        let before = try #require(model.days.first?.capacity)
        let event = try #require(model.days.first?.events.first)
        await model.setTravelOverride(.fixed(minutes: 45), for: event, series: false)
        let segment = try #require(model.days.first?.travel.first)
        #expect(segment.source == .manual)
        #expect(segment.minutes == 45)
        #expect(segment.range == 795..<840)
        let after = try #require(model.days.first?.capacity)
        #expect(before.availableMinutes - after.availableMinutes == 20)
        #expect(model.days.first?.planInput?.busy.contains(795..<840) == true)
        // Back to automatic: the Apple Maps value is there again.
        await model.setTravelOverride(.automatic, for: event, series: false)
        #expect(model.days.first?.travel.first?.minutes == 25)
        #expect(model.travelOverrideMode(for: event) == .automatic)
    }

    @Test func setTravelChoice_reloadsAndChangesTheSegment() async throws {
        calendarStore.storedEvents = [meeting()]
        let (model, estimator) = await travelModel()
        await model.refreshTravelTimes()
        let event = try #require(model.days.first?.events.first)
        #expect(model.days.first?.travel.first?.transport == nil)
        await model.setTravelChoice(TravelChoice(transport: .transit), for: event, series: false)
        #expect(model.travelChoice(for: event) == TravelChoice(transport: .transit))
        // The trip with the other transport is asked for once, then the block carries it.
        await model.refreshTravelTimes()
        #expect(estimator.tripCalls.last?.hasSuffix(">transit") == true)
        #expect(model.days.first?.travel.first?.transport == .transit)
        // A fixed time keeps the transport that was chosen before.
        await model.setTravelOverride(.fixed(minutes: 40), for: event, series: false)
        #expect(model.travelChoice(for: event) == TravelChoice(mode: .fixed(minutes: 40), transport: .transit))
    }

    @Test func setTravelChoice_default_removesTheEntry() async throws {
        calendarStore.storedEvents = [meeting()]
        let (model, _) = await travelModel()
        let event = try #require(model.days.first?.events.first)
        await model.setTravelChoice(TravelChoice(start: .home), for: event, series: false)
        #expect(TravelOverrideStore(context: container.mainContext).all().count == 1)
        await model.setTravelChoice(TravelChoice(), for: event, series: false)
        #expect(TravelOverrideStore(context: container.mainContext).all().isEmpty)
    }

    @Test func returnTrip_showsOnlyWithTheSwitch() async throws {
        calendarStore.storedEvents = [meeting()]
        let (model, _) = await travelModel()
        await model.refreshTravelTimes()
        #expect(model.days.first?.travel.contains { $0.direction == .returnHome } == false)
        settings.travelShowsReturn = true
        await model.reload()
        await model.refreshTravelTimes()
        let back = try #require(model.days.first?.travel.first { $0.direction == .returnHome })
        #expect(back.range.lowerBound == 900)
        // The way home counts as busy time like the way there (the part inside the buffer after the event counts once).
        let withReturn = try #require(model.days.first?.capacity)
        settings.travelShowsReturn = false
        await model.reload()
        let without = try #require(model.days.first?.capacity)
        #expect(without.availableMinutes - withReturn.availableMinutes == back.range.upperBound - (900 + settings.bufferMinutes))
    }

    @Test func previousPlace_isKnownOnlyAfterAnEventWithAPlace() async throws {
        calendarStore.storedEvents = [meeting("early", hour: 9), meeting("late", hour: 14), meeting("online", hour: 11, location: "Zoom")]
        let (model, _) = await travelModel()
        let early = try #require(model.days.first?.events.first { $0.id == "early" })
        let late = try #require(model.days.first?.events.first { $0.id == "late" })
        #expect(!model.hasPreviousPlace(before: early))
        #expect(model.hasPreviousPlace(before: late))
    }

    @Test func manualTravelTime_worksOfflineAndWithoutHomeAddress() async throws {
        calendarStore.storedEvents = [meeting()]
        let estimator = FakeTravelEstimator()
        estimator.isOffline = true
        let (model, _) = await travelModel(estimator, home: nil)
        #expect(model.days.first?.travel.isEmpty == true)
        let event = try #require(model.days.first?.events.first)
        await model.setTravelOverride(.fixed(minutes: 20), for: event, series: false)
        let segment = try #require(model.days.first?.travel.first)
        #expect(segment.minutes == 20)
        #expect(segment.source == .manual)
        #expect(estimator.tripCalls.isEmpty)
    }

    @Test func manualTravelTime_forAnEventWithoutPlace_isHonoured() async throws {
        calendarStore.storedEvents = [meeting(location: nil)]
        let (model, _) = await travelModel()
        let event = try #require(model.days.first?.events.first)
        await model.setTravelOverride(.fixed(minutes: 10), for: event, series: false)
        #expect(model.days.first?.travel.first?.minutes == 10)
    }

    @Test func manualTravelTime_isIgnoredWhileTravelIsOff() async throws {
        calendarStore.storedEvents = [meeting()]
        let (model, _) = await travelModel(enabled: false)
        let event = try #require(model.days.first?.events.first)
        await model.setTravelOverride(.fixed(minutes: 20), for: event, series: false)
        #expect(model.days.first?.travel.isEmpty == true)
        // The decision is kept for when the setting is switched on again.
        #expect(model.travelOverrideMode(for: event) == .fixed(minutes: 20))
    }

    @Test func manualTravelTime_ofARepeatingEvent_appliesToOneOrAllFollowing() async throws {
        var first = meeting("series|1800000000")
        first.isRecurring = true
        var second = meeting("series|1800604800")
        second.isRecurring = true
        second.start = first.start.addingTimeInterval(7 * 86_400)
        second.end = first.end.addingTimeInterval(7 * 86_400)
        var third = meeting("series|1801209600")
        third.isRecurring = true
        third.start = first.start.addingTimeInterval(14 * 86_400)
        third.end = first.end.addingTimeInterval(14 * 86_400)
        let (model, _) = await travelModel()
        let store = TravelOverrideStore(context: container.mainContext)

        store.set(.none, eventID: second.id, seriesID: "series", start: second.start, series: true)
        #expect(model.travelOverrideMode(for: first) == .automatic)
        #expect(model.travelOverrideMode(for: second) == .none)
        #expect(model.travelOverrideMode(for: third) == .none)
        // "Only this one" for the third occurrence beats the series.
        store.set(.fixed(minutes: 15), eventID: third.id, seriesID: "series", start: third.start, series: false)
        #expect(model.travelOverrideMode(for: third) == .fixed(minutes: 15))
        #expect(model.travelOverrideMode(for: second) == .none)
        // "Only this one: automatic" beats the series "none".
        store.set(.automatic, eventID: third.id, seriesID: "series", start: third.start, series: false)
        #expect(model.travelOverrideMode(for: third) == .automatic)
    }

    @Test func travel_lateValue_reloadsOnce() async {
        calendarStore.storedEvents = [meeting()]
        let (model, estimator) = await travelModel()
        #expect(await model.refreshTravelTimes())
        // Everything is cached now: the next call neither asks nor reloads.
        #expect(await model.refreshTravelTimes() == false)
        #expect(estimator.tripCalls.count == 1)
        #expect(model.days.first?.travel.count == 1)
    }

    @Test func travel_rowPrecedesEventInTimeline() async throws {
        calendarStore.storedEvents = [meeting()]
        let (model, _) = await travelModel()
        await model.refreshTravelTimes()
        let plan = try #require(model.days.first)
        let rows = model.timelineWithGaps(for: plan)
        let travelIndex = try #require(rows.firstIndex { if case .travel = $0 { true } else { false } })
        let eventIndex = try #require(rows.firstIndex { if case .event = $0 { true } else { false } })
        #expect(travelIndex < eventIndex)
        #expect(rows[travelIndex].id == "travel-m1")
        // The free stretches leave the trip out.
        let gaps = model.gaps(for: plan)
        #expect(gaps.allSatisfy { !$0.overlaps(815..<840) })
    }

    @Test func travel_planInputMarksTravelBusy() async throws {
        calendarStore.storedEvents = [meeting()]
        let (model, _) = await travelModel()
        await model.refreshTravelTimes()
        let input = try #require(model.days.first?.planInput)
        #expect(input.busy.contains(815..<840))
        let travelEvent = try #require(input.events.first { $0.travel })
        #expect(travelEvent.title == "Fahrzeit")
        #expect(travelEvent.busy)
        // No place reaches the AI input.
        #expect(!input.events.contains { $0.title.contains("Büro") && $0.travel })
    }

    @Test func travel_followingEvent_startsAtPreviousPlace() async throws {
        calendarStore.storedEvents = [meeting("a", hour: 11, location: "Büro, Berlin"), meeting("b", hour: 13, minute: 30, location: "Kunde, Potsdam")]
        let (model, estimator) = await travelModel()
        await model.refreshTravelTimes()
        #expect(estimator.tripCalls.contains("Büro, Berlin>Kunde, Potsdam>automobile"))
        let second = try #require(model.days.first?.travel.first { $0.eventID == "b" })
        #expect(second.origin == .previousEvent(id: "a"))
    }

    // MARK: Running entry (PL2b)

    private func timedEvent(from start: Date, to end: Date) -> CalendarEvent {
        CalendarEvent(id: "run|1", externalID: nil, calendarID: "cal", title: "Lauf", start: start, end: end,
                      isAllDay: false, url: nil, isBusy: true, version: "1")
    }

    @Test func runningRemaining_eventAroundNow_countsTheMinutesLeft() async {
        let model = await model()   // now is 10:00
        #expect(model.runningRemaining(of: timedEvent(from: at(18, 9, 30), to: at(18, 10, 28)), on: today) == 28)
        // Starting now counts as running, ending now does not.
        #expect(model.runningRemaining(of: timedEvent(from: at(18, 10), to: at(18, 11)), on: today) == 60)
        #expect(model.runningRemaining(of: timedEvent(from: at(18, 9), to: at(18, 10)), on: today) == nil)
    }

    /// The running seminar of the demo data in the UI test mode (10:00–12:30, clock at 10:30), moved to the clock of this model (10:00):
    /// the time left and the texts the grid puts on the running entry. Replaces `NowMarkerUITests.testRunningEntryShowsTheTimeLeftAndTheNowCapsule`.
    @Test func runningRemaining_longEvent_saysHowMuchTimeIsLeftInBothTexts() async throws {
        let model = await model()   // now is 10:00
        let remaining = try #require(model.runningRemaining(of: timedEvent(from: at(18, 8), to: at(18, 12)), on: today))
        #expect(remaining == 120)
        #expect(NowText.runningAccessibility(remainingMinutes: remaining) == "läuft, noch 120 Minuten")
        #expect(NowText.runningDetail(remainingMinutes: remaining) == "läuft · noch 120 min")
    }

    @Test func runningRemaining_otherDay_isNil() async {
        let model = await model()
        let event = timedEvent(from: at(18, 9, 30), to: at(18, 10, 30))
        #expect(model.runningRemaining(of: event, on: today.adding(days: 1, calendar: calendar)) == nil)
    }

    @Test func runningRemaining_eventFromTheDayBefore_runsOnToday() async {
        let model = await model()
        // An overnight event is still running at 10:00 of the next day.
        let event = timedEvent(from: at(17, 22), to: at(18, 11))
        #expect(model.runningRemaining(of: event, on: today) == 60)
    }

    @Test func runningRemaining_range_followsTheSameRule() async {
        let model = await model()
        #expect(model.runningRemaining(range: 600..<630, on: today) == 30)
        #expect(model.runningRemaining(range: 660..<700, on: today) == nil)
    }

    // MARK: Aligning to now (PL4b)

    @Test func showToday_bumpsTheToken() async {
        let model = await model()
        model.anchor = today.adding(days: 3, calendar: calendar)
        let before = model.nowAlignmentToken
        model.showToday()
        #expect(model.anchor == today)
        #expect(model.nowAlignmentToken == before + 1)
        #expect(model.dayOpeningToken == 0)
    }

    @Test func jump_toAnotherDay_bumpsTheOpeningToken() async {
        let model = await model()
        let target = today.adding(days: 2, calendar: calendar)
        model.jump(to: target)
        #expect(model.anchor == target)
        #expect(model.dayOpeningToken == 1)
        #expect(model.nowAlignmentToken == 0)
    }

    @Test func jump_toToday_bumpsTheNowToken() async {
        let model = await model()
        model.jump(to: today)
        #expect(model.nowAlignmentToken == 1)
        #expect(model.dayOpeningToken == 0)
    }

    @Test func step_neverBumpsATokens() async {
        let model = await model()
        model.step(1)
        model.step(-1)
        model.step(-1)
        model.scope = .week
        model.step(1)
        #expect(model.nowAlignmentToken == 0)
        #expect(model.dayOpeningToken == 0)
    }

    @Test func planBecameVisible_after31Minutes_bumps() async {
        let model = await model()
        let hidden = testNow()
        model.planBecameHidden(at: hidden)
        model.planBecameVisible(at: hidden.addingTimeInterval(31 * 60))
        #expect(model.nowAlignmentToken == 1)
    }

    @Test func planBecameVisible_after10Minutes_doesNotBump() async {
        let model = await model()
        let hidden = testNow()
        model.planBecameHidden(at: hidden)
        model.planBecameVisible(at: hidden.addingTimeInterval(10 * 60))
        #expect(model.nowAlignmentToken == 0)
    }

    @Test func planBecameVisible_keepsTheFirstHideAndForgetsItAfterwards() async {
        let model = await model()
        let hidden = testNow()
        // Leaving the tab and then the app: the absence counts from the first one.
        model.planBecameHidden(at: hidden)
        model.planBecameHidden(at: hidden.addingTimeInterval(20 * 60))
        model.planBecameVisible(at: hidden.addingTimeInterval(35 * 60))
        #expect(model.nowAlignmentToken == 1)
        // A second return without a new absence changes nothing.
        model.planBecameVisible(at: hidden.addingTimeInterval(90 * 60))
        #expect(model.nowAlignmentToken == 1)
    }

    @Test func planBecameVisible_onAnotherDay_doesNotBump() async {
        let model = await model()
        model.anchor = today.adding(days: 1, calendar: calendar)
        let hidden = testNow()
        model.planBecameHidden(at: hidden)
        model.planBecameVisible(at: hidden.addingTimeInterval(60 * 60))
        #expect(model.nowAlignmentToken == 0)
    }

    // MARK: Title while dragging (PL6b)

    @Test func titleAnchor_followsThePreviewStep_inDayWeekAndMonth() async {
        let model = await model()
        // Without a preview the header shows the real period.
        #expect(model.titleAnchor == model.anchor)
        #expect(model.titleRange == model.range)

        model.titlePreviewStep = 1
        #expect(model.titleAnchor == today.adding(days: 1, calendar: calendar))
        #expect(model.titleRange == model.titleAnchor...model.titleAnchor)

        model.scope = .week
        #expect(model.titleAnchor == today.adding(days: 7, calendar: calendar))
        #expect(model.titleRange.lowerBound == PlanDay(year: 2026, month: 11, day: 23))   // the Monday of the next week
        #expect(model.titleRange.upperBound == PlanDay(year: 2026, month: 11, day: 29))

        model.scope = .month
        model.titlePreviewStep = -1
        #expect(model.titleAnchor == PlanDay(year: 2026, month: 10, day: 18))
        // The grid of October starts on Monday 28 Sep and ends on Sunday 1 Nov.
        #expect(model.titleRange == PlanDay(year: 2026, month: 9, day: 28)...PlanDay(year: 2026, month: 11, day: 1))

        model.titlePreviewStep = nil
        #expect(model.titleAnchor == model.anchor)
        // The preview is never stored: the real anchor did not move.
        #expect(model.anchor == today)
    }

    // MARK: Month page (PL7b)

    @Test func monthGridDays_coversWholeWeeks() {
        // November 2026: Sunday the 1st to Monday the 30th, so the grid runs Monday 26 Oct to Sunday 6 Dec.
        let days = PlanningModel.monthGridDays(anchor: PlanDay(year: 2026, month: 11, day: 18), calendar: calendar)
        #expect(days.first == PlanDay(year: 2026, month: 10, day: 26))
        #expect(days.last == PlanDay(year: 2026, month: 12, day: 6))
        #expect(days.count % 7 == 0)
        #expect(days.count == 42)
        // February 2027 has exactly four weeks (Monday 1 Feb to Sunday 28 Feb).
        let february = PlanningModel.monthGridDays(anchor: PlanDay(year: 2027, month: 2, day: 10), calendar: calendar)
        #expect(february.count == 28)
        #expect(february.first == PlanDay(year: 2027, month: 2, day: 1))
        // The days follow each other without a gap.
        #expect(zip(days, days.dropFirst()).allSatisfy { $1 == $0.adding(days: 1, calendar: calendar) })
    }

    @Test func monthGridDays_matchesTheLoadedRange() async {
        let model = await model()
        model.scope = .month
        await model.reload()
        #expect(model.days.map(\.day) == PlanningModel.monthGridDays(anchor: model.anchor, calendar: calendar))
        // The neighbouring month, as the preview of a drag draws it, is the grid the model loads after paging.
        let next = PlanHeaderText.shiftedAnchor(scope: .month, anchor: model.anchor, step: 1, calendar: calendar)
        model.step(1)
        await model.reload()
        #expect(model.anchor.month == next.month)
        #expect(model.days.map(\.day) == PlanningModel.monthGridDays(anchor: next, calendar: calendar))
    }

    // MARK: Week content (#259)

    private func weekModel() async -> PlanningModel {
        let model = await model()
        model.scope = .week
        await model.reload()
        return model
    }

    private func weekPlan(_ model: PlanningModel, day: Int) throws -> DayPlan {
        try #require(model.days.first { $0.day == PlanDay(year: 2026, month: 11, day: day) })
    }

    private func timedEvent(_ id: String, _ start: Date, _ end: Date, busy: Bool = true) -> CalendarEvent {
        CalendarEvent(id: id, externalID: nil, calendarID: "work", title: id, start: start, end: end, isAllDay: false, url: nil,
                      isBusy: busy, version: "1")
    }

    @Test func weekContent_allDayEventsComeFirstAndTimedEntriesFollowChronologically() async throws {
        calendarStore.storedEvents = [
            timedEvent("afternoon", at(18, 14), at(18, 15)),
            timedEvent("morning", at(18, 9), at(18, 10)),
            CalendarEvent(id: "trip", externalID: nil, calendarID: "work", title: "Dienstreise", start: at(18, 0), end: at(19, 0),
                          isAllDay: true, url: nil, isBusy: true, version: "1"),
        ]
        let model = await weekModel()
        let content = model.weekContent(for: try weekPlan(model, day: 18))
        #expect(content.allDay.map(\.title) == ["Dienstreise"])
        #expect(content.timed.map(\.event.title) == ["morning", "afternoon"])
        #expect(content.hasEntries)
    }

    @Test func weekContent_overlappingEventsStayAndAreOrderedByStart() async throws {
        calendarStore.storedEvents = [
            timedEvent("late", at(18, 10, 30), at(18, 12)),
            timedEvent("long", at(18, 10), at(18, 13)),
            timedEvent("short", at(18, 10), at(18, 10, 30)),
        ]
        let model = await weekModel()
        let content = model.weekContent(for: try weekPlan(model, day: 18))
        // All three stay; the two that start together keep the order of the day plan.
        #expect(content.timed.map(\.event.title) == ["long", "short", "late"])
    }

    @Test func weekContent_freeEventsAreListed() async throws {
        calendarStore.storedEvents = [timedEvent("Geburtstag", at(18, 9), at(18, 10), busy: false)]
        let model = await weekModel()
        let content = model.weekContent(for: try weekPlan(model, day: 18))
        #expect(content.timed.map(\.event.title) == ["Geburtstag"])
    }

    @Test func weekContent_eventCrossingMidnightAppearsOnBothDaysAndLeadsTheSecond() async throws {
        calendarStore.storedEvents = [
            timedEvent("Nachtschicht", at(17, 22), at(18, 2)),
            timedEvent("Frühstück", at(18, 7), at(18, 8)),
        ]
        let model = await weekModel()
        let before = model.weekContent(for: try weekPlan(model, day: 17))
        let after = model.weekContent(for: try weekPlan(model, day: 18))
        #expect(before.timed.map(\.event.title) == ["Nachtschicht"])
        #expect(after.timed.map(\.event.title) == ["Nachtschicht", "Frühstück"])
    }

    @Test func weekContent_taskWithBlockIsAnEntryWhileTaskWithoutBlockStaysPlannedWithoutTime() async throws {
        await taskList.reload()
        let withBlock = try #require(taskList.items.first { $0.title == "Fahrrad" })
        let without = try #require(taskList.items.first { $0.title == "Abgabe" })
        _ = try blocks.createBlock(for: withBlock, start: at(18, 11), minutes: 60)
        planStore.assign(without.id, to: today)
        let model = await weekModel()
        let plan = try weekPlan(model, day: 18)
        let content = model.weekContent(for: plan)
        let entry = try #require(content.timed.first)
        #expect(content.timed.count == 1)
        #expect(entry.taskID == withBlock.id)
        #expect(entry.isBlock)
        // The task without a block is not part of the entries; the week lists it as "planned without time".
        #expect(plan.assigned.map(\.title) == ["Abgabe"])
        #expect(plan.assigned.contains { $0.id == withBlock.id } == false)
    }

    @Test func weekContent_timedDeadlineEventIsOneEntryWithItsDeadlineAndNoSeparateLine() async throws {
        settings.deadlineCalendarIDs = ["uni"]
        calendarStore.storedEvents = [
            CalendarEvent(id: "klausur", externalID: nil, calendarID: "uni", title: "Klausur", start: at(18, 10), end: at(18, 12),
                          isAllDay: false, url: nil, isBusy: true, version: "1"),
            CalendarEvent(id: "anmeldung", externalID: nil, calendarID: "uni", title: "Anmeldung", start: at(18, 0), end: at(19, 0),
                          isAllDay: true, url: nil, isBusy: true, version: "1"),
        ]
        let model = await weekModel()
        let plan = try weekPlan(model, day: 18)
        #expect(plan.deadlines.map(\.title).sorted() == ["Anmeldung", "Klausur"])
        let content = model.weekContent(for: plan)
        #expect(content.timed.map(\.event.title) == ["Klausur"])
        #expect(content.timed.first?.deadline?.title == "Klausur")
        // The all-day deadline is no all-day entry; it stays a deadline line, the timed one does not repeat.
        #expect(content.allDay.isEmpty)
        #expect(content.deadlines.map(\.title) == ["Anmeldung"])
    }

    @Test func weekContent_emptyDayHasNoEntries() async throws {
        let model = await weekModel()
        let content = model.weekContent(for: try weekPlan(model, day: 20))
        #expect(content.hasEntries == false)
    }

    @Test func weekContent_tripsBelongToTheirEventAndKeepTheDayCapacity() async throws {
        calendarStore.storedEvents = [meeting("a", hour: 11, location: "Büro, Berlin"), meeting("b", hour: 13, minute: 30, location: "Kunde, Potsdam")]
        let (model, _) = await travelModel()
        model.scope = .week
        await model.reload()
        await model.refreshTravelTimes()
        let plan = try weekPlan(model, day: 18)
        let content = model.weekContent(for: plan)
        #expect(content.timed.map(\.event.id) == ["a", "b"])
        #expect(content.timed.allSatisfy { $0.trips.contains { $0.direction == .toEvent } })
        #expect(content.timed.flatMap(\.trips).allSatisfy { trip in content.timed.contains { $0.event.id == trip.eventID } })
        // The week shows the numbers of the day: both come from the same plan.
        model.scope = .day
        await model.reload()
        #expect(model.days.first?.capacity == plan.capacity)
    }
}
