import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct RecurrenceEditorModelTests {
    let calendar = testCalendar()
    /// Wednesday, the third Wednesday of November 2026.
    let wednesday = PlanDay(year: 2026, month: 11, day: 18)
    /// Thursday.
    let thursday = PlanDay(year: 2026, month: 11, day: 19)

    private func model(_ original: Recurrence? = nil, start: PlanDay? = nil) -> RecurrenceEditorModel {
        RecurrenceEditorModel(original: original, start: start ?? wednesday, calendar: calendar)
    }

    @Test func preset_weekdays_setsMondayToFriday() {
        let sut = model()
        sut.apply(preset: .weekdays)
        #expect(sut.frequency == .week)
        #expect(sut.interval == 1)
        #expect(sut.weekdays == [2, 3, 4, 5, 6])
        #expect(sut.selectedPreset == .weekdays)
        #expect(sut.recurrence == Recurrence(rule: .weekly(interval: 1, weekdays: [2, 3, 4, 5, 6]), start: wednesday,
                                             end: nil, count: nil))
    }

    @Test func customWeekdays_deselectsPreset() {
        let sut = model(start: thursday)
        sut.apply(preset: .biweekly)
        #expect(sut.selectedPreset == .biweekly)
        sut.toggleWeekday(2)
        #expect(sut.weekdays == [2, 5])
        #expect(sut.selectedPreset == nil)
        #expect(sut.recurrence?.rule == .weekly(interval: 2, weekdays: [2, 5]))
    }

    @Test func switchToMonth_derivesDayAndOrdinalFromDue() {
        let sut = model()
        sut.apply(preset: .daily)
        sut.setInterval(3)
        sut.setFrequency(.month)
        #expect(sut.interval == 3)
        #expect(sut.monthDay == 18)
        #expect(sut.ordinal == 3)
        #expect(sut.ordinalWeekday == 4)
        #expect(sut.recurrence?.rule == .monthly(interval: 3, day: 18))
        sut.setMonthOption(.weekdayOfMonth)
        #expect(sut.recurrence?.rule == .monthlyWeekday(interval: 3, ordinal: 3, weekday: 4))
        sut.setFrequency(.week)
        #expect(sut.weekdays == [4])
        #expect(sut.recurrence?.rule == .weekly(interval: 3, weekdays: [4]))
    }

    @Test func fifthWeekday_cannotBeChosen() {
        let sut = model(start: PlanDay(year: 2026, month: 12, day: 30))
        sut.setFrequency(.month)
        #expect(!sut.canUseWeekdayOfMonth)
        sut.setMonthOption(.weekdayOfMonth)
        #expect(sut.recurrence?.rule == .monthly(interval: 1, day: 30))
    }

    @Test func lastWeekday_cannotBeRemoved() {
        let sut = model()
        sut.apply(preset: .weekly)
        sut.toggleWeekday(4)
        #expect(sut.weekdays == [4])
        #expect(sut.recurrence?.rule == .weekly(interval: 1, weekdays: [4]))
    }

    @Test func preview_matchesCoreOccurrences() {
        let sut = model(start: thursday)
        sut.apply(preset: .biweekly)
        sut.toggleWeekday(2)
        let recurrence = try! #require(sut.recurrence)
        let expected = occurrences(of: recurrence, in: thursday...thursday.adding(days: 60, calendar: calendar), calendar: calendar)
        #expect(sut.nextOccurrences(5) == Array(expected.prefix(5)))
        // The dates of the mockup (RK3, weekly page).
        #expect(sut.nextOccurrences(5) == [19, 30].map { PlanDay(year: 2026, month: 11, day: $0) }
                + [3, 14, 17].map { PlanDay(year: 2026, month: 12, day: $0) })
    }

    @Test func end_dateAndCount() {
        let sut = model()
        sut.apply(preset: .monthly)
        sut.setEndKind(.count)
        sut.setCount(12)
        #expect(sut.recurrence?.count == 12)
        #expect(sut.recurrence?.end == nil)
        #expect(sut.lastOccurrence == PlanDay(year: 2027, month: 10, day: 18))
        let end = PlanDay(year: 2027, month: 3, day: 31)
        sut.setEndKind(.date)
        sut.setEndDate(end)
        #expect(sut.recurrence?.end == end)
        #expect(sut.recurrence?.count == nil)
        sut.setEndKind(.never)
        #expect(sut.recurrence?.end == nil && sut.recurrence?.count == nil)
    }

    /// "Letzter Termin" is computed within 20 years; a longer series shows none instead of blocking the page.
    @Test func lastOccurrence_onlyWithinTwentyYears() {
        let sut = model()
        sut.apply(preset: .yearly)
        sut.setEndKind(.count)
        sut.setCount(20)
        #expect(sut.lastOccurrence == PlanDay(year: 2045, month: 11, day: 18))
        sut.setCount(999)
        #expect(sut.lastOccurrence == nil)
    }

    @Test func endDate_notBeforeStart() {
        let sut = model()
        sut.apply(preset: .daily)
        sut.setEndKind(.date)
        sut.setEndDate(PlanDay(year: 2026, month: 11, day: 1))
        #expect(sut.recurrence?.end == wednesday)
    }

    @Test func never_removesRecurrence() {
        let sut = model(Recurrence(rule: .daily(interval: 1), start: wednesday, end: nil, count: nil))
        #expect(!sut.isNever)
        sut.selectNever()
        #expect(sut.recurrence == nil)
        #expect(sut.isNever)
    }

    @Test func existingRule_isShownInControls() {
        let original = Recurrence(rule: .monthlyWeekday(interval: 2, ordinal: 3, weekday: 4), start: wednesday, end: nil, count: 6)
        let sut = model(original)
        #expect(sut.frequency == .month)
        #expect(sut.monthOption == .weekdayOfMonth)
        #expect(sut.interval == 2)
        #expect(sut.endKind == .count)
        #expect(sut.count == 6)
        #expect(sut.recurrence == original)
    }

    /// Opening the page must not rewrite anything, also not by normalising a rule ("weekly" without days).
    @Test func openWithoutChoice_keepsOriginalExactly() {
        let original = Recurrence(rule: .weekly(interval: 1, weekdays: []), start: wednesday, end: nil, count: nil)
        let sut = model(original)
        #expect(!sut.isChanged)
        #expect(sut.recurrence == original)
        #expect(sut.weekdays == [4])
    }

    @Test func unsupportedOriginal_staysUntouchedWithoutChoice() {
        let original = Recurrence(rule: .unsupported, start: wednesday, end: nil, count: nil)
        let sut = model(original)
        #expect(sut.isUnsupportedOriginal)
        #expect(sut.recurrence == original)
        #expect(sut.selectedPreset == nil)
        #expect(!sut.isNever)
        sut.apply(preset: .weekly)
        #expect(sut.recurrence?.rule == .weekly(interval: 1, weekdays: [4]))
    }

    @Test func suggestedDue_isNextMatchingDay() {
        let sut = model()
        sut.apply(preset: .weekly)
        #expect(sut.suggestedDue == nil)
        sut.toggleWeekday(2)
        sut.toggleWeekday(5)
        sut.toggleWeekday(4)
        #expect(sut.weekdays == [2, 5])
        #expect(sut.suggestedDue == thursday)
        sut.updateStart(thursday)
        #expect(sut.suggestedDue == nil)
        #expect(sut.recurrence?.start == thursday)
    }

    @Test func summary_usesPlainText() {
        let sut = model()
        #expect(sut.summary == "Nie")
        sut.apply(preset: .weekdays)
        #expect(sut.summary == "Jeden Werktag (Mo bis Fr)")
    }
}

