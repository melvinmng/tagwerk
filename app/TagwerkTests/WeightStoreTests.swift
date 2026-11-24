import Foundation
import HealthBridge
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Own body weights: the store, the Health mirror and the merged history. All dates are fixed.
@MainActor
struct WeightStoreTests {
    let container: ModelContainer
    let intake: IntakeStore
    let health = FakeHealthStore()
    let calendar = Calendar.tagwerk
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        intake = IntakeStore(context: container.mainContext)
    }

    private func weight(_ kg: Double = 82.1, at date: Date? = nil, bodyFat: Double? = nil) -> WeightValue {
        WeightValue(id: UUID(), date: date ?? now, kilograms: kg, bodyFatPercent: bodyFat)
    }

    private func mirror(_ health: FakeHealthStore? = nil, at date: Date? = nil) -> HealthMirror {
        let instant = date ?? now
        return HealthMirror(store: intake, health: health ?? self.health, now: { instant })
    }

    private var window: DateInterval { DateInterval(start: now.addingTimeInterval(-40 * 86_400), end: now.addingTimeInterval(86_400)) }

    // MARK: Store

    @Test func addWeight_thenInterval_returnsItOldestFirst() {
        let early = weight(82.5, at: now.addingTimeInterval(-3_600))
        let late = weight(81.9)
        intake.addWeight(late)
        intake.addWeight(early)
        #expect(intake.weights(in: window) == [early, late])
        #expect(intake.latestWeight() == late)
        #expect(intake.weights(in: DateInterval(start: now.addingTimeInterval(60), end: now.addingTimeInterval(120))).isEmpty)
    }

    @Test func updateWeight_bumpsVersion_marksUnsynced() {
        var entry = weight()
        intake.addWeight(entry)
        intake.markSynced(entry.id, version: 1)
        #expect(intake.unsyncedEntries().isEmpty)
        entry.kilograms = 81.7
        intake.updateWeight(entry)
        #expect(intake.unsyncedEntries().first?.version == 2)
        #expect(intake.weight(entry.id)?.kilograms == 81.7)
    }

    @Test func existsAndHealthSynced_knowWeights() {
        let entry = weight()
        intake.addWeight(entry)
        #expect(intake.exists(entry.id))
        #expect(!intake.healthSynced(entry.id))
        intake.markSynced(entry.id, version: 1)
        #expect(intake.healthSynced(entry.id))
    }

    // MARK: Mirror

    @Test func mirror_writesUnsyncedWeight() async {
        health.setGroupAccess(.asked, for: .body)
        let entry = weight(82.1, bodyFat: 22.5)
        intake.addWeight(entry)
        await mirror().sync()
        #expect(health.weights.map(\.kilograms) == [82.1])
        #expect(health.weights.first?.bodyFatPercent == 22.5)
        #expect(health.weights.first?.version == 1)
        #expect(intake.unsyncedEntries().isEmpty)
    }

    @Test func mirror_weightWaitsUntilTheBodyGroupWasAsked_withoutAskingItself() async {
        let entry = weight()
        intake.addWeight(entry)
        await mirror().sync()
        #expect(health.weights.isEmpty)
        #expect(intake.unsyncedEntries().count == 1)
        #expect(health.groupRequests(.body) == 0, "the sheet appears only from a user tap, never from the mirror")
        health.setGroupAccess(.asked, for: .body)
        await mirror().sync()
        #expect(health.weights.count == 1)
        #expect(intake.unsyncedEntries().isEmpty)
    }

    @Test func mirror_weightDoesNotNeedTheCoreGroup() async {
        let undetermined = FakeHealthStore(access: .notDetermined)
        undetermined.setGroupAccess(.asked, for: .body)
        intake.addWeight(weight())
        intake.addDrink(DrinkValue(id: UUID(), date: now, milliliters: 250))
        await mirror(undetermined).sync()
        #expect(undetermined.weights.count == 1)
        #expect(undetermined.drinks.isEmpty, "the core entries still wait for their own group")
    }

    @Test func mirror_weightRefusedByHealth_staysUnsynced_thenRetried() async {
        health.setGroupAccess(.asked, for: .body)
        intake.addWeight(weight())
        health.incompleteWrites = true
        await mirror().sync()
        #expect(intake.unsyncedEntries().count == 1)
        health.incompleteWrites = false
        await mirror().sync()
        #expect(intake.unsyncedEntries().isEmpty)
    }

    @Test func edit_sendsHigherVersion() async {
        health.setGroupAccess(.asked, for: .body)
        var entry = weight()
        intake.addWeight(entry)
        await mirror().sync()
        entry.kilograms = 81.6
        intake.updateWeight(entry)
        await mirror().sync()
        #expect(health.weights.map(\.version) == [1, 2])
    }

    @Test func delete_withinUndoWindow_neverReachesHealth() async throws {
        health.setGroupAccess(.asked, for: .body)
        let entry = weight()
        intake.addWeight(entry)
        await mirror().sync()
        let deleted = try #require(intake.delete(entry.id, healthNotBefore: now.addingTimeInterval(HealthMirror.undoWindow)))
        await mirror().sync()
        #expect(health.deleted.isEmpty, "the window is still open")
        intake.restore(deleted)
        // The late run finds the entry again: it must neither delete the old sample nor lose the rewritten one.
        await mirror(at: now.addingTimeInterval(HealthMirror.undoWindow + 1)).sync()
        #expect(health.deleted.isEmpty)
        #expect(health.weights.map(\.version) == [1, 2])
        #expect(intake.dueDeletions(now: now.addingTimeInterval(60)).isEmpty)
    }

    @Test func delete_afterTheWindow_removesTheSampleFromHealth() async throws {
        health.setGroupAccess(.asked, for: .body)
        let entry = weight()
        intake.addWeight(entry)
        await mirror().sync()
        intake.delete(entry.id, healthNotBefore: now.addingTimeInterval(HealthMirror.undoWindow))
        await mirror(at: now.addingTimeInterval(HealthMirror.undoWindow + 1)).sync()
        #expect(health.deleted == [entry.id])
        #expect(health.weights.isEmpty)
        #expect(intake.dueDeletionEntries(now: now.addingTimeInterval(60)).isEmpty)
    }

    @Test func delete_queuedWeightDeletion_isKeptWhileTheBodyGroupWasAsked_andDroppedWhenItWasNot() async throws {
        let entry = weight()
        intake.addWeight(entry)
        intake.delete(entry.id, healthNotBefore: now)
        #expect(intake.dueDeletionEntries(now: now).first?.kind == .weight)
        // Not asked: nothing ever reached Health, so there is nothing to delete.
        await mirror().sync()
        #expect(intake.dueDeletionEntries(now: now).isEmpty)
        #expect(health.deleted.isEmpty)

        let again = weight()
        intake.addWeight(again)
        intake.delete(again.id, healthNotBefore: now)
        health.setGroupAccess(.asked, for: .body)
        health.failWrites = true
        await mirror().sync()
        #expect(intake.dueDeletionEntries(now: now).count == 1, "a failed deletion stays queued")
        health.failWrites = false
        await mirror().sync()
        #expect(health.deleted == [again.id])
    }

    // MARK: History

    @Test func measurements_mergeOwnAndForeign_withSourceNames() async {
        let store = WeightStore(intake: intake, health: health, calendar: calendar)
        health.setGroupAccess(.asked, for: .body)
        intake.addWeight(weight(82.0, at: now))
        health.foreignWeights = [ForeignWeight(id: UUID(), date: now.addingTimeInterval(-86_400), kilograms: 82.6, sourceName: "Waage",
                                               bodyFatPercent: 23.4)]
        let list = await store.measurements(in: window)
        #expect(list.map(\.kilograms) == [82.6, 82.0])
        #expect(list.map(\.sourceName) == ["Waage", nil])
        #expect(list.first?.bodyFatPercent == 23.4)
    }

    @Test func measurements_withoutTheBodyGroup_areOwnOnly() async {
        let store = WeightStore(intake: intake, health: health, calendar: calendar)
        intake.addWeight(weight(82.0))
        health.foreignWeights = [ForeignWeight(id: UUID(), date: now, kilograms: 99, sourceName: "Waage")]
        #expect(await store.measurements(in: window).map(\.kilograms) == [82.0])
    }

    @Test func dayValues_takeTheEarliestMeasurementOfTheDay() async {
        let store = WeightStore(intake: intake, health: health, calendar: calendar)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 6, minute: 40))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 21, minute: 5))!
        intake.addWeight(weight(83.0, at: evening))
        intake.addWeight(weight(82.2, at: morning))
        let days = await store.dayValues(in: DateInterval(start: morning.addingTimeInterval(-86_400), end: evening.addingTimeInterval(86_400)))
        #expect(days[PlanDay(year: 2026, month: 11, day: 18)]?.kilograms == 82.2)
    }
}
