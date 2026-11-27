import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The local activity log (#332): the wiring of a moved planned day from the plan to the log, end to end with the real plan store.
@MainActor
struct TaskActivityStoreTests {
    let container: ModelContainer
    let log: TaskActivityStore
    let plan: PlanStore
    let now = testNow()
    let today = PlanDay(year: 2026, month: 11, day: 18)
    let later = PlanDay(year: 2026, month: 11, day: 20)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        log = TaskActivityStore(context: container.mainContext)
        plan = PlanStore(context: container.mainContext)
    }

    /// The wiring of `AppEnvironment`: the plan store reports a move, the log writes the entry for the loaded task.
    private func connect(_ items: [TaskItem]) {
        plan.onDayMoved = { [log, now] id, from, to in log.recordPlanDayMove(of: id, from: from, to: to, among: items, at: now) }
        plan.onDayMoveUndone = { [log] id, undone, restored in log.removePlanDayMove(of: id, from: restored, to: undone) }
    }

    @Test func undoingAMoveRemovesItsEntryAndKeepsEarlierMoves() {
        let task = makeTask("Bericht", source: .local)
        let third = PlanDay(year: 2026, month: 11, day: 24)
        connect([task])
        plan.assign(task.id, to: today)
        plan.assign(task.id, to: later)
        plan.assign(task.id, to: third)
        plan.restore(task.id, to: later)
        let entries = log.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.from == "2026-11-18" && entries.first?.to == "2026-11-20")
    }

    @Test func aMoveOfALoadedTaskIsLoggedWithItsProjects() {
        let task = makeTask("Bericht", source: .reminders)
        connect([task])
        plan.assign(task.id, to: today)
        plan.assign(task.id, to: later)
        let entries = log.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.kind == .replanned)
        #expect(entries.first?.from == "2026-11-18" && entries.first?.to == "2026-11-20")
        #expect(entries.first?.taskKey == task.id.key && entries.first?.title == "Bericht")
        #expect(entries.first?.projectKeys == ProjectProgressReference.keys(of: task))
        #expect(entries.first?.occurredAt == now)
    }

    @Test func firstPlanningRemovalAndTheSameDayWriteNothing() {
        let task = makeTask("Bericht", source: .local)
        connect([task])
        plan.assign(task.id, to: today)
        plan.assign(task.id, to: today)
        plan.unassign(task.id)
        #expect(log.entries().isEmpty)
    }

    @Test func aTaskThatIsNotLoadedWritesNothing() {
        connect([])
        let task = makeTask("Fremd", source: .github)
        plan.assign(task.id, to: today)
        plan.assign(task.id, to: later)
        #expect(log.entries().isEmpty)
    }

    @Test func theLogKeepsTheMovesOfOneTaskInOrder() {
        let task = makeTask("Bericht", source: .local)
        connect([task])
        plan.assign(task.id, to: today)
        plan.assign(task.id, to: later)
        plan.assign(task.id, to: PlanDay(year: 2026, month: 11, day: 25))
        #expect(log.entries().compactMap(\.to).sorted() == ["2026-11-20", "2026-11-25"])
    }
}
