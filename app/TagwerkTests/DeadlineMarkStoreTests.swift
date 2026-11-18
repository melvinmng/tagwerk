import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Deadline marks and preparation links live in SwiftData only (plan deadline-marking, Task 4).
@MainActor
struct DeadlineMarkStoreTests {
    let container: ModelContainer
    let store: DeadlineMarkStore
    let calendar = testCalendar()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = DeadlineMarkStore(context: container.mainContext)
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func event(_ id: String, title: String = "Klausur Statistik", calendarID: String = "timetable",
                       externalID: String? = "ext-exam", start: Date, minutes: Int = 120, recurring: Bool = false) -> CalendarEvent {
        var event = CalendarEvent(id: id, externalID: externalID, calendarID: calendarID, title: title, start: start,
                                  end: start.addingTimeInterval(TimeInterval(minutes * 60)), isAllDay: false, url: nil,
                                  isBusy: true, version: "1")
        event.isRecurring = recurring
        return event
    }

    private var window: DateInterval { DateInterval(start: at(13, 0), end: at(12, 0, month: 12)) }

    @Test func markStoresSnapshot() throws {
        store.mark(event("exam", start: at(27, 10)), series: false)
        let mark = try #require(store.marks().first)
        #expect(mark.eventKey == "exam")
        #expect(mark.externalID == "ext-exam")
        #expect(mark.calendarID == "timetable")
        #expect(mark.title == "Klausur Statistik")
        #expect(mark.start == at(27, 10))
        #expect(mark.isSeries == false)
    }

    @Test func markTwiceKeepsOneRecord() {
        store.mark(event("exam", start: at(27, 10)), series: false)
        store.mark(event("exam", start: at(27, 11)), series: false)
        #expect(store.marks().count == 1)
        #expect(store.marks().first?.start == at(27, 11))
    }

    @Test func seriesMarkCoversEveryOccurrence() {
        let first = event("lecture|100", title: "Vorlesung", start: at(23, 8), recurring: true)
        let second = event("lecture|200", title: "Vorlesung", start: at(30, 8), recurring: true)
        let other = event("other|100", title: "Vorlesung", start: at(24, 8), recurring: true)
        store.mark(first, series: true)
        #expect(store.marks().first?.eventKey == "lecture")
        #expect(store.markedIDs(in: [first, second, other]) == ["lecture|100", "lecture|200"])
        store.mark(other, series: false)
        #expect(store.markedIDs(in: [first, second, other]) == ["lecture|100", "lecture|200", "other|100"])
    }

    @Test func unmarkDeletesMarkAndItsLinks() {
        let exam = event("exam", start: at(27, 10))
        store.mark(exam, series: false)
        store.link(event("group", title: "Lerngruppe", start: at(19, 16)), toDeadline: "event:exam", title: exam.title,
                   until: exam.start, series: false)
        store.link(event("other", title: "Lernblock", start: at(20, 16)), toDeadline: "task:local:Angebot", title: "Angebot",
                   until: at(21, 0), series: false)
        #expect(store.linkCount(forDeadline: "event:exam") == 1)
        store.unmark(exam)
        #expect(store.marks().isEmpty)
        #expect(store.allLinks().map(\.deadlineKey) == ["task:local:Angebot"])
    }

    @Test func linkAndUnlinkPreparation() throws {
        let group = event("group", title: "Lerngruppe", start: at(19, 16))
        store.link(group, toDeadline: "event:exam", title: "Klausur Statistik", until: at(27, 10), series: false)
        store.link(group, toDeadline: "event:exam", title: "Klausur Statistik", until: at(27, 10), series: false)
        let link = try #require(store.links(forDeadline: "event:exam").first)
        #expect(store.links(forDeadline: "event:exam").count == 1)
        #expect(store.linkedEvents(forDeadline: "event:exam", among: [group, event("x", start: at(20, 9))]).map(\.id) == ["group"])
        store.unlink(key: link.key)
        #expect(store.allLinks().isEmpty)
    }

