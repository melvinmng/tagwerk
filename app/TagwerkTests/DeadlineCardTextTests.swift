import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// Texts of the deadline card, the marks in the timeline and the orphaned rows (plan deadline-marking, Task 6).
struct DeadlineCardTextTests {
    let calendar = testCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 18)

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func deadline(_ kind: DeadlineKind, time: Date? = nil) -> ImportantDeadline {
        ImportantDeadline(id: "event:exam", title: "Klausur Statistik", day: PlanDay(year: 2026, month: 11, day: 27), time: time,
                          kind: kind, taskID: nil, eventID: kind == .markedEvent || kind == .deadlineCalendar ? "exam" : nil,
                          calendarID: "timetable")
    }

    @Test func kindTextNamesCalendarAndMark() {
        let marked = deadline(.markedEvent, time: at(27, 10))
        let text = DeadlineText(calendar: calendar)
        #expect(text.detail(marked, calendarName: "Stundenplan") == "Stundenplan, \(at(27, 10).formatted(date: .omitted, time: .shortened))")
        #expect(text.badge(marked) == "markiert")
        #expect(text.detail(deadline(.deadlineCalendar), calendarName: "Uni-Fristen") == "Kalender Uni-Fristen")
        #expect(text.detail(deadline(.deadlineCalendar), calendarName: nil) == "Kalender")
        #expect(text.badge(deadline(.deadlineCalendar)) == nil)
        #expect(text.detail(deadline(.priorityOne), calendarName: nil) == "P1")
        #expect(text.detail(deadline(.epic), calendarName: nil) == "Epic")
    }

    @Test func preparationLineOnlyWithLinks() {
        let text = DeadlineText(calendar: calendar)
        #expect(text.preparation(nil) == nil)
        #expect(text.preparation(PreparationSummary(minutes: 0, count: 0)) == nil)
        #expect(text.preparation(PreparationSummary(minutes: 390, count: 3)) == "Vorbereitung 6 h 30 · 3 Termine")
        #expect(text.preparation(PreparationSummary(minutes: 120, count: 1)) == "Vorbereitung 2 h · 1 Termin")
    }

    @Test func voiceOverReadsTitleKindMarkCalendarAndDistance() {
        let text = DeadlineText(calendar: calendar)
        let label = text.accessibilityLabel(deadline(.markedEvent, time: at(27, 10)), calendarName: "Stundenplan", today: today,
                                            preparation: PreparationSummary(minutes: 390, count: 3))
        #expect(label.hasPrefix("Klausur Statistik, Deadline, markiert, Stundenplan, "))
        #expect(label.hasSuffix("in 9 Tagen, Vorbereitung 6 h 30 · 3 Termine"))
    }

    @Test func relativeDayText() {
        let text = DeadlineText(calendar: calendar)
        #expect(text.relative(PlanDay(year: 2026, month: 11, day: 17), today: today) == "überfällig")
        #expect(text.relative(today, today: today) == "heute")
        #expect(text.relative(PlanDay(year: 2026, month: 11, day: 19), today: today) == "morgen")
        #expect(text.relative(PlanDay(year: 2026, month: 11, day: 27), today: today) == "in 9 Tagen")
    }

    @Test func orphanTextSaysWhatHappened() {
        let text = DeadlineText(calendar: calendar)
        let gone = OrphanedMark(eventKey: "exam", title: "Klausur Statistik", calendarID: "timetable", start: at(27, 10),
                                isAllDay: false, candidate: nil)
        #expect(text.orphan(gone, calendarName: "Stundenplan").hasPrefix("Stundenplan · nicht mehr im Kalender (zuletzt "))
        let candidate = CalendarEvent(id: "exam-2", externalID: nil, calendarID: "timetable", title: "Klausur Statistik",
                                      start: at(30, 10), end: at(30, 12), isAllDay: false, url: nil, isBusy: true, version: "1")
        let moved = OrphanedMark(eventKey: "exam", title: "Klausur Statistik", calendarID: "timetable", start: at(27, 10),
                                 isAllDay: false, candidate: candidate)
        #expect(text.orphan(moved, calendarName: "Stundenplan").hasPrefix("Stundenplan · nicht mehr am "))
        #expect(text.adopt(candidate).hasSuffix("übernehmen"))
    }

    @Test func preparationMarkNamesDeadlineAndDistance() {
        let text = DeadlineText(calendar: calendar)
        let target = PreparationTarget(deadlineKey: "event:exam", title: "Klausur Statistik", until: at(27, 10))
        #expect(text.preparationMark(target, today: PlanDay(year: 2026, month: 11, day: 19)) == "→ Klausur Statistik · in 8 Tagen")
    }

    @Test func timelineSuffixNamesDeadlineKind() {
        let text = DeadlineText(calendar: calendar)
        #expect(text.timelineMark(isMarked: true) == "Deadline, markiert")
        #expect(text.timelineMark(isMarked: false) == "Deadline")
    }
}
