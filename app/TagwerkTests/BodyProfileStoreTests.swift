import Foundation
import HealthBridge
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The body values for the cross-check of goals (decision PV4b). All data is invented.
@MainActor
struct BodyProfileStoreTests {
    let container: ModelContainer
    let settings: AppSettings
    let health = FakeHealthStore()
    let calendar = testCalendar()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
    }

    private func store() -> BodyProfileStore {
        BodyProfileStore(settings: settings, health: health, calendar: calendar, now: { testNow() })
    }

    @Test func refresh_notAsked_readsNothing() async {
        health.bodyProfileValue = HealthBodyProfile(heightCm: 181, birthYear: 1990, sex: .male)
        let store = store()
        #expect(await store.refresh() == .notAsked)
        #expect(settings.healthBodyValues == .empty && settings.healthBodyProfileReadAt == nil)
        #expect(health.groupRequests(.bodyProfile) == 0, "reading never asks by itself")
    }

    @Test func readFromHealth_asksOnceAndStoresWholeCentimetresAndTheBirthYear() async {
        health.bodyProfileValue = HealthBodyProfile(heightCm: 180.6, birthYear: 1990, sex: .female)
        let store = store()
        #expect(await store.readFromHealth() == .delivered)
        #expect(health.groupRequests(.bodyProfile) == 1)
        #expect(settings.healthBodyValues == BodyProfileValues(heightCm: 181, birthYear: 1990, sex: .female))
        #expect(settings.healthBodyProfileReadAt != nil)
        #expect(store.profile.height == BodyValue(value: 181, source: .health))
        _ = await store.readFromHealth()
        #expect(health.groupRequests(.bodyProfile) == 1, "an asked group is not asked again")
    }

    @Test func refresh_healthSilent_keepsLastReadValue() async {
        health.bodyProfileValue = HealthBodyProfile(heightCm: 181, birthYear: 1990, sex: .male)
        let store = store()
        _ = await store.readFromHealth()
        health.bodyProfileValue = .empty
        #expect(await store.refresh() == .nothingDelivered)
        #expect(settings.healthBodyValues == BodyProfileValues(heightCm: 181, birthYear: 1990, sex: .male))
        #expect(store.lastRead == .nothingDelivered)
    }

    @Test func refresh_partialAnswer_changesOnlyTheDeliveredFields() async {
        health.bodyProfileValue = HealthBodyProfile(heightCm: 181, birthYear: 1990, sex: .male)
        let store = store()
        _ = await store.readFromHealth()
        health.bodyProfileValue = HealthBodyProfile(heightCm: 183)
        _ = await store.refresh()
        #expect(settings.healthBodyValues == BodyProfileValues(heightCm: 183, birthYear: 1990, sex: .male))
    }

    @Test func resolved_prefersHealthValuePerField_andFallsBackToTyped() async {
        settings.typedBodyValues = BodyProfileValues(heightCm: 170, birthYear: 1985, sex: .female)
        health.bodyProfileValue = HealthBodyProfile(heightCm: 181, birthYear: nil, sex: nil)
        let store = store()
        _ = await store.readFromHealth()
        let profile = store.profile
        #expect(profile.height == BodyValue(value: 181, source: .health))
        #expect(profile.birthYear == BodyValue(value: 1985, source: .typed))
        #expect(profile.sex == BodyValue(value: .female, source: .typed))
    }

    @Test func sexOtherOrUnset_requiresTypedChoice() async {
        // Health knows more values than the formula; they arrive as nil, and the field stays missing until it is typed.
        health.bodyProfileValue = HealthBodyProfile(heightCm: 181, birthYear: 1990, sex: nil)
        let store = store()
        _ = await store.readFromHealth()
        #expect(store.profile.missingFields == [.sex])
        store.setTypedSex(.male)
        #expect(store.profile.sex == BodyValue(value: .male, source: .typed))
        #expect(store.profile.isComplete)
    }

    @Test func healthValuesOutsideTheLimits_countAsNotDelivered() async {
        health.bodyProfileValue = HealthBodyProfile(heightCm: 20, birthYear: 1850, sex: nil)
        let store = store()
        #expect(await store.readFromHealth() == .nothingDelivered)
        #expect(settings.healthBodyValues == .empty)
    }

    @Test func typedValues_outsideTheLimits_areIgnored() {
        let store = store()
        store.setTypedHeight(180)
        store.setTypedHeight(900)
        store.setTypedBirthYear(1990)
        store.setTypedBirthYear(3000)
        #expect(settings.bodyHeightCm == 180 && settings.birthYear == 1990)
        store.setTypedHeight(nil)
        #expect(settings.bodyHeightCm == nil, "an empty field clears the value")
    }

    @Test func age_usesTheClockOfTheStore() {
        settings.typedBodyValues = BodyProfileValues(birthYear: 1990)
        let store = store()
        #expect(store.profile.ageYears(inYear: store.currentYear) == store.currentYear - 1990)
    }

    // MARK: Backup

    @Test func backup_roundTripsTypedValuesButNotWhatHealthDelivered() throws {
        settings.typedBodyValues = BodyProfileValues(heightCm: 175, birthYear: 1988, sex: .female)
        settings.healthBodyValues = BodyProfileValues(heightCm: 181, birthYear: 1990, sex: .male)
        let data = try JSONEncoder().encode(AppSettingsBackup(settings))
        let target = try ModelContainerFactory.make(inMemory: true)
        let targetSettings = try AppSettings.current(in: target.mainContext)
        try JSONDecoder().decode(AppSettingsBackup.self, from: data).apply(to: targetSettings)
        #expect(targetSettings.typedBodyValues == BodyProfileValues(heightCm: 175, birthYear: 1988, sex: .female))
        #expect(targetSettings.healthBodyValues == .empty, "Health values are device state and are read again")
    }

    @Test func backup_oldFileWithoutBodyData_decodes() throws {
        settings.typedBodyValues = BodyProfileValues(heightCm: 175, birthYear: 1988, sex: .female)
        let data = try JSONEncoder().encode(AppSettingsBackup(settings))
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["bodyHeightCm", "birthYear", "formulaSexRaw"] { object[key] = nil }
        let older = try JSONDecoder().decode(AppSettingsBackup.self, from: JSONSerialization.data(withJSONObject: object))
        let target = try ModelContainerFactory.make(inMemory: true)
        let targetSettings = try AppSettings.current(in: target.mainContext)
        targetSettings.typedBodyValues = BodyProfileValues(heightCm: 190)
        older.apply(to: targetSettings)
        #expect(targetSettings.typedBodyValues == BodyProfileValues(heightCm: 190), "the device keeps its own values")
    }
}
