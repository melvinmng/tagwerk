import Foundation
import Testing
@testable import TagwerkCore

/// The learned reminder time (BS8). Time zone fixed to Europe/Berlin; "now" is Friday 2026-11-20 12:00.
struct BibleStudyHabitTimeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { date(2026, 11, 20, 12, 0) }

    /// Weekday sessions on Monday to Friday of the weeks before now, at the given clock minutes (one per entry, one a day).
    private func weekdaySessions(_ minutes: [Int]) -> [Date] {
        // Monday 2026-11-16 and the days before it: 2026-11-16, 11-17, 11-18, 11-19, then 11-09 ...
        let days = [(11, 16), (11, 17), (11, 18), (11, 19), (11, 12), (11, 11), (11, 10), (11, 9), (11, 6), (11, 5), (11, 4), (11, 3)]
        return zip(minutes, days).map { date(2026, $1.0, $1.1, $0 / 60, $0 % 60) }
    }

    /// Weekend sessions: Saturdays and Sundays before now.
    private func weekendSessions(_ minutes: [Int]) -> [Date] {
        let days = [(11, 14), (11, 15), (11, 7), (11, 8), (10, 31), (11, 1), (10, 24), (10, 25)]
        return zip(minutes, days).map { date(2026, $1.0, $1.1, $0 / 60, $0 % 60) }
    }

    private func suggestions(_ starts: [Date], existing: [BibleStudyReminderTime] = [], snoozedUntil: Date? = nil) -> [BibleStudyHabitTime.Suggestion] {
        BibleStudyHabitTime.suggestions(startTimes: starts, existing: existing, snoozedUntil: snoozedUntil, now: now, calendar: calendar)
    }

    @Test func thresholds_areTheAgreedStartingValues() {
        #expect(BibleStudyHabitTime.weeks == 8 && BibleStudyHabitTime.minimumSessions == 5 && BibleStudyHabitTime.windowMinutes == 60)
        #expect(BibleStudyHabitTime.minimumShare == 2.0 / 3.0 && BibleStudyHabitTime.minimumDifferenceMinutes == 20)
        #expect(BibleStudyHabitTime.snoozeDays == 28)
    }

    @Test func suggestion_needsFiveSessions() {
        #expect(suggestions(weekdaySessions([400, 405, 410, 400])).isEmpty)
        #expect(suggestions(weekdaySessions([400, 405, 410, 400, 405])).count == 1)
    }

    @Test func suggestion_needsTwoThirdsInOneHour() {
        // Six sessions: four of them within an hour is exactly two thirds.
        #expect(suggestions(weekdaySessions([400, 410, 420, 430, 600, 900])).count == 1)
        // Three of six is only half.
        #expect(suggestions(weekdaySessions([400, 410, 420, 600, 900, 1100])).isEmpty)
    }

    @Test func suggestion_roundsToFiveMinutes() throws {
        // 06:21 … 06:58: the middle is 06:39.5, which rounds to 06:40.
        let suggestion = try #require(suggestions(weekdaySessions([6 * 60 + 21, 6 * 60 + 30, 6 * 60 + 40, 6 * 60 + 50, 6 * 60 + 58])).first)
        #expect(suggestion.minutes == 6 * 60 + 40)
        #expect(suggestion.windowStart == 6 * 60 + 21 && suggestion.windowEnd == 6 * 60 + 58)
        #expect(suggestion.sessionsInWindow == 5 && suggestion.sessions == 5 && suggestion.group == .weekdays)
        #expect(suggestion.key == "weekdays-400")
    }

    @Test func suggestion_separatesWeekdaysAndWeekend() throws {
        let starts = weekdaySessions([405, 410, 400, 415, 405]) + weekendSessions([510, 500, 520, 505, 515])
        let result = suggestions(starts)
        #expect(result.map(\.group) == [.weekdays, .weekend])
        #expect(result[0].minutes == 410 && result[1].minutes == 510)
        // Weekend sessions do not count towards the weekdays.
        #expect(suggestions(weekdaySessions([405, 410, 400, 415]) + weekendSessions([510, 500, 520, 505, 515])).map(\.group) == [.weekend])
    }

    @Test func suggestion_ignoresSessionsOlderThanEightWeeks() {
        let old = (0..<5).map { date(2026, 9, 14 + $0, 7, 0) }  // 9 weeks before the 20th and earlier
        #expect(suggestions(old).isEmpty)
        // Two of five are too old: only three count.
        let mixed = Array(weekdaySessions([400, 405, 410]) + old.prefix(2))
        #expect(suggestions(mixed).isEmpty)
    }

    @Test func suggestion_noneWhenCloseToExistingTime() {
        let starts = weekdaySessions([405, 410, 400, 415, 405])
        let setForAll = [BibleStudyReminderTime(minutes: 6 * 60 + 45, weekdays: [2, 3, 4, 5, 6])]
        // 06:50 against 06:45 is 5 minutes apart: no suggestion.
        #expect(suggestions(starts, existing: setForAll).isEmpty)
        // 19 minutes apart is still too close, 20 is far enough.
        #expect(suggestions(starts, existing: [BibleStudyReminderTime(minutes: 410 - 19, weekdays: [2, 3, 4, 5, 6])]).isEmpty)
        #expect(suggestions(starts, existing: [BibleStudyReminderTime(minutes: 410 - 20, weekdays: [2, 3, 4, 5, 6])]).count == 1)
        // One weekday without a time keeps the suggestion.
        #expect(suggestions(starts, existing: [BibleStudyReminderTime(minutes: 410, weekdays: [2, 3, 4, 5])]).count == 1)
        // A time for the weekend does not concern the weekdays.
        #expect(suggestions(starts, existing: [BibleStudyReminderTime(minutes: 410, weekdays: [7, 1])]).count == 1)
    }

    @Test func suggestion_noneWhileSnoozed() {
        let starts = weekdaySessions([405, 410, 400, 415, 405])
        #expect(suggestions(starts, snoozedUntil: now.addingTimeInterval(60)).isEmpty)
        #expect(suggestions(starts, snoozedUntil: now).count == 1)
        #expect(suggestions(starts, snoozedUntil: now.addingTimeInterval(-60)).count == 1)
    }

    @Test func suggestion_scatteredTimes_none() {
        #expect(suggestions(weekdaySessions([360, 480, 600, 720, 900, 1080, 1200])).isEmpty)
    }

    @Test func suggestion_windowAcrossMidnight_isNotJoined() {
        // 23:40 and 00:10 are half an hour apart on the clock but belong to the two ends of the day: no joined window.
        let late = [23 * 60 + 40, 23 * 60 + 50, 23 * 60 + 55]
        let early = [10, 20]
        #expect(suggestions(weekdaySessions(late + early)).isEmpty)
    }

    @Test func suggestion_densestWindowWins() throws {
        // Two clusters of different size: the larger one is the suggestion.
        let suggestion = try #require(suggestions(weekdaySessions([400, 405, 410, 415, 420, 1200, 1210])).first)
        #expect(suggestion.minutes == 410 && suggestion.sessionsInWindow == 5 && suggestion.sessions == 7)
    }
}
