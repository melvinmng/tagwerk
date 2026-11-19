import Foundation
import Testing
@testable import TagwerkCore

struct MailTaskSuggestionTests {
    private let calendar = makeCalendar()
    /// 19 November 2026, noon.
    private var now: Date { instant(2026, 11, 19, 12) }

    private func suggestion(title: String = "Angebot senden", summary: String = "Kurz.", due: String? = nil) -> MailTaskSuggestion {
        MailTaskSuggestion(title: title, summary: summary, due: due)
    }

    @Test func pastDue_isDropped() {
        #expect(suggestion(due: "2026-11-18").normalized(now: now, calendar: calendar)?.due == nil)
        #expect(suggestion(due: "2025-01-01T10:00").normalized(now: now, calendar: calendar)?.due == nil)
        // Today still counts, also when the time already passed.
        #expect(suggestion(due: "2026-11-19").normalized(now: now, calendar: calendar)?.due == DueDate(year: 2026, month: 11, day: 19))
    }

    @Test func farDue_isDropped() {
        #expect(suggestion(due: "2029-01-01").normalized(now: now, calendar: calendar)?.due == nil)
        #expect(suggestion(due: "2028-11-18").normalized(now: now, calendar: calendar)?.due != nil)
    }

    @Test func unparsableDue_isDropped() {
        for text in ["bald", "2026-13-01", "2026-02-30", "19.12.2026", ""] {
            #expect(suggestion(due: text).normalized(now: now, calendar: calendar)?.due == nil, "\(text)")
        }
    }

    @Test func dateOnly_isAllDay() {
        let due = suggestion(due: "2026-12-01").normalized(now: now, calendar: calendar)?.due
        #expect(due == DueDate(year: 2026, month: 12, day: 1))
        #expect(due?.hasTime == false)
    }

    @Test func dateWithTime_keepsTheTimeInTheCalendarZone() {
        let local = suggestion(due: "2026-12-01T14:30").normalized(now: now, calendar: calendar)?.due
        #expect(local == DueDate(year: 2026, month: 12, day: 1, hour: 14, minute: 30))
        // 13:30 UTC is 14:30 in Berlin in December.
        let utc = suggestion(due: "2026-12-01T13:30:00Z").normalized(now: now, calendar: calendar)?.due
        #expect(utc == DueDate(year: 2026, month: 12, day: 1, hour: 14, minute: 30))
    }

    @Test func emptyTitle_isNil() {
        #expect(suggestion(title: "  \n ").normalized(now: now, calendar: calendar) == nil)
    }

    @Test func overlongFields_areCut() {
        let result = suggestion(title: String(repeating: "t", count: 200), summary: String(repeating: "s", count: 900))
            .normalized(now: now, calendar: calendar)
        #expect(result?.title.count == MailTaskSuggestion.maximumTitleLength)
        #expect(result?.summary.count == MailTaskSuggestion.maximumSummaryLength)
    }

    @Test func fieldsAreTrimmed() {
        let result = suggestion(title: "  Titel \n", summary: "\n Text  ").normalized(now: now, calendar: calendar)
        #expect(result?.title == "Titel")
        #expect(result?.summary == "Text")
    }

    @Test func decode_readsJSONAroundText() throws {
        let answer = "Hier: {\"title\":\"A\",\"summary\":\"B\",\"due\":null} Ende"
        let decoded = try MailTaskSuggestion.decode(Data(answer.utf8))
        #expect(decoded == MailTaskSuggestion(title: "A", summary: "B", due: nil))
        #expect(throws: (any Error).self) { try MailTaskSuggestion.decode(Data("nope".utf8)) }
    }

    @Test func redactingAddresses_removesEveryAddress() {
        let text = "Von Erika <erika.muster+x@mail.example.com>, Kopie an max@example.org.\nAm 5.1. schrieb Hans (hans@sub.example.com):"
        let redacted = MailTaskSuggestion.redactingAddresses(text)
        #expect(!redacted.contains("@"))
        #expect(redacted == "Von Erika <[Adresse]>, Kopie an [Adresse].\nAm 5.1. schrieb Hans ([Adresse]):")
        #expect(MailTaskSuggestion.redactingAddresses("Kein Treffer: 5 @ 3") == "Kein Treffer: 5 @ 3")
    }

    @Test func instructions_forbidInventedDeadlines() {
        let text = MailTaskSuggestion.instructions(language: .german, today: now, calendar: calendar)
        #expect(text.contains("2026-11-19"))
        #expect(text.contains("Erfinde keine Fristen"))
        #expect(text.contains("JSON"))
    }
}
