import Foundation

/// How a focus session ended.
public enum FocusOutcome: String, Sendable, Codable, Equatable {
    /// The timer ran through or was finished by the user.
    case completed
    /// The user stopped it before its phase ended; it reads as "ended early" and keeps the stage reached.
    case aborted
    /// Stopped within the first minute; it leaves nothing behind.
    case discarded
}

/// Growth stage of a piece of the collection, 1 (smallest) to 5. Deliberately plain numbers: the look of the
/// stages is a design decision of its own.
public enum FocusRewardStage: Int, Sendable, Codable, CaseIterable, Comparable {
    case one = 1, two, three, four, five

    public static func < (lhs: FocusRewardStage, rhs: FocusRewardStage) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Focus minutes needed for the stage.
    public var minimumMinutes: Int {
        switch self {
        case .one: 1
        case .two: 10
        case .three: 25
        case .four: 50
        case .five: 90
        }
    }
}

/// One piece of the collection: a brick of the stage reached. `endedEarly` marks a session that was stopped before
/// its phase ended; it keeps its stage (FO9b). A task finished early with "Erledigt" is `completed` in its stage.
public enum FocusRewardPiece: Sendable, Equatable, Codable {
    case completed(FocusRewardStage)
    case endedEarly(FocusRewardStage)

    public var stage: FocusRewardStage {
        switch self {
        case .completed(let stage), .endedEarly(let stage): stage
        }
    }

    public var isEndedEarly: Bool {
        if case .endedEarly = self { return true }
        return false
    }
}

/// Counts of a collection.
public struct FocusCollectionSummary: Sendable, Equatable {
    public let completed: Int
    public let endedEarly: Int

    public init(completed: Int, endedEarly: Int) {
        self.completed = completed
        self.endedEarly = endedEarly
    }

    public var total: Int { completed + endedEarly }
}

public enum FocusReward {
    /// A session that is stopped before this much focus time leaves no piece.
    public static let discardSeconds = 60

    /// The outcome of a session that was stopped by the user after `focusedSeconds` of work.
    public static func outcomeOfStop(focusedSeconds: Int) -> FocusOutcome {
        focusedSeconds < discardSeconds ? .discarded : .aborted
    }

    /// The highest stage reached with `focusedMinutes`; `nil` below the first stage.
    public static func stage(focusedMinutes: Int) -> FocusRewardStage? {
        FocusRewardStage.allCases.last { focusedMinutes >= $0.minimumMinutes }
    }

    /// The piece a session leaves: a completed brick when completed, an early-ended brick when aborted, none when
    /// discarded or when less than a minute was focused. `aborted` is stored for sessions the user ended early.
    public static func piece(focusedMinutes: Int, outcome: FocusOutcome) -> FocusRewardPiece? {
        guard outcome != .discarded, let stage = stage(focusedMinutes: focusedMinutes) else { return nil }
        return outcome == .completed ? .completed(stage) : .endedEarly(stage)
    }

    public static func summary(of pieces: [FocusRewardPiece]) -> FocusCollectionSummary {
        FocusCollectionSummary(completed: pieces.filter { !$0.isEndedEarly }.count, endedEarly: pieces.filter(\.isEndedEarly).count)
    }
}
