import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct TaskListModelTests {
    let reminders = FakeTaskProvider(source: .reminders, tasks: [makeTask("Einkaufen", source: .reminders)])
    let local = FakeTaskProvider(source: .local, tasks: [makeTask("Fahrrad", source: .local)])

    private func makeModel() -> TaskListModel {
        TaskListModel(providers: [reminders, local], now: testNow, calendar: testCalendar())
    }

    @Test func highlight_setsAndClears() {
        let model = makeModel()
        let id = TaskID(source: .local, rawValue: "Fahrrad")
        model.highlight(id)
        #expect(model.highlightedTaskID == id)
        model.clearHighlight()
        #expect(model.highlightedTaskID == nil)
    }

    @Test func bulkActions_completeRescheduleDelete() async {
        local.tasks.append(makeTask("Lesen", source: .local))
        let model = makeModel()
        await model.reload()
        let fahrrad = TaskID(source: .local, rawValue: "Fahrrad"), lesen = TaskID(source: .local, rawValue: "Lesen")
        await model.reschedule([fahrrad, lesen], option: .tomorrow)
        #expect(model.items.filter { [fahrrad, lesen].contains($0.id) }.allSatisfy { $0.due == DueDate(year: 2026, month: 11, day: 19) })
        await model.complete([fahrrad, lesen])
        #expect(!model.items.contains { [fahrrad, lesen].contains($0.id) })
        await model.delete([TaskID(source: .reminders, rawValue: "Einkaufen")])
        #expect(model.items.isEmpty)
    }

    @Test func reload_mergesAllProviders() async {
        let model = makeModel()
        await model.reload()
        #expect(Set(model.items.map(\.title)) == ["Einkaufen", "Fahrrad"])
        #expect(model.sourceStates[.reminders] == .loaded)
        #expect(model.sourceStates[.local] == .loaded)
    }

    @Test func filter_local_showsOnlyLocal() async {
        let model = makeModel()
        await model.reload()
        model.filter = .local
        #expect(model.sections.flatMap(\.1).map(\.title) == ["Fahrrad"])
    }

    @Test func availableFilters_withoutGitHub_hidesGitHub() {
        #expect(makeModel().availableFilters == [.all, .reminders, .local])
        #expect(TaskFilter.allCases.map(\.title) == ["Alle", "Erinnerungen", "GitHub", "Lokal"])
    }

    @Test func reload_providerThrowsAccessDenied_marksNoAccessAndKeepsOthers() async {
        reminders.readError = .accessDenied
        let model = makeModel()
        await model.reload()
        #expect(model.sourceStates[.reminders] == .noAccess)
        #expect(model.items.map(\.title) == ["Fahrrad"])
    }

    @Test func reload_providerFails_marksFailed() async {
        reminders.readError = .failed("kaputt")
        let model = makeModel()
        await model.reload()
        #expect(model.sourceStates[.reminders] == .failed("kaputt"))
    }

    @Test func reload_githubCacheBecauseOfError_carriesReason() async {
        let github = FakeTaskProvider(source: .github, tasks: [makeTask("#42 Login", source: .github)])
        let since = testNow()
        github.offlineSince = since
        github.offlineReason = "GitHub antwortet mit Fehler 502."
        let model = TaskListModel(providers: [github], now: testNow, calendar: testCalendar())
        await model.reload()
        #expect(model.sourceStates[.github] == .offline(since: since, reason: "GitHub antwortet mit Fehler 502."))
    }

    @Test func reload_githubOffline_marksOfflineAndShowsItems() async {
        let github = FakeTaskProvider(source: .github, tasks: [makeTask("#42 Login", source: .github)])
        let since = testNow().addingTimeInterval(-600)
        github.offlineSince = since
        let model = TaskListModel(providers: [github], now: testNow, calendar: testCalendar())
        await model.reload()
        #expect(model.sourceStates[.github] == .offline(since: since))
        #expect(model.items.map(\.title) == ["#42 Login"])
        #expect(model.availableFilters.contains(.github))
    }

    @Test func reload_providerSignedOut_removesProviderAndKeepsSignedOutState() async {
        let github = FakeTaskProvider(source: .github, tasks: [makeTask("#1", source: .github)])
        github.readError = .signedOut
        var lost: [TaskSource] = []
        let model = TaskListModel(providers: [local, github], now: testNow, calendar: testCalendar())
        model.onSignedOut = { lost.append($0) }
        await model.reload()
        #expect(model.provider(for: .github) == nil)
        #expect(model.sourceStates[.github] == .signedOut)
        #expect(lost == [.github])
        #expect(!model.availableFilters.contains(.github))
        await model.reload()
        #expect(model.sourceStates[.github] == .signedOut)
    }

    @Test func register_afterSignOut_clearsSignedOutState() async {
        let github = FakeTaskProvider(source: .github, tasks: [makeTask("#1", source: .github)])
        github.readError = .signedOut
        let model = TaskListModel(providers: [github], now: testNow, calendar: testCalendar())
        await model.reload()
        github.readError = nil
        await model.register(github)
        #expect(model.sourceStates[.github] == .loaded)
        #expect(model.items.map(\.title) == ["#1"])
    }

    @Test func write_signedOut_removesProvider() async {
        let github = FakeTaskProvider(source: .github, tasks: [makeTask("#1", source: .github)])
        let model = TaskListModel(providers: [github], now: testNow, calendar: testCalendar())
        await model.reload()
        github.applyError = .signedOut
        await model.complete(TaskID(source: .github, rawValue: "#1"))
        #expect(model.provider(for: .github) == nil)
        #expect(model.sourceStates[.github] == .signedOut)
    }

    @Test func reload_publishesFastSourceBeforeSlowSource() async {
        let slow = FakeTaskProvider(source: .github, tasks: [makeTask("#1", source: .github)])
        slow.gate = Gate()
        let model = TaskListModel(providers: [slow, local], now: testNow, calendar: testCalendar())
        let running = Task { await model.reload() }

        await waitUntil { model.items.contains { $0.title == "Fahrrad" } }
        #expect(model.items.map(\.title) == ["Fahrrad"])
        #expect(model.sourceStates[.local] == .loaded)

        slow.gate?.open()
        await running.value
        #expect(Set(model.items.map(\.title)) == ["Fahrrad", "#1"])
    }

    @Test func reload_onlyReminders_leavesOtherSourcesUntouched() async {
        let model = makeModel()
        await model.reload()
        let localCalls = local.openTasksCalls
        reminders.tasks.append(makeTask("Neu aus Reminders", source: .reminders))

        await model.reload(only: [.reminders])

        #expect(local.openTasksCalls == localCalls)
        #expect(Set(model.items.map(\.title)) == ["Einkaufen", "Neu aus Reminders", "Fahrrad"])
    }

    @Test func complete_duringRunningReload_staysRemoved() async {
        let model = makeModel()
        await model.reload()
        let gate = Gate()
        local.gate = gate
        let running = Task { await model.reload(only: [.local]) }
        await waitUntil { local.openTasksCalls == 2 }

        await model.complete(TaskID(source: .local, rawValue: "Fahrrad"))
        gate.open()
        await running.value

        #expect(!model.items.contains { $0.title == "Fahrrad" })
    }

    @Test func delete_removesItemWithDisplayedVersion() async {
        let model = makeModel()
        await model.reload()
        let id = TaskID(source: .local, rawValue: "Fahrrad")
        await model.delete(id)
        #expect(!model.items.contains { $0.id == id })
        #expect(local.deleted.first?.1 == "1")
    }

    @Test func delete_conflict_keepsItemAndReloads() async {
        let model = makeModel()
        await model.reload()
        local.conflictOnNextApply = makeTask("Fahrrad", source: .local, version: "9")
        await model.delete(TaskID(source: .local, rawValue: "Fahrrad"))
        #expect(model.lastError != nil)
        #expect(model.items.contains { $0.title == "Fahrrad" })
    }

    @Test func unregister_duringRunningLoad_staysRemoved() async {
        let github = FakeTaskProvider(source: .github, tasks: [makeTask("#1", source: .github)])
        let model = TaskListModel(providers: [github], now: testNow, calendar: testCalendar())
        let gate = Gate()
        github.gate = gate
        let running = Task { await model.reload() }
        await waitUntil { github.openTasksCalls == 1 }

        await model.unregister(.github)
        gate.open()
        await running.value

        #expect(model.items.isEmpty)
        #expect(model.sourceStates[.github] == nil)
    }

    @Test func undoComplete_whileLoadAlreadyReturnedItem_noDuplicate() async {
        let model = makeModel()
        await model.reload()
        let id = TaskID(source: .local, rawValue: "Fahrrad")
        await model.complete(id)
        // A reload that runs between completion and undo still lists the reopened task.
        local.tasks = local.tasks.map { var task = $0; task.isCompleted = false; return task }
        await model.reload(only: [.local])
        await model.undoComplete()
        #expect(model.items.filter { $0.id == id }.count == 1)
    }

    /// At start the GitHub cache is shown at once; the slow (or offline) fetch replaces it later.
    @Test func reload_showsCachedItemsWhileSourceLoads() async {
        let slow = FakeTaskProvider(source: .github, tasks: [makeTask("#1 neu", source: .github)])
        slow.cached = [makeTask("#1 aus Cache", source: .github)]
        slow.gate = Gate()
        let model = TaskListModel(providers: [slow], now: testNow, calendar: testCalendar())
        let running = Task { await model.reload() }

        await waitUntil { model.items.contains { $0.title == "#1 aus Cache" } }
        #expect(model.items.map(\.title) == ["#1 aus Cache"])
        #expect(model.loadingSources == [.github])

        slow.gate?.open()
        await running.value
        #expect(model.items.map(\.title) == ["#1 neu"])
        #expect(model.loadingSources.isEmpty)
    }

    @Test func complete_removesItemAfterSuccess() async {
        let model = makeModel()
        await model.reload()
        let id = TaskID(source: .local, rawValue: "Fahrrad")
        await model.complete(id)
        #expect(!model.items.contains { $0.id == id })
        #expect(model.lastCompleted?.id == id)
        #expect(local.appliedEdits.first?.expectedVersion == "1")
        #expect(local.appliedEdits.first?.edit.isCompleted == .set(true))
    }

    @Test func undoComplete_reopensWithIsCompletedFalse() async {
        let model = makeModel()
        await model.reload()
        let id = TaskID(source: .local, rawValue: "Fahrrad")
        await model.complete(id)
        await model.undoComplete()
        #expect(local.appliedEdits.last?.edit.isCompleted == .set(false))
        #expect(model.items.contains { $0.id == id })
        #expect(model.lastCompleted == nil)
    }

    @Test func complete_conflict_reloadsAndSetsError() async {
        let model = makeModel()
        await model.reload()
        var changed = makeTask("Fahrrad", source: .local, version: "7")
        changed.title = "Fahrrad (geändert)"
        local.conflictOnNextApply = changed

        await model.complete(TaskID(source: .local, rawValue: "Fahrrad"))

        #expect(model.lastError != nil)
        #expect(model.items.contains { $0.title == "Fahrrad (geändert)" && !$0.isCompleted })
        #expect(model.lastCompleted == nil)
    }

    @Test func reschedule_tomorrow_appliesOnlyDue() async {
        let model = makeModel()
        await model.reload()
        let id = TaskID(source: .reminders, rawValue: "Einkaufen")
        await model.reschedule(id, option: .tomorrow)

        let applied = reminders.appliedEdits.first
        var expected = TaskEdit()
        expected.due = .set(DueDate(year: 2026, month: 11, day: 19))
        #expect(applied?.edit == expected)
        #expect(model.items.first { $0.id == id }?.due == DueDate(year: 2026, month: 11, day: 19))
    }

    @Test func create_local_appendsItem() async {
        let model = makeModel()
        await model.reload()
        await model.create(TaskDraft(title: "Neu"), in: .local)
        #expect(model.items.contains { $0.title == "Neu" && $0.id.source == .local })
    }

    @Test func write_failure_setsErrorAndKeepsItem() async {
        let model = makeModel()
        await model.reload()
        local.applyError = .failed("Speicher voll")
        await model.complete(TaskID(source: .local, rawValue: "Fahrrad"))
        #expect(model.lastError == "Speicher voll")
        #expect(model.items.contains { $0.title == "Fahrrad" })
    }
}

