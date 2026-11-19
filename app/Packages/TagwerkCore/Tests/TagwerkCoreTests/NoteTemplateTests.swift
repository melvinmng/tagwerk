import Foundation
import Testing
@testable import TagwerkCore

struct NoteTemplateTests {
    let german = Locale(identifier: "de_DE")

    @Test func guidingQuestions_german() {
        #expect(NoteTemplate.guidingQuestions(locale: german)
                == ["Was will ich in meinem Leben (im Moment) erreichen?",
                    "Was habe ich gemacht, um zu erreichen, was ich will?",
                    "Was habe ich gemacht, das mich davon abgehalten hat, zu erreichen, was ich will?",
                    "Was für Erfahrungen habe ich in letzter Zeit mit anderen Menschen gemacht? (positive und negative)",
                    "Was bedrückt mich sonst grade?",
                    "Wie habe ich gehandelt und was für Gedanken habe ich mir gemacht, die diese Erfahrungen schlimmer gemacht haben, als nötig?",
                    "Was für eine Rolle spiele ich in den negativen Dingen, die passiert sind? Kann ich Eigenverantwortung übernehmen?",
                    "Was kann ich machen, um die negativen Dinge in meinem Leben aktiv zu verbessern?"])
    }

    @Test func appending_toEmptyText() {
        #expect(NoteTemplate.appendingGuidingQuestions(to: "", locale: german)
                == NoteTemplate.guidingQuestions(locale: german).map { $0 + "\n\n" }.joined())
    }

    @Test func appending_keepsExistingText() {
        let result = NoteTemplate.appendingGuidingQuestions(to: "Heute war gut.", locale: german)
        #expect(result.hasPrefix("Heute war gut.\n\nWas will ich in meinem Leben (im Moment) erreichen?\n\n"))
        // Trailing white space of the note does not pile up.
        #expect(NoteTemplate.appendingGuidingQuestions(to: "Heute war gut.\n\n\n", locale: german).hasPrefix("Heute war gut.\n\nWas will ich in meinem Leben (im Moment) erreichen?\n\n"))
    }

    @Test func contains_hidesTheButtonOnceInserted() {
        #expect(!NoteTemplate.containsGuidingQuestions("Heute war gut.", locale: german))
        let inserted = NoteTemplate.appendingGuidingQuestions(to: "Heute war gut.", locale: german)
        #expect(NoteTemplate.containsGuidingQuestions(inserted, locale: german))
    }

    @Test func guidingQuestions_english_haveEightEntries() {
        let english = NoteTemplate.guidingQuestions(locale: Locale(identifier: "en_US"))
        #expect(english.count == 8)
        #expect(english.first == "What do I want to achieve in my life (right now)?")
        #expect(Set(english).count == 8)
    }

    @Test func contains_recognizesTheLegacyQuestions() {
        let english = Locale(identifier: "en_US")
        for locale in [german, english] {
            #expect(NoteTemplate.containsGuidingQuestions("Was war mein Ziel?\n\nWas hat geholfen?", locale: locale))
            #expect(NoteTemplate.containsGuidingQuestions("What was my goal?\n\nWhat helped?", locale: locale))
        }
    }

    @Test func contains_findsTheQuestionInEitherLanguage() {
        let english = NoteTemplate.appendingGuidingQuestions(to: "", locale: Locale(identifier: "en_US"))
        #expect(NoteTemplate.containsGuidingQuestions(english, locale: Locale(identifier: "en_US")))
        #expect(!NoteTemplate.containsGuidingQuestions(english, locale: german))
    }
}
