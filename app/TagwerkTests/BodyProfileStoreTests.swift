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

    // MARK: Overrides and writing (#317)

    @Test func typedBirthYearAndSex_overrideHealth_andSurviveANewReading() async {
        health.bodyProfileValue = HealthBodyProfile(heightCm: 180, birthYear: 1994, sex: .male)
        let store = store()
        _ = await store.readFromHealth()
        store.setTypedBirthYear(1995)
        store.setTypedSex(.female)
        #expect(store.profile.birthYear == BodyValue(value: 1995, source: .typed))
        #expect(store.profile.sex == BodyValue(value: .female, source: .typed))
        _ = await store.refresh()
        #expect(store.profile.birthYear.value == 1995, "reading Health again does not undo the override")
        #expect(settings.healthBodyValues.birthYear == 1994, "what Health says stays known, for the hint")
        #expect(store.profile.height == BodyValue(value: 180, source: .health), "a field without an edit stays with Health")
    }

    @Test func clearingAField_returnsToTheValueOfHealth() async {
        health.bodyProfileValue = HealthBodyProfile(heightCm: 180, birthYear: 1994, sex: .male)
        let store = store()
        _ = await store.readFromHealth()
        store.setTypedBirthYear(1995)
        store.setTypedBirthYear(nil)
        #expect(store.profile.birthYear == BodyValue(value: 1994, source: .health))
        #expect(settings.bodyOverrides.isEmpty)
    }

    @Test func staleTypedValue_withoutAnOverride_doesNotWinOverHealth() async {
        // A value typed while Health was silent (before the override existed) must not resurface.
        settings.typedBodyValues = BodyProfileValues(heightCm: 170, birthYear: 1980, sex: .female)
        health.bodyProfileValue = HealthBodyProfile(heightCm: 180, birthYear: 1994, sex: .male)
        let store = store()
        _ = await store.readFromHealth()
        #expect(store.profile.values == BodyProfileValues(heightCm: 180, birthYear: 1994, sex: .male))
    }

    @Test func rejectedInput_setsNoOverride() {
        let store = store()
        store.setTypedBirthYear(3000)
        store.setTypedHeight(900)
        #expect(settings.bodyOverrides.isEmpty)
    }

    @Test func updateHeight_writesToHealthOnce_andReplacesTheEarlierValue() async {
        health.setWriteAccess(.allowed, for: .height)
        let store = store()
        #expect(await store.updateHeight(181) == .written)
        #expect(health.heights.map(\.centimeters) == [181])
        #expect(store.profile.height == BodyValue(value: 181, source: .typed))
        #expect(await store.updateHeight(182) == .written)
        #expect(health.heights.map(\.centimeters) == [182], "one sample, not one per edit")
        #expect(await store.updateHeight(182) == .notNeeded, "an unchanged value writes nothing")
        #expect(health.heights.count == 1)
    }

    @Test func updateHeight_withoutPermission_keepsTheValueLocal_andSaysSo() async {
        let store = store()
        #expect(await store.updateHeight(181) == .notAllowed)
        #expect(health.heights.isEmpty)
        #expect(store.profile.height == BodyValue(value: 181, source: .typed), "Tagwerk calculates with it anyway")
    }

    @Test func pendingHeight_isWrittenOnceThePermissionComes() async {
        let store = store()
        #expect(await store.updateHeight(181) == .notAllowed)
        #expect(await store.writePendingHeight() == .notAllowed, "still no permission")
        health.setWriteAccess(.allowed, for: .height)
        #expect(await store.writePendingHeight() == .written)
        #expect(health.heights.map(\.centimeters) == [181])
        settings.healthBodyHeightCm = 181
        #expect(await store.writePendingHeight() == .notNeeded, "Health holds the value now")
    }

    @Test func pendingHeight_withoutAnEditedHeight_writesNothing() async {
        health.setWriteAccess(.allowed, for: .height)
        settings.typedBodyValues = BodyProfileValues(heightCm: 170)
        let store = store()
        #expect(await store.writePendingHeight() == .notNeeded, "a typed value without the marker is only a fallback")
        #expect(health.heights.isEmpty)
    }

    @Test func updateHeight_outOfRange_writesNothing() async {
        health.setWriteAccess(.allowed, for: .height)
        let store = store()
        #expect(await store.updateHeight(900) == .notNeeded)
        #expect(health.heights.isEmpty)
    }

    @Test func updateHeight_cleared_removesTheOverrideWithoutWriting() async {
        health.setWriteAccess(.allowed, for: .height)
        let store = store()
        _ = await store.updateHeight(181)
        #expect(await store.updateHeight(nil) == .notNeeded)
        #expect(settings.bodyHeightCm == nil && !settings.bodyOverrides.contains(.height))
    }

    @Test func notes_sayWhereAValueComesFrom() {
        #expect(BodyProfileSection.note(source: .health, value: "1994", health: "1994") == "aus Health")
        #expect(BodyProfileSection.note(source: .typed, value: "1995", health: "1994") == "eingetragen · Health sagt 1994")
        #expect(BodyProfileSection.note(source: .typed, value: "1995", health: nil) == "eingetragen")
        #expect(BodyProfileSection.note(source: .typed, value: "1994", health: "1994") == "eingetragen")
        #expect(BodyProfileSection.note(source: .missing, value: nil, health: nil) == "fehlt")
    }

    @Test func heightNote_saysWhetherHealthTakesTheValue() {
        #expect(BodyProfileSection.heightNote(source: .typed, value: 181, health: 180, writeAccess: .allowed)
                == "eingetragen · wird nach Health geschrieben")
        #expect(BodyProfileSection.heightNote(source: .typed, value: 181, health: 180, writeAccess: .denied)
                == "eingetragen · nicht nach Health geschrieben")
        #expect(BodyProfileSection.heightNote(source: .typed, value: 181, health: nil, writeAccess: .notAsked)
                == "eingetragen · nicht nach Health geschrieben")
        #expect(BodyProfileSection.heightNote(source: .health, value: 180, health: 180, writeAccess: .allowed) == "aus Health")
    }

    @Test func overrides_roundTripThroughTheBackup() throws {
        settings.bodyOverrides = [.birthYear, .sex]
        let data = try JSONEncoder().encode(AppSettingsBackup(settings))
        let target = try ModelContainerFactory.make(inMemory: true)
        let targetSettings = try AppSettings.current(in: target.mainContext)
        try JSONDecoder().decode(AppSettingsBackup.self, from: data).apply(to: targetSettings)
        #expect(targetSettings.bodyOverrides == [.birthYear, .sex])
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
