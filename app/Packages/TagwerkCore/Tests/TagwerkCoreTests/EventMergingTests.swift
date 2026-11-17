import Foundation
import Testing
@testable import TagwerkCore

struct EventMergingTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ id: String, _ calendar: String, title: String = "Seminar", minutes: Int = 90) -> CalendarEvent {
        CalendarEvent(id: id, externalID: nil, calendarID: calendar, title: title, start: start,
                      end: start.addingTimeInterval(TimeInterval(minutes * 60)), isAllDay: false, url: nil,
                      isBusy: true, version: "1")
    }

    @Test func sameTitleAndTime_inTwoCalendars_becomesOne() {
        let merged = mergingDuplicates([event("a", "work"), event("b", "shared", title: " seminar ")], links: [:])
        #expect(merged.map(\.id) == ["a"])
        #expect(merged.first?.mergedCalendarIDs == ["shared"])
    }

    @Test func sameCalendar_staysSeparate() {
        #expect(mergingDuplicates([event("a", "work"), event("b", "work")], links: [:]).count == 2)
    }

    @Test func differentEnd_staysSeparate() {
        #expect(mergingDuplicates([event("a", "work"), event("b", "shared", minutes: 60)], links: [:]).count == 2)
    }

    @Test func copyWithMoreInformation_isKept() {
        var detailed = event("b", "shared")
        detailed.notes = "Raum 2.14"
        detailed.location = "Campus"
        let merged = mergingDuplicates([event("a", "work"), detailed], links: [:])
        #expect(merged.map(\.id) == ["b"])
    }

    @Test func linkedCopy_isKept() {
        let merged = mergingDuplicates([event("a", "work"), event("b", "shared")],
                                       links: ["b": TaskID(source: .local, rawValue: "x")])
        #expect(merged.map(\.id) == ["b"])
        #expect(merged.first?.mergedCalendarIDs == ["work"])
    }
}

struct MergeSuggestionTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ id: String, _ calendar: String, _ title: String) -> CalendarEvent {
        CalendarEvent(id: id, externalID: nil, calendarID: calendar, title: title, start: start,
                      end: start.addingTimeInterval(5400), isAllDay: false, url: nil, isBusy: true, version: "1")
    }

    @Test func placeholderAtSameTime_isSuggested() {
        let suggestions = mergeSuggestions([event("real", "uni", "Vorlesung"), event("p", "work", "Busy")])
        #expect(suggestions == [MergeSuggestion(placeholderID: "p", keptID: "real", placeholderTitle: "Busy",
                                                placeholderCalendarID: "work")])
    }

    @Test func twoRealTitles_areNotSuggested() {
        #expect(mergeSuggestions([event("a", "uni", "Vorlesung"), event("b", "work", "Meeting")]).isEmpty)
    }

    @Test func identicalTitles_areSuggested_detailedCopyKept() {
        var detailed = event("b", "uni", "Seminar")
        detailed.location = "Raum 2.14"
        let suggestions = mergeSuggestions([event("a", "work", "Seminar"), detailed])
        #expect(suggestions.map(\.placeholderID) == ["a"])
        #expect(suggestions.first?.keptID == "b")
    }

    @Test func excludedCalendars_areNotSuggested() {
        #expect(mergeSuggestions([event("a", "work", "Seminar"), event("b", "uni", "Seminar")], excluding: ["uni"]).isEmpty)
    }

    @Test func sameCalendar_isNotSuggested() {
        #expect(mergeSuggestions([event("a", "work", "Vorlesung"), event("b", "work", "Busy")]).isEmpty)
    }
}
