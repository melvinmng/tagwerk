import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct FocusUpNextTests {
    private let dayStart = Date(timeIntervalSince1970: 1_800_000_000)

    private func date(_ minutes: Int) -> Date { dayStart.addingTimeInterval(TimeInterval(minutes * 60)) }

    private func event(_ id: String, _ title: String, from: Int, to: Int) -> CalendarEvent {
        CalendarEvent(id: id, externalID: nil, calendarID: "cal", title: title, start: date(from), end: date(to),
                      isAllDay: false, url: nil, isBusy: true, version: "1")
    }

    private func block(_ id: String, from: Int, to: Int) -> TimelineRow {
        .block(event(id, "Bericht schreiben", from: from, to: to), TaskID(source: .local, rawValue: id))
    }

    private func departure(_ eventID: String, at start: Int, minutes: Int) -> TimelineRow {
        .travel(TravelSegment(eventID: eventID, range: start..<(start + minutes), minutes: minutes, origin: .home))
    }

    private var timeline: [TimelineRow] {
        [.event(event("a", "Mittag mit Jana", from: 13 * 60, to: 14 * 60)),
         block("b", from: 14 * 60, to: 15 * 60),
         .gap(15 * 60..<(15 * 60 + 5)),
         departure("c", at: 15 * 60 + 5, minutes: 25),
         .event(event("c", "Zahnarzt", from: 15 * 60 + 30, to: 16 * 60 + 30))]
    }

    @Test func rows_startWithTheBlockEnd() {
        let rows = FocusUpNext.rows(timeline: timeline, blockEventID: "b", nowMinutes: 14 * 60 + 32, dayStart: dayStart)
        #expect(rows.map(\.startMinutes) == [15 * 60, 15 * 60 + 5, 15 * 60 + 30])
        #expect(rows.first?.kind == .blockEnd(title: "Bericht schreiben"))
    }

    @Test func rows_includeDepartures() {
        let rows = FocusUpNext.rows(timeline: timeline, blockEventID: "b", nowMinutes: 14 * 60 + 32, dayStart: dayStart)
        #expect(rows[1].kind == .departure(minutes: 25))
        #expect(rows[2].kind == .entry(title: "Zahnarzt", endMinutes: 16 * 60 + 30))
    }

    @Test func rows_skipGapsAndPastEntries() {
        let rows = FocusUpNext.rows(timeline: timeline + [.lunch(startMinutes: 14 * 60 + 40, minutes: 20)], blockEventID: nil,
                                    nowMinutes: 14 * 60 + 32, dayStart: dayStart)
        // The lunch row, the past event "Mittag mit Jana", the running block and the gap are not listed.
        #expect(rows.map(\.startMinutes) == [15 * 60 + 5, 15 * 60 + 30])
        #expect(rows.allSatisfy { if case .blockEnd = $0.kind { false } else { true } })
    }

    @Test func rows_respectTheLimit() {
        let rows = FocusUpNext.rows(timeline: timeline, blockEventID: "b", nowMinutes: 14 * 60 + 32, dayStart: dayStart, limit: 2)
        #expect(rows.count == 2)
        #expect(FocusUpNext.rows(timeline: timeline, blockEventID: "b", nowMinutes: 23 * 60, dayStart: dayStart).isEmpty)
    }
}
