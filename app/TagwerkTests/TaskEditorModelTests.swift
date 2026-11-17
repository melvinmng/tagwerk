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

    @Test func editor_multiProject_defaultsToAllProjects() async {
        var multi = item
        multi.subContainers = [TaskContainer(id: "PVT_1", name: "App", colorHex: nil), TaskContainer(id: "PVT_2", name: "Studium", colorHex: nil)]
        provider.tasks = [multi]
        let model = TaskEditorModel(item: multi, provider: provider)
        #expect(model.targetProjects == ["PVT_1", "PVT_2"])
        model.draft.priority = .p1
        _ = await model.save()
        #expect(provider.appliedEdits.last?.edit.targetSubContainerIDs == nil)
    }

    @Test func editor_multiProject_restrictedTarget_isSent() async {
        var multi = item
        multi.subContainers = [TaskContainer(id: "PVT_1", name: "App", colorHex: nil), TaskContainer(id: "PVT_2", name: "Studium", colorHex: nil)]
        provider.tasks = [multi]
        let model = TaskEditorModel(item: multi, provider: provider)
        model.targetProjects = ["PVT_2"]
        model.draft.priority = .p1
        _ = await model.save()
        #expect(provider.appliedEdits.last?.edit.targetSubContainerIDs == ["PVT_2"])
    }

    @Test func editor_postComment_callsProvider() async {
        var posted: [(TaskID, String)] = []
        let model = TaskEditorModel(item: item, provider: provider, addComment: { posted.append(($0, $1)) })
        model.comment = "  Erledigt bis Freitag  "
        await model.postComment()
        #expect(posted.count == 1)
        #expect(posted.first?.1 == "Erledigt bis Freitag")
        #expect(model.comment.isEmpty)
        #expect(model.canComment)
    }

    @Test func editor_withoutCommentSupport_cannotComment() {
        #expect(!TaskEditorModel(item: item, provider: provider).canComment)
    }
}
