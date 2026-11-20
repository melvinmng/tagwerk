import Foundation

/// Everything the watch app knows: the last snapshot of the phone, the actions that wait for delivery, and the
/// "Rückgängig" offer of the last tap. A pure value, so the rules are tested on the phone's simulator; the app
/// keeps it in an `@Observable` shell and stores the parts in files.
public struct WatchState: Sendable, Equatable {
    /// The offer of the line "Rückgängig" after a tap.
    public struct UndoOffer: Sendable, Equatable {
        public enum Subject: Sendable, Equatable {
            case task(title: String)
            case habit(name: String, checked: Bool)
            case water(milliliters: Int)
        }

        public var actionID: UUID
        public var subject: Subject
        public var expiresAt: Date
    }

    /// A checked task stays visible (as checked) for this long, then it leaves the list.
    public static let vanishDelay: TimeInterval = 1
    /// How long "Rückgängig" is offered.
    public static let undoWindow: TimeInterval = 5

    public private(set) var snapshot: WatchSnapshot?
    public private(set) var queue: WatchActionQueue
    public private(set) var undoOffer: UndoOffer?

    public init(snapshot: WatchSnapshot? = nil, queue: WatchActionQueue = WatchActionQueue()) {
        self.snapshot = snapshot
        self.queue = queue
    }

    // MARK: From the phone

    /// A snapshot arrived: keeps the newest one and removes the actions the phone reports as applied.
    public mutating func receive(_ incoming: WatchSnapshot) {
        if let current = snapshot, incoming.createdAt < current.createdAt { return }
        snapshot = incoming
        queue.acknowledge(incoming.appliedActionIDs)
    }

    /// The phone answered a direct message: the action is done.
    public mutating func acknowledge(_ id: UUID) {
        queue.acknowledge([id])
    }

    /// Actions recorded by the complications' buttons join the queue.
    public mutating func ingest(_ actions: [WatchAction]) {
        for action in actions { queue.enqueue(action) }
    }

    // MARK: Taps

    @discardableResult
    public mutating func completeTask(_ task: WatchTask, now: Date) -> WatchAction {
        let action = WatchAction(createdAt: now, kind: .completeTask(key: task.key, version: task.version))
        record(action, subject: .task(title: task.title), now: now)
        return action
    }

    /// `nil` when the habit cannot be changed (automatic) or is not in the snapshot.
    @discardableResult
    public mutating func setHabit(_ id: UUID, checked: Bool, now: Date) -> WatchAction? {
        guard let habit = snapshot?.habits.first(where: { $0.id == id }), habit.isCheckable else { return nil }
        let action = WatchAction(createdAt: now, kind: .checkHabit(id: id, on: checked))
        record(action, subject: .habit(name: habit.name, checked: checked), now: now)
        return action
    }

    @discardableResult
    public mutating func logWater(milliliters: Int, now: Date) -> WatchAction {
        let action = WatchAction(createdAt: now, kind: .logWater(milliliters: milliliters, entryID: UUID()))
        record(action, subject: .water(milliliters: milliliters), now: now)
        return action
    }

    private mutating func record(_ action: WatchAction, subject: UndoOffer.Subject, now: Date) {
        queue.enqueue(action)
        undoOffer = UndoOffer(actionID: action.id, subject: subject, expiresAt: now.addingTimeInterval(Self.undoWindow))
    }

    // MARK: Undo

    /// The offer while it is valid.
    public func activeUndoOffer(at now: Date) -> UndoOffer? {
        guard let undoOffer, undoOffer.expiresAt > now else { return nil }
        return undoOffer
    }

    /// Takes the last tap back: drops it when it has not left the watch, otherwise queues the counter-action.
    /// `nil` when there is nothing to take back.
    @discardableResult
    public mutating func undoLast(now: Date) -> WatchActionQueue.UndoOutcome? {
        guard let offer = activeUndoOffer(at: now) else { return nil }
        undoOffer = nil
        return queue.requestUndo(of: offer.actionID, at: now)
    }

    // MARK: Display

    /// The snapshot as the screen shows it: the pending actions are carried out, except the check-off of a task
    /// that is younger than `vanishDelay`. `nil` before the first snapshot.
    public func display(at now: Date) -> WatchSnapshot? {
        snapshot?.applying(visibleActions(at: now))
    }

    /// The keys of tasks that were just checked and are about to leave the list.
    public func completingKeys(at now: Date) -> Set<String> {
        Set(queue.entries.compactMap { entry -> String? in
            guard case .completeTask(let key, _) = entry.action.kind, isYoung(entry.action, at: now) else { return nil }
            return key
        })
    }

    private func visibleActions(at now: Date) -> [WatchAction] {
        let all = queue.entries.map(\.action)
        let undone = Set(all.compactMap { action -> UUID? in
            if case .undo(let target) = action.kind { return target }
            return nil
        })
        // A young check-off is shown as checked in place, so it is not applied yet; an undone one never is.
        return all.filter { action in
            if case .completeTask = action.kind, isYoung(action, at: now), !undone.contains(action.id) { return false }
            return true
        }
    }

    private func isYoung(_ action: WatchAction, at now: Date) -> Bool {
        now.timeIntervalSince(action.createdAt) < Self.vanishDelay
    }

    // MARK: Hints

    public var pendingCount: Int { queue.count }
    public var droppedCount: Int { queue.droppedCount }

    public mutating func dropExpired(now: Date) {
        queue.dropExpired(now: now)
    }

    public mutating func clearDroppedNotice() {
        queue.clearDroppedNotice()
    }

    public func pending(now: Date) -> [WatchAction] {
        queue.pending(now: now)
    }

    public mutating func markSent(_ id: UUID, at now: Date) {
        queue.markSent(id, at: now)
    }

    /// The watch shows "Öffne Tagwerk auf dem iPhone" instead of old data.
    public func isStale(at now: Date, calendar: Calendar) -> Bool {
        snapshot?.isStale(at: now, calendar: calendar) ?? true
    }
}
