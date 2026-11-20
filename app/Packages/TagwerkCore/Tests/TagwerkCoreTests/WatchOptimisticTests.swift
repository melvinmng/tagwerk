import Foundation
import Testing
@testable import TagwerkCore

struct WatchOptimisticTests {
    let calendar = makeCalendar()
    let readingHabit = UUID()
    let stepsHabit = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func task(_ title: String) -> WatchTask {
        WatchTask(key: "local:\(title)", title: title, due: nil, hasTime: false, isDeadline: false, source: .local, version: "1")
    }

    private func snapshot(applied: [UUID] = []) -> WatchSnapshot {
        WatchSnapshot(createdAt: start, day: PlanDay(date: start, calendar: calendar), entries: [], tasks: [task("A"), task("B")],
                      habits: [WatchHabit(id: readingHabit, name: "Lesen", symbol: "book", done: false, isAutomatic: false),
                               WatchHabit(id: stepsHabit, name: "Schritte", symbol: "figure.walk", done: false, isAutomatic: true)],
                      habitCounter: HabitCounter(done: 0, total: 2),
                      water: WatchWater(milliliters: 500, goalMilliliters: 2000, showsInComplication: true), appliedActionIDs: applied)
    }

    private func action(_ kind: WatchAction.Kind, at offset: TimeInterval = 0) -> WatchAction {
        WatchAction(createdAt: start.addingTimeInterval(offset), kind: kind)
    }

    @Test func pendingActionsShowAsDone() {
        let result = snapshot().applying([action(.completeTask(key: "local:A", version: "1")), action(.checkHabit(id: readingHabit, on: true)),
                                          action(.logWater(milliliters: 250, entryID: UUID()))])
        #expect(result.tasks.map(\.title) == ["B"])
        #expect(result.habits[0].done)
        #expect(result.water?.milliliters == 750)
    }

    @Test func automaticHabitStaysAsItIs() {
        let result = snapshot().applying([action(.checkHabit(id: stepsHabit, on: true))])
        #expect(!result.habits[1].done)
    }

    @Test func undoneAndAppliedActionsAreSkipped() {
        let undone = action(.completeTask(key: "local:A", version: "1"))
        let appliedAlready = action(.logWater(milliliters: 250, entryID: UUID()))
        let result = snapshot(applied: [appliedAlready.id]).applying([undone, action(.undo(of: undone.id), at: 2), appliedAlready])
        #expect(result.tasks.map(\.title) == ["A", "B"])
        #expect(result.water?.milliliters == 500)
    }

    @Test func counterFollowsTheLocalChanges() {
        let original = snapshot()
        let changed = original.applying([action(.checkHabit(id: readingHabit, on: true))])
        #expect(changed.habitCounter(relativeTo: original) == HabitCounter(done: 1, total: 2))
    }

    @Test func inbox_collectsActionsInOrder_andDrains() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "watch-inbox-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let later = action(.completeTask(key: "local:B", version: "1"), at: 5), earlier = action(.completeTask(key: "local:A", version: "1"), at: 1)
        try WatchActionInbox.add(later, to: directory)
        try WatchActionInbox.add(earlier, to: directory)
        #expect(WatchActionInbox.pending(in: directory).map(\.id) == [earlier.id, later.id])
        #expect(WatchActionInbox.drain(from: directory).map(\.id) == [earlier.id, later.id])
        #expect(WatchActionInbox.pending(in: directory).isEmpty)
        #expect(WatchActionInbox.drain(from: nil).isEmpty)
    }
}
