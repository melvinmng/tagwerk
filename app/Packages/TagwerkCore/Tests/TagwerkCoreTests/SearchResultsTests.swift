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

    private func repository(_ owner: String, _ name: String) -> GitHubTargetSearchItem {
        GitHubTargetSearchItem(kind: .repository, targetID: "\(owner)/\(name)", title: name, ownerText: owner)
    }

    private func project(_ id: String, _ title: String, number: Int = 1, owner: String = "octo") -> GitHubTargetSearchItem {
        GitHubTargetSearchItem(kind: .project, targetID: id, title: title, ownerText: owner, projectNumber: number)
    }

    private func targetIDs(_ results: SearchResults) -> [String] {
        results.sections.first { $0.kind == .githubTargets }?.rows.compactMap { row -> String? in
            if case .githubTarget(let item) = row { item.targetID } else { nil }
        } ?? []
    }

    private func make(_ input: SearchInput, filter: SearchFilter = .all, includeCompleted: Bool = true,
                      _ text: String = "statistik") -> SearchResults {
        SearchResults.make(query: SearchQuery(text)!, filter: filter, includeCompleted: includeCompleted, input: input,
                           now: now, calendar: calendar)
    }

    @Test func sectionsFollowSpecOrderAndDropEmptyOnes() {
        var input = full()
        input.settings = [SettingsSearchItem(id: "s", title: "Erfassen", pathText: "")]
        input.githubTargets = [repository("octo", "statistik-app")]
        #expect(make(input).sections.map(\.kind) == SearchSectionKind.allCases)
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

    private func settings(_ count: Int) -> [SettingsSearchItem] {
        (1...count).map { SettingsSearchItem(id: "s\($0)", title: "Einstellung \($0)", pathText: "Erfassen") }
    }

    @Test func settingsOnlyUnderAll() {
        var input = full()
        input.settings = settings(2)
        #expect(make(input, filter: .all).sections.map(\.kind).contains(.settings))
        for filter in [SearchFilter.events, .tasks] {
            #expect(!make(input, filter: filter).sections.map(\.kind).contains(.settings))
        }
    }

    @Test func settingsAreTheLastSection() {
        var input = full()
        input.settings = settings(1)
        #expect(make(input).sections.last?.kind == .settings)
    }

    @Test func settingsAreCappedAtFiveInGivenOrder() {
        var input = SearchInput()
        input.settings = settings(8)
        let section = make(input).sections.first { $0.kind == .settings }!
        let ids = section.rows.compactMap { row -> String? in if case .setting(let item) = row { item.id } else { nil } }
        #expect(ids == ["s1", "s2", "s3", "s4", "s5"])
        #expect(SearchResults.settingsLimit == 5)
    }

    @Test func settingsAreNotFilteredAgain() {
        // The caller matched the settings with its own index (titles and keywords); the text of the query need not occur in a title.
        var input = SearchInput()
        input.settings = [SettingsSearchItem(id: "k", title: "Kalorien (Grundziel)", pathText: "Erfassen")]
        #expect(make(input, "ernährung").sections.first?.kind == .settings)
    }

    @Test func noSettingsMeansNoSection() {
        #expect(!make(full()).sections.map(\.kind).contains(.settings))
    }

    @Test func githubTargetsOnlyUnderAll() {
        var input = SearchInput()
        input.githubTargets = [repository("octo", "statistik-app")]
        #expect(make(input, filter: .all).sections.map(\.kind) == [.githubTargets])
        for filter in [SearchFilter.events, .tasks] {
            #expect(make(input, filter: filter).isEmpty)
        }
    }

    @Test func githubTargetsComeBeforeTheSettings() {
        var input = SearchInput()
        input.githubTargets = [repository("octo", "statistik-app")]
        input.settings = settings(1)
        #expect(make(input).sections.map(\.kind) == [.githubTargets, .settings])
    }

    @Test func githubTargetsAreMatchedByNameOwnerAndTitleIgnoringCaseAndUmlauts() {
        var input = SearchInput()
        input.githubTargets = [repository("octo", "Statistik-App"), repository("uni-münchen", "notizen"), project("P1", "Prüfungsplanung"),
                               project("P2", "Haushalt")]
        #expect(targetIDs(make(input, "STATISTIK")) == ["octo/Statistik-App"])
        #expect(targetIDs(make(input, "münchen")) == ["uni-münchen/notizen"])
        #expect(targetIDs(make(input, "prufungsplanung")) == ["P1"])
        #expect(targetIDs(make(input, "PRÜFUNG")) == ["P1"])
        #expect(targetIDs(make(input, "octo/stat")) == ["octo/Statistik-App"])
    }

    @Test func githubTargetsNeedEveryWordOfTheQuery() {
        var input = SearchInput()
        input.githubTargets = [repository("octo", "statistik-app"), repository("octo", "statistik-web"), project("P1", "Statistik")]
        #expect(targetIDs(make(input, "octo web")) == ["octo/statistik-web"])
        #expect(targetIDs(make(input, "statistik nirgends")) == [])
    }

    @Test func githubTargetsListRepositoriesBeforeProjectsAndKeepTheOrderOtherwise() {
        var input = SearchInput()
        input.githubTargets = [project("P1", "Statistik"), repository("octo", "statistik-b"), repository("octo", "statistik-a")]
        #expect(targetIDs(make(input)) == ["octo/statistik-b", "octo/statistik-a", "P1"])
    }

    @Test func githubTargetsThatStartAWordComeBeforeThoseThatContainTheText() {
        var input = SearchInput()
        input.githubTargets = [repository("octo", "xstatistik"), repository("octo", "statistik")]
        #expect(targetIDs(make(input)) == ["octo/statistik", "octo/xstatistik"])
    }

    @Test func githubTargetsAreNotCappedBecausePagingOfTheSheetApplies() {
        var input = SearchInput()
        input.githubTargets = (1...40).map { repository("octo", "statistik-\($0)") }
        #expect(targetIDs(make(input)).count == 40)
    }

    @Test func githubTargetIdentityDistinguishesKindWithTheSameID() {
        #expect(repository("a", "b").id != project("a/b", "b").id)
    }

    @Test func aTapOpensTheProjectProgressOfTheHit() {
        let repository = repository("octo", "statistik-app").progressReference
        #expect(repository == ProjectProgressReference(kind: .gitHubRepository, id: "octo/statistik-app", title: "octo/statistik-app"))
        let project = project("PVT_1", "Prüfungsplanung").progressReference
        #expect(project == ProjectProgressReference(kind: .gitHubProject, id: "PVT_1", title: "Prüfungsplanung"))
    }

    @Test func noGithubTargetsMeansNoSection() {
        #expect(!make(full()).sections.map(\.kind).contains(.githubTargets))
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
