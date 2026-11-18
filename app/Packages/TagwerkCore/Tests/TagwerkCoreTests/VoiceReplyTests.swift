import Testing
@testable import TagwerkCore

struct VoiceReplyTests {
    @Test(arguments: [
        ("ja", VoiceReply.confirm), ("Ja.", .confirm), ("  Ja bitte! ", .confirm), ("Bestätigen", .confirm),
        ("Yes", .confirm), ("yes please", .confirm), ("Confirm.", .confirm),
        ("Ja, löschen.", .confirmDelete), ("ja löschen", .confirmDelete), ("Yes, delete", .confirmDelete),
        ("Alle bestätigen", .confirmAll), ("confirm all", .confirmAll),
        ("Nein", .decline), ("Nein.", .decline), ("Verwerfen", .decline), ("Abbrechen", .decline), ("No", .decline),
        ("Discard", .decline), ("Cancel", .decline),
        ("Stopp", .stop), ("stop", .stop), ("Halt!", .stop),
        ("ja aber um 11", .other), ("jaja", .other), ("ja genau", .other), ("nein danke, lieber morgen", .other),
        ("ok", .other), ("passt", .other), ("mach das", .other), ("alle", .other), ("", .other),
        ("Nimm den Arbeitskalender", .other),
    ])
    func classify(_ text: String, _ expected: VoiceReply) {
        #expect(VoiceReply(text) == expected, "\(text)")
    }
}

struct OpenCardsTests {
    @Test func countsDeletes() {
        let cards = OpenCards(ids: ["a", "b"], deletes: 1)
        #expect(cards.count == 2)
        #expect(!cards.isEmpty)
        #expect(OpenCards.none.isEmpty)
    }
}

struct VoiceModeAnnouncementTests {
    @Test func oneCard_asksForYesOrNo() {
        let text = ActionAnnouncement.text(for: [("Test", "Termin anlegen · Do. 19. Nov.")], language: .german, byVoice: true)
        #expect(text?.hasSuffix("Sag ja oder nein, oder was anders sein soll.") == true)
        let english = ActionAnnouncement.text(for: [("Test", "Create event")], language: .english, byVoice: true)
        #expect(english?.hasSuffix("Say yes or no, or what should be different.") == true)
    }

    @Test func deleteCard_asksForExplicitPhrase() {
        let text = ActionAnnouncement.text(for: [("Test", "Termin löschen · Do. 19. Nov.")], language: .german, byVoice: true, deletes: 1)
        #expect(text?.hasSuffix("Zum Löschen sag: Ja, löschen. Oder nein.") == true)
    }

    @Test func severalCards_explainAllConfirm() {
        let cards = [("A", "x"), ("B", "y")]
        #expect(ActionAnnouncement.text(for: cards, language: .german, byVoice: true)
            == "Zwei Änderungen warten. Sag alle bestätigen, oder tippe auf eine Karte.")
    }

    @Test func prompts() {
        #expect(ActionAnnouncement.prompt(.severalCards(3), language: .german) == "Es sind drei Vorschläge offen. Sag alle bestätigen, oder tippe auf eine Karte.")
        #expect(ActionAnnouncement.prompt(.sayDelete, language: .german) == "Zum Löschen sag: Ja, löschen.")
        #expect(ActionAnnouncement.prompt(.deletesNeedTap, language: .german) == "Löschungen bitte einzeln bestätigen.")
        #expect(ActionAnnouncement.prompt(.cancelled, language: .english) == "Cancelled.")
    }
}
