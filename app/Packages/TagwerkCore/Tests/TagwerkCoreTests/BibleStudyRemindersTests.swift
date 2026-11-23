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

/// The planned Bible Study reminders (BS7). Time zone fixed to Europe/Berlin so the tests do not depend on the machine's.
struct BibleStudyRemindersPlanTests {
    private let german = Locale(identifier: "de_DE")
    private let workdays: Set<Int> = [2, 3, 4, 5, 6]
    private let weekend: Set<Int> = [7, 1]

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private var times: [BibleStudyReminderTime] {
        [BibleStudyReminderTime(minutes: 6 * 60 + 45, weekdays: workdays), BibleStudyReminderTime(minutes: 8 * 60 + 30, weekdays: weekend)]
    }

    /// 20.11.2026 is a Friday.
    private func plan(times: [BibleStudyReminderTime]? = nil, enabled: Bool = true, completed: Set<PlanDay> = [], skipped: PlanDay? = nil,
                      passage: String? = nil, now: Date? = nil, days: Int = RoutineSchedule.bibleStudyHorizonDays) -> [DatedRoutineNotification] {
        BibleStudyReminders.notifications(times: times ?? self.times, enabled: enabled, completedDays: completed, skippedDay: skipped,
                                          nextPassage: passage, now: now ?? date(2026, 11, 20, 5, 0), calendar: calendar, locale: german, days: days)
    }

    private func clock(_ notification: DatedRoutineNotification) -> String {
        String(format: "%04d-%02d-%02d %02d:%02d", notification.year, notification.month, notification.day, notification.hour, notification.minute)
    }

    @Test func notifications_planThreeDays() {
        let result = plan()
        #expect(result.map(clock) == ["2026-11-20 06:45", "2026-11-21 08:30", "2026-11-22 08:30"])
        #expect(result.map(\.id) == ["tagwerk.routine.bible.2026-11-20", "tagwerk.routine.bible.2026-11-21", "tagwerk.routine.bible.2026-11-22"])
        #expect(result.allSatisfy { $0.route == .bibleStudyStart && $0.categoryIdentifier == BibleStudyReminders.categoryIdentifier })
        #expect(result.allSatisfy { $0.title == "Bible Study" })
        #expect(plan(days: 1).count == 1)
    }

    @Test func notifications_skipDayWithoutTime() {
        let onlyWorkdays = [BibleStudyReminderTime(minutes: 405, weekdays: workdays)]
        #expect(plan(times: onlyWorkdays).map(clock) == ["2026-11-20 06:45"])
    }

    @Test func notifications_skipCompletedDay() {
        let saturday = PlanDay(year: 2026, month: 11, day: 21)
        #expect(plan(completed: [saturday]).map(clock) == ["2026-11-20 06:45", "2026-11-22 08:30"])
    }

    @Test func notifications_skipSkippedDayOnly() {
        #expect(plan(skipped: PlanDay(year: 2026, month: 11, day: 20)).map(clock) == ["2026-11-21 08:30", "2026-11-22 08:30"])
        // "Heute nicht" of yesterday does not touch today.
        #expect(plan(skipped: PlanDay(year: 2026, month: 11, day: 19)).count == 3)
    }

    @Test func notifications_skipPastMoment() {
        #expect(plan(now: date(2026, 11, 20, 6, 45)).map(clock) == ["2026-11-21 08:30", "2026-11-22 08:30"])
        #expect(plan(now: date(2026, 11, 20, 6, 44)).count == 3)
    }

    @Test func notifications_disabled_isEmpty() {
        #expect(plan(enabled: false).isEmpty)
        #expect(plan(times: []).isEmpty)
    }

    @Test func notifications_bodyWithAndWithoutPassage() {
        #expect(plan().first?.body == "Zeit für Bible Study.")
        #expect(plan(passage: "Weiter in Römer ab 3,27").first?.body == "Zeit für Bible Study. Weiter in Römer ab 3,27.")
    }

    @Test func notifications_summerTimeDay_keepsClockTime() {
        // 28.03.2027: the clocks go forward at 02:00; the reminder stays at 06:45 on the clock.
        let everyDay = [BibleStudyReminderTime(minutes: 6 * 60 + 45, weekdays: Set(1...7))]
        let result = plan(times: everyDay, now: date(2027, 3, 27, 20, 0))
        #expect(result.map(clock) == ["2027-03-28 06:45", "2027-03-29 06:45"])
        #expect(result.allSatisfy { $0.hour == 6 && $0.minute == 45 })
    }

    @Test func identifier_isStablePerDay() {
        let day = PlanDay(year: 2026, month: 3, day: 5)
        #expect(BibleStudyReminders.identifier(day: day) == "tagwerk.routine.bible.2026-03-05")
        #expect(BibleStudyReminders.identifier(day: day) == BibleStudyReminders.identifier(day: PlanDay(year: 2026, month: 3, day: 5)))
        #expect(BibleStudyReminders.identifier(day: day).hasPrefix(PlannedNotification.routineIdentifierPrefix))
    }

    @Test func nextPassageText_namesBookAndVerse() {
        let next = BibleProgress.Next.start(BibleReference(chapter: 3, verse: 27))
        #expect(BibleStudyReminders.nextPassageText(bookName: "Römer", next: next, showsPassage: true, locale: german) == "Weiter in Römer ab 3,27")
    }

    @Test func nextPassageText_hiddenBySwitch() {
        let next = BibleProgress.Next.start(BibleReference(chapter: 3, verse: 27))
        #expect(BibleStudyReminders.nextPassageText(bookName: "Römer", next: next, showsPassage: false, locale: german) == nil)
    }

    @Test func nextPassageText_finishedBook_isNil() {
        let finished = BibleProgress.Next.bookFinished(last: BibleReference(chapter: 16, verse: 27))
        #expect(BibleStudyReminders.nextPassageText(bookName: "Römer", next: finished, showsPassage: true, locale: german) == nil)
        #expect(BibleStudyReminders.nextPassageText(bookName: nil, next: nil, showsPassage: true, locale: german) == nil)
        // A session typed as free text gives no next verse.
        #expect(BibleStudyReminders.nextPassageText(bookName: "Römer", next: nil, showsPassage: true, locale: german) == nil)
    }
}
