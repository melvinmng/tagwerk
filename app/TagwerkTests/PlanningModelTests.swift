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
                                  blocks: blocks, settings: settings, now: testNow, calendar: calendar)
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

    @Test func leftovers_showPastOpenAssignments() async {
        planStore.assign(id("Fahrrad"), to: PlanDay(year: 2026, month: 11, day: 16))
        let model = await model()
        #expect(model.leftovers.map(\.title) == ["Fahrrad"])
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
}
