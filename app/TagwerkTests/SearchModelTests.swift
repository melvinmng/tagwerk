import Foundation
import Testing
import GitHubKit
import TagwerkCore
@testable import Tagwerk

/// Stand-in for everything the search reads; records calls so tests can count them.
@MainActor
final class SearchProbe {
    var tasks: [TaskItem] = [makeTask("Statistik lernen", source: .local), makeTask("Mathe Übung", source: .local)]
    var events: [CalendarEvent]? = []
    var eventsByCall: [[CalendarEvent]] = []
    var completed: [CompletedTask] = []
    var notes: [NoteSearchItem] = []
    var shopping: [ShoppingSearchItem] = []
    /// What the settings index answers for a text; the texts asked are recorded.
    var settingsHits: [SettingsSearchItem] = []
    private(set) var settingsTexts: [String] = []
    /// The repositories and projects of the GitHub account; `nil` = GitHub not connected. The reads are counted.
    var githubTargets: [GitHubTargetSearchItem]?
    private(set) var githubTargetReads = 0
    var gate: Gate?
    /// `nil` = GitHub not connected.
    var online: Result<[OnlineIssue], IssueSearchError>?
    var onlineGate: Gate?
    /// `nil` = no shopping list set up.
    var checkedOff: [String]?
    private(set) var onlineTexts: [String] = []
    private(set) var eventIntervals: [DateInterval] = []
    private(set) var completedCalls = 0
    private(set) var sleeps: [Duration] = []

    func sources() -> SearchSources {
        var sources = SearchSources(
            openTasks: { self.tasks },
            events: { interval in
                self.eventIntervals.append(interval)
                if let gate = self.gate { await gate.wait() }
                if !self.eventsByCall.isEmpty { return self.eventsByCall.removeFirst() }
                return self.events
            },
            calendarNames: { ["cal": "Uni"] },
            completedTasks: {
                self.completedCalls += 1
                return self.completed
            },
            notes: { self.notes },
            shopping: { self.shopping },
            settings: { text in
                self.settingsTexts.append(text)
                return self.settingsHits
            })
        if githubTargets != nil {
            sources.githubTargets = {
                self.githubTargetReads += 1
                return self.githubTargets ?? []
            }
        }
        if checkedOff != nil {
            sources.checkOffShopping = { id in
                self.checkedOff?.append(id)
                self.shopping.removeAll { $0.id == id }
            }
        }
        if online != nil {
            sources.searchOnline = { text in
                self.onlineTexts.append(text)
                if let gate = self.onlineGate { await gate.wait() }
                return try self.online!.get()
            }
        }
        return sources
    }

    func model() -> SearchModel {
        SearchModel(sources: sources(), now: testNow, calendar: testCalendar(), sleep: { self.sleeps.append($0) })
    }
}

func searchEvent(_ title: String, id: String? = nil, start: Date, recurring: Bool = false) -> CalendarEvent {
    var event = CalendarEvent(id: id ?? title, externalID: nil, calendarID: "cal", title: title, start: start,
                              end: start.addingTimeInterval(3600), isAllDay: false, url: nil, isBusy: true, version: "1")
    event.isRecurring = recurring
    return event
}

