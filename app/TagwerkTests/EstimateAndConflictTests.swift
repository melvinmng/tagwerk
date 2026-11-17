import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct EstimateHoursTests {
    @Test func text_usesGermanDecimalComma() {
        #expect(EstimateHours.text(minutes: 45) == "0,75 h")
        #expect(EstimateHours.text(minutes: 60) == "1 h")
        #expect(EstimateHours.text(minutes: 90) == "1,5 h")
        #expect(EstimateHours.text(minutes: nil) == "–")
    }

    @Test func minutes_roundToQuarterHourAndClamp() {
        #expect(EstimateHours.minutes(fromHours: 0.75) == 45)
        #expect(EstimateHours.minutes(fromHours: 0.8) == 45)
        #expect(EstimateHours.minutes(fromHours: 0.9) == 60)
        #expect(EstimateHours.minutes(fromHours: 0.1) == 15)
        #expect(EstimateHours.minutes(fromHours: 30) == 1440)
        #expect(EstimateHours.minutes(fromHours: 0) == nil)
        #expect(EstimateHours.minutes(fromHours: nil) == nil)
    }

    @Test func step_movesByQuarterHourWithinBounds() {
        #expect(EstimateHours.stepped(minutes: nil, by: 1) == 15)
        #expect(EstimateHours.stepped(minutes: 15, by: -1) == nil)
        #expect(EstimateHours.stepped(minutes: 45, by: 1) == 60)
        #expect(EstimateHours.stepped(minutes: 1440, by: 1) == 1440)
    }
}

struct ConflictChangesTests {
    let original = makeTask("Login-Fehler beheben", source: .github, due: DueDate(year: 2026, month: 11, day: 18), version: "1")

    @Test func changes_listFieldsChangedAtSource_markOverlapWithOwnEdits() {
        var current = original
        current.due = DueDate(year: 2026, month: 11, day: 20)
        current.priority = .p3
        current.version = "2"
        var draft = original
        draft.priority = .p1

        let changes = ConflictChange.changes(original: original, draft: draft, current: current)

        #expect(changes.map(\.field) == ["Fällig", "Priorität"])
        #expect(changes[0].before == "18.11.2026" && changes[0].after == "20.11.2026" && changes[0].mine == nil)
        #expect(changes[1].before == "–" && changes[1].after == "P3" && changes[1].mine == "P1")
    }

    @Test func changes_noSourceChange_isEmpty() {
        var draft = original
        draft.title = "Neu"
        var current = original
        current.version = "2"
        #expect(ConflictChange.changes(original: original, draft: draft, current: current).isEmpty)
    }
}
