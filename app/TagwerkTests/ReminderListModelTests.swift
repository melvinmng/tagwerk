import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct ReminderListModelTests {
    let defaults: [ReminderOffset] = [.before(amount: 1, unit: .days), .before(amount: 2, unit: .hours)]

    @Test func newEntry_followsTheDefault() {
        let model = ReminderListModel(offsets: nil, defaultOffsets: defaults, isAllDay: false)
        #expect(model.isUsingDefault)
        #expect(model.displayed == defaults)
        #expect(model.result == .useDefault)
    }

    @Test func customize_startsFromDefaults() {
        let model = ReminderListModel(offsets: nil, defaultOffsets: defaults, isAllDay: false)
        model.customize()
        #expect(!model.isUsingDefault)
        #expect(model.offsets == defaults)
        #expect(model.result == .custom(defaults))
    }

    @Test func add_duplicate_isIgnored() {
        let model = ReminderListModel(offsets: [.before(amount: 1, unit: .days)], defaultOffsets: defaults, isAllDay: false)
        model.add(.before(amount: 24, unit: .hours))
        model.add(.before(amount: 1, unit: .days))
        #expect(model.offsets == [.before(amount: 1, unit: .days)])
        model.add(.before(amount: 1, unit: .weeks))
        #expect(model.offsets == [.before(amount: 1, unit: .weeks), .before(amount: 1, unit: .days)])
    }

    @Test func add_whileUsingDefault_startsAnOwnListFirst() {
        let model = ReminderListModel(offsets: nil, defaultOffsets: defaults, isAllDay: false)
        model.add(.before(amount: 1, unit: .weeks))
        #expect(!model.isUsingDefault)
        #expect(model.offsets.count == 3)
    }

    @Test func remove_dropsTheRowOfAnOwnList_only() {
        let model = ReminderListModel(offsets: nil, defaultOffsets: defaults, isAllDay: false)
        model.remove(at: 0)
        #expect(model.displayed == defaults)
        model.customize()
        model.remove(at: 0)
        #expect(model.offsets == [.before(amount: 2, unit: .hours)])
        model.remove(at: 5)
        #expect(model.offsets.count == 1)
    }

    @Test func useDefault_returnsUseDefault() {
        let model = ReminderListModel(offsets: [.before(amount: 3, unit: .days)], defaultOffsets: defaults, isAllDay: false)
        #expect(model.result == .custom([.before(amount: 3, unit: .days)]))
        model.useDefault()
        #expect(model.result == .useDefault)
        #expect(model.offsets.isEmpty)
    }

    @Test func emptyOwnList_isAnOwnListWithoutReminders() {
        let model = ReminderListModel(offsets: [], defaultOffsets: defaults, isAllDay: false)
        #expect(model.result == .custom([]))
        #expect(model.displayed.isEmpty)
    }

    @Test func allDay_hidesHourUnits() {
        let model = ReminderListModel(offsets: nil, defaultOffsets: defaults, isAllDay: true)
        #expect(model.availableUnits == [.days, .weeks])
        #expect(model.displayed == [.before(amount: 1, unit: .days)])
        model.customize()
        model.add(.before(amount: 30, unit: .minutes))
        #expect(model.offsets == [.before(amount: 1, unit: .days)])
    }

    @Test func switchingToAllDay_dropsHourOffsetsOfTheOwnList() {
        let model = ReminderListModel(offsets: [.before(amount: 1, unit: .hours), .before(amount: 2, unit: .days)], defaultOffsets: [],
                                      isAllDay: false)
        model.configure(isAllDay: true, defaultOffsets: [])
        #expect(model.offsets == [.before(amount: 2, unit: .days)])
    }

    @Test func listWithoutDefault_isAlwaysAnOwnList() {
        let model = ReminderListModel(list: [.before(amount: 1, unit: .days)], isAllDay: false)
        #expect(!model.isUsingDefault)
        #expect(model.result == .custom([.before(amount: 1, unit: .days)]))
    }

    @Test func toggle_setsAndRemoves() {
        let model = ReminderListModel(offsets: [], defaultOffsets: defaults, isAllDay: false)
        model.toggle(.before(amount: 15, unit: .minutes))
        #expect(model.offsets == [.before(amount: 15, unit: .minutes)])
        #expect(model.isSelected(.before(amount: 15, unit: .minutes)))
        model.toggle(.before(amount: 15, unit: .minutes))
        #expect(model.offsets.isEmpty)
        #expect(model.result == .custom([]))
    }

    @Test func toggle_whileDefault_startsFromTheDefault() {
        let model = ReminderListModel(offsets: nil, defaultOffsets: defaults, isAllDay: false)
        model.toggle(.before(amount: 1, unit: .weeks))
        #expect(!model.isUsingDefault)
        #expect(model.offsets == [.before(amount: 1, unit: .weeks)] + defaults)
        #expect(model.defaultOffsets == ReminderOffset.normalized(defaults, isAllDay: false))
    }

    @Test func toggle_whileDefault_onADefaultRow_removesItFromTheCopy() {
        let model = ReminderListModel(offsets: nil, defaultOffsets: defaults, isAllDay: false)
        model.toggle(.before(amount: 2, unit: .hours))
        #expect(model.offsets == [.before(amount: 1, unit: .days)])
    }

    @Test func toggle_equivalentDistance_countsAsSelected() {
        let model = ReminderListModel(offsets: [.before(amount: 60, unit: .minutes)], defaultOffsets: [], isAllDay: false)
        #expect(model.isSelected(.before(amount: 1, unit: .hours)))
        model.toggle(.before(amount: 1, unit: .hours))
        #expect(model.offsets.isEmpty)
    }

    @Test func isSelected_whileDefault_followsTheDefault() {
        let model = ReminderListModel(offsets: nil, defaultOffsets: defaults, isAllDay: false)
        #expect(model.isSelected(.before(amount: 2, unit: .hours)))
        #expect(!model.isSelected(.before(amount: 15, unit: .minutes)))
        #expect(model.isUsingDefault)
    }

    @Test func choiceRows_listTheCommonDistancesAndTheSetOnes() {
        let model = ReminderListModel(offsets: [.at(daysBefore: 1, hour: 18, minute: 0)], defaultOffsets: defaults, isAllDay: false)
        #expect(model.choiceRows.count == 6)
        #expect(model.choiceRows.contains(.at(daysBefore: 1, hour: 18, minute: 0)))
    }

    @Test func rowSummary_prefixesTheDefaultAndNamesTheSubject() {
        let german = Locale(identifier: "de_DE")
        let model = ReminderListModel(offsets: nil, defaultOffsets: [.before(amount: 0, unit: .minutes)], isAllDay: false)
        #expect(model.rowSummary(subject: .task, locale: german) == "Standard · Zur Fälligkeit")
        model.toggle(.before(amount: 15, unit: .minutes))
        #expect(model.rowSummary(subject: .task, locale: german) == "15 Minuten vorher + 1 weitere")
        model.toggle(.before(amount: 15, unit: .minutes))
        model.toggle(.before(amount: 0, unit: .minutes))
        #expect(model.rowSummary(subject: .task, locale: german) == "Keine")
    }
}