struct DueTextTests {
    let calendar = testCalendar()
    let now = testNow()

    @Test func text_relativeDays() {
        #expect(DueText.text(DueDate(year: 2026, month: 11, day: 18), now: now, calendar: calendar) == "heute")
        #expect(DueText.text(DueDate(year: 2026, month: 11, day: 19), now: now, calendar: calendar) == "morgen")
        #expect(DueText.text(DueDate(year: 2026, month: 11, day: 17), now: now, calendar: calendar) == "gestern")
    }

    @Test func text_withTime_appendsTime() {
        #expect(DueText.text(DueDate(year: 2026, month: 11, day: 18, hour: 9, minute: 5), now: now, calendar: calendar) == "heute, 09:05")
    }

    @Test func text_otherDays_usesDayAndMonth() {
        #expect(DueText.text(DueDate(year: 2026, month: 11, day: 27), now: now, calendar: calendar) == "27.11.")
        #expect(DueText.text(DueDate(year: 2027, month: 1, day: 3), now: now, calendar: calendar) == "03.01.2027")
    }
}

struct DueTextFormatTests {
    let calendar = testCalendar()
    let now = testNow()
    let english = Locale(identifier: "en_US")

    @Test func text_numbersFollowTheLocale() {
        // The words stay German until the English texts exist; day order and clock follow the locale.
        #expect(DueText.text(DueDate(year: 2026, month: 11, day: 27), now: now, calendar: calendar, locale: english) == "11/27")
        #expect(DueText.text(DueDate(year: 2027, month: 1, day: 3), now: now, calendar: calendar, locale: english) == "01/03/2027")
        #expect(DueText.text(DueDate(year: 2026, month: 11, day: 18, hour: 14, minute: 5), now: now, calendar: calendar, locale: english)
            == "heute, 2:05\u{202F}PM")
    }
}

