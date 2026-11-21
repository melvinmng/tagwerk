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

    private func makeModel(taskList override: TaskListModel? = nil, isRecurring: ((TaskItem) -> Bool)? = nil,
                           closedIssueCount: @escaping @MainActor () -> (@MainActor (DateInterval) async throws -> Int)? = { nil }) -> RoutinesModel {
        let clock = self.clock, completed = self.completed
        return RoutinesModel(store: routineStore, planning: planning, taskList: override ?? taskList, habits: habits,
                             settings: settings, completedCount: { _ in completed.count }, calendar: calendar,
                             now: { clock.now }, isRecurring: isRecurring, closedIssueCount: closedIssueCount)
    }

    private func task(_ title: String) -> TaskItem { local.tasks.first { $0.title == title }! }

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

    @Test func leftoverEntry_eveningSheetOfToday_isOffered() {
        // 22:00: today's work is over and "Heute fällig" is still open.
        #expect(!planning.leftFromToday.isEmpty)
        let model = makeModel()
        #expect(model.offersLeftover(for: today))
        model.openLeftover()
        #expect(model.sheet == .leftover)
    }

    @Test func leftoverEntry_afterMidnight_isNotOffered() {
        let model = makeModel()
        // 00:10: the wrap-up still belongs to yesterday; the tasks of the new day are not its leftovers.
        clock.now = at(19, 0, 10)
        model.openEvening()
        guard case .evening(let opened) = model.sheet else { Issue.record("no evening sheet"); return }
        #expect(opened == today)
        #expect(!model.offersLeftover(for: opened))
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

    @Test func toggleItem_callsHook() async {
        addChecklist()
        let model = makeModel()
        let id = model.checklist()[0].id
        var calls: [(UUID, PlanDay, Bool)] = []
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var remaining = 2
            model.onChecklistToggled = { id, day, isChecked in
                calls.append((id, day, isChecked))
                remaining -= 1
                if remaining == 0 { continuation.resume() }
            }
            model.toggleItem(id, on: today)
            model.toggleItem(id, on: today)
        }
        #expect(calls.map(\.2) == [true, false])
        #expect(calls.allSatisfy { $0.0 == id && $0.1 == today })
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

    // MARK: Closed GitHub issues in the day review

    private struct GitHubDown: Error {}

    @Test func dayReview_withoutGitHub_isNotConnected() async {
        let review = await makeModel().dayReview(today)
        #expect(review.gitHub == .notConnected)
        // Nothing is added without GitHub, also when the second step runs.
        let after = await makeModel().addingClosedIssues(to: review, day: today)
        #expect(after == review)
    }

    @Test func dayReview_withGitHub_startsLoading() async {
        completed.count = 4
        let review = await makeModel(closedIssueCount: { { _ in 9 } }).dayReview(today)
        #expect(review.gitHub == .loading)
        // The local numbers come first and do not include GitHub yet.
        let withoutGitHub = await makeModel().dayReview(today)
        #expect(review.tasksDone == 4 && review.tasksDone == withoutGitHub.tasksDone)
        #expect(review.tasksTotal == withoutGitHub.tasksTotal)
    }

    @Test func addingClosedIssues_addsToDoneAndTotal() async {
        planStore.assign(TaskID(source: .local, rawValue: "Geplant"), to: today)
        completed.count = 4
        let model = makeModel(closedIssueCount: { { _ in 2 } })
        let local = await model.dayReview(today)
        let review = await model.addingClosedIssues(to: local, day: today)
        // e and n rise by the same number: a closed issue is no longer an open task of the day.
        #expect(review.tasksDone == local.tasksDone + 2)
        #expect(review.tasksTotal == local.tasksTotal + 2)
        #expect(review.gitHub == .counted(2))
        #expect(review.habits == local.habits && review.focus == local.focus)
    }

    @Test func addingClosedIssues_calledTwice_addsOnce() async {
        let model = makeModel(closedIssueCount: { { _ in 2 } })
        let local = await model.dayReview(today)
        let once = await model.addingClosedIssues(to: local, day: today)
        #expect(await model.addingClosedIssues(to: once, day: today) == once)
    }

    @Test func addingClosedIssues_failure_isUnavailable_keepsLocalNumbers() async {
        completed.count = 4
        let model = makeModel(closedIssueCount: { { _ in throw GitHubDown() } })
        let local = await model.dayReview(today)
        let review = await model.addingClosedIssues(to: local, day: today)
        #expect(review.gitHub == .unavailable)
        #expect(review.tasksDone == 4 && review.tasksTotal == local.tasksTotal)
    }

    @Test func reviewFooter_coversAllStates() {
        #expect(RoutinesModel.reviewFooter(.notConnected) == "Erledigt: Erinnerungen und lokale Aufgaben.")
        #expect(RoutinesModel.reviewFooter(.loading) == "Erledigt: Erinnerungen und lokale Aufgaben. GitHub wird geladen …")
        #expect(RoutinesModel.reviewFooter(.counted(3))
                == "Erledigt: Erinnerungen, lokale Aufgaben und heute geschlossene GitHub-Issues.")
        #expect(RoutinesModel.reviewFooter(.counted(0), isToday: false)
                == "Erledigt: Erinnerungen, lokale Aufgaben und an diesem Tag geschlossene GitHub-Issues.")
        #expect(RoutinesModel.reviewFooter(.unavailable)
                == "Erledigt: Erinnerungen und lokale Aufgaben. GitHub ist gerade nicht erreichbar.")
    }

    @Test func addingClosedIssues_usesCalendarDayOfRoutineDay() async {
        // The wrap-up after midnight belongs to the 17th although the clock shows the 18th (rule 10).
        final class Seen { var intervals: [DateInterval] = [] }
        let seen = Seen()
        let model = makeModel(closedIssueCount: { { interval in seen.intervals.append(interval); return 1 } })
        let yesterday = PlanDay(year: 2026, month: 11, day: 17)
        let local = await model.dayReview(yesterday)
        _ = await model.addingClosedIssues(to: local, day: yesterday)
        #expect(seen.intervals == [DateInterval(start: at(17, 0), end: at(18, 0))])
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

    @Test func tasksOfToday_arePlannedDueOrBlocked() {
        planStore.assign(TaskID(source: .local, rawValue: "Geplant"), to: today)
        let model = makeModel()
        #expect(Set(model.tasks(of: today).map(\.title)) == ["Heute fällig", "Geplant"])
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
        #expect(model.captureStartDetail(today) == "Starten")
        routineStore.update(today) { $0.startCompletedAt = self.at(18, 7, 42) }
        #expect(model.captureStartDetail(today) == "✓ 07:42")
    }

    // MARK: Focus and card

    @Test func card_isMorningBetweenFourAndNoon_untilCompletedOrDismissed() {
        let model = makeModel()
        clock.now = at(18, 8)
        if case .morning = model.card {} else { Issue.record("expected the morning card at 08:00") }
        clock.now = at(18, 3, 59)
        #expect(model.card == nil)
        clock.now = at(18, 8)
        model.dismissMorningCard()
        #expect(model.card == nil)
        routineStore.update(today) { $0.startDismissed = false; $0.startCompletedAt = self.clock.now }
        #expect(model.card == nil)
    }

    @Test func card_isFocusOnceAFocusIsChosen_andAnOpenFocusTaskRemains() {
        let model = makeModel()
        clock.now = at(18, 8)
        routineStore.addFocus(task("Heute fällig"), on: today)
        routineStore.addFocus(task("Geplant"), on: today)
        routineStore.setFocusDone(taskKey: task("Geplant").id.key, on: today, at: clock.now)
        guard case .focus(let marks, let done, let total) = model.card else { Issue.record("expected the focus card"); return }
        #expect(marks.count == 2 && done == 1 && total == 2)
    }

    @Test func card_isNil_whenAllFocusTasksAreDone_orRoutinesAreHiddenInPlan() {
        let model = makeModel()
        clock.now = at(18, 8)
        routineStore.addFocus(task("Geplant"), on: today)
        routineStore.setFocusDone(taskKey: task("Geplant").id.key, on: today, at: clock.now)
        #expect(model.card == nil)
        routineStore.setFocusDone(taskKey: task("Geplant").id.key, on: today, at: nil)
        #expect(model.card != nil)
        settings.showsRoutinesInPlan = false
        #expect(model.card == nil)
    }

    @Test func card_isNil_afterNoonWithoutFocus() {
        let model = makeModel()
        clock.now = at(18, 12)
        #expect(model.card == nil)
    }

    @Test func completeFocus_completesTheTaskInItsSource_andSetsDoneAt() async throws {
        let model = makeModel()
        let item = task("Heute fällig")
        model.toggleFocus(item)
        let mark = try #require(model.focusMarks(today).first)
        await model.completeFocus(mark)
        #expect(local.appliedEdits.contains { $0.id == item.id })
        #expect(model.focusMarks(today).first?.doneAt != nil)
        #expect(!taskList.items.contains { $0.id == item.id })
    }

    @Test func undoComplete_clearsDoneAt() {
        let model = makeModel()
        let item = task("Geplant")
        model.toggleFocus(item)
        model.focusChanged(item.id, isCompleted: true)
        #expect(model.focusMarks(today).first?.doneAt != nil)
        model.focusChanged(item.id, isCompleted: false)
        #expect(model.focusMarks(today).first?.doneAt == nil)
    }

    @Test func vanishedTask_isDoneOnlyAfterItsSourceSettled() async {
        let gone = makeTask("Exposé Kapitel 2", source: .local)
        routineStore.addFocus(gone, on: today)
        // The source has not answered yet: the mark stays open.
        let loadingSource = FakeTaskProvider(source: .local)
        let loading = TaskListModel(providers: [loadingSource], now: { self.clock.now }, calendar: calendar)
        let early = makeModel(taskList: loading)
        early.refreshFocus()
        #expect(early.focusMarks(today).first?.doneAt == nil)
        // Loaded, the task is missing: it counts as done and keeps its remembered title.
        await loading.reload()
        early.refreshFocus()
        #expect(early.focusMarks(today).first?.doneAt != nil)
        #expect(early.focusMarks(today).first?.title == "Exposé Kapitel 2")
    }

    @Test func vanishedTask_staysOpenWhenItsSourceFailedOrLostAccess() async {
        let gone = makeTask("Exposé Kapitel 2", source: .local)
        routineStore.addFocus(gone, on: today)
        for error in [TaskWriteError.accessDenied, .signedOut, .failed("Netzwerk")] {
            let source = FakeTaskProvider(source: .local)
            source.readError = error
            let failing = TaskListModel(providers: [source], now: { self.clock.now }, calendar: calendar)
            let model = makeModel(taskList: failing)
            await failing.reload()
            model.refreshFocus()
            #expect(model.focusMarks(today).first?.doneAt == nil)
        }
    }

    @Test func refreshFocus_followsAChangedTitle_andReopensAMarkWhoseTaskIsOpenAgain() async {
        let model = makeModel()
        let item = task("Geplant")
        model.toggleFocus(item)
        model.focusChanged(item.id, isCompleted: true)
        model.refreshFocus()   // the task is open in the list: the completion was undone elsewhere
        #expect(model.focusMarks(today).first?.doneAt == nil)
    }

    @Test func toggleFocus_onARecurringOccurrence_isIgnored() {
        let model = makeModel(isRecurring: { $0.title == "Geplant" })
        model.toggleFocus(task("Geplant"))
        #expect(model.focusMarks(today).isEmpty)
        model.toggleFocus(task("Heute fällig"))
        #expect(model.focusMarks(today).count == 1)
        #expect(model.isFocus(task("Heute fällig").id))
        model.toggleFocus(task("Heute fällig"))
        #expect(model.focusMarks(today).isEmpty)
    }

    @Test func toggleFocus_stopsAtThree() {
        let model = makeModel()
        for title in ["Heute fällig", "Geplant", "Später"] { model.toggleFocus(task(title)) }
        let extra = makeTask("Vierte", source: .local)
        model.toggleFocus(extra)
        #expect(model.focusMarks(today).count == 3)
    }

    @Test func focusOfPastDays_isReadOnly() {
        // Only "today" takes marks: after midnight the 18th can no longer change.
        let model = makeModel()
        clock.now = at(19, 10)
        model.toggleFocus(task("Geplant"))   // "today" is now the 19th: this marks the 19th, not the 18th
        #expect(model.focusMarks(today).isEmpty)
        #expect(model.focusMarks(today.adding(days: 1, calendar: calendar)).count == 1)
    }

    @Test func captureStartDetail_namesTheFirstFocus() {
        let model = makeModel()
        routineStore.addFocus(makeTask("Exposé Kapitel 2", source: .local), on: today)
        routineStore.update(today) { $0.startCompletedAt = self.at(18, 7, 42) }
        #expect(model.captureStartDetail(today) == "✓ 07:42 · Fokus: Exposé Kapitel 2")
    }

    @Test func dayReview_hasAFocusLineWithFocus() async {
        let model = makeModel()
        model.toggleFocus(task("Heute fällig"))
        model.toggleFocus(task("Geplant"))
        model.focusChanged(task("Geplant").id, isCompleted: true)
        #expect(await model.dayReview(today).focus == HabitCounter(done: 1, total: 2))
    }
}
