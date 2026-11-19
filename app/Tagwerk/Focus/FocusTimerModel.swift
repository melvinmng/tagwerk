import Foundation
import Observation
import TagwerkCore

/// The focus timer: one session at a time, started from a time block, a task or freely.
///
/// The state of a session is only its timestamps (`FocusTimerState`); phase and remaining time are computed from them
/// at the moment they are shown, so closing or losing the app never loses time. The Live Activity and the single
/// notification are brought in line after every change and after every restart.
@MainActor
@Observable
final class FocusTimerModel {
    /// The running session as the views see it.
    struct Session: Equatable {
        let id: UUID
        let taskKey: String?
        let blockEventID: String?
        /// Title of the task or block; empty for a free session. Stays on the device.
        let title: String
        var state: FocusTimerState
    }

    /// A session older than this is treated as lost when the app starts again.
    static let staleAge: TimeInterval = 12 * 3600

    private(set) var session: Session?
    /// The focus sheet is shown.
    var isPresented = false
    /// The piece the last ended session left, for the line "Stück gewachsen"; `nil` when none.
    private(set) var lastPiece: FocusRewardPiece?
    /// Completes a task of the list (`TaskID.key`); set by the app environment.
    @ObservationIgnored var completeTask: ((String) async -> Void)?
    /// Moves a task to tomorrow (`TaskID.key`); set by the app environment.
    @ObservationIgnored var postponeTask: ((String) async -> Void)?

    @ObservationIgnored private let store: FocusStore
    @ObservationIgnored private let settings: () -> FocusTimerSettings
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored private let activity: FocusActivityControlling
    @ObservationIgnored private let notifications: FocusNotificationScheduling
    @ObservationIgnored private let wakesAtPhaseEnd: Bool
    @ObservationIgnored private var record: FocusSessionRecord?
    /// A link of the Live Activity arrived before the session was restored; the sheet opens once it is.
    @ObservationIgnored var showsWhenRestored = false
    @ObservationIgnored private var wake: Task<Void, Never>?

    init(store: FocusStore, settings: @escaping () -> FocusTimerSettings, activity: FocusActivityControlling,
         notifications: FocusNotificationScheduling, now: @escaping () -> Date = Date.init, wakesAtPhaseEnd: Bool = true) {
        self.store = store
        self.settings = settings
        self.activity = activity
        self.notifications = notifications
        self.now = now
        self.wakesAtPhaseEnd = wakesAtPhaseEnd
    }

    var isRunning: Bool { session != nil }

    /// The state of the running session at `date`.
    func snapshot(at date: Date) -> FocusTimerSnapshot? {
        session.map { FocusTimerRules.snapshot(of: $0.state, at: date) }
    }

    /// Whether the running session belongs to this task (`TaskID.key`).
    func isRunning(forTaskKey key: String) -> Bool { session?.taskKey == key }

    // MARK: Start and control

    /// Starts a session. While one runs, it is shown instead. A block without Pomodoro sets the work time to what is left
    /// of the block (at least 5 minutes).
    func start(task: TaskItem?, block: CalendarEvent?) async {
        guard session == nil else {
            isPresented = true
            return
        }
        let moment = now()
        var timerSettings = settings()
        if let block, !timerSettings.isPomodoro {
            let remaining = block.end.timeIntervalSince(max(moment, block.start))
            timerSettings.workMinutes = max(FocusTimerSettings.workRange.lowerBound, Int((remaining / 60).rounded(.up)))
            timerSettings = timerSettings.clamped
        }
        let state = FocusTimerState(start: moment, settings: timerSettings)
        let new = FocusSessionRecord(taskKey: task?.id.key, blockEventID: block?.id, title: task?.title ?? block?.title ?? "", state: state)
        store.insert(new)
        record = new
        session = Session(id: new.id, taskKey: new.taskKey, blockEventID: new.blockEventID, title: new.title, state: state)
        lastPiece = nil
        isPresented = true
        if let content = currentContent() { await activity.start(content) }
        await syncOutputs()
    }

    func pause() async {
        guard var current = session, current.state.pausedSince == nil, snapshot(at: now())?.phase != .finished else { return }
        current.state.pausedSince = now()
        update(current)
        await syncOutputs()
    }

    func resume() async {
        guard var current = session, let since = current.state.pausedSince else { return }
        current.state.pauses.append(DateInterval(start: since, end: max(since, now())))
        current.state.pausedSince = nil
        update(current)
        await syncOutputs()
    }

    /// Ends a running break at once; the next work phase starts now.
    func skipBreak() async {
        guard session != nil, let snap = snapshot(at: now()), snap.phase.isBreak else { return }
        if snap.isPaused { await resume() }
        guard var current = session else { return }
        current.state.skips.append(now())
        update(current)
        await syncOutputs()
    }

    /// The user gives up. Within the first minute nothing is left of the session; later its piece wilts.
    func stop() async {
        guard let snap = snapshot(at: now()) else { return }
        await end(snap.phase == .finished ? .completed : FocusReward.outcomeOfStop(focusedSeconds: snap.focusedSeconds))
    }