struct TagwerkCalendarTests {
    /// The calendar must follow time zone changes without an app restart.
    @Test func tagwerkCalendar_followsSystemTimeZoneChanges() {
        #expect(Calendar.tagwerk.timeZone == TimeZone.autoupdatingCurrent)
    }

    @Test func tagwerkCalendar_keepsMondayAndIsoWeeksInEveryLocale() {
        for identifier in ["de_DE", "en_US", "en_GB"] {
            let calendar = Calendar.tagwerk(locale: Locale(identifier: identifier))
            #expect(calendar.firstWeekday == 2)
            #expect(calendar.minimumDaysInFirstWeek == 4)
            // 2027-01-01 is a Friday: still week 53 of 2026 in ISO numbering, also for en_US.
            var utc = calendar
            utc.timeZone = TimeZone(identifier: "UTC")!
            let date = utc.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 12))!
            #expect(utc.component(.weekOfYear, from: date) == 53)
        }
    }

    @Test func tagwerkCalendar_followsTheCurrentLocale() {
        #expect(Calendar.tagwerk.locale?.identifier == Locale.current.identifier)
    }

    @Test func tagwerkCalendar_startsWeekOnMonday() {
        #expect(Calendar.tagwerk.firstWeekday == 2)
    }
}

struct CreationTargetTests {
    @Test func creationTarget_followsFilter_allMeansReminders() {
        let all: Set<TaskSource> = [.reminders, .github, .local]
        #expect(TaskFilter.all.creationTarget(available: all) == .reminders)
        #expect(TaskFilter.reminders.creationTarget(available: all) == .reminders)
        #expect(TaskFilter.github.creationTarget(available: all) == .github)
        #expect(TaskFilter.local.creationTarget(available: all) == .local)
    }

