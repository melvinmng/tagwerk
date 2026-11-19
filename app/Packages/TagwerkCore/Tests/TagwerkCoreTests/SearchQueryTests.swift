import Foundation
import Testing
@testable import TagwerkCore

@Suite struct SearchQueryTests {
    private func doc(title: String) -> SearchDocument {
        SearchDocument(task: makeItem(title))
    }

    private func event(_ title: String, location: String? = nil, notes: String? = nil) -> CalendarEvent {
        var event = CalendarEvent(id: title, externalID: nil, calendarID: "cal", title: title,
                                  start: instant(2026, 11, 20, 9), end: instant(2026, 11, 20, 10),
                                  isAllDay: false, url: nil, isBusy: true, version: "1")
        event.location = location
        event.notes = notes
        return event
    }

    private func task(_ title: String, notes: String? = nil) -> TaskItem {
        var item = makeItem(title)
        item.notes = notes
        return item
    }

    private func github(_ title: String, url: String) -> TaskItem {
        var item = makeItem(title, source: .github)
        item.url = URL(string: url)
        return item
    }

    @Test func foldingIgnoresCaseAccentsWidthAndSharpS() {
        #expect(SearchText.fold("Übung") == "ubung")
        #expect(SearchText.fold("Straße") == "strasse")
        #expect(SearchQuery("ubung")!.match(doc(title: "Übungsblatt 3")) != nil)
        #expect(SearchQuery("strasse")!.match(doc(title: "Hauptstraße 5")) != nil)
        #expect(SearchQuery("ue")!.match(doc(title: "Übung")) == nil)
    }

    @Test func everyWordMustMatchSomeField() {
        let lecture = SearchDocument(event: event("Statistik", location: "Hörsaal 2"), calendarName: "Uni")
        #expect(SearchQuery("statistik hörsaal")!.match(lecture)?.matchedFields == [.title, .location])
        #expect(SearchQuery("statistik mensa")!.match(lecture) == nil)
        #expect(SearchQuery("uni")!.match(lecture)?.matchedFields == [.calendar])
    }

    @Test func queryNeedsTwoCharactersAfterTrimming() {
        #expect(SearchQuery(" a ") == nil)
        #expect(SearchQuery("") == nil)
        #expect(SearchQuery("ab") != nil)
        #expect(SearchQuery("  ab  ")?.text == "ab")
    }

    @Test func issueNumberRules() {
        let issue42 = SearchDocument(task: github("Login-Fehler", url: "https://github.com/o/r/issues/42"))
        let issue7 = SearchDocument(task: github("Fehler 42 beheben", url: "https://github.com/o/r/issues/7"))
        #expect(SearchQuery("#42")!.match(issue42)?.matchedFields == [.issueNumber])
        #expect(SearchQuery("#42")!.match(issue7) == nil)
        #expect(SearchQuery("42")!.match(issue42) != nil)
        #expect(SearchQuery("42")!.match(issue7)?.matchedFields == [.title])
        #expect(SearchQuery("#4")!.match(issue42) == nil)
    }

    @Test func onlyGitHubTasksCarryAnIssueNumber() {
        var local = makeItem("Lokal")
        local.url = URL(string: "https://example.com/issues/42")
        #expect(SearchQuery("#42")!.match(SearchDocument(task: local)) == nil)
    }

    @Test func taskFieldsIncludeContainerProjectsAndLabels() {
        var item = makeItem("Aufgabe", source: .github)
        item.container = TaskContainer(id: "r", name: "octo/tagwerk", colorHex: nil)
        item.subContainers = [TaskContainer(id: "p", name: "Roadmap", colorHex: nil)]
        item.labels = ["bug", "Dringend"]
        let document = SearchDocument(task: item)
        #expect(SearchQuery("tagwerk")!.match(document)?.matchedFields == [.container])
        #expect(SearchQuery("roadmap")!.match(document)?.matchedFields == [.project])
        #expect(SearchQuery("dringend")!.match(document)?.matchedFields == [.label])
        #expect(SearchQuery("dringend")!.match(document)?.snippet?.text == "Dringend")
    }

    @Test func snippetAppearsOnlyWithoutTitleHit() {
        let long = String(repeating: "x", count: 200) + " Klausur " + String(repeating: "y", count: 200)
        let match = SearchQuery("klausur")!.match(SearchDocument(task: task("Lernen", notes: long)))!
        #expect(match.titleRanges.isEmpty)
        #expect(match.snippet?.field == .notes)
        #expect(match.snippet!.text.count <= 80)
        #expect(SearchText.fold(match.snippet!.text).contains("klausur"))
        #expect(match.snippet!.ranges.count == 1)
        #expect(SearchQuery("lernen")!.match(SearchDocument(task: task("Lernen", notes: long)))!.snippet == nil)
    }

    @Test func titleRangesCoverEveryWord() {
        let title = "Statistik Klausur"
        let match = SearchQuery("klausur stat")!.match(doc(title: title))!
        #expect(match.titleRanges.map { String(title[$0]) } == ["Stat", "Klausur"])
    }

    @Test func noteAndShoppingDocuments() {
        let note = SearchDocument(noteText: "Ideen Hausarbeit\nGliederung prüfen", kindLabel: "Tagesabschluss")
        #expect(note.title == "Ideen Hausarbeit")
        #expect(SearchQuery("hausarbeit")!.match(note)?.matchedFields == [.title])
        #expect(SearchQuery("gliederung")!.match(note)?.matchedFields == [.notes])
        #expect(SearchQuery("tagesabschluss")!.match(note)?.matchedFields == [.kind])
        let article = SearchDocument(shoppingName: "Hafermilch", quantity: "2 Packungen")
        #expect(SearchQuery("packungen")!.match(article)?.matchedFields == [.quantity])
    }

    @Test func specialCharactersAreSearchedLiterally() {
        #expect(SearchQuery("c++")!.match(doc(title: "C++ Übung")) != nil)
        #expect(SearchQuery("a.b")!.match(doc(title: "axb")) == nil)
        #expect(SearchQuery("#abc")!.match(doc(title: "Kanal #abc")) != nil)
        #expect(SearchQuery("((")!.match(doc(title: "ohne Klammern")) == nil)
    }

    @Test func highlightRangesAreValidInOriginalString() {
        for title in ["Hauptstraße 5", "🎓 Straßenfest", "ＳＴＲＡＳＳＥ 1", "Stra\u{0308}sse"] {
            let ranges = SearchText.ranges(of: "strasse", in: title)
            #expect(ranges.count == 1)
            if let range = ranges.first {
                #expect(SearchText.fold(String(title[range])) == "strasse")
            }
        }
        // A word that ends inside the folded "ss" still covers the whole "ß".
        let title = "Straße"
        #expect(SearchText.ranges(of: "stras", in: title).map { String(title[$0]) } == ["Straß"])
    }
}
