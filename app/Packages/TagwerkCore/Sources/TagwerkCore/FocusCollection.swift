import Foundation

/// One brick of the collection: a session of a minute or more (FO8c).
public struct FocusBrick: Sendable, Equatable {
    public let piece: FocusRewardPiece
    public let focusedMinutes: Int

    public init(piece: FocusRewardPiece, focusedMinutes: Int) {
        self.piece = piece
        self.focusedMinutes = focusedMinutes
    }
}

/// A calendar week of the collection: the bricks per weekday and the focus time of the week.
public struct FocusCollectionWeek: Sendable, Equatable, Identifiable {
    public let start: Date
    /// Seven days in the order of the calendar's week, each with its bricks in the order the sessions ended.
    public let days: [[FocusBrick]]
    public let focusedMinutes: Int
    public let summary: FocusCollectionSummary

    public var id: Date { start }

    public init(start: Date, days: [[FocusBrick]], focusedMinutes: Int, summary: FocusCollectionSummary) {
        self.start = start
        self.days = days
        self.focusedMinutes = focusedMinutes
        self.summary = summary
    }
}

public enum FocusCollection {
    /// Gap between two stacked bricks in points.
    public static let brickSpacing = 2.0
    /// Height of a brick per stage 1...5 in points when the column has room.
    public static let stageHeights = [8.0, 14.0, 22.0, 32.0, 44.0]

    /// The collection by calendar week, newest week first. A week without a session does not appear.
    public static func weeks(sessions: [(endedAt: Date, piece: FocusRewardPiece, focusedSeconds: Int)],
                             calendar: Calendar) -> [FocusCollectionWeek] {
        var grouped: [Date: [(endedAt: Date, piece: FocusRewardPiece, focusedSeconds: Int)]] = [:]
        for session in sessions {
            let start = calendar.dateInterval(of: .weekOfYear, for: session.endedAt)?.start ?? calendar.startOfDay(for: session.endedAt)
            grouped[start, default: []].append(session)
        }
        return grouped.keys.sorted(by: >).map { start in
            let ordered = grouped[start, default: []].enumerated()
                .sorted { ($0.element.endedAt, $0.offset) < ($1.element.endedAt, $1.offset) }.map(\.element)
            var days = Array(repeating: [FocusBrick](), count: 7)
            var seconds = 0
            for session in ordered {
                let offset = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: session.endedAt)).day ?? 0
                days[min(max(offset, 0), 6)].append(FocusBrick(piece: session.piece, focusedMinutes: session.focusedSeconds / 60))
                seconds += session.focusedSeconds
            }
            return FocusCollectionWeek(start: start, days: days, focusedMinutes: seconds / 60,
                                       summary: FocusReward.summary(of: ordered.map(\.piece)))
        }
    }

    /// Height of a brick in points for a column of `available` points that holds `bricks`; stages 1...5 map to
    /// 8, 14, 22, 32, 44 and shrink together when the column would overflow.
    public static func heights(of bricks: [FocusBrick], available: Double) -> [Double] {
        let natural = bricks.map { stageHeights[$0.piece.stage.rawValue - 1] }
        guard !natural.isEmpty else { return [] }
        let gaps = brickSpacing * Double(natural.count - 1)
        let total = natural.reduce(0, +)
        guard total + gaps > available else { return natural }
        let scale = max(0, available - gaps) / total
        return natural.map { $0 * scale }
    }
}
