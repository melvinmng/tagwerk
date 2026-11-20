import Foundation
import Testing
@testable import TagwerkCore

struct WatchComplicationTextTests {
    let calendar = makeCalendar()
    let de = Locale(identifier: "de_DE")

    private func entry(_ title: String, hour: Int, kind: SnapshotEntry.Kind = .event) -> SnapshotEntry {
        SnapshotEntry(id: title, title: title, start: instant(2026, 11, 20, hour, 30, in: calendar), end: instant(2026, 11, 20, hour + 1, 30, in: calendar),
                      kind: kind, colorHex: nil, isAllDay: false)
    }

    private func task(_ title: String, deadline: Bool = false) -> WatchTask {
        WatchTask(key: "local:\(title)", title: title, due: nil, hasTime: false, isDeadline: deadline, source: .local, version: "1")
    }

    @Test func habitCounterHasNoNames() {
        let counter = HabitCounter(done: 3, total: 5)
        #expect(WatchComplicationText.habitCounter(counter) == "3/5")
        // The rule takes the counter only: there is no way to pass a name into it.
        let letters = WatchComplicationText.habitCounter(counter).filter { $0.isLetter }
        #expect(letters.isEmpty)
    }

    @Test func inlineFormat_entry() {
        let text = WatchNextUpText.make(.entry(entry("Meeting", hour: 9), isRunning: false), calendar: calendar, locale: de)
        #expect(text.inline == "09:30 Meeting")
        #expect(text.title == "Meeting")
        #expect(!text.isTask)
    }

    @Test func inlineFormat_longTitleIsShortened() {
        let text = WatchNextUpText.make(.entry(entry("Quarterly planning with the whole team", hour: 9), isRunning: true), calendar: calendar, locale: de)
        #expect(text.inline == "09:30 Quarterly plannin…")
        #expect(text.caption == "Läuft")
    }

    @Test func inlineFormat_untimedTaskWithCount() {
        let text = WatchNextUpText.make(.untimedTask(task("Mail"), more: 4), calendar: calendar, locale: de)
        #expect(text.inline == "Mail +4")
        #expect(text.suffix == "+4")
        #expect(text.isTask)
        #expect(WatchNextUpText.make(.untimedTask(task("Mail"), more: 0), calendar: calendar, locale: de).inline == "Mail")
    }

    @Test func inlineFormat_tomorrow() {
        let text = WatchNextUpText.make(.tomorrow(entry("Zahnarzt", hour: 9)), calendar: calendar, locale: de)
        #expect(text.inline == "Morgen 09:30 Zahnarzt")
    }

    @Test func emptyStatesCarryNoUserContent() {
        let nothing = WatchNextUpText.make(.nothingLeft, calendar: calendar, locale: de)
        #expect(nothing.title == nil)
        #expect(nothing.inline == "Nichts mehr heute")
        let stale = WatchNextUpText.make(.stale, calendar: calendar, locale: de)
        #expect(stale.title == nil)
        #expect(stale.inline == "Öffne Tagwerk auf dem iPhone")
    }

    @Test func deadlineTaskUsesFlag() {
        #expect(WatchNextUpText.make(.untimedTask(task("Abgabe", deadline: true), more: 0), calendar: calendar, locale: de).symbolName == "flag.fill")
    }

    @Test func shortening() {
        #expect(WatchComplicationText.shortened("Kurz", limit: 10) == "Kurz")
        #expect(WatchComplicationText.shortened("  Kurz  ", limit: 10) == "Kurz")
        #expect(WatchComplicationText.shortened("Ein langer Titel", limit: 8) == "Ein lan…")
    }

    @Test func ringFractionIsClamped() {
        #expect(WatchComplicationText.fraction(done: 500, goal: 2000) == 0.25)
        #expect(WatchComplicationText.fraction(done: 3000, goal: 2000) == 1)
        #expect(WatchComplicationText.fraction(done: 100, goal: 0) == 0)
    }

    @Test func liters() {
        #expect(WatchComplicationText.liters(milliliters: 1200, locale: de).hasPrefix("1,2"))
    }
}
