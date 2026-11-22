import Testing
@testable import Tagwerk

@MainActor
struct NoteInsertMenuTests {
    private let reference = "![Bild](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)"

    @Test func inserting_atTheCursor_getsItsOwnLine() {
        let text = "Vorher Nachher"
        let cursor = text.index(text.startIndex, offsetBy: 7)
        let result = NoteInsertMenu.inserting(reference, into: text, replacing: cursor..<cursor)
        #expect(result.text == "Vorher \n\(reference)\nNachher")
        #expect(result.cursorOffset == "Vorher \n\(reference)\n".count)
    }

    @Test func inserting_withoutCursor_appendsAtTheEnd() {
        #expect(NoteInsertMenu.inserting(reference, into: "Text", replacing: nil).text == "Text\n\(reference)\n")
        #expect(NoteInsertMenu.inserting(reference, into: "Text\n", replacing: nil).text == "Text\n\(reference)\n")
        #expect(NoteInsertMenu.inserting(reference, into: "", replacing: nil).text == "\(reference)\n")
    }

    @Test func inserting_replacesASelection_andKeepsLineBreaksOnce() {
        let text = "a\nXXX\nb"
        let range = text.index(text.startIndex, offsetBy: 2)..<text.index(text.startIndex, offsetBy: 5)
        #expect(NoteInsertMenu.inserting(reference, into: text, replacing: range).text == "a\n\(reference)\nb")
    }

    // MARK: Menu entries

    @Test func groups_offerCaptureAndCreate() {
        let groups = NoteInsertMenu.groups(canTakePhoto: true, canScan: true)
        #expect(groups.map { $0.group } == [.capture, .create])
        #expect(groups[0].entries == [.choosePhoto, .takePhoto, .scanDocument, .chooseFile, .paste])
        #expect(groups[1].entries == [.drawing, .table])
    }

    @Test func insertMenu_hidesScanWithoutDocumentCamera() {
        let withoutScanner = NoteInsertMenu.groups(canTakePhoto: true, canScan: false)
        #expect(!withoutScanner.flatMap { $0.entries }.contains(.scanDocument))
        #expect(withoutScanner[0].entries == [.choosePhoto, .takePhoto, .chooseFile, .paste])
        let withoutCamera = NoteInsertMenu.groups(canTakePhoto: false, canScan: false)
        #expect(withoutCamera[0].entries == [.choosePhoto, .chooseFile, .paste])
        #expect(withoutCamera[1].entries == [.drawing, .table])
    }
}
