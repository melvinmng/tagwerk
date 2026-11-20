import Foundation
import Testing
@testable import TagwerkCore

struct NumberEntryTests {
    let german = Locale(identifier: "de_DE")
    let english = Locale(identifier: "en_US")

    private func parse(_ text: String, _ kind: NumberEntryKind, _ locale: Locale) -> Double? {
        NumberEntry.parse(text, kind: kind, locale: locale)
    }

    @Test func parse_integer_plain() {
        #expect(parse("42", .integer, german) == 42)
        #expect(parse(" 42 ", .integer, english) == 42)
    }

    @Test func parse_integerIgnoresGroupingSeparator() {
        #expect(parse("2.300", .integer, german) == 2300)
        #expect(parse("30.000", .integer, german) == 30000)
        #expect(parse("2,300", .integer, english) == 2300)
        #expect(parse("1.234.567", .integer, german) == 1_234_567)
    }

    @Test func parse_decimalSeparatorFollowsLocale() {
        #expect(parse("1,5", .decimal(fractionDigits: 2), german) == 1.5)
        #expect(parse("1.5", .decimal(fractionDigits: 2), english) == 1.5)
        // A single separator is the decimal mark in either language.
        #expect(parse("1.5", .decimal(fractionDigits: 2), german) == 1.5)
        #expect(parse("1,5", .decimal(fractionDigits: 2), english) == 1.5)
        #expect(parse("1.234,5", .decimal(fractionDigits: 2), german) == 1234.5)
        #expect(parse("1,234.5", .decimal(fractionDigits: 2), english) == 1234.5)
    }

    @Test func parse_rejectsEmptyAndText() {
        for text in ["", " ", "abc", "1,2,3", "1.2.3", "1,5,", ",", "."] {
            #expect(parse(text, .decimal(fractionDigits: 2), german) == nil, "decimal \(text)")
        }
        for text in ["", " ", "abc", "12a"] {
            #expect(parse(text, .integer, german) == nil, "integer \(text)")
            #expect(parse(text, .durationMinutes, german) == nil, "duration \(text)")
        }
        #expect(parse("1,2,3", .integer, english) == nil)
    }

    @Test func parse_negativeIsRejected() {
        #expect(parse("-5", .integer, german) == nil)
        #expect(parse("−5", .integer, german) == nil)
        #expect(parse("-1,5", .decimal(fractionDigits: 2), german) == nil)
        #expect(parse("-30", .durationMinutes, german) == nil)
    }

    @Test func parseDuration_acceptsMinutesHoursAndClock() {
        for text in ["90", "90 min", "1,5 h", "1.5h", "1:30", "1 h 30", "1h30min", "1 Std 30 Min", "1,5 Stunden"] {
            #expect(parse(text, .durationMinutes, german) == 90, "\(text)")
        }
        #expect(parse("2 h", .durationMinutes, german) == 120)
        #expect(parse("1.5h", .durationMinutes, english) == 90)
        #expect(parse("0:45", .durationMinutes, german) == 45)
        #expect(parse("1:75", .durationMinutes, german) == nil)
        #expect(parse("1.200", .durationMinutes, german) == 1200)
    }

    @Test func normalize_roundsToNearestStep_andClamps() {
        let range = 0.0...60.0
        #expect(NumberEntry.normalize(7, range: range, step: 5) == 5)
        #expect(NumberEntry.normalize(8, range: range, step: 5) == 10)
        #expect(NumberEntry.normalize(99, range: range, step: 5) == 60)
        #expect(NumberEntry.normalize(-3, range: range, step: 5) == 0)
    }

    @Test func normalize_stepRelativeToLowerBound() {
        let range = 15.0...720.0
        #expect(NumberEntry.normalize(20, range: range, step: 15) == 15)
        #expect(NumberEntry.normalize(23, range: range, step: 15) == 30)
        // The range starts off the grid of whole multiples: steps count from the lower bound.
        #expect(NumberEntry.normalize(1050, range: 1000.0...6000.0, step: 50) == 1050)
        #expect(NumberEntry.normalize(1020, range: 20.0...400.0, step: 5) == 400)
        #expect(NumberEntry.normalize(399, range: 20.0...400.0, step: 15) == 395)
    }

    @Test func normalize_decimalStep() {
        #expect(NumberEntry.normalize(1.3, range: 0.25...10, step: 0.25) == 1.25)
        #expect(NumberEntry.normalize(0.1, range: 0.5...3, step: 0.5) == 0.5)
        #expect(NumberEntry.normalize(1.7, range: 0.5...3, step: 0.5) == 1.5)
    }

    @Test func quantity_litersToMilliliters_roundedToStep() {
        // Typed liters become milliliters on the 250 ml grid that starts at 500 ml.
        #expect(NumberEntry.normalize(2.25 * 1000, range: 500...6000, step: 250) == 2250)
        #expect(NumberEntry.normalize(2.1 * 1000, range: 500...6000, step: 250) == 2000)
    }

    @Test func wasAdjusted_detectsChange() {
        #expect(NumberEntry.wasAdjusted(7, normalized: 5))
        #expect(!NumberEntry.wasAdjusted(5, normalized: 5))
    }

    @Test func editingText_noGroupingNoUnit() {
        #expect(NumberEntry.editingText(2300, kind: .integer, locale: german) == "2300")
        #expect(NumberEntry.editingText(1.5, kind: .decimal(fractionDigits: 2), locale: german) == "1,5")
        #expect(NumberEntry.editingText(1.5, kind: .decimal(fractionDigits: 2), locale: english) == "1.5")
        #expect(NumberEntry.editingText(2, kind: .decimal(fractionDigits: 2), locale: german) == "2")
        #expect(NumberEntry.editingText(90, kind: .durationMinutes, locale: german) == "90")
        #expect(NumberEntry.editingText(30000, kind: .integer, locale: english) == "30000")
    }
}