    @Test func creationTarget_unavailableSource_fallsBackToLocal() {
        #expect(TaskFilter.all.creationTarget(available: [.local]) == .local)
        #expect(TaskFilter.github.creationTarget(available: [.local, .reminders]) == .local)
    }
}

struct ReconnectPolicyTests {
    @Test func delay_growsAndCapsAtFiveMinutes() {
        #expect(ReconnectPolicy.delay(afterAttempts: 0) == .seconds(30))
        #expect(ReconnectPolicy.delay(afterAttempts: 1) == .seconds(60))
        #expect(ReconnectPolicy.delay(afterAttempts: 2) == .seconds(120))
        #expect(ReconnectPolicy.delay(afterAttempts: 3) == .seconds(240))
        #expect(ReconnectPolicy.delay(afterAttempts: 4) == .seconds(300))
        #expect(ReconnectPolicy.delay(afterAttempts: 10) == .seconds(300))
    }

    @Test func needsRetry_onlyForOfflineOrFailed() {
        #expect(ReconnectPolicy.needsRetry(.offline(since: .now)))
        #expect(ReconnectPolicy.needsRetry(.failed("x")))
        #expect(!ReconnectPolicy.needsRetry(.loaded))
        #expect(!ReconnectPolicy.needsRetry(.signedOut))
        #expect(!ReconnectPolicy.needsRetry(.noAccess))
        #expect(!ReconnectPolicy.needsRetry(nil))
    }
}