@MainActor
struct SearchModelTests {
    let probe = SearchProbe()
    let calendar = testCalendar()

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: hour))!
    }

    private func titles(_ results: SearchResults) -> [String] {
        results.sections.flatMap(\.rows).compactMap { row in
            switch row {
            case .event(let row, _): row.event.title
            case .task(let item, _): item.title
            case .completed(let group, _): group.latest.item.title
            case .online(let issue): issue.title
            case .note(let note, _): note.text.split(separator: "\n").first.map(String.init) ?? note.text
            case .shopping(let item, _): item.name
            case .setting(let item): item.title
            case .githubTarget(let item): item.title
            }
        }
    }

    @Test func settingsHitsComeFromTheSourceWithTheTypedText() async {
        probe.settingsHits = [SettingsSearchItem(id: "capture.kilocalories", title: "Kalorien (Grundziel)", pathText: "Erfassen")]
        let model = probe.model()
        model.text = "kalorien"
        #expect(model.results.sections.map(\.kind) == [.settings])
        #expect(probe.settingsTexts.last == "kalorien")
        #expect(titles(model.results) == ["Kalorien (Grundziel)"])
    }

    @Test func settingsAreNotAskedBelowTwoCharactersNorUnderAFilter() async {
        probe.settingsHits = [SettingsSearchItem(id: "x", title: "Fokus-Timer", pathText: "")]
        let model = probe.model()
        model.text = "f"
        #expect(probe.settingsTexts.isEmpty)
        model.text = "fo"
        model.filter = .tasks
        #expect(!model.results.sections.map(\.kind).contains(.settings))
    }

    private func repository(_ fullName: String) -> GitHubTargetSearchItem {
        let parts = fullName.split(separator: "/").map(String.init)
        return GitHubTargetSearchItem(kind: .repository, targetID: fullName, title: parts[1], ownerText: parts[0])
    }

    @Test func githubTargetsAreReadOnceNoMatterHowOftenTheTextChanges() async {
        probe.githubTargets = [repository("octo/statistik-app"), repository("octo/notizen")]
        let model = probe.model()
        for text in ["st", "sta", "stat", "stati", "statistik"] {
            model.text = text
            await model.settle()
        }
        #expect(probe.githubTargetReads == 1)
        #expect(model.results.sections.map(\.kind) == [.openTasks, .githubTargets])
        #expect(titles(model.results).suffix(1) == ["statistik-app"])
    }

    @Test func githubTargetsAreNotReadBeforeTheFirstSearchText() async {
        probe.githubTargets = [repository("octo/statistik-app")]
        let model = probe.model()
        model.text = "s"
        await model.settle()
        #expect(probe.githubTargetReads == 0)
        model.text = "st"
        await model.settle()
        #expect(probe.githubTargetReads == 1)
    }

    @Test func withoutGitHubThereIsNoSourceAndNoSection() async {
        let model = probe.model()
        model.text = "statistik"
        await model.settle()
        #expect(probe.githubTargetReads == 0)
        #expect(!model.results.sections.map(\.kind).contains(.githubTargets))
    }

    @Test func githubTargetsAppearOnlyUnderTheFilterAll() async {
        probe.githubTargets = [repository("octo/statistik-app")]
        let model = probe.model()
        model.text = "statistik"
        await model.settle()
        #expect(model.results.sections.map(\.kind).contains(.githubTargets))
        model.filter = .tasks
        #expect(!model.results.sections.map(\.kind).contains(.githubTargets))
        model.filter = .all
        #expect(model.results.sections.map(\.kind).contains(.githubTargets))
        #expect(probe.githubTargetReads == 1)
    }

    @Test func aSourceWithoutCandidatesLeavesNoSectionAndNoMessage() async {
        probe.githubTargets = []
        let model = probe.model()
        model.text = "statistik"
        await model.settle()
        #expect(!model.results.sections.map(\.kind).contains(.githubTargets))
        #expect(model.onlineState == .idle)
    }

    @Test func githubTargetsAreForgottenWhenTheSheetCloses() async {
        probe.githubTargets = [repository("octo/statistik-app")]
        let model = probe.model()
        model.text = "statistik"
        await model.settle()
        model.close()
        model.evaluate()
        #expect(model.results.isEmpty)
    }

    @Test func belowTwoCharactersNothingLoads() async {
        let model = probe.model()
        model.text = "a"
        await model.settle()
        #expect(model.eventState == .idle)
        #expect(probe.eventIntervals.isEmpty)
        #expect(model.results.isEmpty)
    }

    @Test func tasksFilterAtOnceEventsAfter250Milliseconds() async {
        probe.events = [searchEvent("Statistik Klausur", start: day(2026, 11, 25))]
        let model = probe.model()
        model.text = "st"
        #expect(model.results.sections.map(\.kind) == [.openTasks])     // before the debounce ends
        await model.settle()
        #expect(probe.sleeps == [.milliseconds(250)])
        #expect(model.results.sections.map(\.kind) == [.upcomingEvents, .openTasks])
    }

    @Test func eventsLoadOncePerSheet() async {
        let model = probe.model()
        model.text = "st"
        model.text = "sta"
        await model.settle()
        model.text = "stat"
        await model.settle()
        #expect(probe.eventIntervals.count == 1)
    }

    @Test func initialWindowIsSixMonthsBackTwelveAhead() async {
        let model = probe.model()
        model.text = "st"
        await model.settle()
        #expect(probe.eventIntervals == [SearchWindow.initial(now: testNow(), calendar: calendar)])
        #expect(model.windowStart == SearchWindow.initial(now: testNow(), calendar: calendar).start)
    }

    @Test func lateEventLoadNeverOverwritesNewerQuery() async {
        probe.events = [searchEvent("Statistik Klausur", start: day(2026, 11, 25)), searchEvent("Mathe Klausur", start: day(2026, 11, 26))]
        let gate = Gate()
        probe.gate = gate
        let model = probe.model()
        model.text = "statistik"
        await waitUntil { probe.eventIntervals.count == 1 }
        model.text = "mathe"
        gate.open()
        await model.settle()
        #expect(model.query == SearchQuery("mathe"))
        #expect(titles(model.results).allSatisfy { SearchText.fold($0).contains("mathe") })
        #expect(titles(model.results).contains("Mathe Klausur"))
        model.close()
        model.text = "statistik"
        await model.settle()
        #expect(model.results.isEmpty)
    }

    @Test func closingBeforeTheFetchEndsIgnoresTheAnswer() async {
        probe.events = [searchEvent("Statistik Klausur", start: day(2026, 11, 25))]
        let gate = Gate()
        probe.gate = gate
        let model = probe.model()
        model.text = "statistik"
        await waitUntil { probe.eventIntervals.count == 1 }
        model.close()
        gate.open()
        await model.settle()
        #expect(model.results.isEmpty)
    }

    @Test func noCalendarAccessIsReportedOnce() async {
        probe.events = nil
        let model = probe.model()
        model.text = "statistik"
        await model.settle()
        #expect(model.eventState == .noAccess)
        #expect(model.results.sections.map(\.kind) == [.openTasks])
        model.text = "statistik lernen"
        await model.settle()
        #expect(probe.eventIntervals.count == 1)
    }

    @Test func extendWindowAppendsOneYearAndKeepsItAcrossQueries() async {
        probe.eventsByCall = [[], [searchEvent("Statistik 2025", start: day(2025, 10, 1))]]
        let model = probe.model()
        model.text = "statistik"
        await model.settle()
        let start = model.windowStart
        await model.extendWindow()
        #expect(model.windowStart == calendar.date(byAdding: .year, value: -1, to: start))
        #expect(probe.eventIntervals.last == SearchWindow.extended(before: start, calendar: calendar))
        #expect(titles(model.results).contains("Statistik 2025"))
        model.text = "statistik 2025"
        #expect(titles(model.results).contains("Statistik 2025"))
        #expect(model.windowStart == calendar.date(byAdding: .year, value: -1, to: start))
        #expect(model.canExtendWindow)
    }

    @Test func emptyExtensionHidesTheRow() async {
        probe.eventsByCall = [[], []]
        let model = probe.model()
        model.text = "statistik"
        await model.settle()
        await model.extendWindow()
        #expect(!model.canExtendWindow)
    }

    @Test func completedReloadedEachTimeSwitchTurnsOn() async {
        var done = makeTask("Statistik Übung", source: .reminders)
        done.isCompleted = true
        probe.completed = [CompletedTask(item: done, completedAt: day(2026, 11, 12))]
        let model = probe.model()
        model.text = "statistik"
        #expect(probe.completedCalls == 0)
        model.includeCompleted = true
        await model.settle()
        model.includeCompleted = false
        model.includeCompleted = true
        await model.settle()
        #expect(probe.completedCalls == 2)
        #expect(model.results.sections.map(\.kind).contains(.completedTasks))
        model.includeCompleted = false
        #expect(!model.results.sections.map(\.kind).contains(.completedTasks))
    }

    @Test func completedTaskCompletedWhileSwitchWasOff_showsAfterTurningItOnAgain() async {
        let model = probe.model()
        model.text = "statistik"
        model.includeCompleted = true
        await model.settle()
        #expect(!model.results.sections.map(\.kind).contains(.completedTasks))
        model.includeCompleted = false
        var done = makeTask("Statistik Übung", source: .reminders)
        done.isCompleted = true
        probe.completed = [CompletedTask(item: done, completedAt: day(2026, 11, 12))]
        model.includeCompleted = true
        await model.settle()
        #expect(model.results.sections.map(\.kind).contains(.completedTasks))
    }

    @Test func eventStoreChangeRefetchesLoadedWindow() async {
        probe.eventsByCall = [[searchEvent("Statistik alt", start: day(2026, 11, 25))],
                              [searchEvent("Statistik neu", start: day(2026, 11, 26))]]
        let model = probe.model()
        model.text = "statistik"
        await model.settle()
        #expect(titles(model.results).contains("Statistik alt"))
        model.eventStoreChanged()
        await waitUntil { titles(model.results).contains("Statistik neu") }
        #expect(!titles(model.results).contains("Statistik alt"))
        #expect(probe.eventIntervals.count == 2)
    }

    @Test func eventStoreChangeWhileLoadingRefetchesOnce() async {
        let gate = Gate()
        probe.gate = gate
        let model = probe.model()
        model.text = "statistik"
        await waitUntil { probe.eventIntervals.count == 1 }
        model.eventStoreChanged()
        gate.open()
        await model.settle()
        await waitUntil { probe.eventIntervals.count == 2 }
        #expect(probe.eventIntervals.count == 2)
    }

    @Test func refreshReadsTasksAgain() async {
        let model = probe.model()
        model.text = "statistik"
        await model.settle()
        probe.tasks = []
        await model.refresh()
        #expect(titles(model.results).isEmpty)
    }

    @Test func refreshReloadsCompletedTasksOnlyWhileTheSwitchIsOn() async {
        let model = probe.model()
        model.text = "statistik"
        await model.refresh()
        #expect(probe.completedCalls == 0)
        model.includeCompleted = true
        await model.settle()
        #expect(probe.completedCalls == 1)
        var done = makeTask("Statistik Übung", source: .reminders)
        done.isCompleted = true
        probe.completed = [CompletedTask(item: done, completedAt: day(2026, 11, 12))]
        await model.refresh()
        #expect(probe.completedCalls == 2)
        #expect(model.results.sections.map(\.kind).contains(.completedTasks))
    }

    private func issue(_ id: String, _ title: String, marker: OnlineIssueMarker? = .closed) -> OnlineIssue {
        OnlineIssue(id: id, number: 42, title: title, repository: "octo/r", url: URL(string: "https://github.com/octo/r/issues/42")!,
                    updatedAt: testNow(), marker: marker)
    }

    @Test func onlineSearchRunsOnlyOnTap() async {
        probe.online = .success([issue("I_1", "Statistik-Bug")])
        let model = probe.model()
        model.text = "  statistik "
        await model.settle()
        #expect(probe.onlineTexts.isEmpty)
        #expect(model.showsOnlineSearchRow)
        await model.searchOnline()
        #expect(probe.onlineTexts == ["statistik"])
        #expect(model.onlineState == .loaded)
        #expect(model.results.sections.map(\.kind).contains(.online))
        #expect(!model.showsOnlineSearchRow)
    }

    @Test func onlineSectionDisappearsWhenTheTextChanges() async {
        probe.online = .success([issue("I_1", "Statistik-Bug")])
        let model = probe.model()
        model.text = "statistik"
        await model.searchOnline()
        #expect(model.results.sections.map(\.kind).contains(.online))
        model.text = "statistik lernen"
        #expect(model.onlineState == .idle)
        #expect(!model.results.sections.map(\.kind).contains(.online))
        #expect(model.showsOnlineSearchRow)
    }

    @Test func onlineFailureKeepsLocalResults() async {
        probe.online = .failure(.offline)
        let model = probe.model()
        model.text = "statistik"
        let before = model.results.sections.map(\.kind)
        await model.searchOnline()
        #expect(model.onlineState == .failed(.offline))
        #expect(model.results.sections.map(\.kind) == before)
        #expect(model.showsOnlineSearchRow)          // "Erneut versuchen"
    }

    @Test func onlineRowHiddenWithoutGitHubAndUnderEventsFilter() async {
        let withoutGitHub = probe.model()
        withoutGitHub.text = "statistik"
        #expect(!withoutGitHub.showsOnlineSearchRow)
        probe.online = .success([])
        let model = probe.model()
        #expect(!model.showsOnlineSearchRow)          // no text yet
        model.text = "statistik"
        #expect(model.showsOnlineSearchRow)
        model.filter = .events
        #expect(!model.showsOnlineSearchRow)
    }

    @Test func lateOnlineAnswerNeverOverwritesNewerQuery() async {
        probe.online = .success([issue("I_1", "Statistik-Bug")])
        let gate = Gate()
        probe.onlineGate = gate
        let model = probe.model()
        model.text = "statistik"
        let search = Task { await model.searchOnline() }
        await waitUntil { probe.onlineTexts.count == 1 }
        model.text = "mathe"
        gate.open()
        await search.value
        #expect(model.onlineState == .idle)
        #expect(!model.results.sections.map(\.kind).contains(.online))
    }

    @Test func closedModelIgnoresTheOnlineAnswer() async {
        probe.online = .success([issue("I_1", "Statistik-Bug")])
        let gate = Gate()
        probe.onlineGate = gate
        let model = probe.model()
        model.text = "statistik"
        let search = Task { await model.searchOnline() }
        await waitUntil { probe.onlineTexts.count == 1 }
        model.close()
        gate.open()
        await search.value
        #expect(model.results.isEmpty)
    }

    @Test func notesMatchTextAndKindLabel() async {
        probe.notes = [NoteSearchItem(id: UUID(), text: "Ideen Hausarbeit\nGliederung", kindLabel: "Notiz", updatedAt: testNow()),
                       NoteSearchItem(id: UUID(), text: "Ruhiger Tag", kindLabel: "Tagesabschluss", updatedAt: testNow(), dayKey: "2026-11-17")]
        let model = probe.model()
        model.text = "hausarbeit"
        #expect(model.results.sections.map(\.kind) == [.notes])
        model.text = "tagesabschluss"
        #expect(titles(model.results) == ["Ruhiger Tag"])
        model.filter = .tasks
        #expect(model.results.isEmpty)
    }

    @Test func shoppingMatchesNameAndQuantity() async {
        probe.shopping = [ShoppingSearchItem(id: "1", name: "Hafermilch", quantity: "2 Packungen")]
        let model = probe.model()
        model.text = "packungen"
        #expect(model.results.sections.map(\.kind) == [.shopping])
        model.text = "hafer"
        #expect(titles(model.results) == ["Hafermilch"])
    }

    @Test func checkOffRemovesTheShoppingRow() async {
        probe.checkedOff = []
        probe.shopping = [ShoppingSearchItem(id: "1", name: "Hafermilch", quantity: nil)]
        let model = probe.model()
        model.text = "hafermilch"
        #expect(model.results.sections.map(\.kind) == [.shopping])
        await model.checkOff(ShoppingSearchItem(id: "1", name: "Hafermilch", quantity: nil))
        #expect(probe.checkedOff == ["1"])
        #expect(model.results.isEmpty)
    }

    @Test func checkOffWithoutAShoppingListDoesNothing() async {
        probe.shopping = [ShoppingSearchItem(id: "1", name: "Hafermilch", quantity: nil)]
        let model = probe.model()
        model.text = "hafermilch"
        await model.checkOff(ShoppingSearchItem(id: "1", name: "Hafermilch", quantity: nil))
        #expect(model.results.sections.map(\.kind) == [.shopping])
    }

    @Test func sectionsStayHiddenWithoutPhaseFiveData() async {
        let model = probe.model()
        model.text = "statistik"
        #expect(!model.results.sections.map(\.kind).contains(.notes) && !model.results.sections.map(\.kind).contains(.shopping))
    }

    @Test func sectionsShowTwentyFiveRowsThenMore() async {
        probe.tasks = (1...60).map { makeTask("Treffer \($0)", source: .local) }
        let model = probe.model()
        model.text = "treffer"
        let section = model.results.sections[0]
        #expect(model.visibleRows(in: section).count == 25)
        #expect(model.hiddenCount(in: section) == 35)
        model.showMore(.openTasks)
        #expect(model.visibleRows(in: section).count == 50)
        #expect(model.hiddenCount(in: section) == 10)
        model.text = "treffer 1"
        #expect(model.visibleRows(in: model.results.sections[0]).count <= 25)
    }

    @Test func filterChangeReevaluatesAtOnce() async {
        probe.events = [searchEvent("Statistik Klausur", start: day(2026, 11, 25))]
        let model = probe.model()
        model.text = "statistik"
        await model.settle()
        model.filter = .events
        #expect(model.results.sections.map(\.kind) == [.upcomingEvents])
        model.filter = .tasks
        #expect(model.results.sections.map(\.kind) == [.openTasks])
    }

    @Test func notesAndShoppingAreReadAtEachEvaluation() async {
        let model = probe.model()
        model.text = "hafer"
        #expect(model.results.isEmpty)
        probe.shopping = [ShoppingSearchItem(id: "1", name: "Hafermilch", quantity: nil)]
        model.evaluate()
        #expect(model.results.sections.map(\.kind) == [.shopping])
    }
}