struct RecurrenceAvailabilityTests {
    let due = DueDate(year: 2026, month: 11, day: 19, hour: 9, minute: 0)
    var weekly: Recurrence {
        Recurrence(rule: .weekly(interval: 1, weekdays: [5]), start: PlanDay(year: 2026, month: 11, day: 18), end: nil, count: nil)
    }

    @Test func newTask_onlyRemindersRepeatInStageOne() {
        #expect(RecurrenceAvailability.forNewTask(.reminders) == .available)
        #expect(RecurrenceAvailability.forNewTask(.local) == .unavailable(reason: "Nur für Erinnerungen"))
        #expect(RecurrenceAvailability.forNewTask(.github) == .unavailable(reason: "GitHub-Issues wiederholen sich nicht"))
    }

    @Test func draftRecurrence_startsAtDueDate() {
        #expect(RecurrenceAvailability.draftRecurrence(weekly, target: .reminders, due: due)?.start == PlanDay(year: 2026, month: 11, day: 19))
    }

    /// A rule chosen before switching to another source is not taken over.
    @Test func draftRecurrence_droppedForOtherSourcesOrWithoutDue() {
        #expect(RecurrenceAvailability.draftRecurrence(weekly, target: .github, due: due) == nil)
        #expect(RecurrenceAvailability.draftRecurrence(weekly, target: .local, due: due) == nil)
        #expect(RecurrenceAvailability.draftRecurrence(weekly, target: .reminders, due: nil) == nil)
    }
}
