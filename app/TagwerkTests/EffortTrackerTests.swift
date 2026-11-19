import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct EffortTrackerTests {
    let container: ModelContainer
    let calendarStore = FakeCalendarStore()
    let focusStore: FocusStore
    let settings: AppSettings
    let calendar = testCalendar()
    let planner: BlockPlanner

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.planCalendarID = "plan"
        focusStore = FocusStore(context: container.mainContext)
        planner = BlockPlanner(store: calendarStore, planStore: PlanStore(context: container.mainContext),
                               links: EventLinkStore(context: container.mainContext), settings: settings, calendar: calendar)
    }

    private func tracker(now: Date? = nil) -> EffortTracker {
        EffortTracker(store: focusStore, blocks: planner, calendarStore: calendarStore, settings: settings, now: { now ?? testNow() })
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func task(_ title: String = "Bericht", estimate: Int? = 60, labels: [String]? = nil) -> TaskItem {
        var item = makeTask(title, source: .local)
        item.estimateMinutes = estimate
        item.labels = labels
        return item
    }

    @discardableResult
    private func addBlock(_ item: TaskItem, day: Int = 18, from: (Int, Int), to: (Int, Int)) throws -> CalendarEvent {
        try calendarStore.createBlock(BlockDraft(title: item.title, start: at(day, from.0, from.1), end: at(day, to.0, to.1), taskID: item.id),
                                      in: "plan")
    }

    private var samples: [EffortSampleRecord] {
        focusStore.samples(in: DateInterval(start: at(1, 0), end: at(30, 0)))
    }

    @Test func earlyCompletion_trimsTheBlockAndRecordsTheElapsedTime() async throws {
        let item = task()
        let block = try addBlock(item, from: (14, 0), to: (15, 0))
        let trimmed = await tracker().didComplete(item, at: at(18, 14, 20))
        #expect(trimmed)
        #expect(calendarStore.event(id: block.id)?.end == at(18, 14, 20))
        #expect(samples.count == 1)
        #expect(samples.first?.actualMinutes == 20)
        #expect(samples.first?.estimateMinutes == 60)
        #expect(samples.first?.methodRaw == EffortMethod.partialBlock.rawValue)
        #expect(samples.first?.trimmedOriginalEnd == at(18, 15, 0))
    }

    @Test func undo_restoresTheBlockEnd() async throws {
        let item = task()
        let block = try addBlock(item, from: (14, 0), to: (15, 0))
        let tracker = tracker(now: at(18, 14, 25))
        await tracker.didComplete(item, at: at(18, 14, 20))
        await tracker.didReopen(item.id)
        #expect(calendarStore.event(id: block.id)?.end == at(18, 15, 0))
        #expect(samples.isEmpty)
    }

    @Test func undo_afterTheBlockChanged_leavesItAlone() async throws {
        let item = task()
        let block = try addBlock(item, from: (14, 0), to: (15, 0))
        let tracker = tracker(now: at(18, 14, 25))
        await tracker.didComplete(item, at: at(18, 14, 20))
        // Somebody moved the end of the block in the Calendar app.
        let current = try #require(calendarStore.event(id: block.id))
        _ = try calendarStore.moveBlock(id: block.id, to: current.start, end: at(18, 14, 40), expectedVersion: current.version)
        await tracker.didReopen(item.id)
        #expect(calendarStore.event(id: block.id)?.end == at(18, 14, 40))
        #expect(samples.isEmpty)
    }

    @Test func undo_afterADay_keepsTheSample() async throws {
        let item = task()
        try addBlock(item, from: (14, 0), to: (15, 0))
        await tracker(now: at(20, 9)).didComplete(item, at: at(18, 14, 20))
        await tracker(now: at(20, 9)).didReopen(item.id)
        #expect(samples.count == 1)
    }

    @Test func trimConflict_keepsTheBlockButRecordsTheSample() async throws {
        let item = task()
        let block = try addBlock(item, from: (14, 0), to: (15, 0))
        // Somebody moves the end between reading the block and writing the cut.
        let movedEnd = at(18, 15, 30)
        calendarStore.beforeUpdate = { [calendarStore] in
            calendarStore.storedEvents[0].version = "edited-elsewhere"
            calendarStore.storedEvents[0].end = movedEnd
        }
        let trimmed = await tracker().didComplete(item, at: at(18, 14, 20))
        #expect(!trimmed)
        #expect(calendarStore.event(id: block.id)?.end == at(18, 15, 30))
        #expect(samples.first?.actualMinutes == 20)
        #expect(samples.first?.trimmedEventID == nil)
    }

    @Test func completionWithoutBlockOrFocus_recordsNothing() async {
        let trimmed = await tracker().didComplete(task(), at: at(18, 14, 20))
        #expect(!trimmed)
        #expect(samples.isEmpty)
    }

    @Test func completionHoursLater_countsTheBlockAndChangesNothing() async throws {
        let item = task()
        let block = try addBlock(item, from: (9, 0), to: (10, 0))
        await tracker().didComplete(item, at: at(18, 17, 0))
        #expect(calendarStore.event(id: block.id)?.end == at(18, 10, 0))
        #expect(samples.first?.actualMinutes == 60)
        #expect(samples.first?.methodRaw == EffortMethod.blocks.rawValue)
    }

    @Test func bulkComplete_recordsEachTask() async throws {
        let first = task("Eins"), second = task("Zwei")
        try addBlock(first, from: (9, 0), to: (9, 30))
        try addBlock(second, from: (10, 0), to: (11, 0))
        let tracker = tracker()
        await tracker.didComplete(first, at: at(18, 12, 0))
        await tracker.didComplete(second, at: at(18, 12, 0))
        #expect(Set(samples.map(\.taskKey)) == [first.id.key, second.id.key])
        #expect(Set(samples.map(\.actualMinutes)) == [30, 60])
    }

    private func addSession(_ item: TaskItem, from start: Date, to end: Date, pauses: [DateInterval] = []) {
        var state = FocusTimerState(start: start, settings: FocusTimerSettings(isPomodoro: false), pauses: pauses)
        state.endedAt = end
        let session = FocusSessionRecord(taskKey: item.id.key, blockEventID: nil, title: item.title, state: state)
        session.outcome = .completed
        session.focusedSeconds = FocusTimerRules.snapshot(of: state, at: end).focusedSeconds
        focusStore.insert(session)
    }

    @Test func focusInsideTheBlock_isNotCountedTwice() async throws {
        let item = task()
        try addBlock(item, from: (9, 0), to: (10, 0))
        addSession(item, from: at(18, 9, 5), to: at(18, 9, 30))
        await tracker().didComplete(item, at: at(18, 12, 0))
        #expect(samples.first?.actualMinutes == 60)
        #expect(samples.first?.methodRaw == EffortMethod.blocks.rawValue)
    }

    @Test func focusOutsideTheBlock_isAddedToTheBlock() async throws {
        let item = task()
        try addBlock(item, from: (9, 0), to: (10, 0))
        addSession(item, from: at(18, 11, 0), to: at(18, 11, 25))
        await tracker().didComplete(item, at: at(18, 12, 0))
        #expect(samples.first?.actualMinutes == 85)
        #expect(samples.first?.methodRaw == EffortMethod.blocksAndFocus.rawValue)
    }

    @Test func focusWithPause_countsTheWorkedTimeOutsideTheBlock() async throws {
        let item = task()
        try addBlock(item, from: (9, 0), to: (10, 0))
        // 25 minutes of work from 11:00 with a pause of 10 minutes at 11:10: the work ends at 11:35.
        addSession(item, from: at(18, 11, 0), to: at(18, 11, 35), pauses: [DateInterval(start: at(18, 11, 10), end: at(18, 11, 20))])
        await tracker().didComplete(item, at: at(18, 12, 0))
        #expect(samples.first?.actualMinutes == 85)
    }

    @Test func withoutBlock_focusSessionIsTheEffort() async throws {
        let item = task()
        addSession(item, from: at(18, 11, 0), to: at(18, 11, 25))
        await tracker().didComplete(item, at: at(18, 12, 0))
        #expect(samples.first?.actualMinutes == 25)
        #expect(samples.first?.methodRaw == EffortMethod.focus.rawValue)
    }

    @Test func recurringTask_secondCompletionDoesNotCountTheFirstBlocksAgain() async throws {
        let item = task()
        try addBlock(item, day: 17, from: (9, 0), to: (10, 0))
        await tracker().didComplete(item, at: at(17, 12, 0))
        try addBlock(item, day: 18, from: (9, 0), to: (9, 45))
        await tracker().didComplete(item, at: at(18, 12, 0))
        #expect(samples.map(\.actualMinutes) == [60, 45])
    }

    @Test func expectedMinutes_useTheSamplesOfThePastWeeks() async throws {
        let now = at(18, 12, 0)
        for offset in 1...3 {
            let sample = EffortSampleRecord(taskKey: "local:x\(offset)", source: .local, labels: [], estimateMinutes: 30, actualMinutes: 45,
                                            method: .blocks, completedAt: now.addingTimeInterval(TimeInterval(-offset * 86_400)))
            focusStore.add(sample)
        }
        let tracker = tracker(now: now)
        let expected = tracker.expectedMinutes(for: [task("A", estimate: 30), task("B", estimate: nil), task("C", estimate: 60)])
        #expect(expected == ["local:A": 45, "local:C": 90])
        settings.effortHistoryInPlanning = false
        #expect(tracker.expectedMinutes(for: [task("A", estimate: 30)]).isEmpty)
    }
}
