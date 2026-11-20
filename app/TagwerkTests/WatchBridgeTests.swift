import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
private final class FakeWatchSession: WatchSessioning {
    var isSupported = true
    var canSendContext = true
    var onAction: (@MainActor (Data) async -> WatchReply)?
    var onReady: (@MainActor () -> Void)?
    private(set) var activations = 0
    private(set) var contexts: [Data] = []

    func activate() { activations += 1 }

    func sendContext(_ snapshot: Data) throws { contexts.append(snapshot) }
}

@MainActor
private final class CountingExecutor: WatchActionPerforming {
    private(set) var performed: [UUID] = []
    var result = WatchActionResult.done
    /// Time the action takes, so concurrent repeats overlap it.
    var delay = Duration.zero

    func perform(_ action: WatchAction) async -> WatchActionResult {
        try? await Task.sleep(for: delay)
        performed.append(action.id)
        return result
    }
}

@MainActor
struct WatchBridgeTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "watch-bridge-\(UUID().uuidString)")

    private func snapshot(applied: [UUID] = []) -> WatchSnapshot {
        let calendar = Calendar.tagwerk(locale: .current)
        return WatchSnapshot(createdAt: .now, day: PlanDay(date: .now, calendar: calendar), entries: [], tasks: [], habits: [],
                             habitCounter: nil, water: nil, appliedActionIDs: applied)
    }

    private func makeBridge(session: FakeWatchSession, executor: any WatchActionPerforming) -> WatchBridge {
        WatchBridge(session: session, executor: executor, snapshotProvider: { [self] applied in snapshot(applied: applied) },
                    directory: directory, debounce: .milliseconds(30))
    }

    private func data(_ kind: WatchAction.Kind, id: UUID = UUID()) throws -> (UUID, Data) {
        let action = WatchAction(id: id, createdAt: .now, kind: kind)
        return (action.id, try action.encoded())
    }

    /// Waits until `condition` holds (the debounce runs in the background).
    private func wait(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    // MARK: Real models

    private func makeEnvironment() throws -> (AppEnvironment, IntentServices) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let environment = try AppEnvironment(modelContainer: container, notificationCenter: FakeNotificationCenter(),
                                             health: FakeHealthStore(), focusNotificationCenter: FakeFocusNotificationCenter())
        environment.settings.setupCompleted = true
        return (environment, IntentServices(environment: environment))
    }

    private func today(_ environment: AppEnvironment) -> DueDate {
        DueDate(date: .now, includeTime: false, calendar: environment.planning.calendar)
    }

    // MARK: Tests

    @Test func duplicateActionID_isAppliedOnce() async throws {
        let executor = CountingExecutor()
        executor.delay = .milliseconds(40)
        let bridge = makeBridge(session: FakeWatchSession(), executor: executor)
        let (id, payload) = try data(.completeTask(key: "local:x", version: "1"))
        // Three deliveries of the same action, two of them while the first is still running.
        async let first = bridge.handle(payload)
        async let second = bridge.handle(payload)
        async let third = bridge.handle(payload)
        _ = await (first, second, third)
        _ = await bridge.handle(payload)
        #expect(executor.performed == [id])
    }

    @Test func actionsAreAppliedInArrivalOrder() async throws {
        let executor = CountingExecutor()
        executor.delay = .milliseconds(10)
        let bridge = makeBridge(session: FakeWatchSession(), executor: executor)
        let ids = try (0..<4).map { index -> (UUID, Data) in try data(.completeTask(key: "local:\(index)", version: "1")) }
        // Tasks created in a row on the main actor start in that order.
        let replies = ids.map { entry in Task { @MainActor in await bridge.handle(entry.1) } }
        for reply in replies { _ = await reply.value }
        #expect(executor.performed == ids.map(\.0))
    }

    @Test func laterResult_isNotRemembered_andRetried() async throws {
        let executor = CountingExecutor()
        executor.result = .later
        let bridge = makeBridge(session: FakeWatchSession(), executor: executor)
        let (id, payload) = try data(.completeTask(key: "local:x", version: "1"))
        #expect(await bridge.handle(payload) == .later)
        executor.result = .done
        #expect(await bridge.handle(payload) == .done)
        #expect(executor.performed == [id, id])
    }

    @Test func appliedIDs_surviveARestart() async throws {
        let executor = CountingExecutor()
        let first = makeBridge(session: FakeWatchSession(), executor: executor)
        let (_, payload) = try data(.completeTask(key: "local:x", version: "1"))
        _ = await first.handle(payload)
        let second = makeBridge(session: FakeWatchSession(), executor: executor)
        _ = await second.handle(payload)
        #expect(executor.performed.count == 1)
    }

    @Test func undoThatOvertakesItsAction_skipsTheAction() async throws {
        let executor = CountingExecutor()
        let bridge = makeBridge(session: FakeWatchSession(), executor: executor)
        let (originalID, original) = try data(.logWater(milliliters: 250, entryID: UUID()))
        let (_, undo) = try data(.undo(of: originalID))
        _ = await bridge.handle(undo)
        _ = await bridge.handle(original)
        #expect(executor.performed.isEmpty)
    }

    @Test func completeMissingTask_isIgnoredAndSnapshotIsResent() async throws {
        let (environment, services) = try makeEnvironment()
        let session = FakeWatchSession()
        let executor = WatchActionExecutor(environment: environment, services: services, loadTimeout: .milliseconds(500))
        let bridge = makeBridge(session: session, executor: executor)
        // The task was completed or deleted on the phone; the watch still shows it.
        let created = try #require(await environment.taskList.create(TaskDraft(title: "Done on the phone", due: today(environment)), in: .local))
        await environment.taskList.complete(created.id)
        let (id, payload) = try data(.completeTask(key: created.id.key, version: created.version))
        #expect(await bridge.handle(payload) == .done)
        #expect(environment.taskList.lastCompleted?.id == created.id)
        await wait { !session.contexts.isEmpty }
        let sent = try #require(session.contexts.last.flatMap(WatchSnapshot.decode))
        #expect(sent.appliedActionIDs == [id])
        // A malformed key is ignored as well.
        let (_, junk) = try data(.completeTask(key: "no-source", version: "1"))
        #expect(await bridge.handle(junk) == .done)
    }

    @Test func completeTask_completesOnce_andUndoReopensIt() async throws {
        let (environment, services) = try makeEnvironment()
        let executor = WatchActionExecutor(environment: environment, services: services, loadTimeout: .milliseconds(500))
        let bridge = makeBridge(session: FakeWatchSession(), executor: executor)
        let created = try #require(await environment.taskList.create(TaskDraft(title: "Write report", due: today(environment)), in: .local))
        let (actionID, payload) = try data(.completeTask(key: created.id.key, version: created.version))
        #expect(await bridge.handle(payload) == .done)
        #expect(!environment.taskList.items.contains { $0.id == created.id })
        #expect(await bridge.handle(payload) == .done)  // a repeat does nothing
        let (_, undo) = try data(.undo(of: actionID))
        #expect(await bridge.handle(undo) == .done)
        let reopened = try #require(environment.taskList.items.first { $0.id == created.id })
        #expect(!reopened.isCompleted)
    }

    @Test func undoAfterApply_reopensTask_evenWhenAnotherTaskWasCompletedLast() async throws {
        let (environment, services) = try makeEnvironment()
        let executor = WatchActionExecutor(environment: environment, services: services, loadTimeout: .milliseconds(500))
        let bridge = makeBridge(session: FakeWatchSession(), executor: executor)
        let first = try #require(await environment.taskList.create(TaskDraft(title: "First", due: today(environment)), in: .local))
        let second = try #require(await environment.taskList.create(TaskDraft(title: "Second", due: today(environment)), in: .local))
        let (firstAction, firstPayload) = try data(.completeTask(key: first.id.key, version: first.version))
        let (_, secondPayload) = try data(.completeTask(key: second.id.key, version: second.version))
        _ = await bridge.handle(firstPayload)
        _ = await bridge.handle(secondPayload)
        let (_, undo) = try data(.undo(of: firstAction))
        _ = await bridge.handle(undo)
        #expect(environment.taskList.items.contains { $0.id == first.id && !$0.isCompleted })
        #expect(!environment.taskList.items.contains { $0.id == second.id })
    }

    @Test func logWater_undo_deletesThatEntry() async throws {
        let (environment, services) = try makeEnvironment()
        let executor = WatchActionExecutor(environment: environment, services: services)
        let bridge = makeBridge(session: FakeWatchSession(), executor: executor)
        let calendar = environment.capture.calendar
        let day = PlanDay(date: .now, calendar: calendar)
        let keptEntry = UUID(), watchEntry = UUID()
        _ = await bridge.handle(try data(.logWater(milliliters: 330, entryID: keptEntry)).1)
        let (actionID, payload) = try data(.logWater(milliliters: 250, entryID: watchEntry))
        _ = await bridge.handle(payload)
        #expect(environment.intake.drinks(on: day, calendar: calendar).map(\.id).contains(watchEntry))
        #expect(environment.capture.undo == nil)
        _ = await bridge.handle(try data(.undo(of: actionID)).1)
        let remaining = environment.intake.drinks(on: day, calendar: calendar)
        #expect(remaining.map(\.id) == [keptEntry])
        #expect(environment.capture.undo == nil)  // no "Eintrag gelöscht" bar on the phone
    }

    @Test func checkHabit_checksAndUnchecks_andUndo() async throws {
        let (environment, services) = try makeEnvironment()
        let executor = WatchActionExecutor(environment: environment, services: services)
        let bridge = makeBridge(session: FakeWatchSession(), executor: executor)
        let habit = Habit(name: "Lesen", symbol: "book", order: 0, start: environment.habits.today)
        environment.habits.save(habit)
        func isChecked() -> Bool {
            environment.habits.refreshLocal(notify: false)
            return environment.habits.facts.manualChecks[habit.id]?.contains(environment.habits.today) == true
        }
        let (checkAction, check) = try data(.checkHabit(id: habit.id, on: true))
        _ = await bridge.handle(check)
        #expect(isChecked())
        _ = await bridge.handle(try data(.undo(of: checkAction)).1)
        #expect(!isChecked())
        _ = await bridge.handle(try data(.checkHabit(id: habit.id, on: true)).1)
        _ = await bridge.handle(try data(.checkHabit(id: habit.id, on: false)).1)
        #expect(!isChecked())
        // A habit that is gone is ignored.
        #expect(await bridge.handle(try data(.checkHabit(id: UUID(), on: true)).1) == .done)
    }

    @Test func snapshot_isSentAfterChanges_debounced() async throws {
        let session = FakeWatchSession()
        let bridge = makeBridge(session: session, executor: CountingExecutor())
        for _ in 0..<5 { bridge.snapshotInputsChanged() }
        await wait { !session.contexts.isEmpty }
        try await Task.sleep(for: .milliseconds(150))
        #expect(session.contexts.count == 1)
        // The same content is not sent again; a forced send (the watch just became ready) is.
        bridge.snapshotInputsChanged()
        try await Task.sleep(for: .milliseconds(150))
        #expect(session.contexts.count == 1)
        bridge.sendSnapshot(force: true)
        #expect(session.contexts.count == 2)
    }

    @Test func snapshot_waitsForAPairedWatchWithTheApp() async throws {
        let session = FakeWatchSession()
        session.canSendContext = false
        let bridge = makeBridge(session: session, executor: CountingExecutor())
        bridge.sendSnapshot(force: true)
        #expect(session.contexts.isEmpty)
    }

    @Test func unsupportedSession_doesNothing() async throws {
        let session = FakeWatchSession()
        session.isSupported = false
        let bridge = makeBridge(session: session, executor: CountingExecutor())
        bridge.start()
        bridge.snapshotInputsChanged()
        bridge.sendSnapshot(force: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(session.activations == 0)
        #expect(session.contexts.isEmpty)
        #expect(session.onAction == nil)
    }

    @Test func start_activatesTheSession_andSendsWhenReady() async throws {
        let session = FakeWatchSession()
        let bridge = makeBridge(session: session, executor: CountingExecutor())
        bridge.start()
        #expect(session.activations == 1)
        session.onReady?()
        #expect(session.contexts.count == 1)
    }
}
