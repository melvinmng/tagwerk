import Foundation
import Testing
@testable import TagwerkCore

/// The reminder times of Bible Study (BS6, BE2b). Weekdays count like `Calendar` (1 = Sunday).
struct BibleStudyRemindersTimesTests {
    private let german = Locale(identifier: "de_DE")
    private let workdays: Set<Int> = [2, 3, 4, 5, 6]
    private let weekend: Set<Int> = [7, 1]

    private func time(_ minutes: Int, _ weekdays: Set<Int>) -> BibleStudyReminderTime {
        BibleStudyReminderTime(minutes: minutes, weekdays: weekdays)
    }

    @Test func saving_movesWeekdaysToTheNewTime() {
        let early = time(6 * 60 + 45, workdays.union(weekend))
        let late = time(8 * 60 + 30, weekend)
        let result = BibleStudyReminderTimes.saving(late, into: [early])
        #expect(result.count == 2)
        #expect(result.first { $0.id == early.id }?.weekdays == workdays)
        #expect(result.first { $0.id == late.id }?.weekdays == weekend)
        // Every weekday belongs to at most one time.
        #expect(result.flatMap(\.weekdays).count == Set(result.flatMap(\.weekdays)).count)
    }

    @Test func saving_replacesTheTimeWithTheSameId() {
        let early = time(6 * 60 + 45, workdays)
        var changed = early
        changed.minutes = 7 * 60
        changed.weekdays = [2, 3]
        let result = BibleStudyReminderTimes.saving(changed, into: [early])
        #expect(result == [changed])
    }

    @Test func saving_dropsTimeWithoutWeekdays() {
        let early = time(6 * 60 + 45, workdays)
        let takeover = time(7 * 60, workdays)
        // The older time loses all its days and goes.
        #expect(BibleStudyReminderTimes.saving(takeover, into: [early]) == [takeover])
        // A saved time without days is not added.
        #expect(BibleStudyReminderTimes.saving(time(9 * 60, []), into: [early]) == [early])
    }

    @Test func takenWeekdays_excludesOwn() {
        let early = time(6 * 60 + 45, workdays)
        let late = time(8 * 60 + 30, weekend)
        #expect(BibleStudyReminderTimes.takenWeekdays(for: early, in: [early, late]) == weekend)
        #expect(BibleStudyReminderTimes.takenWeekdays(for: time(9 * 60, []), in: [early, late]) == workdays.union(weekend))
        #expect(BibleStudyReminderTimes.takenWeekdays(for: early, in: [early]).isEmpty)
    }

    @Test func minutes_onWeekday() {
        let times = [time(6 * 60 + 45, workdays), time(8 * 60 + 30, weekend)]
        #expect(BibleStudyReminderTimes.minutes(on: 2, in: times) == 6 * 60 + 45)
        #expect(BibleStudyReminderTimes.minutes(on: 1, in: times) == 8 * 60 + 30)
        #expect(BibleStudyReminderTimes.minutes(on: 4, in: [time(60, weekend)]) == nil)
    }

    @Test func summary_ordersWeekdaysFromMonday() {
        #expect(BibleStudyReminderTimes.summary(time(6 * 60 + 45, workdays), locale: german) == "06:45 · Mo Di Mi Do Fr")
        // Sunday (1) is the last day of the week, not the first.
        #expect(BibleStudyReminderTimes.summary(time(8 * 60 + 30, [1, 7]), locale: german) == "08:30 · Sa So")
        #expect(BibleStudyReminderTimes.weekdayNames(Set(1...7), locale: german) == ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"])
    }

    @Test func times_areCodable() throws {
        let times = [time(6 * 60 + 45, workdays), time(8 * 60 + 30, weekend)]
        let data = try JSONEncoder().encode(times)
        #expect(try JSONDecoder().decode([BibleStudyReminderTime].self, from: data) == times)
    }
}
