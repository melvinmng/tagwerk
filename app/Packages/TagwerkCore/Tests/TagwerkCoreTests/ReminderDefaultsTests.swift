import Foundation
import Testing
@testable import TagwerkCore

struct ReminderDefaultsTests {
    @Test func legacy_matchesTodaysRules() {
        let defaults = ReminderDefaults.legacy(leadTimeMinutes: 120)
        #expect(defaults.offsets(for: .localTask, isAllDay: false) == [.before(amount: 2, unit: .hours)])
        #expect(defaults.offsets(for: .localTask, isAllDay: true) == [.at(daysBefore: 0, hour: 9, minute: 0)])
        #expect(defaults.offsets(for: .deadline, isAllDay: false) == [.before(amount: 2, unit: .hours)])
        #expect(defaults.offsets(for: .deadline, isAllDay: true) == [.at(daysBefore: 1, hour: 18, minute: 0)])
        #expect(defaults.offsets(for: .event, isAllDay: false).isEmpty)
        #expect(defaults.offsets(for: .event, isAllDay: true).isEmpty)
    }

    @Test func legacy_neverUsesDays_soDaylightSavingDoesNotShiftTheMoment() {
        #expect(ReminderDefaults.legacy(leadTimeMinutes: 1440).offsets(for: .localTask, isAllDay: false) == [.before(amount: 24, unit: .hours)])
        #expect(ReminderDefaults.legacy(leadTimeMinutes: 2880).offsets(for: .deadline, isAllDay: false) == [.before(amount: 48, unit: .hours)])
        #expect(ReminderDefaults.legacy(leadTimeMinutes: 15).offsets(for: .localTask, isAllDay: false) == [.before(amount: 15, unit: .minutes)])
    }

    @Test func legacy_usesTheGivenHours() {
        let defaults = ReminderDefaults.legacy(leadTimeMinutes: 90, dateOnlyHour: 8, allDayEventHour: 20)
        #expect(defaults.offsets(for: .localTask, isAllDay: false) == [.before(amount: 90, unit: .minutes)])
        #expect(defaults.offsets(for: .localTask, isAllDay: true) == [.at(daysBefore: 0, hour: 8, minute: 0)])
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
        defaults.set([.before(amount: 1, unit: .weeks), .at(daysBefore: 1, hour: 18, minute: 0)], for: .localTask, isAllDay: false)
        defaults.set([.before(amount: 1, unit: .days)], for: .deadline, isAllDay: true)
        defaults.set([.before(amount: 15, unit: .minutes)], for: .event, isAllDay: false)
        #expect(ReminderDefaults.decode(defaults.encoded(), leadTimeMinutes: 999) == defaults)
        // Equal defaults give identical data, also when one of them was decoded (its dictionaries may order differently).
        let decoded = ReminderDefaults.decode(defaults.encoded(), leadTimeMinutes: 999)
        #expect(decoded.encoded() == defaults.encoded())
        #expect(ReminderDefaults.legacy(leadTimeMinutes: 90).encoded() == ReminderDefaults.legacy(leadTimeMinutes: 90).encoded())
    }

    @Test func offsets_areNormalized() {
        let defaults = ReminderDefaults(
            timed: [.localTask: [.before(amount: 15, unit: .minutes), .before(amount: 1, unit: .days), .before(amount: 15, unit: .minutes)]],
            allDay: [.localTask: [.before(amount: 30, unit: .minutes), .before(amount: 1, unit: .days)]])
        #expect(defaults.offsets(for: .localTask, isAllDay: false) == [.before(amount: 1, unit: .days), .before(amount: 15, unit: .minutes)])
        #expect(defaults.offsets(for: .localTask, isAllDay: true) == [.before(amount: 1, unit: .days)])
    }

    @Test func everyTaskSource_hasItsOwnKind() {
        #expect(ReminderKind.forTask(source: .local) == .localTask)
        #expect(ReminderKind.forTask(source: .github) == .githubIssue)
        #expect(ReminderKind.forTask(source: .reminders) == .appleReminder)
    }

    @Test func kinds_haveIndependentLists() {
        var defaults = ReminderDefaults.legacy(leadTimeMinutes: 60)
        defaults.set([.before(amount: 1, unit: .days)], for: .githubIssue, isAllDay: false)
        #expect(defaults.offsets(for: .githubIssue, isAllDay: false) == [.before(amount: 1, unit: .days)])
        #expect(defaults.offsets(for: .localTask, isAllDay: false) == [.before(amount: 1, unit: .hours)])
        #expect(defaults.offsets(for: .appleReminder, isAllDay: false) == [.before(amount: 1, unit: .hours)])
    }

    /// Data written before the kinds were split holds one list "task" for all three task sources.
    private func formerData(_ defaults: ReminderDefaults) -> Data {
        Data(String(decoding: defaults.encoded(), as: UTF8.self).replacingOccurrences(of: "\"localTask\"", with: "\"task\"").utf8)
    }

    @Test func decode_formerTaskList_appliesToEveryTaskKind() throws {
        var former = ReminderDefaults()
        former.set([.before(amount: 3, unit: .hours)], for: .localTask, isAllDay: false)
        former.set([.at(daysBefore: 1, hour: 9, minute: 0)], for: .localTask, isAllDay: true)
        let data = formerData(former)
        #expect(String(decoding: data, as: UTF8.self).contains("\"task\""))
        let decoded = ReminderDefaults.decode(data, leadTimeMinutes: 60)
        for kind in [ReminderKind.localTask, .githubIssue, .appleReminder] {
            #expect(decoded.offsets(for: kind, isAllDay: false) == [.before(amount: 3, unit: .hours)])
            #expect(decoded.offsets(for: kind, isAllDay: true) == [.at(daysBefore: 1, hour: 9, minute: 0)])
        }
        // Encoded again, the former key is gone.
        #expect(!String(decoding: decoded.encoded(), as: UTF8.self).contains("\"task\""))
    }

    @Test func decode_formerTaskList_doesNotOverrideAnExplicitKind() throws {
        var mixed = ReminderDefaults()
        mixed.set([.before(amount: 5, unit: .minutes)], for: .localTask, isAllDay: false)
        mixed.set([.before(amount: 2, unit: .days)], for: .githubIssue, isAllDay: false)
        let decoded = ReminderDefaults.decode(formerData(mixed), leadTimeMinutes: 60)
        #expect(decoded.offsets(for: .githubIssue, isAllDay: false) == [.before(amount: 2, unit: .days)])
        #expect(decoded.offsets(for: .localTask, isAllDay: false) == [.before(amount: 5, unit: .minutes)])
        #expect(decoded.offsets(for: .appleReminder, isAllDay: false) == [.before(amount: 5, unit: .minutes)])
    }

    /// The defaults of a settings file from before the split behave the same as the settings of today.
    @Test func decode_formerLegacyData_equalsTheLegacyDefaults() {
        let legacy = ReminderDefaults.legacy(leadTimeMinutes: 90)
        #expect(ReminderDefaults.decode(formerData(legacy), leadTimeMinutes: 1) == legacy)
    }
}
