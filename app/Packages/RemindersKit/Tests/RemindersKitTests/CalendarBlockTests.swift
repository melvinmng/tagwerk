import Foundation
import Testing
import TagwerkCore
@testable import RemindersKit

struct CalendarBlockTests {
    let event = CalendarEvent(id: "e1", externalID: nil, calendarID: "plan", title: "#42 Login", start: .now, end: .now,
                              isAllDay: false, url: nil, isBusy: true, version: "100.0")

    @Test func versionCheck_matchingOrForced_passes() throws {
        try CalendarBlockRules.checkVersion(of: event, expected: "100.0")
        try CalendarBlockRules.checkVersion(of: event, expected: nil)
    }

    @Test func versionCheck_stale_throwsConflict() {
        #expect(throws: TaskWriteError.self) { try CalendarBlockRules.checkVersion(of: event, expected: "99.0") }
    }

    @Test func occurrenceID_roundTrip() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let id = CalendarBlockRules.occurrenceID(eventIdentifier: "ABC:123", occurrence: date, isRecurring: true)
        #expect(CalendarBlockRules.parseOccurrenceID(id) == ("ABC:123", date))
        #expect(CalendarBlockRules.occurrenceID(eventIdentifier: "X", occurrence: date, isRecurring: false) == "X")
        #expect(CalendarBlockRules.parseOccurrenceID("X") == ("X", nil))
    }

    @Test func blockNotes_isFixedText() {
        #expect(CalendarBlockRules.blockNotes == "Geplant mit Tagwerk")
    }
}
