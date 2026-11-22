import Foundation
import Testing
@testable import TagwerkCore

@Suite struct SearchResultsTests {
    private let calendar = makeCalendar()
    private let now = instant(2026, 11, 19, 10)

    private func event(_ title: String, id: String? = nil, start: Date, recurring: Bool = false) -> CalendarEvent {
        var event = CalendarEvent(id: id ?? title, externalID: nil, calendarID: "cal", title: title, start: start,
                                  end: start.addingTimeInterval(3600), isAllDay: false, url: nil, isBusy: true, version: "1")
        event.isRecurring = recurring
        return event
    }

    private func completed(_ title: String, on date: Date?) -> CompletedTask {
        var item = makeItem(title, source: .reminders)
        item.isCompleted = true
        return CompletedTask(item: item, completedAt: date)
    }

    private func online(_ id: String, _ title: String) -> OnlineIssue {
        OnlineIssue(id: id, number: 1, title: title, repository: "octo/r", url: URL(string: "https://github.com/octo/r/issues/1")!,
                    updatedAt: now, marker: nil)
    }

    private func full(includeEmptyKinds: Bool = false) -> SearchInput {
        SearchInput(
            events: [event("Statistik kommend", start: instant(2026, 11, 20, 9)),
                     event("Statistik vorbei", start: instant(2026, 11, 10, 9))],
            calendarNames: ["cal": "Uni"],
            openTasks: [makeItem("Statistik lernen")],
            completed: [completed("Statistik Übung", on: instant(2026, 11, 12))],
            online: [online("I_1", "Statistik-Bug")],
            notes: [NoteSearchItem(id: UUID(), text: "Statistik Ideen", kindLabel: "Notiz", updatedAt: instant(2026, 11, 1))],
            shopping: [ShoppingSearchItem(id: "s", name: "Statistik-Heft", quantity: nil)])
    }

    private func make(_ input: SearchInput, filter: SearchFilter = .all, includeCompleted: Bool = true,
                      _ text: String = "statistik") -> SearchResults {
        SearchResults.make(query: SearchQuery(text)!, filter: filter, includeCompleted: includeCompleted, input: input,
                           now: now, calendar: calendar)
    }

    @Test func sectionsFollowSpecOrderAndDropEmptyOnes() {
        #expect(make(full()).sections.map(\.kind) == SearchSectionKind.allCases)
        var input = full()
        input.completed = []
        #expect(!make(input).sections.map(\.kind).contains(.completedTasks))
    }

    @Test func filterEventsShowsOnlyEventSections() {
        #expect(make(full(), filter: .events).sections.map(\.kind) == [.upcomingEvents, .pastEvents])
    }

    @Test func filterTasksShowsTaskSectionsOnly() {
        #expect(make(full(), filter: .tasks).sections.map(\.kind) == [.openTasks, .completedTasks, .online])
    }

    @Test func notesAndShoppingOnlyUnderAll() {
        #expect(make(full(), filter: .all).sections.map(\.kind).suffix(2) == [.notes, .shopping])
        for filter in [SearchFilter.events, .tasks] {
            let kinds = make(full(), filter: filter).sections.map(\.kind)
            #expect(!kinds.contains(.notes) && !kinds.contains(.shopping))
        }
    }

    @Test func completedOnlyWithSwitch() {
        let kinds = make(full(), includeCompleted: false).sections.map(\.kind)
        #expect(!kinds.contains(.completedTasks))
        #expect(kinds.contains(.shopping))
    }

    @Test func openTasksKeepAppOrder() {
        var input = full()
        let early = makeItem("Statistik B", due: DueDate(year: 2026, month: 11, day: 25))
        let late = makeItem("Statistik A", due: DueDate(year: 2026, month: 12, day: 25))
        let none = makeItem("Statistik C")
        input.openTasks = [none, late, early]
        let section = make(input, filter: .tasks).sections.first { $0.kind == .openTasks }!
        let titles = section.rows.compactMap { row -> String? in if case .task(let item, _) = row { item.title } else { nil } }
        #expect(titles == sortedTasks([none, late, early], calendar: calendar).map(\.title))
    }