@MainActor
struct TaskListAssigneeTests {
    let github: FakeTaskProvider
    let model: TaskListModel
    let issueID = TaskID(source: .github, rawValue: "Login")

    init() {
        var issue = makeTask("Login", source: .github, due: DueDate(year: 2026, month: 11, day: 20))
        issue.assignees = ["octo"]
        issue.url = URL(string: "https://github.com/beispiel/app/issues/42")
        github = FakeTaskProvider(source: .github, tasks: [issue])
        github.viewerLogin = "octo"
        model = TaskListModel(providers: [github], now: testNow, calendar: testCalendar())
    }

    private func draft(_ assignees: [String]?) -> TaskDraft {
        TaskDraft(title: "Export", containerID: "beispiel/app", subContainerIDs: ["PVT_1"], assignees: assignees)
    }

    private var listedTitles: [String] { model.items.map(\.title) }

    @Test func create_forMe_addsItemWithoutNotice() async {
        await model.create(draft(nil), in: .github)
        #expect(listedTitles == ["Export"])
        #expect(model.lastHandedOver == nil)
        #expect(model.lastError == nil)
    }

    @Test func create_forOthers_neverEntersItems_andSetsNotice() async {
        await model.create(draft(["lea-m"]), in: .github)
        #expect(!model.items.contains { $0.id.source == .github })
        #expect(model.lastHandedOver?.number == 151)
        #expect(model.lastHandedOver?.assignees == ["lea-m"])
        #expect(model.lastHandedOver?.url == URL(string: "https://github.com/beispiel/app/issues/151"))
        #expect(model.lastError == nil)
    }

    @Test func create_forNoOne_setsNoticeWithoutAssignees() async {
        await model.create(draft([]), in: .github)
        #expect(model.items.isEmpty)
        #expect(model.lastHandedOver?.number == 151)
        #expect(model.lastHandedOver?.assignees == [])
    }

    @Test func create_droppedAssignee_warnsByName() async {
        github.droppedAssignees = ["lea-m"]
        await model.create(draft(["octo", "lea-m"]), in: .github)
        #expect(model.lastError == "#151 angelegt, aber lea-m konnte nicht zugewiesen werden.")
        #expect(listedTitles == ["Export"])
        #expect(model.lastHandedOver == nil)
    }

    @Test func create_droppedOnlyAssignee_warnsAndHandsOver() async {
        github.droppedAssignees = ["lea-m"]
        await model.create(draft(["lea-m"]), in: .github)
        #expect(model.lastError == "#151 angelegt, aber lea-m konnte nicht zugewiesen werden.")
        #expect(model.lastHandedOver?.assignees == [])
        #expect(model.items.isEmpty)
    }

