import Foundation
import Testing
@testable import TagwerkCore

struct FocusCollectionTests {
    /// A Monday-first calendar in UTC, so the tests do not depend on the machine's region.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 10) -> Date {
        // November 2026: the 16th is a Monday.
        DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 11, day: day, hour: hour).date!
    }

    private func session(_ day: Int, hour: Int = 10, _ piece: FocusRewardPiece, minutes: Int)
        -> (endedAt: Date, piece: FocusRewardPiece, focusedSeconds: Int) {
        (date(day, hour), piece, minutes * 60)
    }

    @Test func weeks_groupByWeekAndWeekday() {
        let weeks = FocusCollection.weeks(sessions: [
            session(16, .completed(.three), minutes: 25),
            session(16, hour: 14, .endedEarly(.two), minutes: 12),
            session(18, .completed(.four), minutes: 50),
            session(22, .completed(.one), minutes: 3),
        ], calendar: calendar)
        #expect(weeks.count == 1)
        let week = weeks[0]
        #expect(week.start == date(16, 0))
        #expect(week.days.count == 7)
        // Monday has two bricks in the order the sessions ended; Wednesday one; Sunday (index 6) one.
        #expect(week.days[0].map(\.piece) == [.completed(.three), .endedEarly(.two)])
        #expect(week.days[0].map(\.focusedMinutes) == [25, 12])
        #expect(week.days[2].map(\.piece) == [.completed(.four)])
        #expect(week.days[6].map(\.piece) == [.completed(.one)])
        #expect(week.days[1].isEmpty && week.days[3].isEmpty && week.days[4].isEmpty && week.days[5].isEmpty)
        #expect(week.summary == FocusCollectionSummary(completed: 3, endedEarly: 1))
    }

    @Test func weeks_followTheFirstWeekdayOfTheCalendar() {
        var sunday = calendar
        sunday.firstWeekday = 1
        let weeks = FocusCollection.weeks(sessions: [session(22, .completed(.one), minutes: 3), session(23, .completed(.one), minutes: 3)],
                                          calendar: sunday)
        // Sunday 22 Nov starts a week in a Sunday-first calendar; Monday 23 Nov is its second day.
        #expect(weeks.count == 1)
        #expect(weeks[0].days[0].count == 1 && weeks[0].days[1].count == 1)
    }

    @Test func weeks_newestFirst() {
        let weeks = FocusCollection.weeks(sessions: [
            session(9, .completed(.one), minutes: 5),
            session(23, .completed(.two), minutes: 10),
            session(17, .completed(.three), minutes: 30),
        ], calendar: calendar)
        #expect(weeks.map(\.start) == [date(23, 0), date(16, 0), date(9, 0)])
    }

    @Test func weeks_sumFocusMinutes() {
        let weeks = FocusCollection.weeks(sessions: [
            session(16, .completed(.three), minutes: 25),
            session(17, .endedEarly(.two), minutes: 12),
            session(18, .completed(.four), minutes: 50),
        ], calendar: calendar)
        #expect(weeks[0].focusedMinutes == 87)
        #expect(FocusCollection.weeks(sessions: [], calendar: calendar).isEmpty)
    }

    @Test func heights_followTheStage() {
        let bricks = FocusRewardStage.allCases.map { FocusBrick(piece: .completed($0), focusedMinutes: $0.minimumMinutes) }
        #expect(FocusCollection.heights(of: bricks, available: 1000) == [8, 14, 22, 32, 44])
        #expect(FocusCollection.heights(of: [], available: 100).isEmpty)
        // Early-ended bricks keep the height of their stage.
        #expect(FocusCollection.heights(of: [FocusBrick(piece: .endedEarly(.four), focusedMinutes: 30)], available: 100) == [32])
    }

    @Test func heights_shrinkWhenTheColumnOverflows() {
        let bricks = Array(repeating: FocusBrick(piece: .completed(.five), focusedMinutes: 90), count: 8)
        let heights = FocusCollection.heights(of: bricks, available: 200)
        let used = heights.reduce(0, +) + FocusCollection.brickSpacing * 7
        #expect(abs(used - 200) < 0.001)
        // The bricks shrink together: the ratio between stages stays.
        let mixed = [FocusBrick(piece: .completed(.five), focusedMinutes: 90), FocusBrick(piece: .completed(.one), focusedMinutes: 1)]
        let small = FocusCollection.heights(of: mixed, available: 30)
        #expect(abs(small[0] / small[1] - 44.0 / 8.0) < 0.001)
        #expect(small.reduce(0, +) + FocusCollection.brickSpacing <= 30.001)
    }
}
