import Testing
import TagwerkCore
@testable import Tagwerk

struct CollapsedGroupBlockTests {
    private let titles = ["Projektbesprechung", "Zahnarzt Kontrolle", "Anruf Steuerberater"]

    @Test func visibleTitles_allFit_noRemainder() {
        let result = CollapsedGroupBlock.visibleTitles(titles, slots: 3)
        #expect(result.lines == titles)
        #expect(result.hidden == 0)
        #expect(CollapsedGroupBlock.visibleTitles(titles, slots: 5).hidden == 0)
    }

    @Test func visibleTitles_notAllFit_lastLineCountsTheRest() {
        // Two lines: one title and "+2 weitere".
        let result = CollapsedGroupBlock.visibleTitles(titles, slots: 2)
        #expect(result.lines == ["Projektbesprechung"])
        #expect(result.hidden == 2)
    }

    @Test func visibleTitles_noRoom_showsNoTitleAtAll() {
        let result = CollapsedGroupBlock.visibleTitles(titles, slots: 1)
        #expect(result.lines.isEmpty)
        #expect(result.hidden == 3)
        #expect(CollapsedGroupBlock.visibleTitles(titles, slots: 0).hidden == 3)
    }

    @Test func texts_inGermanAndEnglish() {
        #expect(String(localized: "\(3) Termine · \("10:00–11:00")") == "3 Termine · 10:00–11:00")
        #expect(Localized.string("\(3) Termine · \("10:00–11:00")", in: .english, bundle: .main) == "3 events · 10:00–11:00")
        #expect(Localized.string("+\(2) weitere", in: .english, bundle: .main) == "+2 more")
        #expect(Localized.string("Zum Verschieben den Eintrag öffnen.", in: .english, bundle: .main) == "Open the entry to move it.")
    }
}
