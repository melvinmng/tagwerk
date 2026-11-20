import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct ValueEntryModelTests {
    let german = Locale(identifier: "de_DE")

    private func buffer() -> ValueEntryModel {
        ValueEntryModel(kind: .durationMinutes, range: 0...60, step: 5, locale: german)
    }

    @Test func commit_validValue_isNormalized() {
        var model = buffer()
        model.begin(value: 10)
        #expect(model.typed("30") == 30)
        #expect(model.commit(current: 30, display: { "\(Int($0)) min" }) == 30)
        #expect(model.hint == nil)
        #expect(!model.isEditing)
        // A typed value between two steps is rounded: 8 becomes 10.
        model.begin(value: 30)
        #expect(model.typed("8") == 10)
        #expect(model.commit(current: 10, display: { "\(Int($0)) min" }) == 10)
    }

    @Test func commit_unreadable_keepsOldValueAndShowsHint() {
        var model = buffer()
        model.begin(value: 25)
        #expect(model.typed("abc") == nil)
        #expect(model.commit(current: 25, display: { "\(Int($0)) min" }) == 25)
        #expect(model.hint?.contains("Zahl") == true)
        // Cleared text counts as unreadable, even after a readable keystroke changed the value on the way.
        model.begin(value: 25)
        _ = model.typed("7")
        _ = model.typed("")
        #expect(model.commit(current: 5, display: { "\(Int($0)) min" }) == 25)
        #expect(model.hint != nil)
    }

    @Test func commit_outOfRange_clampsAndShowsAdjustedHint() {
        var model = buffer()
        model.begin(value: 10)
        #expect(model.typed("99") == 60)
        #expect(model.commit(current: 60, display: { "\(Int($0)) min" }) == 60)
        #expect(model.hint?.contains("60 min") == true)
        model.begin(value: 10)
        _ = model.typed("7")
        #expect(model.commit(current: 5, display: { "\(Int($0)) min" }) == 5)
        #expect(model.hint?.contains("5 min") == true)
    }

    @Test func commit_liters_scaledToMilliliters() {
        var model = ValueEntryModel(kind: .decimal(fractionDigits: 2), range: 500...6000, step: 250, scale: 1000, locale: german)
        model.begin(value: 2000)
        #expect(model.text == "2")
        _ = model.typed("2,25")
        #expect(model.commit(current: 2250, display: { "\($0)" }) == 2250)
        #expect(model.hint == nil)
        model.begin(value: 2250)
        _ = model.typed("2,1")
        #expect(model.commit(current: 2000, display: { "\($0)" }) == 2000)
        #expect(model.hint != nil)
    }

    @Test func update_changedRange_appliesToTypedValue() {
        var model = ValueEntryModel(kind: .integer, range: 1...52, step: 1, locale: german)
        model.begin(value: 2)
        model.update(range: 1...24, step: 1)
        #expect(model.typed("40") == 24)
    }

    @Test func begin_showsEditingTextWithoutUnit() {
        var kilocalories = ValueEntryModel(kind: .integer, range: 1000...6000, step: 50, locale: german)
        kilocalories.begin(value: 2300)
        #expect(kilocalories.text == "2300")
        #expect(kilocalories.isEditing)
        var factor = ValueEntryModel(kind: .decimal(fractionDigits: 2), range: 0.5...3, step: 0.5, locale: german)
        factor.begin(value: 1.5)
        #expect(factor.text == "1,5")
        var duration = ValueEntryModel(kind: .durationMinutes, range: 15...240, step: 15, locale: german)
        duration.begin(value: 90)
        #expect(duration.text == "90")
    }

    @Test func commit_withoutBegin_returnsCurrentValue() {
        var model = buffer()
        #expect(model.commit(current: 15, display: { "\(Int($0)) min" }) == 15)
        #expect(model.hint == nil)
    }
}
