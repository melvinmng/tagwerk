import Testing
@testable import Tagwerk

struct NoteAttachmentMenuTests {
    private let reference = "![Bild](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)"

    @Test func inserting_atTheCursor_getsItsOwnLine() {
        let text = "Vorher Nachher"
        let cursor = text.index(text.startIndex, offsetBy: 7)
        let result = NoteAttachmentMenu.inserting(reference, into: text, replacing: cursor..<cursor)
        #expect(result.text == "Vorher \n\(reference)\nNachher")
        #expect(result.cursorOffset == "Vorher \n\(reference)\n".count)
    }

    @Test func inserting_withoutCursor_appendsAtTheEnd() {
        #expect(NoteAttachmentMenu.inserting(reference, into: "Text", replacing: nil).text == "Text\n\(reference)\n")
        #expect(NoteAttachmentMenu.inserting(reference, into: "Text\n", replacing: nil).text == "Text\n\(reference)\n")
        #expect(NoteAttachmentMenu.inserting(reference, into: "", replacing: nil).text == "\(reference)\n")
    }

    @Test func inserting_replacesASelection_andKeepsLineBreaksOnce() {
        let text = "a\nXXX\nb"
        let range = text.index(text.startIndex, offsetBy: 2)..<text.index(text.startIndex, offsetBy: 5)
        #expect(NoteAttachmentMenu.inserting(reference, into: text, replacing: range).text == "a\n\(reference)\nb")
    }
}
