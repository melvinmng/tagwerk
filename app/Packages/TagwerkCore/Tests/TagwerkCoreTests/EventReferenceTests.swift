import Foundation
import Testing
@testable import TagwerkCore

/// Finding a remembered event again after the source changed it (plan deadline-marking, Task 2).
struct EventReferenceTests {
    let calendar = makeCalendar()
    let exam = instant(2026, 11, 27, 10, 0)
    var window: DateInterval { DateInterval(start: instant(2026, 11, 13), end: instant(2026, 12, 12)) }

    private func event(_ id: String, externalID: String? = "ext-1", calendarID: String = "timetable",
                       title: String = "Klausur Statistik", start: Date, recurring: Bool = false) -> CalendarEvent {
        var event = CalendarEvent(id: id, externalID: externalID, calendarID: calendarID, title: title, start: start,
                                  end: start.addingTimeInterval(7200), isAllDay: false, url: nil, isBusy: true, version: "1")
        event.isRecurring = recurring
        return event
    }

    private var reference: EventReference {
        EventReference(eventKey: "ev-1", externalID: "ext-1", calendarID: "timetable", title: "Klausur Statistik", start: exam)
    }

    @Test func exactIDMatches() {
        let found = event("ev-1", start: exam)
        #expect(resolveEventReference(reference, in: [found], readCalendarIDs: ["timetable"], window: window) == .exact(found))
    }

    @Test func changedIdentifierMatchesByExternalIDCalendarAndStart() {
        let renamed = event("ev-2", start: exam)
        #expect(resolveEventReference(reference, in: [renamed], readCalendarIDs: ["timetable"], window: window) == .exact(renamed))
    }

    @Test func movedEventFollowsUniqueExternalID() {
        let moved = event("ev-2", start: instant(2026, 11, 30, 10, 0))
        #expect(resolveEventReference(reference, in: [moved], readCalendarIDs: ["timetable"], window: window) == .moved(moved))
    }

    @Test func seriesOccurrencesNeverMatchByExternalIDAlone() {
        let first = event("series|1", start: instant(2026, 11, 26, 10, 0), recurring: true)
        let second = event("series|2", start: instant(2026, 11, 28, 10, 0), recurring: true)
        let result = resolveEventReference(reference, in: [first, second], readCalendarIDs: ["timetable"], window: window)
        #expect(result == .missing)
        let single = resolveEventReference(reference, in: [first], readCalendarIDs: ["timetable"], window: window)
        #expect(single != .moved(first))
    }

    @Test func sameExternalIDInOtherCalendarIsIgnored() {
        let other = event("ev-2", calendarID: "other", title: "Anderer Titel", start: exam)
        #expect(resolveEventReference(reference, in: [other], readCalendarIDs: ["timetable", "other"], window: window) == .missing)
    }

