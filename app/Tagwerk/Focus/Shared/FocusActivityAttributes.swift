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
    }

    /// Title of the task or block; empty for a free session.
    var title: String
    var isPomodoro: Bool
}

/// The link a tap on the Live Activity opens.
enum FocusLink {
    static let url = URL(string: "tagwerk://focus")!
}
