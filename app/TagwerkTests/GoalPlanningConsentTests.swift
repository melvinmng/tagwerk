import Foundation
import SwiftData
import Testing
@testable import Tagwerk

/// The consent "Ziele mit ChatGPT planen" (decision PV1b).
@MainActor
struct GoalPlanningConsentTests {
    let container: ModelContainer
    let settings: AppSettings

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
    }

    @Test func consent_defaultOff() {
        #expect(!settings.goalPlanningConsent)
    }

    @Test func consent_roundTripsThroughTheBackup() throws {
        settings.goalPlanningConsent = true
        let data = try JSONEncoder().encode(AppSettingsBackup(settings))
        let target = try ModelContainerFactory.make(inMemory: true)
        let targetSettings = try AppSettings.current(in: target.mainContext)
        try JSONDecoder().decode(AppSettingsBackup.self, from: data).apply(to: targetSettings)
        #expect(targetSettings.goalPlanningConsent)
    }

    @Test func consent_notRestoredAsOnFromOldBackup() throws {
        settings.goalPlanningConsent = true
        let data = try JSONEncoder().encode(AppSettingsBackup(settings))
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["goalPlanningConsent"] = nil
        let older = try JSONDecoder().decode(AppSettingsBackup.self, from: JSONSerialization.data(withJSONObject: object))
        let target = try ModelContainerFactory.make(inMemory: true)
        let targetSettings = try AppSettings.current(in: target.mainContext)
        targetSettings.goalPlanningConsent = true
        older.apply(to: targetSettings)
        #expect(!targetSettings.goalPlanningConsent, "a file from before the goal planning never held the consent")
    }
}
