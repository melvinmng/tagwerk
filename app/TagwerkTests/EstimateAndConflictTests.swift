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

    @Test func number_followsTheLocale_andTypingAcceptsBothSeparators() {
        let english = Locale(identifier: "en_US")
        #expect(EstimateHours.number(90, locale: english) == "1.5")
        #expect(EstimateHours.number(45, locale: english) == "0.75")
        #expect(DecimalField.format(1.5, locale: english) == "1.5")
        #expect(DecimalField.format(1.5, locale: Locale(identifier: "de_DE")) == "1,5")
        #expect(DecimalField.format(5) == "5")
        var comma = EstimateInput(minutes: nil)
        comma.typed("1,5")
        var point = EstimateInput(minutes: nil)
        point.typed("1.5")
        #expect(comma.minutes == 90)
        #expect(point.minutes == 90)
    }

    @Test func minutes_roundToQuarterHourAndClamp() {
        #expect(EstimateHours.minutes(fromHours: 0.75) == 45)
        #expect(EstimateHours.minutes(fromHours: 0.8) == 45)
        #expect(EstimateHours.minutes(fromHours: 0.9) == 60)
        #expect(EstimateHours.minutes(fromHours: 0.1) == 15)
        #expect(EstimateHours.minutes(fromHours: 30) == 1800)
        #expect(EstimateHours.minutes(fromHours: 120) == 7200)
        #expect(EstimateHours.minutes(fromHours: 0) == nil)
        #expect(EstimateHours.minutes(fromHours: nil) == nil)
    }

    @Test func step_movesByQuarterHourWithinBounds() {
        #expect(EstimateHours.stepped(minutes: nil, by: 1) == 15)
        #expect(EstimateHours.stepped(minutes: 15, by: -1) == nil)
        #expect(EstimateHours.stepped(minutes: 45, by: 1) == 60)
        #expect(EstimateHours.stepped(minutes: 1440, by: 1) == 1455)
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

struct EstimateInputTests {
    @Test func typing_updatesMinutesImmediately() {
        var input = EstimateInput(minutes: nil)
        input.typed("2")
        #expect(input.minutes == 120)
        input.typed("0,8")
        #expect(input.minutes == 45)
        #expect(input.text == "0,8")
    }

    @Test func typeThenStep_stepsFromTypedValueAndShowsIt() {
        var input = EstimateInput(minutes: 60)
        input.typed("2")
        input.step(1)
        input.step(1)
        #expect(input.minutes == 150)
        #expect(input.text == "2,5")
    }

    @Test func quickValue_overridesTypedText() {
        var input = EstimateInput(minutes: 60)
        input.typed("3")
        input.choose(30)
        #expect(input.minutes == 30)
        #expect(input.text == "0,5")
    }

    @Test func endEditing_normalisesTextButKeepsOffGridValue() {
        var input = EstimateInput(minutes: 50)
        input.endEditing()
        #expect(input.minutes == 50)
    }

    @Test func emptyText_meansNoEffort_invalidTextKeepsValue() {
        var input = EstimateInput(minutes: 60)
        input.typed("abc")
        #expect(input.minutes == 60)
        input.typed("")
        #expect(input.minutes == nil)
        input.typed("0")
        #expect(input.minutes == nil)
    }
}