    /// The choices at the end of a phase or of the whole session. The session is ended and saved before the task is
    /// changed, so the effort of the completion sees this session's focus time.
    func finish(_ action: FocusEndAction) async {
        guard let current = session, let snap = snapshot(at: now()) else { return }
        switch action {
        case .complete:
            await end(.completed)
            if let key = current.taskKey { await completeTask?(key) }
        case .postpone:
            await end(snap.phase.isWork ? FocusReward.outcomeOfStop(focusedSeconds: snap.focusedSeconds) : .completed)
            if let key = current.taskKey { await postponeTask?(key) }
        case .keepGoing:
            if snap.phase.isBreak {
                await skipBreak()
            } else if snap.phase == .finished {
                // A finished session is closed with its piece, the next one starts for the same task.
                await end(.completed)
                await startFollowUp(of: current)
            }
        }
    }

    /// The task was completed somewhere else (list, assistant). Its running session ends as completed.
    func didComplete(taskKey: String) async {
        guard session?.taskKey == taskKey else { return }
        await end(.completed)
    }

    // MARK: Restart

    /// Takes over a session from the store after the app started again, or brings the outputs back in line after it came
    /// to the foreground. A session older than 12 hours is ended; the Live Activity is taken over, never doubled.
    func restore() async {
        // A link that came in before the restore opens the sheet, but only for a session that is really there.
        defer {
            if showsWhenRestored && session != nil { isPresented = true }
            showsWhenRestored = false
        }
        if session != nil {
            await syncOutputs()
            return
        }
        let open = store.openSessions().sorted { $0.start > $1.start }
        guard let newest = open.first else {
            if activity.adopt() { await activity.end() }
            return
        }
        for leftover in open.dropFirst() { close(leftover, at: now(), as: nil) }
        let moment = now()
        if moment.timeIntervalSince(newest.start) > Self.staleAge {
            close(newest, at: moment, as: nil)
            if activity.adopt() { await activity.end() }
            await notifications.cancel()
            return
        }
        record = newest
        session = Session(id: newest.id, taskKey: newest.taskKey, blockEventID: newest.blockEventID, title: newest.title, state: newest.state)
        if !activity.adopt(), let content = currentContent() { await activity.start(content) }
        await syncOutputs()
    }

    /// Brings the Live Activity and the notification in line with the current phase.
    func refresh() async {
        await syncOutputs()
    }

    // MARK: Private

    private func startFollowUp(of previous: Session) async {
        let moment = now()
        let state = FocusTimerState(start: moment, settings: previous.state.settings)
        let new = FocusSessionRecord(taskKey: previous.taskKey, blockEventID: previous.blockEventID, title: previous.title, state: state)
        store.insert(new)
        record = new
        session = Session(id: new.id, taskKey: new.taskKey, blockEventID: new.blockEventID, title: new.title, state: state)
        isPresented = true
        if let content = currentContent() { await activity.start(content) }
        await syncOutputs()
    }

    private func update(_ changed: Session) {
        session = changed
        record?.apply(changed.state)
        store.save()
    }

    private func currentContent() -> FocusActivityContent? {
        guard let session, let snap = snapshot(at: now()) else { return nil }
        return FocusActivityContent(title: session.title, state: session.state, snapshot: snap)
    }

    private func syncOutputs() async {
        guard let session, let snap = snapshot(at: now()), let content = currentContent() else { return }
        await activity.update(content)
        if let phaseEnd = snap.phaseEnd {
            let kind = FocusActivityContent(title: "", state: session.state, snapshot: snap).kind
            await notifications.schedule(FocusPhaseNotice(endingKind: kind, fireDate: phaseEnd,
                                                          taskTitle: session.title.isEmpty ? nil : session.title, taskKey: session.taskKey))
        } else {
            await notifications.cancel()
        }
        scheduleWake(at: snap.phaseEnd)
    }

    /// Syncs the outputs again right after the phase ended while the app is in use. State itself never depends on it.
    private func scheduleWake(at phaseEnd: Date?) {
        wake?.cancel()
        guard wakesAtPhaseEnd, let phaseEnd else { return }
        let delay = max(0.5, phaseEnd.timeIntervalSince(now()) + 0.5)
        wake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Ends the running session with `outcome` and removes the Live Activity and the notification.
    private func end(_ outcome: FocusOutcome) async {
        guard let record else { return }
        close(record, at: now(), as: outcome)
        wake?.cancel()
        session = nil
        isPresented = false
        self.record = nil
        await activity.end()
        await notifications.cancel()
    }

    /// Writes the end of a session. Without `outcome` it is derived: a session that ran through is completed, any other
    /// is aborted, or discarded when under a minute.
    private func close(_ record: FocusSessionRecord, at moment: Date, as outcome: FocusOutcome?) {
        var state = record.state
        if let since = state.pausedSince {
            state.pauses.append(DateInterval(start: since, end: max(since, moment)))
            state.pausedSince = nil
        }
        let before = FocusTimerRules.snapshot(of: state, at: moment)
        let ended = before.finishedAt.map { min($0, moment) } ?? moment
        state.endedAt = outcome == nil ? ended : moment
        let snap = FocusTimerRules.snapshot(of: state, at: moment)
        record.apply(state)
        record.focusedSeconds = snap.focusedSeconds
        record.outcome = outcome ?? (before.phase == .finished ? .completed : FocusReward.outcomeOfStop(focusedSeconds: snap.focusedSeconds))
        lastPiece = record.piece
        store.save()
    }
}
