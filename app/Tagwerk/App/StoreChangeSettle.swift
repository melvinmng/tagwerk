import Foundation

/// Decides when the app has finished reacting to the EventKit changes that the demo data of the UI test mode causes.
/// The demo data is written through a store of its own; the store of the gateway hears about it with a delay
/// (`.EKEventStoreChanged`) and reloads tasks, plan and shopping list. The UI tests may only start once that echo is handled,
/// otherwise the screen changes under a running accessibility audit.
enum StoreChangeSettle {
    enum State: Equatable {
        case waiting
        case settled
        /// The limit is over without a settled state; the caller continues and logs a warning.
        case timedOut
    }

    /// Time without any further change after which the app counts as settled.
    static let quietTime: TimeInterval = 0.5
    /// Longest wait; a missing echo must not block a run.
    static let limit: TimeInterval = 10

    /// - Parameters:
    ///   - handled: number of changes the app has finished handling now
    ///   - handledBeforeSeed: the same number before the demo data was written
    ///   - isHandling: a change is being handled right now
    ///   - quietFor: seconds since the last handled change (or since one started)
    ///   - waited: seconds since the wait began
    static func state(handled: Int, handledBeforeSeed: Int, isHandling: Bool, quietFor: TimeInterval, waited: TimeInterval) -> State {
        if waited >= limit { return .timedOut }
        if isHandling { return .waiting }
        if handled == handledBeforeSeed { return .waiting }
        return quietFor >= quietTime ? .settled : .waiting
    }
}
