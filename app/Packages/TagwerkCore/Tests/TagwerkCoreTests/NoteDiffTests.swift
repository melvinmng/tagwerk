import Testing
@testable import TagwerkCore

struct NoteDiffTests {
    @Test func summary_addedRemovedAndTitle() {
        let old = "Umzug\n- Kartons\n- Tape\n- Karte"
        let new = "Umzug planen\n- Kartons\n- Tape\n- Lampen\n- Kabel"
        let summary = NoteDiff.summary(old: old, new: new)
        // Removed: "Umzug", "- Karte"; new: "Umzug planen", "- Lampen", "- Kabel".
        #expect(summary == NoteDiff.Summary(added: 3, removed: 2, titleChanged: true))
        #expect(!summary.isEmpty)
    }

    @Test func lines_keepOrder() {
        let lines = NoteDiff.lines(old: "A\nB\nC", new: "A\nX\nC\nD")
        #expect(lines == [
            NoteDiff.Line(kind: .same, text: "A"),
            NoteDiff.Line(kind: .removed, text: "B"),
            NoteDiff.Line(kind: .added, text: "X"),
            NoteDiff.Line(kind: .same, text: "C"),
            NoteDiff.Line(kind: .added, text: "D"),
        ])
        // Old and new text can be rebuilt from the lines.
        #expect(lines.filter { $0.kind != .added }.map(\.text).joined(separator: "\n") == "A\nB\nC")
        #expect(lines.filter { $0.kind != .removed }.map(\.text).joined(separator: "\n") == "A\nX\nC\nD")
    }

    @Test func summary_identicalTexts_isEmpty() {
        let summary = NoteDiff.summary(old: "Titel\nZeile", new: "Titel\nZeile")
        #expect(summary == NoteDiff.Summary(added: 0, removed: 0, titleChanged: false))
        #expect(summary.isEmpty)
        #expect(NoteDiff.lines(old: "Titel\nZeile", new: "Titel\nZeile").allSatisfy { $0.kind == .same })
    }

    @Test func lines_emptyOldText_isAllNew() {
        let lines = NoteDiff.lines(old: "", new: "Neu\nZeile")
        #expect(lines.filter { $0.kind == .added }.map(\.text) == ["Neu", "Zeile"])
    }

    @Test func lines_repeatedLines_stayInTheirPlace() {
        let lines = NoteDiff.lines(old: "x\nx\ny", new: "x\ny\nx")
        #expect(lines.filter { $0.kind != .added }.map(\.text).joined(separator: "\n") == "x\nx\ny")
        #expect(lines.filter { $0.kind != .removed }.map(\.text).joined(separator: "\n") == "x\ny\nx")
    }

    @Test func summary_titleIsTheFirstNonEmptyLine() {
        #expect(NoteDiff.summary(old: "\nTitel\nA", new: "Titel\nA\nB").titleChanged == false)
        #expect(NoteDiff.summary(old: "Titel\nA", new: "Anderer Titel\nA").titleChanged == true)
    }
}
