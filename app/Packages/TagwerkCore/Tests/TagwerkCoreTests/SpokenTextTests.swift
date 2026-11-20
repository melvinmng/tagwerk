import Testing
@testable import TagwerkCore

struct SpokenTextTests {
    private func de(_ text: String) -> String { SpokenText.prepare(text, language: .german) }
    private func en(_ text: String) -> String { SpokenText.prepare(text, language: .english) }

    @Test func prepare_stripsMarkdownAndSymbols() {
        #expect(de("**Heute** ✦ drei Termine") == "Heute drei Termine")
        #expect(de("__fett__ und `code`") == "fett und code")
        #expect(de("⚑ Wichtig ✓ erledigt ✕ offen → morgen") == "Wichtig erledigt offen morgen")
    }

    @Test func prepare_stripsHeadingsAndListMarkers() {
        #expect(de("# Titel\n## Unterpunkt\ntext") == "Titel Unterpunkt text")
        #expect(de("- Mail senden\n* Anruf\n1. Plan\n12. Ende") == "Mail senden Anruf Plan Ende")
    }

    @Test func prepare_replacesLinksWithLabel() {
        #expect(de("Siehe [die Doku](https://example.com/a?b=c) jetzt") == "Siehe die Doku jetzt")
    }

    // MARK: Markdown answers (#225)

    @Test func prepare_readsAnswerMarkupAsPlainText() {
        #expect(de("Das ist *wichtig* und ~~falsch~~") == "Das ist wichtig und falsch")
        #expect(de("> Zitat hier\nnormal") == "Zitat hier normal")
        #expect(de("Text mit <b>fett</b> und<br>Umbruch") == "Text mit fett und Umbruch")
        #expect(de("Tom &amp; Jerry") == "Tom & Jerry")
    }

    @Test func prepare_readsATableWithoutPipesOrSeparator() {
        let table = "| Name | Zahl |\n|:-----|-----:|\n| a | 1 |\n| b | 2 |"
        #expect(de(table) == "Name Zahl a 1 b 2")
    }

    @Test func prepare_dropsCodeFencesButKeepsTheCode() {
        #expect(de("Vorher\n```swift\nlet a = 1\n```\nNachher") == "Vorher let a = 1 Nachher")
    }

    @Test func prepare_neverSpeaksMarkdownSymbols() {
        let answer = "# Plan\n\n- **Mail** an [Anna](https://example.com)\n- `git push` ausführen\n\n| a | b |\n|---|---|\n| 1 | 2 |"
        let spoken = de(answer)
        for symbol in ["#", "**", "`", "|", "](", "---"] {
            #expect(!spoken.contains(symbol), "found \(symbol) in: \(spoken)")
        }
    }

    @Test func prepare_removesEmoji_butKeepsDigits() {
        #expect(de("Super 😀 gemacht 🎉👍🏽 um 5 Uhr") == "Super gemacht um 5 Uhr")
        #expect(de("Test 1️⃣ ok") == "Test 1 ok")
    }

    @Test func prepare_priority_german() {
        #expect(de("Aufgabe P1") == "Aufgabe Priorität eins")
        #expect(de("P2, P3 und P4") == "Priorität zwei, Priorität drei und Priorität vier")
    }

    @Test func prepare_priority_english() {
        #expect(en("Task P2 is due") == "Task priority two is due")
        #expect(en("P1 P4") == "priority one priority four")
    }

    @Test func prepare_priority_ignoresLongerTokens() {
        #expect(de("P10 bleibt") == "P10 bleibt")
        #expect(de("XP2 und P2x") == "XP2 und P2x")
    }

    @Test func prepare_timeRange_german() {
        #expect(de("16:00–16:30") == "16:00 bis 16:30")
        #expect(de("16:00 - 16:30") == "16:00 bis 16:30")
        #expect(de("von 9:15 – 10:45 Uhr") == "von 9:15 bis 10:45 Uhr")
    }

    @Test func prepare_timeRange_english() {
        #expect(en("16:00–16:30") == "16:00 to 16:30")
    }

    @Test func prepare_keepsSingleTimesAndOtherDashes() {
        #expect(de("um 16:00 Uhr") == "um 16:00 Uhr")
        #expect(de("Mo–Fr") == "Mo–Fr")
    }

    @Test func prepare_collapsesWhitespace() {
        #expect(de("  a   b \n\n c\t d  ") == "a b c d")
    }

    @Test func sentences_splitsOnTerminatorsFollowedByWhitespace() {
        #expect(SpokenText.sentences("Eins. Zwei! Drei? Vier") == ["Eins.", "Zwei!", "Drei?", "Vier"])
    }

    @Test func sentences_doesNotSplitDecimals() {
        #expect(SpokenText.sentences("Das dauert 4,5 Stunden. Oder 2.5 Tage.") == ["Das dauert 4,5 Stunden.", "Oder 2.5 Tage."])
    }

    @Test func sentences_doesNotSplitAbbreviations() {
        #expect(SpokenText.sentences("Heute, z. B. Mo. Nov. und ca. 5 Stunden. Ende.") == ["Heute, z. B. Mo. Nov. und ca. 5 Stunden.", "Ende."])
        #expect(SpokenText.sentences("Das gilt d. h. immer. Gut.") == ["Das gilt d. h. immer.", "Gut."])
    }

    @Test func sentences_doesNotSplitOrdinalDates() {
        #expect(SpokenText.sentences("Am 18. November ist es so. Am 3. Mai nicht.") == ["Am 18. November ist es so.", "Am 3. Mai nicht."])
        #expect(SpokenText.sentences("Mi 18. Nov. 16:00 Uhr. Danach frei.") == ["Mi 18. Nov. 16:00 Uhr.", "Danach frei."])
    }

    @Test func sentences_trimsAndDropsEmpties() {
        #expect(SpokenText.sentences("  Hallo.   Welt.  ") == ["Hallo.", "Welt."])
        #expect(SpokenText.sentences("   ") == [])
        #expect(SpokenText.sentences("") == [])
    }
}
