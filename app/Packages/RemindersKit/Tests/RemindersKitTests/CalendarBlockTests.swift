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

    @Test func checkEditable_readOnlyCalendar_throws() {
        var readOnly = event
        readOnly.isEditable = false
        #expect(throws: TaskWriteError.self) { try CalendarBlockRules.checkEditable(readOnly) }
        try? CalendarBlockRules.checkEditable(event)
    }

    @Test func checkEditable_invitation_throws() {
        var invitation = event
        invitation.isInvitation = true
        #expect(throws: TaskWriteError.self) { try CalendarBlockRules.checkEditable(invitation) }
    }

    @Test func uniqueIDs_sameIdentifierTwice_getOccurrenceSuffix() {
        let first = CalendarEvent(id: "LECTURE", externalID: nil, calendarID: "plan", title: "Vorlesung",
                                  start: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_005_400),
                                  isAllDay: false, url: nil, isBusy: true, version: "1")
        var second = first
        second.start = Date(timeIntervalSince1970: 1_800_018_000)
        second.end = Date(timeIntervalSince1970: 1_800_023_400)
        let unique = CalendarBlockRules.uniqueIDs([first, second, event])
        #expect(Set(unique.map(\.id)).count == 3)
        #expect(unique[0].id == "LECTURE|1800000000")
        #expect(unique[1].id == "LECTURE|1800018000")
        #expect(unique[2].id == "e1")  // unique IDs stay as they are
        #expect(CalendarBlockRules.parseOccurrenceID(unique[1].id) == ("LECTURE", second.start))
    }

    @Test func uniqueIDs_sameItemInTwoCalendars_getsCalendarScope() {
        let lecture = CalendarEvent(id: "ITEM", externalID: nil, calendarID: "lectures", title: "Vorlesung",
                                    start: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_005_400),
                                    isAllDay: false, url: nil, isBusy: true, version: "1")
        var busy = lecture
        busy.calendarID = "work"
        busy.title = "Busy"
        let unique = CalendarBlockRules.uniqueIDs([lecture, busy])
        #expect(unique[0].id != unique[1].id)
        let (identifier, occurrence) = CalendarBlockRules.parseOccurrenceID(unique[1].id)
        #expect(occurrence == lecture.start)
        #expect(CalendarBlockRules.parseCalendarScope(identifier) == ("ITEM", "work"))
        #expect(CalendarBlockRules.parseCalendarScope("PLAIN") == ("PLAIN", nil))
    }

    @Test func blockNotes_isFixedText() {
        #expect(CalendarBlockRules.blockNotes == "Geplant mit Tagwerk")
    }
}