    @Test func uniqueTitleWithinFourteenDaysIsOnlyACandidate() {
        let retitled = event("ev-9", externalID: "ext-9", title: "  klausur   statistik ", start: instant(2026, 12, 4, 10, 0))
        let farAway = event("ev-10", externalID: "ext-10", start: instant(2026, 12, 20, 10, 0))
        #expect(resolveEventReference(reference, in: [retitled, farAway], readCalendarIDs: ["timetable"], window: window)
                == .candidate(retitled))
    }

    @Test func twoTitleCandidatesAreMissing() {
        let one = event("ev-8", externalID: "ext-8", start: instant(2026, 11, 25, 10, 0))
        let two = event("ev-9", externalID: "ext-9", start: instant(2026, 11, 29, 10, 0))
        #expect(resolveEventReference(reference, in: [one, two], readCalendarIDs: ["timetable"], window: window) == .missing)
    }

    @Test func unreadCalendarOrWindowOutsideStartIsUnknown() {
        #expect(resolveEventReference(reference, in: [], readCalendarIDs: ["other"], window: window) == .unknown)
        let earlier = DateInterval(start: instant(2026, 11, 1), end: instant(2026, 11, 20))
        #expect(resolveEventReference(reference, in: [], readCalendarIDs: ["timetable"], window: earlier) == .unknown)
        #expect(resolveEventReference(reference, in: [], readCalendarIDs: ["timetable"], window: window) == .missing)
    }

    @Test func withoutExternalIDMatchingOnlyTitleCandidatesRemain() {
        let renamed = event("ev-2", start: exam)
        #expect(resolveEventReference(reference, in: [renamed], readCalendarIDs: ["timetable"], window: window,
                                      matchesExternalID: false) == .candidate(renamed))
    }

    // MARK: Preparation

    @Test func preparationCountsUpcomingEventsBeforeTheDeadline() {
        let now = instant(2026, 11, 18, 13, 20)
        let past = event("past", start: instant(2026, 11, 17, 10, 0))
        let group = event("group", start: instant(2026, 11, 19, 16, 0))
        let lecture = CalendarEvent(id: "lecture", externalID: nil, calendarID: "timetable", title: "Vorlesung",
                                    start: instant(2026, 11, 23, 8, 15), end: instant(2026, 11, 23, 9, 45),
                                    isAllDay: false, url: nil, isBusy: true, version: "1")
        let after = event("after", start: instant(2026, 11, 28, 10, 0))
        let summary = preparationSummary([past, group, lecture, group, after], now: now, deadline: exam)
        #expect(summary == PreparationSummary(minutes: 210, count: 2))
    }

    @Test func preparationCountsAllDayEventsWithoutMinutes() {
        let now = instant(2026, 11, 18, 13, 20)
        let day = CalendarEvent(id: "day", externalID: nil, calendarID: "timetable", title: "Lerntag",
                                start: instant(2026, 11, 20), end: instant(2026, 11, 21), isAllDay: true, url: nil,
                                isBusy: true, version: "1")
        #expect(preparationSummary([day], now: now, deadline: exam) == PreparationSummary(minutes: 0, count: 1))
    }

    // MARK: Keyword suggestions (DL3)

    @Test func keywordsFindExamsSubmissionsAndCompounds() {
        #expect(looksLikeDeadline("Klausur Statistik"))
        #expect(looksLikeDeadline("Statistik-Klausur"))
        #expect(looksLikeDeadline("Abschlussprüfung Recht"))
        #expect(looksLikeDeadline("Abgabe Hausarbeit"))
        #expect(looksLikeDeadline("Final exam"))
        #expect(looksLikeDeadline("Submission portfolio"))
        #expect(!looksLikeDeadline("Vorlesung Statistik"))
        #expect(!looksLikeDeadline("Klausurvorbereitung Statistik"))
        #expect(!looksLikeDeadline("Lerngruppe Prüfung"))
        #expect(!looksLikeDeadline("Exam preparation"))
    }

    @Test func suggestionsSkipMarkedDismissedAndDeadlineCalendarEvents() {
        let exam = event("exam", start: instant(2026, 11, 27, 10, 0))
        let marked = event("marked", title: "Prüfung Recht", start: instant(2026, 11, 24, 10, 0))
        let dismissed = event("dismissed", title: "Abgabe Essay", start: instant(2026, 11, 25, 10, 0))
        let fromDeadlines = event("deadline", calendarID: "deadlines", title: "Abgabe Bericht", start: instant(2026, 11, 20, 10, 0))
        let lecture = event("lecture", title: "Vorlesung", start: instant(2026, 11, 19, 10, 0))
        let early = event("early", title: "Klausur Mathe", start: instant(2026, 11, 21, 10, 0))
        let result = deadlineSuggestions(events: [exam, marked, dismissed, fromDeadlines, lecture, early, exam],
                                         excludingEventIDs: ["marked", "dismissed"], excludingCalendarIDs: ["deadlines"])
        #expect(result.map(\.id) == ["early", "exam"])
    }
}
