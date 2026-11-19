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

    @Test func completedTaskOutsideTheListCanBeReopenedInTheEditor() async {
        var done = makeTask("Erledigte Aufgabe", source: .reminders, version: "5")
        done.isCompleted = true
        provider.tasks.append(done)
        let model = TaskEditorModel(item: done, provider: provider)
        model.draft.isCompleted = false
        #expect(await model.save())
        #expect(model.saved?.isCompleted == false)
        #expect(provider.appliedEdits.last?.edit.isCompleted == .set(false))
        #expect(provider.appliedEdits.last?.expectedVersion == "5")
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

    /// The rule to check against planned blocks: only a changed, non-empty rule, starting at the draft's due date.
    @Test func changedRecurrence_followsDraftDue() {
        let item = reminder(recurrence: weekly, due: due)
        let model = TaskEditorModel(item: item, provider: FakeTaskProvider(source: .reminders, tasks: [item]))
        #expect(model.changedRecurrence == nil)
        model.draft.due = DueDate(year: 2026, month: 11, day: 23)
        #expect(model.changedRecurrence == nil)
        let mondays = Recurrence(rule: .weekly(interval: 1, weekdays: [2]), start: PlanDay(due), end: nil, count: nil)
        model.setRecurrence(mondays, fallbackDue: PlanDay(due))
        #expect(model.changedRecurrence?.rule == mondays.rule)
        #expect(model.changedRecurrence?.start == PlanDay(year: 2026, month: 11, day: 23))
        model.setRecurrence(nil, fallbackDue: PlanDay(due))
        #expect(model.changedRecurrence == nil)
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


@MainActor
struct TaskEditorAssigneeTests {
    let issue: TaskItem
    let provider: FakeTaskProvider

    init() {
        var issue = makeTask("Login", source: .github, version: "1")
        issue.assignees = ["octo", "lea-m"]
        issue.url = URL(string: "https://github.com/beispiel/app/issues/151")
        self.issue = issue
        provider = FakeTaskProvider(source: .github, tasks: [issue])
        provider.viewerLogin = "octo"
    }

    private func makeModel(_ item: TaskItem? = nil, viewerLogin: String? = "octo") -> TaskEditorModel {
        TaskEditorModel(item: item ?? issue, provider: provider, viewerLogin: viewerLogin)
    }

    @Test func assignees_addPerson_sendsOnlyTheDifference() async {
        let model = makeModel()
        model.draft.assignees = ["octo", "lea-m", "sam"]
        #expect(model.requestedAssignees == ["sam"])
        #expect(await model.save())
        #expect(provider.appliedEdits.last?.edit.assignees == .set(AssigneeChange(add: ["sam"], remove: [])))
        #expect(model.savedIsListed)
    }

    @Test func assignees_unchanged_hasNoChanges() {
        let model = makeModel()
        model.draft.assignees = ["lea-m", "Octo"]
        #expect(!model.hasChanges)
        #expect(model.requestedAssignees.isEmpty)
        #expect(model.savedIsListed)
    }

    @Test func handsOver_onlyWhenIWasAssignedAndLeave() {
        let leaving = makeModel()
        leaving.draft.assignees = ["lea-m"]
        #expect(leaving.handsOver)

        let staying = makeModel()
        staying.draft.assignees = ["octo"]
        #expect(!staying.handsOver)

        var foreign = issue
        foreign.assignees = ["lea-m"]
        let notMine = makeModel(foreign)
        notMine.draft.assignees = []
        #expect(!notMine.handsOver)

        let unknown = makeModel(viewerLogin: nil)
        unknown.draft.assignees = ["lea-m"]
        #expect(!unknown.handsOver)
    }

    @Test func saveQuestion_handOverWins() {
        #expect(TaskEditorModel.saveQuestion(effortChanged: false, blocksOffSeries: [], handOverFutureBlocks: 2)
            == .handOver(futureBlocks: 2))
        #expect(TaskEditorModel.saveQuestion(effortChanged: true, blocksOffSeries: [], handOverFutureBlocks: 0)
            == .handOver(futureBlocks: 0))
        #expect(TaskEditorModel.saveQuestion(effortChanged: false, blocksOffSeries: [], handOverFutureBlocks: nil) == nil)
        #expect(TaskEditorModel.saveQuestion(effortChanged: true, blocksOffSeries: []) == .effortReach(blocksOffSeries: []))
    }

    @Test func handOverMessage_cases() {
        #expect(TaskEditorModel.handOverMessage(number: 151, futureBlocks: 0, leavesUnassigned: false)
            == "#151 verschwindet aus Aufgaben und Planung.")
        #expect(TaskEditorModel.handOverMessage(number: 151, futureBlocks: 2, leavesUnassigned: false)
            == "#151 verschwindet aus Aufgaben und Planung. 2 geplante Zeitblöcke werden gelöscht.")
        #expect(TaskEditorModel.handOverMessage(number: 151, futureBlocks: 1, leavesUnassigned: false)
            .hasSuffix("1 geplanter Zeitblock wird gelöscht."))
        #expect(TaskEditorModel.handOverMessage(number: 151, futureBlocks: 0, leavesUnassigned: true)
            == "#151 verschwindet aus Aufgaben und Planung. Das Issue ist dann niemandem zugewiesen.")
        #expect(TaskEditorModel.handOverMessage(number: nil, futureBlocks: 0, leavesUnassigned: false)
            == "Das Issue verschwindet aus Aufgaben und Planung.")
    }

    @Test func assigneeCandidates_keepAssignedPeopleWhoAreNoLongerAssignable() {
        let model = makeModel()
        #expect(model.assigneeCandidates(assignable: ["octo", "sam"]) == ["octo", "lea-m", "sam"])
        #expect(model.assigneeCandidates(assignable: nil) == ["octo", "lea-m"])
    }

    @Test func setAssignees_keepsCandidateOrder() {
        let model = makeModel()
        model.setAssignees(["sam", "octo"], candidates: ["octo", "lea-m", "sam"])
        #expect(model.draft.assignees == ["octo", "sam"])
        #expect(model.hasChanges)
    }

    @Test func saveAnyway_afterConflict_writesDifferenceAgainstOpeningState() async {
        var external = issue
        external.assignees = ["octo", "lea-m", "new"]
        external.version = "2"
        provider.conflictOnNextApply = external
        let model = makeModel()
        model.draft.assignees = ["octo", "lea-m", "sam"]

        #expect(await model.save() == false)
        #expect(model.conflictChanges.map(\.field) == ["Zugewiesen"])
        #expect(await model.saveAnyway())

        let second = provider.appliedEdits.last
        #expect(provider.appliedEdits.count == 2)
        #expect(second?.expectedVersion == nil)
        #expect(second?.edit.assignees == .set(AssigneeChange(add: ["sam"], remove: [])))
        // The person added on GitHub meanwhile stays.
        #expect(model.saved?.assignees == ["octo", "lea-m", "new", "sam"])
    }

    @Test func handOver_skipsPlanningEdit() async {
        let model = makeModel()
        model.draft.assignees = ["lea-m"]
        #expect(model.handsOver)
        #expect(await model.save())
        #expect(model.saved?.assignees == ["lea-m"])
        #expect(model.savedIsListed == false)
    }
}
