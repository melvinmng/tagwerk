import Foundation
import Observation
import TagwerkCore
import WatchKit
import WidgetKit

/// The watch app's model: a thin shell around `WatchState` (all rules are tested in `TagwerkCore`) that keeps the
/// snapshot and the queue in files and tells the complications when something changed.
@MainActor
@Observable
final class WatchStore {
    private(set) var state: WatchState
    /// Bumped when a time window ends (a checked task leaves the list, "Rückgängig" disappears), so views redraw.
    private(set) var refreshToken = 0
    @ObservationIgnored let directory: URL?
    @ObservationIgnored var client: WatchSessionClient?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?

    init(directory: URL? = WatchStorage.appDirectory) {
        self.directory = directory
        state = WatchState(snapshot: WatchSnapshot.load(from: directory), queue: WatchActionQueue.load(from: directory))
        refreshFromDisk()
    }

    /// The snapshot as the screen shows it; `nil` before the first one.
    func display(at now: Date = .now) -> WatchSnapshot? {
        _ = refreshToken
        return state.display(at: now)
    }

    func completingKeys(at now: Date = .now) -> Set<String> {
        _ = refreshToken
        return state.completingKeys(at: now)
    }

    func undoOffer(at now: Date = .now) -> WatchState.UndoOffer? {
        _ = refreshToken
        return state.activeUndoOffer(at: now)
    }

    var pendingCount: Int { _ = refreshToken; return state.pendingCount }
    var droppedCount: Int { _ = refreshToken; return state.droppedCount }

    func isStale(at now: Date = .now) -> Bool {
        _ = refreshToken
        return state.isStale(at: now, calendar: .watch)
    }

    // MARK: Taps

    func complete(_ task: WatchTask) {
        state.completeTask(task, now: .now)
        changed(expiresIn: WatchState.vanishDelay)
    }

    func setHabit(_ habit: WatchHabit) {
        guard state.setHabit(habit.id, checked: !habit.done, now: .now) != nil else { return }
        changed()
    }

    func logWater(milliliters: Int) {
        state.logWater(milliliters: milliliters, now: .now)
        changed()
    }

    func undoLast() {
        guard state.undoLast(now: .now) != nil else { return }
        WKInterfaceDevice.current().play(.click)
        changed()
    }

    private func changed(expiresIn delay: TimeInterval? = nil) {
        WKInterfaceDevice.current().play(.success)
        persistQueue()
        refreshToken += 1
        schedule(after: delay ?? WatchState.undoWindow)
        if delay != nil { schedule(after: WatchState.undoWindow) }
        WidgetCenter.shared.reloadAllTimelines()
        client?.flush()
    }

    /// Redraws once a window ended; every call adds one wake-up.
    private func schedule(after delay: TimeInterval) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay + 0.05))
            self?.refreshToken += 1
        }
    }

    // MARK: From the phone and the disk

    func receive(_ snapshot: WatchSnapshot) {
        state.receive(snapshot)
        try? snapshot.write(to: directory)
        persistQueue()
        refreshToken += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    func acknowledge(_ id: UUID) {
        state.acknowledge(id)
        persistQueue()
        refreshToken += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    func markSent(_ id: UUID) {
        state.markSent(id, at: .now)
        persistQueue()
    }

    /// What the complications recorded joins the queue; actions that are too old are dropped and counted.
    func refreshFromDisk() {
        let recorded = WatchActionInbox.drain(from: directory)
        state.ingest(recorded)
        state.dropExpired(now: .now)
        persistQueue()
        refreshToken += 1
    }

    func pendingActions(now: Date = .now) -> [WatchAction] {
        state.pending(now: now)
    }

    func clearDroppedNotice() {
        state.clearDroppedNotice()
        persistQueue()
        refreshToken += 1
    }

    /// For the background refresh: picks up the inbox and sends the queue.
    func refreshAndFlush() async {
        refreshFromDisk()
        client?.flush()
    }

    private func persistQueue() {
        try? state.queue.write(to: directory)
    }
}
