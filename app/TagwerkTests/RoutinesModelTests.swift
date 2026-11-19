import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct RoutinesModelTests {
    final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    let container: ModelContainer
    let settings: AppSettings
    let calendar = testCalendar()
    let calendarStore = FakeCalendarStore()
    let local: FakeTaskProvider
    let taskList: TaskListModel
    let planStore: PlanStore
    let planning: PlanningModel
    let habitStore: HabitStore
    let habits: HabitsModel
    let routineStore: RoutineStore
    let clock: Clock
    let completed = CompletedCounter()

    final class CompletedCounter { var count = 0 }

    var today: PlanDay { PlanDay(year: 2026, month: 11, day: 18) }
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    init() async throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.planCalendarID = "plan"
        let now = Clock(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 22))!)
        clock = now
        local = FakeTaskProvider(source: .local, tasks: [
            makeTask("Heute fällig", source: .local, due: DueDate(year: 2026, month: 11, day: 18)),
            makeTask("Geplant", source: .local),
            makeTask("Später", source: .local, due: DueDate(year: 2026, month: 11, day: 25)),
        ])
        taskList = TaskListModel(providers: [local], now: { now.now }, calendar: calendar)
        await taskList.reload()
        planStore = PlanStore(context: container.mainContext)
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                 planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                 blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                 now: { now.now }, calendar: calendar)
        await planning.reload()
        habitStore = HabitStore(context: container.mainContext, now: { now.now })
        habits = HabitsModel(store: habitStore, intake: IntakeStore(context: container.mainContext), health: FakeHealthStore(),
                             settings: settings, calendar: calendar, now: { now.now })
        routineStore = RoutineStore(context: container.mainContext, now: { now.now })
    }

    private func makeModel() -> RoutinesModel {
        let clock = self.clock, completed = self.completed
        return RoutinesModel(store: routineStore, planning: planning, taskList: taskList, habits: habits, settings: settings,
                             completedCount: { _ in completed.count }, calendar: calendar, now: { clock.now })
    }

    private func addChecklist() {
        for (index, offset) in [90, 60, 30].enumerated() {
            routineStore.saveItem(ChecklistItem(title: "Punkt \(index)", order: index, offsetMinutes: offset))
        }
    }

    @Test func openEvening_beforeFour_opensTheDayBefore() {
        let model = makeModel()
        clock.now = at(19, 2)
        model.openEvening()
        #expect(model.sheet == .evening(today))
        #expect(model.eveningDay == today)
    }

    @Test func openStart_opensToday() {
        let model = makeModel()
        model.openStart()
        #expect(model.sheet == .start(today))
    }

    @Test func finishEvening_afterMidnight_writesTheDayTheSheetWasOpenedFor() {
        let model = makeModel()
        model.openEvening()
        guard case .evening(let opened) = model.sheet else { Issue.record("no evening sheet"); return }
        clock.now = at(19, 0, 10)
        model.finishEvening(opened)
        #expect(model.value(today).closeCompletedAt != nil)
        #expect(model.value(today.adding(days: 1, calendar: calendar)) == .empty)
        #expect(model.sheet == nil)
    }

    @Test func toggleItem_twice_unchecks() {
        addChecklist()
        let model = makeModel()
        let id = model.checklist()[0].id
        model.toggleItem(id, on: today)
        #expect(model.value(today).checkedItemIDs == [id])
        model.toggleItem(id, on: today)
        #expect(model.value(today).checkedItemIDs.isEmpty)
    }

    @Test func eveningLine_hiddenBeforeTheEarliestAnchor_andWhenSwitchedOff() {
        addChecklist()
        let model = makeModel()
        clock.now = at(18, 21)
        #expect(model.eveningLine == nil)
        clock.now = at(18, 21, 30)
        #expect(model.eveningLine != nil)
        settings.showsRoutinesInPlan = false
        #expect(model.eveningLine == nil)
    }

    @Test func eveningLine_countsOnlyExistingItems() {
        addChecklist()
        let model = makeModel()
        let first = model.checklist()[0].id
        routineStore.update(today) { $0.checkedItemIDs = [first, UUID()] }
        #expect(model.eveningLine == RoutinesModel.EveningLine(bedtimeMinutes: 1380, checked: 1, total: 3, isDone: false))
    }

    @Test func dayReview_countsCompletionsPlusOpenTasksOfToday() async {
        planStore.assign(TaskID(source: .local, rawValue: "Geplant"), to: today)
        completed.count = 4
        let model = makeModel()
        let review = await model.dayReview(today)
        #expect(review.tasksDone == 4)
        #expect(review.tasksTotal == 6)
    }

    @Test func dayReview_withoutFocus_hasNoFocusLine() async {
        let model = makeModel()
        #expect(await model.dayReview(today).focus == nil)
    }

    @Test func dayReview_habitsCounterBelongsToTheDay() async {
        habitStore.save(Habit(name: "Lesen", symbol: "book", order: 0, start: today))
        habits.refreshLocal()
        let model = makeModel()
        #expect(await model.dayReview(today).habits == HabitCounter(done: 0, total: 1))
    }

    @Test func todayTasks_arePlannedDueOrBlocked() {
        planStore.assign(TaskID(source: .local, rawValue: "Geplant"), to: today)
        let model = makeModel()
        #expect(Set(model.todayTasks().map(\.title)) == ["Heute fällig", "Geplant"])
    }

    @Test func captureEveningDetail_openAndDone() {
        addChecklist()
        let model = makeModel()
        #expect(model.captureEveningDetail(today) == "Schlafzeit 23:00 · Checkliste 0 von 3")
        routineStore.update(today) { $0.closeCompletedAt = self.at(18, 22, 10) }
        #expect(model.captureEveningDetail(today) == "✓ 22:10")
    }

    @Test func captureEveningDetail_withoutChecklist_namesOnlyTheBedtime() {
        #expect(makeModel().captureEveningDetail(today) == "Schlafzeit 23:00")
    }

    // MARK: Morning start

    @Test func finishStart_withoutInput_marksTheDayCompleted() {
        let model = makeModel()
        model.openStart()
        model.finishStart(today)
        #expect(model.value(today).startCompletedAt == clock.now)
        #expect(model.value(today).gratitude.isEmpty)
        #expect(model.sheet == nil)
    }

    @Test func swipeDismiss_savesGratitudeButDoesNotComplete() {
        let model = makeModel()
        model.setGratitude(["Kaffee"], on: today)
        #expect(model.value(today).gratitude == ["Kaffee"])
        #expect(model.value(today).startCompletedAt == nil)
    }

    @Test func gratitude_keepsAtMostThree() {
        let model = makeModel()
        model.setGratitude(["A", "B", "C", "D"], on: today)
        #expect(model.value(today).gratitude == ["A", "B", "C"])
    }

    @Test func overviewText_format() {
        #expect(RoutinesModel.overviewText(.init(events: 3, tasks: 5, freeMinutes: 210)) == "3 Termine · 5 Aufgaben · 3 h 30 frei")
        #expect(RoutinesModel.overviewText(.init(events: 1, tasks: 1, freeMinutes: 45)) == "1 Termin · 1 Aufgabe · 45 min frei")
    }

    @Test func overview_countsTasksOfTodayAndIsTodayOnly() async {
        planStore.assign(TaskID(source: .local, rawValue: "Geplant"), to: today)
        let model = makeModel()
        let overview = await model.overview(for: today)
        #expect(overview?.tasks == 2 && overview?.events == 0)
        #expect(await model.overview(for: today.adding(days: -1, calendar: calendar)) == nil)
    }

    @Test func captureStartDetail_openAndDone() {
        let model = makeModel()
        #expect(model.captureStartDetail(today) == "Fokus wählen")
        routineStore.update(today) { $0.startCompletedAt = self.at(18, 7, 42) }
        #expect(model.captureStartDetail(today) == "✓ 07:42")
    }
}
