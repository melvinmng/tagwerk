import Foundation
import SwiftData
import SwiftUI
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct NoteFieldModelTests {
    let container: ModelContainer
    let store: NoteStore
    let day = PlanDay(year: 2026, month: 11, day: 18)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = NoteStore(context: container.mainContext, now: { testNow() })
    }

    /// A sleep that returns at once, so a debounce only waits for the scheduler.
    private func makeModel(kind: NoteKind = .evening) -> NoteFieldModel {
        NoteFieldModel(store: store, kind: kind, day: day, debounce: .milliseconds(1), sleep: { _ in })
    }

    @Test func typing_savesAfterTheDebounce_asOneNotePerDayAndKind() async throws {
        let model = makeModel()
        model.text = "Heute war viel los."
        model.textChanged()
        await model.waitForSave()
        let note = try #require(store.note(kind: .evening, dayKey: "2026-11-18"))
        #expect(note.kindRaw == "evening" && note.dayKey == "2026-11-18" && note.text == "Heute war viel los.")
        // A second model for the same day and kind edits the same record.
        let second = makeModel()
        #expect(second.text == "Heute war viel los.")
        second.text = "Heute war viel los. Aber gut."
        second.flush()
        #expect(store.count == 1 && store.note(kind: .evening, dayKey: "2026-11-18")?.text == "Heute war viel los. Aber gut.")
        // The morning note of the same day is another one.
        let morning = makeModel(kind: .morning)
        morning.text = "Guten Morgen"
        morning.flush()
        #expect(store.count == 2)
    }

    @Test func dreamLog_savesAsADatedNote_onePerDay_andIsNeverOfferedForSuggestions() async throws {
        let model = NoteFieldModel(store: store, kind: .dream, day: day, debounce: .milliseconds(1), sleep: { _ in },
                                   isSignedIn: { true }, now: { testNow() })
        model.text = "Ich bin geflogen."
        model.textChanged()
        await model.waitForSave()
        let note = try #require(store.note(kind: .dream, dayKey: "2026-11-18"))
        #expect(note.kindRaw == "dream" && note.text == "Ich bin geflogen.")
        // Dream notes are filed into the fixed folder "Dream Log".
        #expect(note.folderID != nil && note.folderID == store.folder(role: .dreamLog)?.id)
        // Same day and kind: the same record; the evening note of that day is another one.
        let again = NoteFieldModel(store: store, kind: .dream, day: day, debounce: .milliseconds(1), sleep: { _ in })
        #expect(again.text == "Ich bin geflogen.")
        again.text = "Ich bin geflogen. Dann gefallen."
        again.flush()
        #expect(store.count == 1)
        #expect(!model.canSuggest)
        #expect(!model.offersGuidingQuestions)
        // Cleared text removes the note like any thought note.
        again.text = "  "
        again.flush()
        #expect(store.note(kind: .dream, dayKey: "2026-11-18") == nil)
    }

    @Test func close_flushesThePendingSave() {
        let model = NoteFieldModel(store: store, kind: .evening, day: day, debounce: .seconds(60), sleep: { _ in try? await Task.sleep(for: .seconds(60)) })
        model.text = "Schnell geschrieben"
        model.textChanged()
        #expect(store.count == 0)
        model.flush()
        #expect(store.note(kind: .evening, dayKey: "2026-11-18")?.text == "Schnell geschrieben")
    }

    @Test func whitespaceOnly_deletesTheNote() {
        let model = makeModel()
        model.text = "Etwas"
        model.flush()
        #expect(store.count == 1)
        model.text = "  \n \t "
        model.flush()
        #expect(store.count == 0)
        #expect(model.noteID == nil)
    }

    @Test func unchangedText_doesNotTouchUpdatedAt() throws {
        let model = makeModel()
        model.text = "Gleich"
        model.flush()
        let first = try #require(store.note(kind: .evening, dayKey: "2026-11-18")).updatedAt
        let later = NoteStore(context: container.mainContext, now: { testNow().addingTimeInterval(3600) })
        let again = NoteFieldModel(store: later, kind: .evening, day: day, debounce: .milliseconds(1), sleep: { _ in })
        again.text = "Gleich"
        again.flush()
        #expect(later.note(kind: .evening, dayKey: "2026-11-18")?.updatedAt == first)
    }

    @Test func dictation_insertsAtTheCursor() throws {
        let model = makeModel()
        model.text = "Anfang Ende"
        let index = model.text.index(model.text.startIndex, offsetBy: "Anfang ".count)
        model.selection = TextSelection(insertionPoint: index)
        #expect(model.draftBeforeCursor() == "Anfang ")
        model.writeDictation("Anfang Mitte")
        #expect(model.text == "Anfang Mitte Ende")
        #expect(model.wasDictated)
        // Further partial results replace the dictated part, the text behind the cursor stays.
        model.writeDictation("Anfang Mitte und mehr")
        #expect(model.text == "Anfang Mitte und mehr Ende")
        // A cancelled recording restores the draft.
        model.writeDictation("Anfang ")
        #expect(model.text == "Anfang Ende")
    }

    @Test func dictation_withoutSelection_appendsAtTheEnd() {
        let model = makeModel()
        model.text = "Schon da"
        #expect(model.draftBeforeCursor() == "Schon da")
        model.writeDictation("Schon da und neu")
        #expect(model.text == "Schon da und neu")
    }

    @Test func taskTitle_isTheFirstNonEmptyLine() {
        let model = makeModel()
        model.text = "\n  Einkauf planen \nmehr"
        #expect(model.taskTitle == "Einkauf planen")
        model.text = "  \n"
        #expect(model.taskTitle == nil)
    }

    @Test func taskCreated_incrementsDerivedActionCount() throws {
        let model = makeModel()
        model.text = "Einkauf planen"
        model.taskCreated()
        model.taskCreated()
        #expect(try #require(store.note(kind: .evening, dayKey: "2026-11-18")).derivedActionCount == 2)
    }

    @Test func freeNotes_areNeverReturnedAsThought() {
        store.create(text: "Eine freie Notiz")
        let model = makeModel()
        #expect(model.text.isEmpty && model.noteID == nil)
    }

    @Test func guidingQuestions_areAppendedAndSavedAsOrdinaryText() {
        let model = makeModel()
        model.text = "Heute war gut."
        #expect(model.offersGuidingQuestions)
        model.insertGuidingQuestions(locale: Locale(identifier: "de_DE"))
        #expect(!model.offersGuidingQuestions)
        model.flush()
        let saved = store.note(kind: .evening, dayKey: "2026-11-18")?.text ?? ""
        #expect(saved.hasPrefix("Heute war gut.\n\nWas will ich in meinem Leben (im Moment) erreichen?"))
        #expect(!model.wasDictated)
    }

    @Test func headerLabel_dreamUsesCloudMoon() {
        let dream = NoteField.headerLabel(for: .dream)
        #expect(dream.symbol == "cloud.moon" && dream.role == .dreamLog)
        for kind in [NoteKind.morning, .evening] {
            let label = NoteField.headerLabel(for: kind)
            #expect(label.symbol == "brain.head.profile" && label.role == .brainDump)
        }
    }
}
