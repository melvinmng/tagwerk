import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The learned reminder time as the app offers it (BS8): the texts and what accepting, changing and pushing away does.
@MainActor
struct BibleStudySuggestionTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "bible-suggestion-\(UUID().uuidString)")
    private let german = Locale(identifier: "de_DE")
    /// The clock of all tests: Wednesday 2026-11-18, 10:00 in Berlin.
    private let now = testNow()

    private func make() throws -> (AppEnvironment, FakeNotificationCenter) {
        let center = FakeNotificationCenter()
        let environment = try AppEnvironment(modelContainer: try ModelContainerFactory.make(inMemory: true), notificationCenter: center,
                                             health: FakeHealthStore(), snapshotWriter: WidgetSnapshotWriter(directory: directory, reload: {}))
        return (environment, center)
    }

    /// Five completed sessions of Römer on the weekdays before `now`, each around 06:40 to 06:55.
    private func completeFiveWeekdaySessions(in environment: AppEnvironment, before now: Date) {
        let calendar = environment.planning.calendar
        let romans = BibleBooks.book(number: 45)!
        var day = calendar.startOfDay(for: now)
        var created = 0
        while created < 5 {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
            guard (2...6).contains(calendar.component(.weekday, from: day)) else { continue }
            let start = calendar.date(bySettingHour: 6, minute: 40 + created * 3, second: 0, of: day)!
            let store = NoteStore(context: environment.modelContainer.mainContext, now: { start })
            let started = store.startSession(book: romans, passage: nil, freeText: "Kap. \(created + 1)", dayKey: NoteDayKey.string(PlanDay(date: day, calendar: calendar)),
                                             dateText: "x", locale: german)
            store.completeSession(started.session.id)
            created += 1
        }
    }

    @Test func card_namesTheWindowAndTheOfferedTime() {
        let weekdays = BibleStudyHabitTime.Suggestion(group: .weekdays, minutes: 6 * 60 + 45, sessionsInWindow: 5, sessions: 5,
                                                      windowStart: 6 * 60 + 30, windowEnd: 7 * 60 + 10)
        #expect(BibleStudySuggestionText.card(weekdays, locale: german)
            == "Du beginnst werktags meist zwischen 06:30 und 07:10. Soll Tagwerk dich Mo–Fr um 06:45 erinnern?")
        let weekend = BibleStudyHabitTime.Suggestion(group: .weekend, minutes: 8 * 60 + 30, sessionsInWindow: 7, sessions: 8,
                                                     windowStart: 8 * 60 + 10, windowEnd: 8 * 60 + 50)
        #expect(BibleStudySuggestionText.card(weekend, locale: german)
            == "Du beginnst am Wochenende meist zwischen 08:10 und 08:50. Soll Tagwerk dich Sa und So um 08:30 erinnern?")
        #expect(BibleStudySuggestionText.title(weekend, locale: german) == "Sa und So gegen 08:30")
        #expect(BibleStudySuggestionText.reason(weekend, locale: german)
            == "An 7 von 8 Sitzungen am Wochenende der letzten 8 Wochen hast du zwischen 08:10 und 08:50 begonnen.")
    }

    @Test func suggestions_followTheCompletedSessions() throws {
        let (environment, _) = try make()
        #expect(environment.bibleStudySuggestions(now: now).isEmpty)
        completeFiveWeekdaySessions(in: environment, before: now)
        let suggestions = environment.bibleStudySuggestions(now: now)
        #expect(suggestions.map(\.group) == [.weekdays])
    }

    @Test func card_comesOncePerNewSuggestion() throws {
        let (environment, _) = try make()
        completeFiveWeekdaySessions(in: environment, before: now)
        let first = try #require(environment.nextBibleStudySuggestionCard(now: now))
        #expect(environment.settings.bibleStudySuggestionShownKeys == first.key)
        #expect(environment.nextBibleStudySuggestionCard(now: now) == nil, "the same suggestion does not come again")
        #expect(!environment.bibleStudySuggestions(now: now).isEmpty, "the settings page keeps showing it")
    }

    @Test func adopt_addsTheTimeSwitchesOnAndPlans() async throws {
        let (environment, _) = try make()
        completeFiveWeekdaySessions(in: environment, before: now)
        let suggestion = try #require(environment.bibleStudySuggestions(now: now).first)
        await environment.adoptBibleStudySuggestion(suggestion)
        #expect(environment.settings.bibleStudyReminderEnabled)
        #expect(environment.settings.bibleStudyReminderTimes.map(\.minutes) == [suggestion.minutes])
        #expect(environment.settings.bibleStudyReminderTimes.first?.weekdays == [2, 3, 4, 5, 6])
        // The time is set now, so the same suggestion is not made again.
        #expect(environment.bibleStudySuggestions(now: now).isEmpty)
    }

    @Test func adopt_takesTheDaysFromAnotherTime() async throws {
        let (environment, _) = try make()
        environment.settings.bibleStudyReminderTimes = [BibleStudyReminderTime(minutes: 20 * 60, weekdays: Set(1...7))]
        let suggestion = BibleStudyHabitTime.Suggestion(group: .weekdays, minutes: 6 * 60 + 45, sessionsInWindow: 5, sessions: 5, windowStart: 400, windowEnd: 420)
        await environment.adoptBibleStudySuggestion(suggestion)
        let times = environment.settings.bibleStudyReminderTimes
        #expect(times.count == 2)
        #expect(times.first { $0.minutes == 20 * 60 }?.weekdays == [7, 1])
        #expect(times.first { $0.minutes == 6 * 60 + 45 }?.weekdays == [2, 3, 4, 5, 6])
    }

    @Test func snooze_keepsTheSuggestionAwayForFourWeeks() throws {
        let (environment, _) = try make()
        completeFiveWeekdaySessions(in: environment, before: now)
        #expect(!environment.bibleStudySuggestions(now: now).isEmpty)
        environment.snoozeBibleStudySuggestion(now: now)
        #expect(environment.bibleStudySuggestions(now: now).isEmpty)
        #expect(environment.bibleStudySuggestions(now: now.addingTimeInterval(27 * 86_400)).isEmpty)
        let until = try #require(environment.settings.bibleStudySuggestionSnoozedUntil)
        #expect(until.timeIntervalSince(now) > 27 * 86_400 && until.timeIntervalSince(now) < 29 * 86_400)
    }
}
