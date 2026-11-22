import Foundation

/// Where "Bible Study starten" is offered: in the evening wrap-up, in the morning start, in both or nowhere (BS6c). The
/// stored default is the evening, the behaviour from before the choice existed.
public enum BibleStudyOffer: String, Sendable, CaseIterable {
    case evening, morning, both, never

    /// Whether the row is offered in the given routine; every route other than the two routine sheets is `false`.
    public func isOffered(in routine: AppRoute) -> Bool {
        switch (self, routine) {
        case (.both, .routineStart), (.both, .routineEvening), (.morning, .routineStart), (.evening, .routineEvening): true
        default: false
        }
    }
}
