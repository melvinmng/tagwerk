import Foundation

/// How a focus session ended.
public enum FocusOutcome: String, Sendable, Codable, Equatable {
    /// The timer ran through or was finished by the user.
    case completed
    /// The user stopped it early.
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

/// One piece of the collection.
public enum FocusRewardPiece: Sendable, Equatable, Codable {
    case grown(FocusRewardStage)
    case wilted(FocusRewardStage)

    public var stage: FocusRewardStage {
        switch self {
        case .grown(let stage), .wilted(let stage): stage
        }
    }

    public var isWilted: Bool {
        if case .wilted = self { return true }
        return false
    }
}

/// Counts of a collection.
public struct FocusCollectionSummary: Sendable, Equatable {
    public let grown: Int
    public let wilted: Int

    public var total: Int { grown + wilted }
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

    /// The piece a session leaves: grown when completed, wilted when aborted, none when discarded or when less than
    /// a minute was focused.
    public static func piece(focusedMinutes: Int, outcome: FocusOutcome) -> FocusRewardPiece? {
        guard outcome != .discarded, let stage = stage(focusedMinutes: focusedMinutes) else { return nil }
        return outcome == .completed ? .grown(stage) : .wilted(stage)
    }

    public static func summary(of pieces: [FocusRewardPiece]) -> FocusCollectionSummary {
        FocusCollectionSummary(grown: pieces.filter { !$0.isWilted }.count, wilted: pieces.filter(\.isWilted).count)
    }
}
