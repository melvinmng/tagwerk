import Foundation
import TagwerkCore

/// What the Live Activity shows. Plain data, so the timer model needs no ActivityKit and tests can use fakes.
struct FocusActivityContent: Equatable, Sendable {
    enum Kind: String, Sendable, Codable {
        case work, shortBreak, longBreak, finished
    }

    var title: String
    var isPomodoro: Bool
    var kind: Kind
    var round: Int
    var rounds: Int
    /// End of the running phase; `nil` while paused or finished.
    var phaseEnd: Date?
    /// Seconds left while the timer is paused.
    var pausedRemaining: Int?

    init(title: String, state: FocusTimerState, snapshot: FocusTimerSnapshot) {
        self.title = title
        isPomodoro = state.settings.isPomodoro
        rounds = state.settings.isPomodoro ? state.settings.rounds : 1
        switch snapshot.phase {
        case .work(let round): kind = .work; self.round = round
        case .shortBreak(let round): kind = .shortBreak; self.round = round
        case .longBreak: kind = .longBreak; self.round = rounds
        case .finished: kind = .finished; self.round = rounds
        }
        phaseEnd = snapshot.phaseEnd
        pausedRemaining = snapshot.isPaused ? snapshot.remainingSeconds : nil
    }

    init(title: String, isPomodoro: Bool, kind: Kind, round: Int, rounds: Int, phaseEnd: Date?, pausedRemaining: Int?) {
        self.title = title
        self.isPomodoro = isPomodoro
        self.kind = kind
        self.round = round
        self.rounds = rounds
        self.phaseEnd = phaseEnd
        self.pausedRemaining = pausedRemaining
    }
}

/// The Live Activity of the running session. At most one exists.
@MainActor
protocol FocusActivityControlling: AnyObject {
    /// Takes over a Live Activity that survived an app restart. Returns whether there was one.
    func adopt() -> Bool
    func start(_ content: FocusActivityContent) async
    func update(_ content: FocusActivityContent) async
    /// Ends the Live Activity right away.
    func end() async
}

/// The one notification of the timer: the end of the running phase.
struct FocusPhaseNotice: Equatable, Sendable {
    /// The phase that ends at `fireDate`.
    var endingKind: FocusActivityContent.Kind
    var fireDate: Date
    var taskTitle: String?
    var taskKey: String?
}

@MainActor
protocol FocusNotificationScheduling: AnyObject {
    /// Replaces the pending notification.
    func schedule(_ notice: FocusPhaseNotice) async
    func cancel() async
}

/// What the user can choose when a session has ended (or its phase is over).
enum FocusEndAction: String, Sendable {
    case complete, keepGoing, postpone
}
