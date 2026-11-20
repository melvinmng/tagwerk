import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// A task ticked off early must shorten its time block, whichever way it was completed and whichever source it comes
/// from (#162, device test F4). The tests drive the real `TaskListModel` and `EffortTracker` over the fakes; the hooks
/// are connected like `AppEnvironment` does.
@MainActor
struct EffortCompletionPathTests {
    let container: ModelContainer
    let calendarStore = FakeCalendarStore()
    let focusStore: FocusStore
    let settings: AppSettings
    let calendar = testCalendar()
    let planner: BlockPlanner
    let clock = EffortTestClock(Self.moment(18, 14, 20))
    var effort: EffortTracker!

    static func moment(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        testCalendar().date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { Self.moment(day, hour, minute) }

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.planCalendarID = "plan"
        focusStore = FocusStore(context: container.mainContext)
        planner = BlockPlanner(store: calendarStore, planStore: PlanStore(context: container.mainContext),
                               links: EventLinkStore(context: container.mainContext), settings: settings, calendar: calendar)
        let clock = clock
        effort = EffortTracker(store: focusStore, blocks: planner, calendarStore: calendarStore, settings: settings,
                               now: { clock.now })
    }

    /// The list model with the hooks of `AppEnvironment` (effort tracking only).
    private func listModel(_ provider: FakeTaskProvider) async -> TaskListModel {
        let clock = clock
        let model = TaskListModel(providers: [provider], now: { clock.now }, calendar: calendar)
        let effort = effort!
        model.onCompletedItem = { item, date in await effort.didComplete(item, at: date) }
        model.onCompletionChanged = { id, isCompleted in
            if !isCompleted { await effort.didReopen(id) }
        }
        await model.reload()
        return model
    }

    private func task(_ rawValue: String, source: TaskSource, estimate: Int? = 60) -> TaskItem {
        var item = makeTask(rawValue, source: source)
        item.estimateMinutes = estimate
        return item
    }

    @discardableResult
    private func addBlock(_ item: TaskItem, from: (Int, Int), to: (Int, Int), day: Int = 18) throws -> CalendarEvent {
        try calendarStore.createBlock(BlockDraft(title: item.title, start: at(day, from.0, from.1), end: at(day, to.0, to.1),
                                                 taskID: item.id), in: "plan")
    }

    private var samples: [EffortSampleRecord] {
        focusStore.samples(in: DateInterval(start: at(1, 0), end: at(30, 0)))
    }

    /// Hooks of `didSave` run in a task of their own.
    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    // MARK: Task list

    @Test(arguments: [TaskSource.reminders, .github, .local])
    func listCompletion_trimsTheBlock_forEverySource(source: TaskSource) async throws {
        let item = task("Bericht", source: source)
        let model = await listModel(FakeTaskProvider(source: source, tasks: [item]))
        let block = try addBlock(item, from: (14, 0), to: (15, 0))
        await model.complete(item.id)
        #expect(calendarStore.event(id: block.id)?.end == at(18, 14, 20))
        #expect(samples.first?.actualMinutes == 20)
    }

    @Test func undo_restoresTheBlock() async throws {
        let item = task("Bericht", source: .reminders)
        let model = await listModel(FakeTaskProvider(source: .reminders, tasks: [item]))
        let block = try addBlock(item, from: (14, 0), to: (15, 0))
        await model.complete(item.id)
        clock.now = at(18, 14, 21)
        await model.undoComplete()
        #expect(calendarStore.event(id: block.id)?.end == at(18, 15, 0))
        #expect(samples.isEmpty)
    }

    @Test func bulkCompletion_trimsEveryBlock() async throws {
        let first = task("Eins", source: .local), second = task("Zwei", source: .local)
        let model = await listModel(FakeTaskProvider(source: .local, tasks: [first, second]))
        let one = try addBlock(first, from: (14, 0), to: (15, 0))
        let two = try addBlock(second, from: (14, 10), to: (15, 0))
        await model.complete([first.id, second.id])
        #expect(calendarStore.event(id: one.id)?.end == at(18, 14, 20))
        #expect(calendarStore.event(id: two.id)?.end == at(18, 14, 20))
    }

    // MARK: Editor and GitHub status

    @Test func editorCompletion_trimsTheBlock() async throws {
        let item = task("Bericht", source: .reminders)
        let model = await listModel(FakeTaskProvider(source: .reminders, tasks: [item]))
        let block = try addBlock(item, from: (14, 0), to: (15, 0))
        var saved = item
        saved.isCompleted = true
        model.didSave(saved)
        await settle { calendarStore.event(id: block.id)?.end != at(18, 15, 0) }
        #expect(calendarStore.event(id: block.id)?.end == at(18, 14, 20))
        #expect(samples.first?.actualMinutes == 20)
    }

    private func githubIssue() -> TaskItem {
        var issue = TaskItem(id: TaskID(source: .github, rawValue: "I_kwDOAbc123"), title: "Fehler beheben", notes: nil, due: nil,
                             priority: nil, estimateMinutes: 60, isCompleted: false,
                             container: TaskContainer(id: "beispiel/app", name: "app", colorHex: nil),
                             url: URL(string: "https://github.com/beispiel/app/issues/42"), version: "1",
                             editableFields: [.title, .notes, .due, .priority, .status])
        issue.statuses = [SubContainerStatus(subContainerID: "PVT_1", subContainerName: "App", current: "In progress",
                                             options: ["Backlog", "In progress", "Done"], isWritable: true)]
        return issue
    }

