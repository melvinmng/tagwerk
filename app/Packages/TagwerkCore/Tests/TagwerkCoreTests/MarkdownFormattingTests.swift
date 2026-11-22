import Foundation
import Testing
@testable import TagwerkCore

struct MarkdownFormattingTests {
    private func apply(_ action: MarkdownFormatting.Action, _ text: String, _ selection: Range<Int>) -> MarkdownFormatting.Edit {
        MarkdownFormatting.apply(action, to: text, selection: selection)
    }

    // MARK: Heading

    @Test func heading_cyclesNoneOneTwoNone() {
        let one = apply(.heading, "Titel", 5..<5)
        #expect(one.text == "# Titel" && one.selection == 7..<7)
        let two = apply(.heading, one.text, one.selection)
        #expect(two.text == "## Titel" && two.selection == 8..<8)
        let none = apply(.heading, two.text, two.selection)
        #expect(none.text == "Titel" && none.selection == 5..<5)
    }

    @Test func heading_onSeveralLines() {
        let edit = apply(.heading, "eins\nzwei\ndrei", 2..<11)
        #expect(edit.text == "# eins\n# zwei\n# drei")
        // The first line decides the next step: a mix is made even.
        let mixed = apply(.heading, "# eins\nzwei", 0..<11)
        #expect(mixed.text == "## eins\n## zwei")
    }

    @Test func heading_cursorLineOnly() {
        let edit = apply(.heading, "eins\nzwei\ndrei", 6..<6)
        #expect(edit.text == "eins\n# zwei\ndrei" && edit.selection == 8..<8)
    }

    @Test func heading_selectionEndingAtLineStartDoesNotReachIntoNextLine() {
        let edit = apply(.heading, "eins\nzwei", 0..<5)
        #expect(edit.text == "# eins\nzwei")
    }

    @Test func heading_hashWithoutSpaceIsNotAHeading() {
        #expect(apply(.heading, "#tag", 0..<0).text == "# #tag")
    }

    // MARK: Bold and italic

    @Test func bold_wrapsSelection() {
        let edit = apply(.bold, "ein Wort hier", 4..<8)
        #expect(edit.text == "ein **Wort** hier" && edit.selection == 6..<10)
    }

    @Test func bold_unwrapsWrappedSelection() {
        // Markers inside the selection.
        let inside = apply(.bold, "ein **Wort** hier", 4..<12)
        #expect(inside.text == "ein Wort hier" && inside.selection == 4..<8)
        // Markers around the selection.
        let around = apply(.bold, "ein **Wort** hier", 6..<10)
        #expect(around.text == "ein Wort hier" && around.selection == 4..<8)
        // The result of wrapping unwraps again.
        let wrapped = apply(.bold, "Wort", 0..<4)
        #expect(apply(.bold, wrapped.text, wrapped.selection).text == "Wort")
    }

    @Test func bold_withoutSelection_insertsPairAndPlacesCursor() {
        let edit = apply(.bold, "ab", 1..<1)
        #expect(edit.text == "a****b" && edit.selection == 3..<3)
        let italic = apply(.italic, "ab", 1..<1)
        #expect(italic.text == "a**b" && italic.selection == 2..<2)
    }

    @Test func bold_keepsSpacesOutside() {
        let edit = apply(.bold, "ein Wort hier", 3..<9)
        #expect(edit.text == "ein **Wort** hier")
        #expect(apply(.bold, "a   b", 1..<4).text == "a****   b")
    }

    @Test func italic_doesNotBreakBold() {
        // Italic on bold text adds a star pair (bold and italic), it never turns the bold into italic.
        let edit = apply(.italic, "**fett**", 0..<8)
        #expect(edit.text == "***fett***")
        // And back: italic off leaves the bold.
        #expect(apply(.italic, edit.text, edit.selection).text == "**fett**")
        // Bold on bold and italic leaves italic.
        #expect(apply(.bold, "***x***", 0..<7).text == "*x*")
        // Italic around the selection of a bold word.
        #expect(apply(.italic, "**fett**", 2..<6).text == "***fett***")
    }

