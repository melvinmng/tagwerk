import ActivityKit
import Foundation

/// Data of the focus timer's Live Activity. Shared by the app and the widget extension. It holds only what is shown on
/// the lock screen and in the Dynamic Island, never notes.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Kind: String, Codable, Hashable, Sendable {
            case work, shortBreak, longBreak, finished
        }

        var kind: Kind
        /// End of the running phase; `nil` while paused or finished.
        var phaseEnd: Date?
        /// Seconds left while the timer is paused.
        var pausedRemaining: Int?
        var round: Int
        var rounds: Int
        // The fields below are optional, so an activity that runs while the app is updated still decodes.
        /// Planned length of the running phase in seconds, for the bar and the ring.
        var phaseSeconds: Int?
        /// The phase that follows; `nil` when the session ends.
        var nextKind: Kind?
        var nextPhaseMinutes: Int?
    }

    /// Title of the task or block; empty for a free session.
    var title: String
    var isPomodoro: Bool
    /// Whether the session belongs to a task, so "Erledigt" has something to tick off; `nil` for an older activity.
    var hasTask: Bool? = nil
}

/// The link a tap on the Live Activity opens.
enum FocusLink {
    static let url = URL(string: "tagwerk://focus")!
}
