import AIKit
import Foundation
import RemindersKit
import Testing
import TagwerkCore
@testable import Tagwerk

/// The editors of event, time block and day proposals (plan ki-vorschlaege-anpassen, task B2).
@MainActor
struct EventProposalEditorTests {
    private let calendars = [ListInfo(id: "cal-plan", title: "Plan", colorHex: nil, kind: .local),
                             ListInfo(id: "cal-family", title: "Familie", colorHex: nil, kind: .calDAV)]

    private func context() -> ProposalEditorContext {
        let calendars = calendars
        return ProposalEditorContext(calendar: testCalendar(), now: testNow, gitHubDirectory: { nil }, writableCalendars: { calendars })
    }

    private func call(_ name: String, _ json: String) -> ToolCall { ToolCall(id: "c1", name: name, arguments: Data(json.utf8)) }

    private func object(_ data: Data) throws -> [String: Any] { try #require(ProposalArguments.decode(data)) }

    private func event(_ json: String, name: String = "create_event") throws -> EventProposalEditor {
        try #require(EventProposalEditor(call: call(name, json), context: context()))
    }

    private func day(_ name: String, _ json: String) throws -> DayHoursProposalEditor {
        try #require(DayHoursProposalEditor(call: call(name, json), context: context()))
    }

    private let timed = #"{"title":"Elternabend","start":"2026-11-26T19:00","end":"2026-11-26T20:30","all_day":false,"calendar_id":"cal-family","location":"Schule","notes":null,"extra":true}"#

    // MARK: Events

    @Test func eventEditor_roundTripsStartEndCalendar() throws {
        let editor = try event(timed)

        let untouched = try object(editor.arguments())
        #expect(NSDictionary(dictionary: untouched).isEqual(to: try object(Data(timed.utf8))))

        editor.start = ProposalDue(day: PlanDay(year: 2026, month: 11, day: 27), minutes: 18 * 60 + 30)
        editor.end = ProposalDue(day: PlanDay(year: 2026, month: 11, day: 27), minutes: 20 * 60)
        editor.calendarID = "cal-plan"
        let changed = try object(editor.arguments())
        #expect(changed["start"] as? String == "2026-11-27T18:30")
        #expect(changed["end"] as? String == "2026-11-27T20:00")
        #expect(changed["calendar_id"] as? String == "cal-plan")
        #expect(changed["title"] as? String == "Elternabend")
        #expect(changed["extra"] as? Bool == true)
    }

    @Test func eventEditor_endBeforeStart_notAccepted() throws {
        let editor = try event(timed)
        #expect(editor.isValid)

        editor.end = ProposalDue(day: PlanDay(year: 2026, month: 11, day: 26), minutes: 18 * 60)
        #expect(!editor.orderIsValid)
        #expect(!editor.isValid)

        editor.end = ProposalDue(day: PlanDay(year: 2026, month: 11, day: 26), minutes: 19 * 60)
        #expect(!editor.isValid)
    }

    @Test func eventEditor_allDay_usesDaysAndInclusiveEnd() throws {
        let editor = try event(#"{"title":"Urlaub","start":"2026-12-01","end":"2026-12-03","all_day":true,"calendar_id":null,"location":null,"notes":null}"#)
        #expect(editor.start?.minutes == nil)
        #expect(editor.isValid)

        // A single day is valid for an all-day event: start and end are the same day (inclusive end).
        editor.end = editor.start
        #expect(editor.isValid)
        #expect(try object(editor.arguments())["end"] as? String == "2026-12-01")
    }

    @Test func eventEditor_switchingAllDay_changesTheMoments() throws {
        let editor = try event(timed)

        editor.setAllDay(true)
        var result = try object(editor.arguments())
        #expect(result["all_day"] as? Bool == true)
        #expect(result["start"] as? String == "2026-11-26")
        #expect(result["end"] as? String == "2026-11-26")

        editor.setAllDay(false)
        result = try object(editor.arguments())
        #expect(result["all_day"] as? Bool == false)
        #expect((result["start"] as? String)?.contains("T") == true)
    }

    @Test func eventEditor_emptyTitle_notValid() throws {
        let editor = try event(timed)
        editor.title = " "
        #expect(!editor.isValid)
    }

    @Test func updateEvent_untouchedFieldsStayNull() throws {
        let editor = try event(#"{"event_id":"e1","title":null,"start":null,"end":null,"all_day":null,"calendar_id":null,"location":null,"notes":null,"series":true}"#, name: "update_event")
        #expect(editor.isValid)

        editor.title = "Neuer Titel"
        let result = try object(editor.arguments())

        #expect(result["title"] as? String == "Neuer Titel")
        for key in ["start", "end", "all_day", "calendar_id", "location", "notes"] { #expect(result[key] is NSNull, "\(key)") }
        #expect(result["series"] as? Bool == true)
        #expect(result["event_id"] as? String == "e1")
    }

    @Test func updateEvent_startChangeWithoutEnd_keepsEndNull() throws {
        let editor = try event(#"{"event_id":"e1","title":null,"start":"2026-11-26T19:00","end":null,"all_day":null,"calendar_id":null,"location":null,"notes":null,"series":false}"#, name: "update_event")
        editor.start = ProposalDue(day: PlanDay(year: 2026, month: 11, day: 27), minutes: 19 * 60)

        let result = try object(editor.arguments())
        #expect(result["start"] as? String == "2026-11-27T19:00")
        #expect(result["end"] is NSNull)
        #expect(editor.isValid)
    }

    @Test func eventEditor_offersOnlyWritableCalendars() throws {
        let editor = try event(timed)
        #expect(editor.calendars.map(\.id) == ["cal-plan", "cal-family"])
        // A calendar the call names stays selectable even when it is not writable any more; the function refuses it.
        let stale = try event(timed.replacingOccurrences(of: "cal-family", with: "cal-gone"))
        #expect(stale.calendars.map(\.id) == ["cal-plan", "cal-family", "cal-gone"])
    }

    // MARK: Time blocks

    @Test func timeBlockEditor_keepsTaskLink() throws {
        let editor = try event(#"{"id":"github:ISSUE_1","day":"2026-11-27","start":"09:00","minutes":60}"#, name: "create_time_block")
        #expect(editor.isValid)

        editor.blockStart = 10 * 60 + 15
        editor.blockMinutes = 90
        editor.blockDay = PlanDay(year: 2026, month: 11, day: 30)
        let result = try object(editor.arguments())

        #expect(result["id"] as? String == "github:ISSUE_1")
        #expect(result["day"] as? String == "2026-11-30")
        #expect(result["start"] as? String == "10:15")
        #expect(result["minutes"] as? Int == 90)

        editor.blockMinutes = 0
        #expect(!editor.isValid)
    }

    // MARK: Day hours, lunch, planning

    @Test func dayHoursEditor_roundTrips() throws {
        let json = #"{"day":"2026-11-27","start":"08:00","end":"16:00","off":false}"#
        let editor = try day("set_day_hours", json)
        #expect(NSDictionary(dictionary: try object(editor.arguments())).isEqual(to: try object(Data(json.utf8))))

        editor.end = 17 * 60 + 30
        #expect(try object(editor.arguments())["end"] as? String == "17:30")

        editor.setOff(true)
        let off = try object(editor.arguments())
        #expect(off["off"] as? Bool == true)
        #expect(off["start"] is NSNull)
        #expect(off["end"] is NSNull)
        #expect(editor.isValid)

        editor.setOff(false)
        editor.start = 18 * 60
        #expect(!editor.isValid)
        #expect(editor.problem != nil)
    }

    @Test func dayHoursEditor_offDay_getsUsualHoursBack() throws {
        let editor = try day("set_day_hours", #"{"day":"2026-11-27","start":null,"end":null,"off":true}"#)
        editor.setOff(false)
        let result = try object(editor.arguments())
        #expect(result["off"] as? Bool == false)
        #expect(result["start"] as? String == "08:00")
        #expect(result["end"] as? String == "17:00")
    }

    @Test func lunchEditor_roundTrips() throws {
        let json = #"{"day":"2026-11-27","start":"12:30","minutes":45}"#
        let editor = try day("set_lunch", json)
        #expect(NSDictionary(dictionary: try object(editor.arguments())).isEqual(to: try object(Data(json.utf8))))

        editor.lunchMinutes = 30
        editor.start = 13 * 60
        var result = try object(editor.arguments())
        #expect(result["minutes"] as? Int == 30)
        #expect(result["start"] as? String == "13:00")

        editor.setLunch(false)
        result = try object(editor.arguments())
        #expect(result["minutes"] as? Int == 0)
        #expect(result["start"] is NSNull)
        #expect(editor.isValid)
    }

    @Test func planPeriodEditor_range() throws {
        let editor = try day("plan_period", #"{"scope":"day","day":"2026-11-27"}"#)
        editor.scope = .week
        editor.day = PlanDay(year: 2026, month: 11, day: 30)
        let result = try object(editor.arguments())
        #expect(result["scope"] as? String == "week")
        #expect(result["day"] as? String == "2026-11-30")
    }

    @Test func registry_knowsTheNewEditors() {
        for name in ["create_event", "update_event", "create_time_block", "set_day_hours", "set_lunch", "plan_period"] {
            #expect(AssistantModel.adjustableToolNames.contains(name), "\(name)")
        }
        for name in ["delete_event", "complete_task", "link_event_to_task", "mark_events_free"] {
            #expect(!AssistantModel.adjustableToolNames.contains(name), "\(name)")
        }
    }
}