    @Test func italic_wrapsAndUnwraps() {
        let edit = apply(.italic, "ein Wort", 4..<8)
        #expect(edit.text == "ein *Wort*" && edit.selection == 5..<9)
        #expect(apply(.italic, edit.text, edit.selection).text == "ein Wort")
    }

    @Test func italic_selectionWithSeveralItalicRuns_isWrappedNotStripped() {
        #expect(apply(.italic, "*a* b *c*", 0..<9).text == "**a* b *c**")
    }

    // MARK: Lists

    @Test func list_togglesMarker() {
        let on = apply(.list, "eins\nzwei", 0..<9)
        #expect(on.text == "- eins\n- zwei" && on.selection == 2..<13)
        let off = apply(.list, on.text, on.selection)
        #expect(off.text == "eins\nzwei" && off.selection == 0..<9)
    }

    @Test func list_partlyMarkedSelectionGetsMarkersEverywhere() {
        #expect(apply(.list, "- eins\nzwei", 0..<11).text == "- eins\n- zwei")
    }

    @Test func list_skipsBlankLinesOfASelection() {
        #expect(apply(.list, "a\n\nb", 0..<4).text == "- a\n\n- b")
        // A cursor on a blank line still gets a marker.
        #expect(apply(.list, "a\n\nb", 2..<2).text == "a\n- \nb")
    }

    @Test func checkbox_fromListLine_replacesMarker() {
        let edit = apply(.checkbox, "- Milch", 7..<7)
        #expect(edit.text == "- [ ] Milch" && edit.selection == 11..<11)
        #expect(apply(.checkbox, edit.text, edit.selection).text == "Milch")
        // And a checkbox line becomes a list line.
        #expect(apply(.list, "- [ ] Milch", 0..<0).text == "- Milch")
        #expect(apply(.list, "- [x] Milch", 0..<0).text == "- Milch")
    }

    @Test func checkbox_keepsCheckedState() {
        #expect(apply(.checkbox, "- [x] a\nb", 0..<9).text == "- [x] a\n- [ ] b")
    }

    @Test func checkbox_keepsIndentation() {
        let edit = apply(.checkbox, "  - Unterpunkt", 0..<0)
        #expect(edit.text == "  - [ ] Unterpunkt")
        #expect(apply(.checkbox, "    eingerückt", 4..<4).text == "    - [ ] eingerückt")
        #expect(apply(.checkbox, "\tTab", 0..<0).text == "\t- [ ] Tab")
    }

    @Test func checkbox_emptyBoxWithoutTrailingSpace() {
        #expect(apply(.checkbox, "- [ ]", 0..<0).text == "")
    }

    // MARK: Offsets

    @Test func apply_selectionAtEndOfText() {
        let edit = apply(.bold, "Ende", 4..<4)
        #expect(edit.text == "Ende****" && edit.selection == 6..<6)
        #expect(apply(.heading, "Ende", 4..<4).selection == 6..<6)
        // A selection beyond the text is clamped.
        #expect(apply(.list, "a", 5..<9).text == "- a")
        #expect(apply(.list, "", 0..<0).text == "- ")
    }

    @Test func apply_emojiOffsets() {
        // The family emoji is one character; the offsets count characters, not UTF-16 units.
        let edit = apply(.bold, "a👨‍👩‍👧b", 1..<2)
        #expect(edit.text == "a**👨‍👩‍👧**b" && edit.selection == 3..<4)
        let line = apply(.heading, "🙂\nzwei", 3..<3)
        #expect(line.text == "🙂\n# zwei" && line.selection == 5..<5)
    }

    @Test func apply_crlf() {
        // "\r\n" is one character and one line break.
        let edit = apply(.list, "eins\r\nzwei", 0..<9)
        #expect(edit.text == "- eins\r\n- zwei")
        let heading = apply(.heading, "eins\r\nzwei\r\ndrei", 6..<6)
        #expect(heading.text == "eins\r\n# zwei\r\ndrei" && heading.selection == 8..<8)
    }
}
