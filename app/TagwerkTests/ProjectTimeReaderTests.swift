import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The records the project time reads (#332, stage 2), checked end to end with the real effort tracker, so a wrong task key or a
/// misread record shows as a missing number instead of a silent zero.
@MainActor
struct ProjectTimeReaderTests {
    let container: ModelContainer
    let calendarStore = FakeCalendarStore()
    let focusStore: FocusStore
    let settings: AppSettings
    let calendar = testCalendar()
    let planner: BlockPlanner
    var calendarAvailable = true

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.planCalendarID = "plan"
        focusStore = FocusStore(context: container.mainContext)
        planner = BlockPlanner(store: calendarStore, planStore: PlanStore(context: container.mainContext),
                               links: EventLinkStore(context: container.mainContext), settings: settings, calendar: calendar)
    }

    private func reader(calendarAvailable: Bool = true) -> ProjectTimeReader {
        ProjectTimeReader(focusStore: focusStore, blocks: { planner.blocks(forTaskKeys: $0, in: $1) }, calendarAvailable: { calendarAvailable })
    }

    private func tracker() -> EffortTracker {
        EffortTracker(store: focusStore, blocks: planner, calendarStore: calendarStore, settings: settings, now: { at(18, 18) })
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// Four weeks up to Wednesday, 18 Nov 2026, 18:00.
    private var range: ProjectRange { ProjectProgress.range(of: .fourWeeks, now: at(18, 18), calendar: calendar) }

    private func task(_ title: String = "Bericht", source: TaskSource = .local) -> TaskItem { makeTask(title, source: source) }

    @discardableResult
    private func addBlock(_ item: TaskItem, day: Int = 18, from: (Int, Int), to: (Int, Int)) throws -> CalendarEvent {
        try calendarStore.createBlock(BlockDraft(title: item.title, start: at(day, from.0, from.1), end: at(day, to.0, to.1), taskID: item.id),
                                      in: "plan")
    }

    private func addSession(_ item: TaskItem, day: Int = 17, from: (Int, Int), minutes: Double, outcome: FocusOutcome = .completed) {
        var state = FocusTimerState(start: at(day, from.0, from.1), settings: FocusTimerSettings(workMinutes: 60))
        state.endedAt = state.start.addingTimeInterval(minutes * 60)
        let record = FocusSessionRecord(taskKey: item.id.key, blockEventID: nil, title: item.title, state: state)
        record.outcome = outcome
        record.focusedSeconds = Int(minutes * 60)
        focusStore.insert(record)
    }

    private func summary(_ items: [TaskItem], calendarAvailable: Bool = true) -> ProjectTimeSummary {
        let keys = Set(items.map(\.id.key))
        let inputs = reader(calendarAvailable: calendarAvailable).inputs(taskKeys: keys, range: range)
        return ProjectTime.summary(inputs: inputs, taskKeys: keys, range: range, calendar: calendar)
    }

    @Test func plannedBlocksOfTheTasksAreRead() throws {
        let item = task()
        try addBlock(item, day: 10, from: (9, 0), to: (11, 0))
        try addBlock(task("Anderes"), day: 10, from: (13, 0), to: (15, 0))
        let result = summary([item])
        #expect(result.plannedSeconds == 2 * 3600)
        #expect(result.investedSeconds == 0, "a block of an open task is only planned")
    }

    @Test func focusSessionsCount_runningAndDiscardedOnesDoNot() {
        let item = task()
        addSession(item, from: (9, 0), minutes: 30)
        addSession(item, from: (10, 0), minutes: 45, outcome: .aborted)
        addSession(item, from: (11, 0), minutes: 20, outcome: .discarded)
        // A session that has not ended.
        focusStore.insert(FocusSessionRecord(taskKey: item.id.key, blockEventID: nil, title: "läuft",
                                             state: FocusTimerState(start: at(17, 12), settings: FocusTimerSettings())))
        #expect(summary([item]).investedSeconds == 75 * 60)
    }

    @Test func sessionOfAnotherTaskOrWithoutATaskIsIgnored() {
        let item = task()
        addSession(task("Anderes"), from: (9, 0), minutes: 30)
        focusStore.insert(FocusSessionRecord(taskKey: nil, blockEventID: nil, title: "frei", state: {
            var state = FocusTimerState(start: at(17, 9), settings: FocusTimerSettings())
            state.endedAt = at(17, 10)
            return state
        }()))
        #expect(summary([item]).hasData == false)
    }

    @Test func earlyCompletion_isPlannedAsPlannedAndInvestedAsElapsed() async throws {
        let item = task()
        try addBlock(item, from: (14, 0), to: (15, 0))
        _ = await tracker().didComplete(item, at: at(18, 14, 20))
        // The block was cut to 14:20; the plan stays at the hour it was planned for.
        let result = summary([item])
        #expect(result.plannedSeconds == 3600)
        #expect(result.investedSeconds == 20 * 60)
    }

    @Test func blockChangedAfterTheCut_isPlannedAsItIsNow() async throws {
        let item = task()
        let block = try addBlock(item, from: (14, 0), to: (15, 0))
        _ = await tracker().didComplete(item, at: at(18, 14, 20))
        let cut = try #require(calendarStore.event(id: block.id))
        _ = try calendarStore.moveBlock(id: block.id, to: cut.start, end: at(18, 14, 50), expectedVersion: cut.version)
        #expect(summary([item]).plannedSeconds == 50 * 60)
    }

    @Test func completion_countsBlocksAndFocusOutsideThem() async throws {
        let item = task()
        // A block that ended before the focus session, and a session outside of it: both count once.
        try addBlock(item, day: 17, from: (8, 0), to: (9, 0))
        addSession(item, day: 17, from: (13, 0), minutes: 30)
        _ = await tracker().didComplete(item, at: at(18, 12))
        let samples = focusStore.samples(in: DateInterval(start: at(1, 0), end: at(30, 0)))
        // The block counts for the sample (it ended before the completion), so the sample is a block measurement.
        #expect(samples.first?.methodRaw == EffortMethod.blocksAndFocus.rawValue)
        #expect(summary([item]).investedSeconds == 90 * 60)
    }

    @Test func withoutCalendarAccessNoBlockIsKnown() throws {
        let item = task()
        try addBlock(item, day: 10, from: (9, 0), to: (11, 0))
        addSession(item, from: (9, 0), minutes: 30)
        let result = summary([item], calendarAvailable: false)
        #expect(!result.hasPlanned && !result.calendarAvailable)
        #expect(result.investedSeconds == 30 * 60, "the focus sessions are on the device and do not need the calendar")
    }

    @Test func eventsOfTheUserWithoutTheTaskLinkAreNotBlocks() throws {
        let item = task()
        // An appointment of the user that only has the task's title: no link in the URL, so it is not Tagwerk's block.
        calendarStore.storedEvents.append(CalendarEvent(id: "own", externalID: nil, calendarID: "plan", title: item.title, start: at(10, 9),
                                                        end: at(10, 11), isAllDay: false, url: nil, isBusy: true, version: "v"))
        #expect(summary([item]).hasData == false)
    }

    @Test func readingWritesNothing() throws {
        let item = task()
        try addBlock(item, from: (14, 0), to: (15, 0))
        _ = summary([item])
        let sessions = (try? container.mainContext.fetchCount(FetchDescriptor<FocusSessionRecord>())) ?? -1
        let samples = (try? container.mainContext.fetchCount(FetchDescriptor<EffortSampleRecord>())) ?? -1
        #expect(sessions == 0 && samples == 0)
    }
}
