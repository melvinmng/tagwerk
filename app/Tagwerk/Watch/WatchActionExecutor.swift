import Foundation
import TagwerkCore

/// What carrying out one watch action came to.
enum WatchActionResult: Equatable, Sendable {
    /// Done, or nothing left to do (the task is gone, the habit was checked before).
    case done
    /// Could not be carried out now; the watch keeps the action queued.
    case later
}

@MainActor
protocol WatchActionPerforming: AnyObject {
    func perform(_ action: WatchAction) async -> WatchActionResult
}

/// Carries out the actions of the watch with the same code paths as the app, Siri and the controls: completing goes
/// through `TaskListModel.complete` (block cutting, effort, undo capsule), habits and water through `IntentServices`.
@MainActor
final class WatchActionExecutor: WatchActionPerforming {
    /// What takes an action back.
    private enum UndoStep {
        case reopen(TaskItem)
        case setHabit(UUID, checked: Bool)
        case deleteWater(UUID)
    }

    private let environment: AppEnvironment
    private let services: IntentServices
    private let loadTimeout: Duration
    private var undoSteps: [UUID: UndoStep] = [:]
    private var undoOrder: [UUID] = []
    /// Steps kept in memory; an undo arrives seconds after the action, so a few dozen are plenty.
    private static let maximumUndoSteps = 50

    init(environment: AppEnvironment, services: IntentServices, loadTimeout: Duration = .seconds(8)) {
        self.environment = environment
        self.services = services
        self.loadTimeout = loadTimeout
    }

    func perform(_ action: WatchAction) async -> WatchActionResult {
        switch action.kind {
        case .completeTask(let key, _):
            return await complete(key: key, actionID: action.id)
        case .checkHabit(let id, let checked):
            return await setHabit(id, checked: checked, actionID: action.id)
        case .logWater(let milliliters, let entryID):
            _ = await services.logWater(milliliters: milliliters, entryID: entryID)
            remember(.deleteWater(entryID), for: action.id)
            return .done
        case .undo(let target):
            return await undo(target)
        }
    }

    // MARK: Tasks

    /// The version of the action is the one the watch displayed. It is not compared: the edit touches only the
    /// completion, and the source still checks its own version when it writes.
    private func complete(key: String, actionID: UUID) async -> WatchActionResult {
        guard let id = TaskID(key: key) else { return .done }
        let taskList = environment.taskList
        if !taskList.items.contains(where: { $0.id == id }) {
            // The app was started in the background for this action: nothing is loaded yet.
            let environment = self.environment
            guard await Self.finishes(within: loadTimeout, { await environment.loadTasksInBackground() }) else { return .later }
        }
        // Gone or done on the phone meanwhile: nothing to do, the next snapshot removes the row on the watch.
        guard taskList.items.contains(where: { $0.id == id && !$0.isCompleted }) else { return .done }
        let before = taskList.lastCompleted
        await taskList.complete(id)
        guard let completed = taskList.lastCompleted, completed.id == id, completed != before else {
            return taskList.items.contains(where: { $0.id == id && !$0.isCompleted }) ? .later : .done
        }
        // The item as the source wrote it, with the version a reopening has to match.
        remember(.reopen(completed), for: actionID)
        return .done
    }

    // MARK: Habits

    private func setHabit(_ id: UUID, checked: Bool, actionID: UUID) async -> WatchActionResult {
        let habits = environment.habits
        habits.refreshLocal(notify: false)
        guard habits.rows(for: habits.today).contains(where: { $0.id == id }) else { return .done }
        let wasChecked = habits.facts.manualChecks[id]?.contains(habits.today) == true
        guard wasChecked != checked else { return .done }
        if checked {
            _ = await services.checkHabit(id: id)
        } else {
            await habits.uncheckToday(id)
            environment.writeSnapshot()
        }
        remember(.setHabit(id, checked: !checked), for: actionID)
        return .done
    }

    // MARK: Undo

    private func undo(_ target: UUID) async -> WatchActionResult {
        // Lost with the process (a restart between the action and its undo): the undo has nothing to take back.
        guard let step = undoSteps.removeValue(forKey: target) else { return .done }
        undoOrder.removeAll { $0 == target }
        switch step {
        case .reopen(let item):
            let taskList = environment.taskList
            // The version of the completion is stale after a moment; `undoComplete` retries against the current one.
            if taskList.lastCompleted?.id == item.id {
                await taskList.undoComplete()
            } else {
                await taskList.reopen(item)
            }
        case .setHabit(let id, let checked):
            if checked {
                _ = await services.checkHabit(id: id)
            } else {
                await environment.habits.uncheckToday(id)
                environment.writeSnapshot()
            }
        case .deleteWater(let entryID):
            await environment.capture.removeEntry(entryID)
            // Like `IntentServices.logWater`: the Health deletion finishes before a background start suspends again.
            await environment.capture.waitForHealth()
            environment.writeSnapshot()
        }
        return .done
    }

    private func remember(_ step: UndoStep, for actionID: UUID) {
        undoSteps[actionID] = step
        undoOrder.append(actionID)
        if undoOrder.count > Self.maximumUndoSteps {
            undoSteps.removeValue(forKey: undoOrder.removeFirst())
        }
    }

    // MARK: Timeout

    /// Runs `work` and reports whether it finished within `timeout`. Work that overruns keeps running.
    private static func finishes(within timeout: Duration, _ work: @escaping @MainActor () async -> Void) async -> Bool {
        let race = Race()
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                await work()
                race.resume(continuation, with: true)
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                race.resume(continuation, with: false)
            }
        }
    }

    @MainActor
    private final class Race {
        private var finished = false

        func resume(_ continuation: CheckedContinuation<Bool, Never>, with value: Bool) {
            guard !finished else { return }
            finished = true
            continuation.resume(returning: value)
        }
    }
}
