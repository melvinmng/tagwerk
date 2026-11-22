import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// Every consent sheet of a function with proposals names the follow-up messages (plan ki-vorschlaege-anpassen, task A4).
@MainActor
struct ConsentFollowUpTextTests {
    /// The sheets that ask for the consent of a function whose proposals can be adjusted or revised.
    private static let sheets = [
        "Capture/MealConsentSheet.swift",
        "Shopping/ShoppingSortSheets.swift",
        "Shopping/RecipeSheets.swift",
        "Share/MailSummaryConsentSheet.swift",
        "Routines/NoteConsentSheet.swift",
    ]

    private static var sourceRoot: URL {
        // .../app/TagwerkTests/<this file> -> .../app/Tagwerk
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tagwerk")
    }

    @Test func sentence_namesWhatIsSentAgain_inBothLanguages() {
        let german = ConsentFollowUpPoint.sentence(in: .german)
        #expect(german == "Wenn du zu einem Vorschlag etwas zurückschreibst, sendet Tagwerk dieselben Angaben noch einmal, dazu den Vorschlag mit deinen Änderungen und deine Nachricht.")
        let english = ConsentFollowUpPoint.sentence(in: .english)
        #expect(english.contains("same") && english.contains("message") && english != german)
    }

    @Test func consentTexts_mentionFollowUps() throws {
        for sheet in Self.sheets {
            let url = Self.sourceRoot.appendingPathComponent(sheet)
            let source = try #require(try? String(contentsOf: url, encoding: .utf8), "cannot read \(sheet)")
            #expect(source.contains("ConsentFollowUpPoint()"), "\(sheet) does not name the follow-up messages")
        }
    }

    @Test func consentTexts_keepTheirPromisesWordForWord() throws {
        // The sentences about what is not sent stay as they were (they are what the user agreed to).
        let promises: [(String, String)] = [
            ("Capture/MealConsentSheet.swift", "**Nicht gesendet werden** Daten aus Health, deine Ziele und frühere Einträge."),
            ("Shopping/ShoppingSortSheets.swift", "**Nicht gesendet werden:** Mengen, erledigte Artikel, Aufgaben, Termine, Notizen, Daten aus Health."),
            ("Share/MailSummaryConsentSheet.swift", "**Nicht gesendet werden** Anhänge, E-Mail-Adressen (auch im Text), Empfänger und der Link zur Mail."),
            ("Routines/NoteConsentSheet.swift", "**Nicht gesendet werden** Dankbarkeit, Gewohnheiten, Wochenreflexion, Daten aus Health und frühere Notizen."),
        ]
        for (sheet, promise) in promises {
            let source = try String(contentsOf: Self.sourceRoot.appendingPathComponent(sheet), encoding: .utf8)
            #expect(source.contains(promise), "\(sheet): the promise changed")
        }
    }

    @Test func existingConsent_staysValid() throws {
        // The new sentence does not bump the version of the sort consent: nobody has to agree again.
        #expect(AppSettings.currentShoppingSortConsentVersion == 1)
        let container = try ModelContainerFactory.make(inMemory: true)
        let settings = try AppSettings.current(in: container.mainContext)
        settings.shoppingSortConsent = true
        settings.shoppingSortConsentVersion = 1
        #expect(settings.hasShoppingSortConsent)
    }
}
