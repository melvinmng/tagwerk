import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// SPC4b: one consent covers "Mit ChatGPT sortieren" and "Artikel übersetzen"; its text changed, so an earlier agreement asks again.
@MainActor
struct ShoppingConsentTests {
    let container: ModelContainer
    let settings: AppSettings

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
    }

    @Test func consent_defaultsToNone() {
        #expect(!settings.hasShoppingSortConsent && settings.shoppingSortConsentVersion == 0)
    }

    @Test func consent_givenForTheOldText_doesNotCountAnymore() {
        // What a device holds that agreed before translating existed: the flag is on, the version was never written.
        settings.shoppingSortConsent = true
        #expect(settings.shoppingSortConsentVersion == 0)
        #expect(!settings.hasShoppingSortConsent)
    }

    @Test func consent_agreeing_storesTheCurrentVersion() {
        settings.hasShoppingSortConsent = true
        #expect(settings.shoppingSortConsent && settings.shoppingSortConsentVersion == AppSettings.currentShoppingSortConsentVersion)
        #expect(settings.hasShoppingSortConsent)
    }

    @Test func consent_revoking_clearsBoth() {
        settings.hasShoppingSortConsent = true
        settings.hasShoppingSortConsent = false
        #expect(!settings.shoppingSortConsent && settings.shoppingSortConsentVersion == 0 && !settings.hasShoppingSortConsent)
    }

    @Test func consent_askedAgainAfterTheOldAgreement_isGivenOnce() {
        settings.shoppingSortConsent = true
        settings.hasShoppingSortConsent = true
        #expect(settings.hasShoppingSortConsent, "after agreeing to the new text the question does not come again")
    }

    @Test func sorterAndTranslator_useTheVersionedConsent() async throws {
        settings.shoppingSortConsent = true
        let environment = try AppEnvironment(modelContainer: container, notificationCenter: FakeNotificationCenter(), health: FakeHealthStore())
        let plan = ShoppingTranslationPlan(openItems: [ShoppingItem(id: "a", name: "Äpfel")])
        // The old agreement does not cover either request: they stop before anything is sent.
        await #expect(throws: ShoppingTranslator.Failure.consentMissing) { try await environment.shoppingTranslator.translate(plan, to: .english) }
        await #expect(throws: ShoppingSorter.Failure.consentMissing) {
            try await environment.shoppingSorter.sort(ShoppingSorter.Request(itemNames: ["Äpfel"], categoryNames: ["Sonstiges"]), current: [:])
        }
    }
}
