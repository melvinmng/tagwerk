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
        var posted: [(TaskID, String, String)] = []
        let model = TaskEditorModel(item: item, provider: provider, addComment: { posted.append(($0, $1, $2)); return nil })
        model.comment = "  Erledigt bis Freitag  "
        await model.postComment()
        #expect(posted.count == 1)
        #expect(posted.first?.1 == "Erledigt bis Freitag")
        #expect(posted.first?.2 == "1")
        #expect(model.comment.isEmpty)
        #expect(model.canComment)
        #expect(model.refreshed == nil)
    }

    @Test func editor_postComment_adoptsNewVersionForNextSave() async {
        var fresh = item
        fresh.version = "after-comment"
        let model = TaskEditorModel(item: item, provider: provider, addComment: { _, _, _ in fresh })
        model.comment = "Notiz"
        await model.postComment()
        #expect(model.refreshed?.version == "after-comment")
        model.draft.title = "Neu"
        _ = await model.save()
        #expect(provider.appliedEdits.last?.expectedVersion == "after-comment")
    }

    @Test func editor_withoutCommentSupport_cannotComment() {
        #expect(!TaskEditorModel(item: item, provider: provider).canComment)
    }

    @Test func supportsDueTime_falseForGitHub() {
        let issue = makeTask("#1", source: .github)
        #expect(!TaskEditorModel(item: issue, provider: FakeTaskProvider(source: .github, tasks: [issue])).supportsDueTime)
        #expect(TaskEditorModel(item: item, provider: provider).supportsDueTime)
    }

    @Test func priorityChoices_remindersOfferFourLevels() {
        #expect(TaskEditorModel(item: item, provider: provider).priorityChoices == [.p1, .p2, .p3, .p4])
        let local = makeTask("Lokal", source: .local)
        #expect(TaskEditorModel(item: local, provider: FakeTaskProvider(source: .local, tasks: [local])).priorityChoices
                == [nil, .p1, .p2, .p3, .p4, .p5])
    }

    @Test func save_afterComment_clearsRefreshedSoListGetsSavedItem() async {
        var fresh = item
        fresh.version = "after-comment"
        let model = TaskEditorModel(item: item, provider: provider, addComment: { _, _, _ in fresh })
        model.comment = "Notiz"
        await model.postComment()
        model.draft.title = "Neu"
        #expect(await model.save())
        #expect(model.refreshed == nil)
        #expect(model.saved?.title == "Neu")
    }
}

@MainActor
struct TaskEditorRecurrenceTests {
    let due = DueDate(year: 2026, month: 11, day: 19)
    var weekly: Recurrence { Recurrence(rule: .weekly(interval: 1, weekdays: [5]), start: PlanDay(due), end: nil, count: nil) }

    private func reminder(recurrence: Recurrence?, due: DueDate?) -> TaskItem {
        var item = makeTask("Wochenbericht", source: .reminders, due: due)
        item.editableFields.insert(.recurrence)
        item.recurrence = recurrence
        return item
    }

    @Test func save_writesRecurrence() async {
        let item = reminder(recurrence: nil, due: due)
        let provider = FakeTaskProvider(source: .reminders, tasks: [item])
        let model = TaskEditorModel(item: item, provider: provider)
        model.setRecurrence(weekly, fallbackDue: PlanDay(due))
        #expect(await model.save())
        #expect(provider.appliedEdits.first?.edit.recurrence == .set(weekly))
        #expect(provider.appliedEdits.first?.edit.due == .unchanged)
    }

    @Test func dueOff_clearsRecurrence() async {
        let item = reminder(recurrence: weekly, due: due)
        let provider = FakeTaskProvider(source: .reminders, tasks: [item])
        let model = TaskEditorModel(item: item, provider: provider)
        model.setHasDue(false, today: PlanDay(due))
        #expect(model.draft.recurrence == nil)
        #expect(model.removesRecurrenceWithDue)
        #expect(await model.save())
        #expect(provider.appliedEdits.first?.edit.recurrence == .set(nil))
        #expect(provider.appliedEdits.first?.edit.due == .set(nil))
    }

    @Test func chooseRule_withoutDue_turnsDueOn() {
        let item = reminder(recurrence: nil, due: nil)
        let model = TaskEditorModel(item: item, provider: FakeTaskProvider(source: .reminders, tasks: [item]))
        model.setRecurrence(weekly, fallbackDue: PlanDay(due))
        #expect(model.draft.due == due)
        #expect(model.draft.due?.hasTime == false)
    }

    @Test func dueChange_keepsUnsupportedRuleUnchanged() async {
        let unsupported = Recurrence(rule: .unsupported, start: PlanDay(due), end: nil, count: nil)
        let item = reminder(recurrence: unsupported, due: due)
        let provider = FakeTaskProvider(source: .reminders, tasks: [item])
        let model = TaskEditorModel(item: item, provider: provider)
        model.draft.due = DueDate(year: 2026, month: 11, day: 26)
        #expect(await model.save())
        #expect(provider.appliedEdits.first?.edit.recurrence == .unchanged)
    }

    @Test func github_hidesRecurrence() {
        let issue = makeTask("Login", source: .github)
        let model = TaskEditorModel(item: issue, provider: FakeTaskProvider(source: .github, tasks: [issue]))
        #expect(!model.isVisible(.recurrence))
        #expect(model.showsRecurrenceRow == false)
        let item = reminder(recurrence: nil, due: due)
        #expect(TaskEditorModel(item: item, provider: FakeTaskProvider(source: .reminders, tasks: [item])).showsRecurrenceRow)
    }

    @Test func saveQuestion_noneWithoutEffortOrBlocks() {
        #expect(TaskEditorModel.saveQuestion(effortChanged: false, blocksOffSeries: []) == nil)
    }

    @Test func saveQuestion_blocksOnly() {
        let block = makeBlock()
        #expect(TaskEditorModel.saveQuestion(effortChanged: false, blocksOffSeries: [block]) == .keepBlocks([block]))
    }

    /// Effort and blocks never become two dialogs: the effort question names the blocks too.
    @Test func saveQuestion_effortAndBlocks_isOneStep() {
        let block = makeBlock()
        #expect(TaskEditorModel.saveQuestion(effortChanged: true, blocksOffSeries: [block]) == .effortReach(blocksOffSeries: [block]))
        #expect(TaskEditorModel.saveQuestion(effortChanged: true, blocksOffSeries: []) == .effortReach(blocksOffSeries: []))
    }

    private func makeBlock() -> CalendarEvent {
        let start = testCalendar().date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 9))!
        return CalendarEvent(id: "b1", externalID: nil, calendarID: "plan", title: "Block", start: start,
                             end: start.addingTimeInterval(3600), isAllDay: false, url: nil, isBusy: true, version: "1")
    }
}

