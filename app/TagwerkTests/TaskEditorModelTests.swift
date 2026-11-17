import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct TaskEditorModelTests {
    let item = makeTask("Login-Fehler beheben", source: .reminders, version: "1")
    let provider: FakeTaskProvider

    init() {
        provider = FakeTaskProvider(source: .reminders, tasks: [item])
    }

    @Test func save_unchangedDraft_doesNotCallProvider() async {
        let model = TaskEditorModel(item: item, provider: provider)
        #expect(await model.save())
        #expect(provider.appliedEdits.isEmpty)
    }

    @Test func save_changedTitle_sendsOnlyTitle() async {
        let model = TaskEditorModel(item: item, provider: provider)
        model.draft.title = "Neu"
        #expect(await model.save())

        var expected = TaskEdit()
        expected.title = .set("Neu")
        #expect(provider.appliedEdits.first?.edit == expected)
        #expect(provider.appliedEdits.first?.expectedVersion == "1")
        #expect(model.saved?.title == "Neu")
    }

    @Test func save_conflict_setsConflictAndKeepsDraft() async {
        var external = item
        external.title = "Extern"
        external.version = "2"
        provider.conflictOnNextApply = external
        let model = TaskEditorModel(item: item, provider: provider)
        model.draft.priority = .p1

        #expect(await model.save() == false)
        #expect(model.conflict?.title == "Extern")
        #expect(model.draft.priority == .p1)
        #expect(model.saved == nil)
    }

    @Test func reloadFromSource_replacesDraftAndClearsConflict() async {
        var external = item
        external.title = "Extern"
        external.version = "2"
        provider.conflictOnNextApply = external
        let model = TaskEditorModel(item: item, provider: provider)
        model.draft.priority = .p1
        _ = await model.save()

        await model.reloadFromSource()

        #expect(model.conflict == nil)
        #expect(model.draft.title == "Extern")
        #expect(model.draft.priority == nil)
        #expect(model.original.version == "2")
    }

    @Test func saveAnyway_sendsOwnChangesWithNilVersion() async {
        var external = item
        external.title = "Extern"
        external.version = "2"
        provider.conflictOnNextApply = external
        let model = TaskEditorModel(item: item, provider: provider)
        model.draft.priority = .p1
        _ = await model.save()

        #expect(await model.saveAnyway())

        var expected = TaskEdit()
        expected.priority = .set(.p1)
        let last = provider.appliedEdits.last
        #expect(last?.edit == expected)
        #expect(last?.expectedVersion == nil)
        #expect(model.saved?.title == "Extern")
        #expect(model.saved?.priority == .p1)
    }

    @Test func save_failure_setsErrorMessage() async {
        provider.applyError = .failed("Netzwerkfehler")
        let model = TaskEditorModel(item: item, provider: provider)
        model.draft.title = "Neu"
        #expect(await model.save() == false)
        #expect(model.errorMessage == "Netzwerkfehler")
    }

    @Test func isVisible_hidesFieldsNotEditable() {
        let model = TaskEditorModel(item: item, provider: provider)
        #expect(model.isVisible(.title))
        #expect(model.isVisible(.priority))
        #expect(!model.isVisible(.estimate))
        #expect(!model.isVisible(.container))
    }
}
