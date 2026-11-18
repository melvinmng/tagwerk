import Testing
@testable import TagwerkCore

struct ActionAnnouncementTests {
    @Test func noCards_returnsNil() {
        #expect(ActionAnnouncement.text(for: [], language: .german) == nil)
        #expect(ActionAnnouncement.text(for: [], language: .english) == nil)
    }

    @Test func single_german() {
        let text = ActionAnnouncement.text(
            for: [(title: "Zeitblock anlegen", change: "Mail an Prüfungsamt · Mi 18. Nov. · 16:00–16:30")],
            language: .german
        )
        #expect(text == "Ich schlage vor: Zeitblock anlegen, Mail an Prüfungsamt, Mi 18. Nov., 16:00 bis 16:30. Bitte bestätige auf dem Bildschirm.")
    }

    @Test func single_english() {
        let text = ActionAnnouncement.text(
            for: [(title: "Create time block", change: "Email exam office · P2")],
            language: .english
        )
        #expect(text == "I suggest: Create time block, Email exam office, priority two. Please confirm on the screen.")
    }

    @Test func multiple_german_usesCapitalisedNumberWords() {
        let three = (0..<3).map { _ in (title: "T", change: "C") }
        #expect(ActionAnnouncement.text(for: three, language: .german) == "Drei Änderungen warten auf deine Bestätigung.")
        let two = Array(three.prefix(2))
        #expect(ActionAnnouncement.text(for: two, language: .german) == "Zwei Änderungen warten auf deine Bestätigung.")
    }

    @Test func multiple_english() {
        let four = (0..<4).map { _ in (title: "T", change: "C") }
        #expect(ActionAnnouncement.text(for: four, language: .english) == "Four changes are waiting for your confirmation.")
    }

    @Test func multiple_twelveIsWord_thirteenIsDigits() {
        let twelve = (0..<12).map { _ in (title: "T", change: "C") }
        let thirteen = (0..<13).map { _ in (title: "T", change: "C") }
        #expect(ActionAnnouncement.text(for: twelve, language: .german) == "Zwölf Änderungen warten auf deine Bestätigung.")
        #expect(ActionAnnouncement.text(for: thirteen, language: .german) == "13 Änderungen warten auf deine Bestätigung.")
        #expect(ActionAnnouncement.text(for: twelve, language: .english) == "Twelve changes are waiting for your confirmation.")
        #expect(ActionAnnouncement.text(for: thirteen, language: .english) == "13 changes are waiting for your confirmation.")
    }

    @Test func executed_confirmation() {
        #expect(ActionAnnouncement.executed(.german) == "Ausgeführt.")
        #expect(ActionAnnouncement.executed(.english) == "Done.")
    }
}
