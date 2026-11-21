import Testing
@testable import Tagwerk

struct NoteEditorSyncTests {
    @Test func resolution_ownSaveKeeps() {
        // The user typed on after the last save: the stored text is still the saved one.
        #expect(NoteEditorSync.resolution(local: "Rezept mit mehr", lastSaved: "Rezept", stored: "Rezept", isTrashed: false) == .keep)
        // The editor saved just now and updated its own record of it.
        #expect(NoteEditorSync.resolution(local: "Rezept", lastSaved: "Rezept", stored: "Rezept", isTrashed: false) == .keep)
    }

    @Test func resolution_externalChangeAdopts() {
        #expect(NoteEditorSync.resolution(local: "Recipe", lastSaved: "Recipe", stored: "Rezept", isTrashed: false) == .adopt("Rezept"))
        // A change from outside wins over text that was typed but not saved yet.
        #expect(NoteEditorSync.resolution(local: "Recipe mit Rest", lastSaved: "Recipe", stored: "Rezept", isTrashed: false) == .adopt("Rezept"))
        // Also a change to an empty text.
        #expect(NoteEditorSync.resolution(local: "Recipe", lastSaved: "Recipe", stored: "", isTrashed: false) == .adopt(""))
    }

    @Test func resolution_trashedCloses() {
        #expect(NoteEditorSync.resolution(local: "a", lastSaved: "a", stored: "a", isTrashed: true) == .close)
        #expect(NoteEditorSync.resolution(local: "a", lastSaved: "a", stored: "b", isTrashed: true) == .close)
    }

    @Test func resolution_missingNoteCloses() {
        #expect(NoteEditorSync.resolution(local: "a", lastSaved: "a", stored: nil, isTrashed: false) == .close)
    }
}
