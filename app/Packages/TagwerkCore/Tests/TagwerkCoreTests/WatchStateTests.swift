import Foundation
import Testing
@testable import TagwerkCore

struct WatchStateTests {
    let calendar = makeCalendar()
    let start = instant(2026, 11, 20, 9, 0)
    let habitID = UUID()

    private func task(_ title: String) -> WatchTask {
        WatchTask(key: "local:\(title)", title: title, due: nil, hasTime: false, isDeadline: false, source: .local, version: "7")
    }

    private func snapshot(at offset: TimeInterval = 0, applied: [UUID] = []) -> WatchSnapshot {
        WatchSnapshot(createdAt: start.addingTimeInterval(offset), day: PlanDay(date: start, calendar: calendar), entries: [],
                      tasks: [task("A"), task("B")],
                      habits: [WatchHabit(id: habitID, name: "Lesen", symbol: "book", done: false, isAutomatic: false),
                               WatchHabit(id: UUID(), name: "Schritte", symbol: "figure.walk", done: false, isAutomatic: true)],
                      habitCounter: HabitCounter(done: 0, total: 2),
                      water: WatchWater(milliliters: 0, goalMilliliters: 2000, showsInComplication: true), appliedActionIDs: applied)
    }

    @Test func receive_acknowledgesAppliedActions() {
        var state = WatchState(snapshot: snapshot())
        let action = state.completeTask(task("A"), now: start)
        #expect(state.pendingCount == 1)
        state.receive(snapshot(at: 5, applied: [action.id]))
        #expect(state.pendingCount == 0)
    }

    @Test func receive_ignoresAnOlderSnapshot() {
        var state = WatchState(snapshot: snapshot(at: 10))
        state.receive(snapshot(at: 0))
        #expect(state.snapshot?.createdAt == start.addingTimeInterval(10))
    }

    @Test func checkedTask_staysVisibleForOneSecond_thenLeaves() {
        var state = WatchState(snapshot: snapshot())
        state.completeTask(task("A"), now: start)
        #expect(state.display(at: start.addingTimeInterval(0.5))?.tasks.map(\.title) == ["A", "B"])
        #expect(state.completingKeys(at: start.addingTimeInterval(0.5)) == ["local:A"])
        #expect(state.display(at: start.addingTimeInterval(1.5))?.tasks.map(\.title) == ["B"])
        #expect(state.completingKeys(at: start.addingTimeInterval(1.5)).isEmpty)
    }

    @Test func undoOffer_lastsFiveSeconds() {
        var state = WatchState(snapshot: snapshot())
        state.completeTask(task("A"), now: start)
        #expect(state.activeUndoOffer(at: start.addingTimeInterval(4.9)) != nil)
        #expect(state.activeUndoOffer(at: start.addingTimeInterval(5.1)) == nil)
        #expect(state.undoLast(now: start.addingTimeInterval(6)) == nil)
    }

    @Test func undoBeforeSend_dropsTheAction_andTheTaskReturns() {
        var state = WatchState(snapshot: snapshot())
        state.completeTask(task("A"), now: start)
        #expect(state.undoLast(now: start.addingTimeInterval(2)) == .dropped)
        #expect(state.pendingCount == 0)
        #expect(state.display(at: start.addingTimeInterval(3))?.tasks.map(\.title) == ["A", "B"])
    }

    @Test func undoAfterSend_queuesACounterAction_andTheTaskReturns() {
        var state = WatchState(snapshot: snapshot())
        let action = state.completeTask(task("A"), now: start)
        state.markSent(action.id, at: start)
        guard case .counterAction(let counter) = state.undoLast(now: start.addingTimeInterval(2)) else { Issue.record("expected a counter action"); return }
        #expect(counter.kind == .undo(of: action.id))
        #expect(state.display(at: start.addingTimeInterval(3))?.tasks.map(\.title) == ["A", "B"])
    }

    @Test func habit_checkAndAutomaticRow() {
        var state = WatchState(snapshot: snapshot())
        #expect(state.setHabit(habitID, checked: true, now: start) != nil)
        #expect(state.display(at: start)?.habits[0].done == true)
        let automatic = state.snapshot!.habits[1].id
        #expect(state.setHabit(automatic, checked: true, now: start) == nil)
        #expect(state.setHabit(UUID(), checked: true, now: start) == nil)
    }

    @Test func water_isAddedAtOnce() {
        var state = WatchState(snapshot: snapshot())
        state.logWater(milliliters: 250, now: start)
        state.logWater(milliliters: 250, now: start.addingTimeInterval(1))
        #expect(state.display(at: start.addingTimeInterval(2))?.water?.milliliters == 500)
        #expect(state.pendingCount == 2)
    }

    @Test func ingest_addsTheComplicationActions() {
        var state = WatchState(snapshot: snapshot())
        let action = WatchAction(createdAt: start, kind: .completeTask(key: "local:B", version: "7"))
        state.ingest([action, action])
        #expect(state.pendingCount == 1)
        #expect(state.display(at: start.addingTimeInterval(5))?.tasks.map(\.title) == ["A"])
    }

    @Test func staleBeforeFirstSnapshotAndAfterMidnight() {
        #expect(WatchState().isStale(at: start, calendar: calendar))
        let state = WatchState(snapshot: snapshot())
        #expect(!state.isStale(at: start, calendar: calendar))
        #expect(state.isStale(at: instant(2026, 11, 21, 0, 5), calendar: calendar))
    }

    @Test func expiredActions_areCountedForTheNotice() {
        var state = WatchState(snapshot: snapshot())
        state.completeTask(task("A"), now: start)
        state.dropExpired(now: start.addingTimeInterval(49 * 3600))
        #expect(state.droppedCount == 1)
        state.clearDroppedNotice()
        #expect(state.droppedCount == 0)
    }
}