    @Test func githubDoneStatus_inTheList_trimsTheBlock() async throws {
        let issue = githubIssue()
        let model = await listModel(FakeTaskProvider(source: .github, tasks: [issue]))
        let block = try addBlock(issue, from: (14, 0), to: (15, 0))
        await model.setStatus(issue.id, subContainerID: "PVT_1", to: "Done")
        #expect(calendarStore.event(id: block.id)?.end == at(18, 14, 20))
    }

    @Test func githubDoneStatus_inTheEditor_trimsTheBlock() async throws {
        let issue = githubIssue()
        let model = await listModel(FakeTaskProvider(source: .github, tasks: [issue]))
        let block = try addBlock(issue, from: (14, 0), to: (15, 0))
        var saved = issue
        saved.statuses[0].current = "Done"
        saved.isCompleted = true
        model.didSave(saved)
        await settle { calendarStore.event(id: block.id)?.end != at(18, 15, 0) }
        #expect(calendarStore.event(id: block.id)?.end == at(18, 14, 20))
    }

    // MARK: Focus timer

    @Test func focusTimerCompletion_trimsTheBlockAndKeepsTheSession() async throws {
        let item = task("Bericht", source: .reminders)
        let model = await listModel(FakeTaskProvider(source: .reminders, tasks: [item]))
        let block = try addBlock(item, from: (14, 0), to: (15, 0))
        // The timer ran for ten minutes inside the block and ended just before "Erledigt" completes the task.
        var state = FocusTimerState(start: at(18, 14, 10), settings: FocusTimerSettings(isPomodoro: false))
        state.endedAt = at(18, 14, 20)
        let session = FocusSessionRecord(taskKey: item.id.key, blockEventID: block.id, title: item.title, state: state)
        session.outcome = .completed
        session.focusedSeconds = 600
        focusStore.insert(session)
        await model.complete(item.id)
        #expect(calendarStore.event(id: block.id)?.end == at(18, 14, 20))
    }

    // MARK: Leftover measurement (the silent no-trim)

    @Test func leftoverSample_doesNotHideTheRunningBlock() async throws {
        let item = task("Bericht", source: .reminders)
        let model = await listModel(FakeTaskProvider(source: .reminders, tasks: [item]))
        // A completion at 14:05 stayed behind: the task was reopened in the Reminders app, which Tagwerk does not see.
        let stale = EffortSampleRecord(taskKey: item.id.key, source: .reminders, labels: [], estimateMinutes: 60, actualMinutes: 5,
                                       method: .partialBlock, completedAt: at(18, 14, 5))
        focusStore.add(stale)
        let block = try addBlock(item, from: (14, 0), to: (15, 0))
        await model.complete(item.id)
        #expect(calendarStore.event(id: block.id)?.end == at(18, 14, 20))
    }

    // MARK: Writes that fail

    @Test func staleVersionOnly_isRetriedAndTrims() async throws {
        let item = task("Bericht", source: .reminders)
        let model = await listModel(FakeTaskProvider(source: .reminders, tasks: [item]))
        let block = try addBlock(item, from: (14, 0), to: (15, 0))
        // Only the version differs (a sync touched the event): start and end are still what was read.
        var touched = false
        calendarStore.beforeUpdate = { [calendarStore] in
            guard !touched else { return }
            touched = true
            calendarStore.storedEvents[0].version = "touched-by-sync"
        }
        await model.complete(item.id)
        #expect(calendarStore.event(id: block.id)?.end == at(18, 14, 20))
    }

    @Test func blockMovedMeanwhile_staysAsTheUserLeftIt() async throws {
        let item = task("Bericht", source: .reminders)
        let model = await listModel(FakeTaskProvider(source: .reminders, tasks: [item]))
        let block = try addBlock(item, from: (14, 0), to: (15, 0))
        calendarStore.beforeUpdate = { [calendarStore] in
            calendarStore.storedEvents[0].end = Self.moment(18, 15, 30)
            calendarStore.storedEvents[0].version = "moved"
        }
        await model.complete(item.id)
        #expect(calendarStore.event(id: block.id)?.end == at(18, 15, 30))
    }

    // MARK: Which events count as a Tagwerk block

    @Test func blockInAnotherCalendar_isStillTrimmed() async throws {
        // The plan calendar setting changed after the block was written; the link in the URL still marks it as Tagwerk's.
        let item = task("Bericht", source: .reminders)
        let model = await listModel(FakeTaskProvider(source: .reminders, tasks: [item]))
        let block = try calendarStore.createBlock(
            BlockDraft(title: item.title, start: at(18, 14, 0), end: at(18, 15, 0), taskID: item.id), in: "older-plan")
        await model.complete(item.id)
        #expect(calendarStore.event(id: block.id)?.end == at(18, 14, 20))
    }

    @Test func linkedEventOfTheUser_isNotTrimmed() async throws {
        // Documented decision: an event the user made in the Calendar app and linked to the task (by title or by hand)
        // is the user's own appointment. Tagwerk never changes it; the effort still counts.
        let item = task("Bericht", source: .reminders)
        let model = await listModel(FakeTaskProvider(source: .reminders, tasks: [item]))
        let event = try calendarStore.createEvent(EventDraft(title: "Bericht", start: at(18, 14, 0), end: at(18, 15, 0),
                                                             isAllDay: false, calendarID: "plan", notes: nil, location: nil, url: nil))
        EventLinkStore(context: container.mainContext).link(eventID: event.id, to: item.id)
        await model.complete(item.id)
        #expect(calendarStore.event(id: event.id)?.end == at(18, 15, 0))
    }
}

/// A clock a test can move.
@MainActor
final class EffortTestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}
