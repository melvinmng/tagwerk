/// Decides whether a new assistant answer is read aloud without an explicit tap.
public enum ReadAloudPolicy: String, CaseIterable, Sendable {
    case never
    case afterSpoken
    case always

    public func readsAutomatically(lastUserMessageWasSpoken: Bool, conversationVisible: Bool) -> Bool {
        guard conversationVisible else { return false }
        switch self {
        case .never: return false
        case .afterSpoken: return lastUserMessageWasSpoken
        case .always: return true
        }
    }

    public var title: String {
        switch self {
        case .never: String(localized: "Nie", bundle: .module)
        case .afterSpoken: String(localized: "Nach gesprochenen Nachrichten", bundle: .module)
        case .always: String(localized: "Immer", bundle: .module)
        }
    }
}
