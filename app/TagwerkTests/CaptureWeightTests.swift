import Foundation
import HealthBridge
import SwiftData
import SwiftUI
import Testing
import TagwerkCore
@testable import Tagwerk

/// Entering a weight in the capture model, the quick-entry layout and the morning row.
@MainActor
struct CaptureWeightTests {
    let container: ModelContainer
    let store: IntakeStore
    let settings: AppSettings
    let calendar = Calendar.tagwerk
    let clock = Clock()

    final class Clock { var now = Date() }

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = IntakeStore(context: container.mainContext)
        settings = try AppSettings.current(in: container.mainContext)
        clock.now = PlanDay(year: 2026, month: 11, day: 18).startDate(in: .tagwerk).addingTimeInterval(7 * 3600 + 5 * 60)
    }

    func make(_ health: FakeHealthStore) -> CaptureModel {
        let clock = self.clock
        let mirror = HealthMirror(store: store, health: health, now: { clock.now })
        return CaptureModel(store: store, mirror: mirror, health: health, settings: settings, calendar: calendar,
                            now: { clock.now }, waitsForHealth: true)
    }

    private func weight(_ kg: Double = 82.1) -> WeightValue { WeightValue(id: UUID(), date: clock.now, kilograms: kg) }

    @Test func saveWeight_storesIt_offersUndo_andAsksTheBodyGroupOnce() async {
        let health = FakeHealthStore()
        let model = make(health)
        let entry = weight()
        await model.saveWeight(entry, isNew: true)
        #expect(store.weight(entry.id) == entry)
        #expect(model.undo?.action == .remove(entry.id))
        #expect(health.groupRequests(.body) == 1)
        #expect(health.weights.map(\.kilograms) == [82.1], "the entry is mirrored once the group was asked")
        await model.saveWeight(weight(81.8), isNew: true)
        #expect(health.groupRequests(.body) == 1, "the sheet of iOS appears at the first weight only")
    }

    @Test func saveWeight_withoutConnectedHealth_asksNothing() async {
        let health = FakeHealthStore(access: .notDetermined)
        let model = make(health)
        await model.saveWeight(weight(), isNew: true)
        #expect(health.groupRequests(.body) == 0)
        #expect(health.weights.isEmpty)
        #expect(store.latestWeight()?.kilograms == 82.1, "the entry is kept in Tagwerk")
    }

    @Test func undo_removesTheNewWeight_andItsHealthCopy() async {
        let health = FakeHealthStore()
        let model = make(health)
        let entry = weight()
        await model.saveWeight(entry, isNew: true)
        await model.undoLast()
        #expect(store.weight(entry.id) == nil)
        #expect(health.weights.isEmpty, "the mirrored sample is removed with the entry")
    }

    @Test func editWeight_keepsOneEntry_withAHigherVersion() async {
        let health = FakeHealthStore()
        let model = make(health)
        var entry = weight()
        await model.saveWeight(entry, isNew: true)
        entry.kilograms = 81.5
        await model.saveWeight(entry, isNew: false)
        #expect(store.weights(in: DateInterval(start: clock.now.addingTimeInterval(-60), end: clock.now.addingTimeInterval(60))).count == 1)
        #expect(health.weights.map(\.version) == [1, 2])
    }

    @Test func latestKnownKilograms_takesTheNewestOwnOrForeignValue() async {
        let health = FakeHealthStore()
        health.setGroupAccess(.asked, for: .body)
        let model = make(health)
        #expect(await model.latestKnownKilograms() == nil)
        health.foreignWeights = [ForeignWeight(id: UUID(), date: clock.now.addingTimeInterval(-86_400), kilograms: 83.3, sourceName: "Waage")]
        #expect(await model.latestKnownKilograms() == 83.3)
        store.addWeight(weight(82.0))
        #expect(await model.latestKnownKilograms() == 82.0)
    }

    @Test func allowBodyAccess_asksTheGroupOnceFromTheSettings() async {
        let health = FakeHealthStore()
        let model = make(health)
        await model.allowBodyAccess()
        #expect(health.groupRequests(.body) == 1)
        #expect(model.bodyAccess == .asked)
        await model.allowBodyAccess()
        #expect(health.groupRequests(.body) == 1)
    }

    // MARK: Layout and row

    @Test func quickEntry_fourButtonsWrapIntoTwoRowsAtLargeText() {
        #expect(QuickEntryLayout.columns(for: .large) == 4)
        #expect(QuickEntryLayout.columns(for: .xLarge) == 2)
        #expect(QuickEntryLayout.columns(for: .accessibility5) == 2)
    }

    @Test func morningRow_hiddenWhenSwitchedOff_andOnOtherDays() {
        let today = PlanDay(year: 2026, month: 11, day: 18)
        #expect(MorningSheet.showsWeightRow(enabled: true, day: today, today: today))
        #expect(!MorningSheet.showsWeightRow(enabled: false, day: today, today: today))
        #expect(!MorningSheet.showsWeightRow(enabled: true, day: today.adding(days: -1, calendar: calendar), today: today))
        #expect(settings.morningWeightEnabled, "on by default: the row replaces a notification")
        #expect(!settings.bodyFatEnabled, "off by default (decision KG4b)")
    }
}