    @Test func create_handedOver_callsHook() async {
        var handedOver: [TaskID] = []
        model.onHandedOver = { handedOver.append($0) }
        await model.create(draft(["lea-m"]), in: .github)
        #expect(handedOver.count == 1)
    }

    @Test func didSave_handedOver_removesItem_callsHookAndSetsNotice() async {
        await model.reload()
        var handedOver: [TaskID] = []
        model.onHandedOver = { handedOver.append($0) }
        var saved = github.tasks[0]
        saved.assignees = ["lea-m"]

        model.didSave(saved)
        await waitUntil { !handedOver.isEmpty }

        #expect(model.items.isEmpty)
        #expect(handedOver == [issueID])
        #expect(model.lastHandedOver?.number == 42)
        #expect(model.lastHandedOver?.assignees == ["lea-m"])
    }

    @Test func didSave_stillMine_replacesItemWithoutNotice() async {
        await model.reload()
        var saved = github.tasks[0]
        saved.title = "Login neu"
        saved.assignees = ["octo", "lea-m"]
        model.didSave(saved, requestedAssignees: ["lea-m"])
        #expect(listedTitles == ["Login neu"])
        #expect(model.lastHandedOver == nil)
        #expect(model.lastError == nil)
    }

    @Test func didSave_missingRequestedAssignee_warns() async {
        await model.reload()
        model.didSave(github.tasks[0], requestedAssignees: ["sam"])
        #expect(model.lastError == "sam konnte nicht zugewiesen werden.")
        #expect(listedTitles == ["Login"])
    }

    @Test func unassignedMessage_listsSeveralPeople() {
        #expect(TaskListModel.unassignedMessage(number: 7, created: true, missing: ["lea-m", "sam"])
            == "#7 angelegt, aber lea-m und sam konnte nicht zugewiesen werden.")
        #expect(TaskListModel.unassignedMessage(number: nil, created: true, missing: ["sam"]) == "sam konnte nicht zugewiesen werden.")
    }

    @Test func createReturning_forOthers_setsNoNotice_butRemovesFromItems() async throws {
        let created = try await model.createReturning(draft(["lea-m"]), in: .github)
        #expect(created.assignees == ["lea-m"])
        #expect(model.items.isEmpty)
        #expect(model.lastHandedOver == nil)
        #expect(model.lastError == nil)
    }

    @Test func applyReturning_handedOver_removesItem() async throws {
        await model.reload()
        var handedOver: [TaskID] = []
        model.onHandedOver = { handedOver.append($0) }
        var edit = TaskEdit()
        edit.assignees = .set(AssigneeChange(add: ["lea-m"], remove: ["octo"]))
        let updated = try await model.applyReturning(edit, to: issueID)
        #expect(updated.assignees == ["lea-m"])
        #expect(model.items.isEmpty)
        #expect(handedOver == [issueID])
        #expect(model.lastHandedOver == nil)
    }

    @Test func handedOverNotice_readsNumberFromURL() {
        var item = makeTask("Ohne", source: .github)
        #expect(HandedOverNotice(item: item).number == nil)
        item.url = URL(string: "https://github.com/beispiel/app/issues/9")
        #expect(item.issueNumber == 9)
    }
}

@MainActor
struct ReconnectTests {
    /// While GitHub is offline, the list retries on its own and leaves the offline state when it answers again.
    @Test func reconnect_retriesUntilOnline() async {
        let github = FakeTaskProvider(source: .github, tasks: [makeTask("#1", source: .github)])
        github.offlineSince = testNow()
        let model = TaskListModel(providers: [github], now: testNow, calendar: testCalendar())
        await model.reload()
        #expect(model.sourceStates[.github]?.isOffline == true)

        var sleeps: [Duration] = []
        let reconnect = Reconnector(model: model, source: .github, sleep: { duration in
            sleeps.append(duration)
            if sleeps.count == 2 { github.offlineSince = nil }  // back online before the second retry
        })
        await reconnect.runUntilOnline()

        #expect(sleeps == [.seconds(30), .seconds(60)])
        #expect(model.sourceStates[.github] == .loaded)
    }
}