    @Test func notesAreNewestFirstAndShoppingIsLast() {
        var input = full()
        input.notes = [NoteSearchItem(id: UUID(), text: "Statistik alt", kindLabel: "Notiz", updatedAt: instant(2026, 1, 1)),
                       NoteSearchItem(id: UUID(), text: "Statistik neu", kindLabel: "Notiz", updatedAt: instant(2026, 11, 18))]
        let section = make(input).sections.first { $0.kind == .notes }!
        let texts = section.rows.compactMap { row -> String? in if case .note(let note, _) = row { note.text } else { nil } }
        #expect(texts == ["Statistik neu", "Statistik alt"])
        #expect(make(input).sections.last?.kind == .shopping)
    }

    @Test func onlineHitsPassThroughInGivenOrder() {
        var input = full()
        input.online = [online("I_2", "Zweiter"), online("I_1", "Erster")]   // neither contains the query
        let section = make(input).sections.first { $0.kind == .online }!
        let ids = section.rows.compactMap { row -> String? in if case .online(let issue) = row { issue.id } else { nil } }
        #expect(ids == ["I_2", "I_1"])
    }

    @Test func eventsNilMeansNoEventSections() {
        var input = full()
        input.events = nil
        let kinds = make(input).sections.map(\.kind)
        #expect(!kinds.contains(.upcomingEvents) && !kinds.contains(.pastEvents))
    }

    @Test func eventsAreGroupedAfterFiltering() {
        var input = full()
        let weekly = (0..<4).map { event("Statistik Serie", id: "abc|\(1_795_000_000 + $0 * 604_800)", start: instant(2026, 11, 20 + $0 * 7, 9), recurring: true) }
        input.events = weekly
        let section = make(input, filter: .events).sections.first { $0.kind == .upcomingEvents }!
        #expect(section.rows.count == 1)
        guard case .event(let row, _) = section.rows[0] else { Issue.record("not an event row"); return }
        #expect(row.moreOccurrences == 3)
    }

    @Test func completedRowsCollapseEqualReminders() {
        var input = full()
        input.completed = [completed("Statistik Übung", on: instant(2026, 11, 5)), completed("Statistik Übung", on: instant(2026, 11, 12))]
        let section = make(input, filter: .tasks).sections.first { $0.kind == .completedTasks }!
        #expect(section.rows.count == 1)
    }

    @Test func rowIDsAreUniqueAcrossSections() {
        let ids = make(full()).sections.flatMap(\.rows).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func noteRow_findsAWordThatOnlyTheScanHas() {
        var input = full()
        input.notes = [NoteSearchItem(id: UUID(), text: "Mietvertrag\nUnterschrieben", kindLabel: "Notiz", updatedAt: instant(2026, 11, 1),
                                      scanText: "Die Kündigungsfrist beträgt drei Monate.")]
        let results = SearchResults.make(query: SearchQuery("kündigungsfrist")!, filter: .all, includeCompleted: true, input: input, now: now, calendar: calendar)
        let rows = results.sections.first { $0.kind == .notes }?.rows ?? []
        #expect(rows.count == 1)
        if case .note(_, let match)? = rows.first { #expect(match.snippet?.field == .scan) } else { Issue.record("Expected a note row") }
        // Without the scan text there is no hit.
        input.notes[0] = NoteSearchItem(id: input.notes[0].id, text: input.notes[0].text, kindLabel: "Notiz", updatedAt: input.notes[0].updatedAt)
        #expect(SearchResults.make(query: SearchQuery("kündigungsfrist")!, filter: .all, includeCompleted: true, input: input, now: now,
                                   calendar: calendar).sections.first { $0.kind == .notes } == nil)
    }
}