    @Test func seriesLinkCoversOccurrencesUntilDeadline() {
        let earlier = event("lecture|1", title: "Vorlesung", start: at(16, 8), recurring: true)
        let picked = event("lecture|2", title: "Vorlesung", start: at(23, 8), recurring: true)
        let later = event("lecture|3", title: "Vorlesung", start: at(26, 8), recurring: true)
        let afterDeadline = event("lecture|4", title: "Vorlesung", start: at(30, 8), recurring: true)
        store.link(picked, toDeadline: "event:exam", title: "Klausur Statistik", until: at(27, 10), series: true)
        #expect(store.linkedEvents(forDeadline: "event:exam", among: [earlier, picked, later, afterDeadline]).map(\.id)
                == ["lecture|2", "lecture|3"])
        #expect(store.preparationTarget(for: later)?.deadlineKey == "event:exam")
        #expect(store.preparationTarget(for: afterDeadline) == nil)
    }

    @Test func followUpdatesKeyAndStart() throws {
        let exam = event("exam", start: at(27, 10))
        store.mark(exam, series: false)
        store.link(event("group", title: "Lerngruppe", start: at(19, 16)), toDeadline: "event:exam", title: exam.title,
                   until: exam.start, series: false)
        let moved = event("exam-new", start: at(30, 10))
        let result = store.resolve(events: [moved], readCalendarIDs: ["timetable"], window: window, now: testNow())
        #expect(result.markedIDs == ["exam-new"])
        #expect(result.orphans.isEmpty)
        let mark = try #require(store.marks().first)
        #expect(mark.eventKey == "exam-new")
        #expect(mark.start == at(30, 10))
        #expect(store.links(forDeadline: "event:exam-new").count == 1)
        #expect(store.links(forDeadline: "event:exam").isEmpty)
    }

    @Test func missingAndCandidateAreReportedNeverDeleted() throws {
        store.mark(event("exam", externalID: nil, start: at(27, 10)), series: false)
        let missing = store.resolve(events: [], readCalendarIDs: ["timetable"], window: window, now: testNow())
        #expect(missing.orphans.map(\.candidate) == [nil])
        let retitled = event("exam-2", title: "klausur statistik", externalID: nil, start: at(30, 10))
        let candidate = store.resolve(events: [retitled], readCalendarIDs: ["timetable"], window: window, now: testNow())
        #expect(candidate.orphans.first?.candidate == retitled)
        #expect(candidate.markedIDs.isEmpty)
        #expect(store.marks().first?.eventKey == "exam")
        let unknown = store.resolve(events: [], readCalendarIDs: [], window: window, now: testNow())
        #expect(unknown.orphans.isEmpty)
        #expect(store.marks().count == 1)
    }

    @Test func adoptingACandidateMovesTheMark() throws {
        store.mark(event("exam", externalID: nil, start: at(27, 10)), series: false)
        let candidate = event("exam-2", externalID: nil, start: at(30, 10))
        let orphan = try #require(store.resolve(events: [candidate], readCalendarIDs: ["timetable"], window: window,
                                                now: testNow()).orphans.first)
        store.adopt(orphan, candidate: candidate)
        #expect(store.marks().first?.eventKey == "exam-2")
        #expect(store.marks().first?.start == at(30, 10))
    }

    @Test func seriesMarkFollowsLastSeenOccurrence() throws {
        let first = event("lecture|1", title: "Vorlesung", externalID: "ext-series", start: at(23, 8), recurring: true)
        store.mark(first, series: true)
        let renamed = event("lecture2|9", title: "Vorlesung", externalID: "ext-series", start: at(30, 8), recurring: true)
        let result = store.resolve(events: [renamed], readCalendarIDs: ["timetable"], window: window, now: testNow())
        #expect(result.markedIDs == ["lecture2|9"])
        let mark = try #require(store.marks().first)
        #expect(mark.eventKey == "lecture2")
        #expect(mark.lastSeen == at(30, 8))
        // A series without occurrences in the window is not reported as missing.
        #expect(store.resolve(events: [], readCalendarIDs: ["timetable"], window: window, now: testNow()).orphans.isEmpty)
    }

    @Test func pruneRemovesMarksOlderThanThirtyDays() {
        store.mark(event("old", start: at(10, 10, month: 10)), series: false)
        store.mark(event("recent", start: at(20, 10, month: 10)), series: false)
        store.mark(event("series|1", start: at(1, 10, month: 9), recurring: true), series: true)
        store.link(event("group", start: at(9, 10, month: 10)), toDeadline: "event:old", title: "Alt", until: at(10, 10, month: 10),
                   series: false)
        store.link(event("prep", start: at(9, 10, month: 10)), toDeadline: "task:local:A", title: "A", until: at(1, 0, month: 12),
                   series: false)
        store.dismissSuggestion(event("dismissed", start: at(1, 10, month: 10)))
        store.prune(now: testNow())
        #expect(store.marks().map(\.eventKey).sorted() == ["recent"])
        #expect(store.allLinks().map(\.deadlineKey) == ["task:local:A"])
        #expect(store.dismissedSuggestionIDs().isEmpty)
    }

    @Test func dismissedSuggestionsAreRemembered() {
        store.dismissSuggestion(event("exam", start: at(27, 10)))
        #expect(store.dismissedSuggestionIDs() == ["exam"])
    }
}
