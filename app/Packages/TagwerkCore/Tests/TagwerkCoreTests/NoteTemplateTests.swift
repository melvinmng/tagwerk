import Foundation
import Testing
@testable import TagwerkCore

struct NoteTemplateTests {
    let german = Locale(identifier: "de_DE")

    @Test func guidingQuestions_german() {
        #expect(NoteTemplate.guidingQuestions(locale: german)
                == ["Was war mein Ziel?", "Was hat geholfen?", "Was hat abgehalten?", "Erfahrungen mit anderen", "Meine eigene Rolle", "Nächste Schritte"])
    }

    @Test func appending_toEmptyText() {
        #expect(NoteTemplate.appendingGuidingQuestions(to: "", locale: german)
                == "Was war mein Ziel?\n\nWas hat geholfen?\n\nWas hat abgehalten?\n\nErfahrungen mit anderen\n\nMeine eigene Rolle\n\nNächste Schritte\n\n")
    }

    @Test func appending_keepsExistingText() {
        let result = NoteTemplate.appendingGuidingQuestions(to: "Heute war gut.", locale: german)
        #expect(result.hasPrefix("Heute war gut.\n\nWas war mein Ziel?\n\n"))
        // Trailing white space of the note does not pile up.
        #expect(NoteTemplate.appendingGuidingQuestions(to: "Heute war gut.\n\n\n", locale: german).hasPrefix("Heute war gut.\n\nWas war mein Ziel?\n\n"))
    }

    @Test func contains_hidesTheButtonOnceInserted() {
        #expect(!NoteTemplate.containsGuidingQuestions("Heute war gut.", locale: german))
        let inserted = NoteTemplate.appendingGuidingQuestions(to: "Heute war gut.", locale: german)
        #expect(NoteTemplate.containsGuidingQuestions(inserted, locale: german))
    }

    @Test func guidingQuestions_english_haveSixEntries() {
        let english = NoteTemplate.guidingQuestions(locale: Locale(identifier: "en_US"))
        #expect(english.count == 6)
        #expect(english.first == "What was my goal?")
        #expect(Set(english).count == 6)
    }

    @Test func contains_findsTheQuestionInEitherLanguage() {
        let english = NoteTemplate.appendingGuidingQuestions(to: "", locale: Locale(identifier: "en_US"))
        #expect(NoteTemplate.containsGuidingQuestions(english, locale: Locale(identifier: "en_US")))
        #expect(!NoteTemplate.containsGuidingQuestions(english, locale: german))
    }
}
