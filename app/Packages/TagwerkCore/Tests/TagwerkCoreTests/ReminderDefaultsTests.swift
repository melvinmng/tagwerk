import Foundation
import Testing
@testable import TagwerkCore

struct ReminderDefaultsTests {
    @Test func legacy_matchesTodaysRules() {
        let defaults = ReminderDefaults.legacy(leadTimeMinutes: 120)
        #expect(defaults.offsets(for: .task, isAllDay: false) == [.before(amount: 2, unit: .hours)])
        #expect(defaults.offsets(for: .task, isAllDay: true) == [.at(daysBefore: 0, hour: 9, minute: 0)])
        #expect(defaults.offsets(for: .deadline, isAllDay: false) == [.before(amount: 2, unit: .hours)])
        #expect(defaults.offsets(for: .deadline, isAllDay: true) == [.at(daysBefore: 1, hour: 18, minute: 0)])
        #expect(defaults.offsets(for: .event, isAllDay: false).isEmpty)
        #expect(defaults.offsets(for: .event, isAllDay: true).isEmpty)
    }

    @Test func legacy_usesTheGivenHours() {
        let defaults = ReminderDefaults.legacy(leadTimeMinutes: 90, dateOnlyHour: 8, allDayEventHour: 20)
        #expect(defaults.offsets(for: .task, isAllDay: false) == [.before(amount: 90, unit: .minutes)])
        #expect(defaults.offsets(for: .task, isAllDay: true) == [.at(daysBefore: 0, hour: 8, minute: 0)])
        #expect(defaults.offsets(for: .deadline, isAllDay: true) == [.at(daysBefore: 1, hour: 20, minute: 0)])
    }

    @Test func decode_nil_fallsBackToLegacy() {
        #expect(ReminderDefaults.decode(nil, leadTimeMinutes: 60) == .legacy(leadTimeMinutes: 60))
    }

    @Test func decode_corrupt_fallsBackToLegacy() {
        #expect(ReminderDefaults.decode(Data("not json".utf8), leadTimeMinutes: 60) == .legacy(leadTimeMinutes: 60))
    }

    @Test func roundTrip_keepsAllKinds() {
        var defaults = ReminderDefaults()
        defaults.set([.before(amount: 1, unit: .weeks), .at(daysBefore: 1, hour: 18, minute: 0)], for: .task, isAllDay: false)
        defaults.set([.before(amount: 1, unit: .days)], for: .deadline, isAllDay: true)
        defaults.set([.before(amount: 15, unit: .minutes)], for: .event, isAllDay: false)
        #expect(ReminderDefaults.decode(defaults.encoded(), leadTimeMinutes: 999) == defaults)
        #expect(defaults.encoded() == defaults.encoded())
    }

    @Test func offsets_areNormalized() {
        let defaults = ReminderDefaults(
            timed: [.task: [.before(amount: 15, unit: .minutes), .before(amount: 1, unit: .days), .before(amount: 15, unit: .minutes)]],
            allDay: [.task: [.before(amount: 30, unit: .minutes), .before(amount: 1, unit: .days)]])
        #expect(defaults.offsets(for: .task, isAllDay: false) == [.before(amount: 1, unit: .days), .before(amount: 15, unit: .minutes)])
        #expect(defaults.offsets(for: .task, isAllDay: true) == [.before(amount: 1, unit: .days)])
    }
}
