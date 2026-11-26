import Foundation
import SwiftData
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

    private func completedTask(_ title: String, source: TaskSource, version: String = "1") -> TaskItem {
        var task = makeTask(title, source: source, version: version)
        task.isCompleted = true
        return task
    }

    @Test func reminderMarks_refreshAfterSaving() async {
        let due = DueDate(year: 2026, month: 11, day: 27, hour: 12)
        let task = makeTask("Bericht", source: .local, due: due)
        let provider = FakeTaskProvider(source: .local, tasks: [task, makeTask("Ohne Datum", source: .local)])
        let model = TaskListModel(providers: [provider], now: testNow, calendar: testCalendar())
        var stored: [String: [ReminderOverride]] = [:]
        model.reminderMarkInputs = { (stored, ReminderDefaults.legacy(leadTimeMinutes: 120)) }
        await model.reload()
        #expect(model.reminderMarks.isEmpty)
        // The editor saved an own list: the mark appears without another reload.
        let key = ReminderOverride.key(task: task.id)
        stored[key] = [ReminderOverride(itemKey: key, scope: .always, offsets: [.before(amount: 1, unit: .days), .before(amount: 1, unit: .weeks)])]
        model.refreshReminderMarks()
        #expect(model.reminderMarks == [task.id.key: .custom(count: 2)])
        // Back to the default: the mark goes.
        stored = [:]
        model.refreshReminderMarks()
        #expect(model.reminderMarks.isEmpty)
    }

    @Test func reminderMarks_withoutInputs_stayEmpty() async {
        let model = makeModel()
        await model.reload()
        #expect(model.reminderMarks.isEmpty)
    }

    @Test func reopen_insertsTaskAndReportsCompletionChange() async {
        let done = completedTask("Fahrrad-Pumpe", source: .local)
        local.tasks.append(done)                                       // the provider holds it completed, items do not
        let model = makeModel()
        await model.reload()
        #expect(!model.items.contains { $0.id == done.id })
        var reported: [(TaskID, Bool)] = []
        model.onCompletionChanged = { id, flag in reported.append((id, flag)) }
        let reopened = await model.reopen(done)
        #expect(reopened?.isCompleted == false)
        #expect(model.items.contains { $0.id == done.id })
        #expect(reported.count == 1 && reported[0].0 == done.id && reported[0].1 == false)
        #expect(local.appliedEdits.last?.expectedVersion == done.version)
    }

    @Test func reopen_reportsMissingTaskInsteadOfInserting() async {
        let model = makeModel()
        await model.reload()
        let ghost = completedTask("Gelöscht", source: .local)
        let reopened = await model.reopen(ghost)
        #expect(reopened == nil)
        #expect(model.lastError == "Die Aufgabe existiert nicht mehr.")
        #expect(!model.items.contains { $0.id == ghost.id })
    }

    @Test func reopen_conflictKeepsTheListAndReloads() async {
        let done = completedTask("Fahrrad-Pumpe", source: .local)
        local.tasks.append(done)
        var current = done
        current.version = "2"
        local.conflictOnNextApply = current
        let model = makeModel()
        await model.reload()
        #expect(await model.reopen(done) == nil)
        #expect(model.lastError == "Die Aufgabe wurde inzwischen geändert. Die Liste ist jetzt aktuell.")
    }

    @Test func didSave_reopenedFromOutsideTheListReportsTheCompletionChange() async {
        let model = makeModel()
        await model.reload()
        var reopened = completedTask("Fahrrad-Pumpe", source: .local)
        reopened.isCompleted = false
        var reported: [(TaskID, Bool)] = []
        model.onCompletionChanged = { id, flag in reported.append((id, flag)) }
        model.didSave(reopened, wasCompleted: true)
        await waitUntil { !reported.isEmpty }
        #expect(reported.count == 1 && reported[0].1 == false)
        #expect(model.items.contains { $0.id == reopened.id })
    }

    @Test func didSave_completedInEditor_offersUndo() async throws {
        let model = makeModel()
        await model.reload()
        var done = try #require(model.items.first { $0.title == "Fahrrad" })
        done.isCompleted = true
        model.didSave(done)
        #expect(!model.items.contains { $0.id == done.id })
        #expect(model.lastCompleted?.id == done.id)
        await model.undoComplete()
        #expect(model.items.contains { $0.id == done.id && !$0.isCompleted })
        #expect(model.lastCompleted == nil)
    }

    /// GitHub project workflows change the issue right after closing; "Rückgängig" must still reopen it.
    @Test func undoComplete_versionChangedAfterCompletion_retriesAgainstCurrentVersion() async {
        let model = makeModel()
        await model.reload()
        let id = TaskID(source: .local, rawValue: "Fahrrad")
        await model.complete(id)
        var touched = completedTask("Fahrrad", source: .local, version: "3")
        touched.notes = "Status von einem Workflow gesetzt"
        local.conflictOnNextApply = touched
        await model.undoComplete()
        #expect(model.lastError == nil)
        #expect(model.items.contains { $0.id == id && !$0.isCompleted })
        #expect(local.appliedEdits.last?.expectedVersion == "3")
        #expect(local.appliedEdits.last?.edit.isCompleted == .set(false))
    }

    @Test func undoComplete_alreadyReopenedElsewhere_adoptsCurrentState() async {
        let model = makeModel()
        await model.reload()
        let id = TaskID(source: .local, rawValue: "Fahrrad")
        await model.complete(id)
        local.conflictOnNextApply = makeTask("Fahrrad", source: .local, version: "4")
        let writesBefore = local.appliedEdits.count
        await model.undoComplete()
        #expect(model.lastError == nil)
        #expect(model.items.contains { $0.id == id && $0.version == "4" })
        #expect(local.appliedEdits.count == writesBefore + 1)
    }

    @Test func didSave_editingAnAlreadyCompletedTask_offersNoUndo() async {
        let model = makeModel()
        await model.reload()
        var edited = completedTask("Fahrrad-Pumpe", source: .local)
        edited.notes = "Ventil prüfen"
        model.didSave(edited, wasCompleted: true)
        #expect(model.lastCompleted == nil)
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

/// Ticking off a repeating local task keeps it in the list with its next due date (plan 2026-11-18, stage 2).
@MainActor
struct RecurringLocalCompletionTests {
    let container: ModelContainer
    let provider: LocalTaskProvider
    let model: TaskListModel
    let due = DueDate(year: 2026, month: 11, day: 18, hour: 8, minute: 0)
    let nextDue = DueDate(year: 2026, month: 11, day: 19, hour: 8, minute: 0)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        provider = LocalTaskProvider(context: container.mainContext, calendar: testCalendar(), now: testNow)
        model = TaskListModel(providers: [provider], now: testNow, calendar: testCalendar())
    }

    private func repeatingTask() async throws -> TaskID {
        let series = Recurrence(rule: .daily(interval: 1), start: PlanDay(due), end: nil, count: nil)
        let created = try await provider.create(TaskDraft(title: "Training", due: due, recurrence: series))
        await model.reload()
        return created.id
    }

    @Test func complete_keepsTaskWithNextDueAndReportsCompletion() async throws {
        let id = try await repeatingTask()
        var reported: [(TaskID, Bool)] = []
        model.onCompletionChanged = { id, isCompleted in reported.append((id, isCompleted)) }
        await model.complete(id)
        #expect(model.items.first { $0.id == id }?.due == nextDue)
        #expect(model.lastCompleted?.id == id)
        #expect(reported.map(\.0) == [id])
        #expect(reported.map(\.1) == [true])
    }

    @Test func undoComplete_restoresDueDate() async throws {
        let id = try await repeatingTask()
        await model.complete(id)
        await model.undoComplete()
        #expect(model.items.filter { $0.id == id }.map(\.due) == [due])
    }

    /// The assistant's "complete_task" also frees the day's effort of the series.
    @Test func completeReturning_reportsCompletion() async throws {
        let id = try await repeatingTask()
        var reported: [Bool] = []
        model.onCompletionChanged = { _, isCompleted in reported.append(isCompleted) }
        let updated = try await model.completeReturning(id)
        #expect(updated.isCompleted == false)
        #expect(model.items.first { $0.id == id }?.due == nextDue)
        #expect(reported == [true])
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

    @Test func create_returnsTheCreatedItem_evenWhenAnAssigneeWasDropped() async {
        github.droppedAssignees = ["lea-m"]
        let created = await model.create(draft(["octo", "lea-m"]), in: .github)
        #expect(created != nil)
        #expect(model.lastError != nil)   // the "could not be assigned" warning must not hide the success
    }

    @Test func create_returnsNilOnFailure_evenWithTheSameMessageAsBefore() async {
        github.applyError = .failed("Nope")
        let first = await model.create(draft(nil), in: .github)
        let second = await model.create(draft(nil), in: .github)
        #expect(first == nil && second == nil)
        #expect(model.lastError != nil)
    }

    @Test func create_returnsNilWithoutARegisteredSource() async {
        #expect(await model.create(TaskDraft(title: "Neu"), in: .reminders) == nil)
    }

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
        #expect(HandedOverNotice(item: item, reason: .handedOver).number == nil)
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


@MainActor
struct TaskListStatusTests {
    let github: FakeTaskProvider
    let model: TaskListModel
    let issueID = TaskID(source: .github, rawValue: "Login")

    init() {
        var issue = makeTask("Login", source: .github, due: DueDate(year: 2026, month: 11, day: 20))
        issue.assignees = ["octo"]
        issue.url = URL(string: "https://github.com/beispiel/app/issues/42")
        issue.editableFields.insert(.status)
        issue.statuses = [
            SubContainerStatus(subContainerID: "PVT_1", subContainerName: "App", current: "Ready",
                               options: ["Backlog", "Ready", "In progress", "Done"], isWritable: true),
            SubContainerStatus(subContainerID: "PVT_2", subContainerName: "Studium", current: "Ready",
                               options: ["Backlog", "Ready", "In progress", "Done"], isWritable: true),
        ]
        github = FakeTaskProvider(source: .github, tasks: [issue])
        github.viewerLogin = "octo"
        github.requiresPlacementToBeListed = true
        model = TaskListModel(providers: [github], now: testNow, calendar: testCalendar())
    }

    @Test func setStatus_sendsOneStatusChange_andKeepsTheItemListed() async {
        await model.reload()
        await model.setStatus(issueID, subContainerID: "PVT_1", to: "In progress")
        #expect(github.appliedEdits.last?.edit.statusChanges == ["PVT_1": "In progress"])
        #expect(model.items.first?.statuses.first?.current == "In progress")
        #expect(model.lastCompleted == nil)
    }

    @Test func setStatus_doneInOneOfTwoProjects_keepsTheIssueOpenInTheList() async {
        await model.reload()
        await model.setStatus(issueID, subContainerID: "PVT_1", to: "Done")
        #expect(model.items.count == 1)
        #expect(model.lastCompleted == nil)
    }

    @Test func setStatus_doneInEveryProject_completesLikeErledigt() async {
        await model.reload()
        var completions: [(TaskID, Bool)] = []
        model.onCompletionChanged = { id, flag in completions.append((id, flag)) }
        await model.setStatus(issueID, subContainerID: "PVT_1", to: "Done")
        await model.setStatus(issueID, subContainerID: "PVT_2", to: "Done")
        #expect(model.items.isEmpty)
        #expect(model.lastCompleted?.id == issueID)
        #expect(completions.count == 1 && completions[0].1 == true)
    }

    @Test func setStatus_failure_showsErrorAndLeavesTheList() async {
        await model.reload()
        github.applyError = .failed("Den Status „Blocked“ gibt es im Projekt „App“ nicht.")
        await model.setStatus(issueID, subContainerID: "PVT_1", to: "Blocked")
        #expect(model.lastError == "Den Status „Blocked“ gibt es im Projekt „App“ nicht.")
        #expect(model.items.first?.statuses.first?.current == "Ready")
    }

    // MARK: Issues without a Project (#153)

    @Test func create_withoutProject_isNotListed_andShowsTheNoProjectCapsule() async {
        await model.reload()
        let draft = TaskDraft(title: "Export", containerID: "beispiel/app", subContainerIDs: [])
        let created = await model.create(draft, in: .github)
        #expect(created != nil)
        #expect(model.items.count == 1)   // only the existing issue
        #expect(!model.items.contains { $0.title == "Export" })
        #expect(model.lastHandedOver?.reason == .noProject(others: []))
        #expect(model.lastHandedOver?.number == 151)
        #expect(model.lastHandedOver?.title == "#151 ohne Projekt")
        #expect(model.lastHandedOver?.url == URL(string: "https://github.com/beispiel/app/issues/151"))
        #expect(model.lastError == nil)
    }

    @Test func create_withProject_staysListed_withoutCapsule() async {
        let draft = TaskDraft(title: "Export", containerID: "beispiel/app", subContainerIDs: ["PVT_1"], startStatus: "In progress")
        await model.create(draft, in: .github)
        #expect(model.items.contains { $0.title == "Export" })
        #expect(model.lastHandedOver == nil)
        #expect(github.createdDrafts.last?.startStatus == "In progress")
    }

    @Test func create_forOthersInAProject_isStillTheHandedOverCapsule() async {
        let draft = TaskDraft(title: "Export", containerID: "beispiel/app", subContainerIDs: ["PVT_1"], assignees: ["lea-m"])
        await model.create(draft, in: .github)
        #expect(model.lastHandedOver?.reason == .handedOver)
        #expect(model.lastHandedOver?.title == "#151 an lea-m")
    }

    @Test func create_withoutProjectForOthers_namesThemInTheCapsule() async {
        let draft = TaskDraft(title: "Export", containerID: "beispiel/app", subContainerIDs: [], assignees: ["lea-m"])
        await model.create(draft, in: .github)
        #expect(model.lastHandedOver?.reason == .noProject(others: ["lea-m"]))
        #expect(model.lastHandedOver?.title == "#151 an lea-m · ohne Projekt")
    }

    @Test func noProjectNotice_texts() {
        #expect(AssigneeSelection.noProjectTitle(number: 7) == "#7 ohne Projekt")
        #expect(AssigneeSelection.noProjectTitle(number: nil) == "Issue ohne Projekt")
        #expect(AssigneeSelection.noProjectAnnouncement(number: 7)
            == "Angelegt, nicht in Aufgaben: #7 ohne Projekt. Auf GitHub öffnen verfügbar.")
    }

    // MARK: Done in the selected project only (GH7b)

    @Test func setStatus_doneInOnlySelectedProject_removesItemAndShowsNotice() async {
        github.selectedSubContainerIDs = ["PVT_1"]
        var handedOver: [TaskID] = []
        model.onHandedOver = { handedOver.append($0) }
        await model.reload()
        await model.setStatus(issueID, subContainerID: "PVT_1", to: "Done")
        #expect(model.items.isEmpty)
        #expect(model.lastCompleted == nil)
        #expect(model.lastHandedOver?.reason == .doneInSelection(doneIn: ["App"], openIn: ["Studium"]))
        #expect(model.lastHandedOver?.title == "#42 noch offen in „Studium“")
        #expect(model.lastHandedOver?.url == URL(string: "https://github.com/beispiel/app/issues/42"))
        #expect(handedOver == [issueID])
    }

    @Test func setStatus_doneInAllProjects_showsUndoCapsule() async {
        github.selectedSubContainerIDs = ["PVT_1"]
        await model.reload()
        await model.setStatus(issueID, subContainerID: "PVT_1", to: "In progress")
        await model.setStatus(issueID, subContainerID: "PVT_2", to: "Done")
        await model.setStatus(issueID, subContainerID: "PVT_1", to: "Done")
        #expect(model.items.isEmpty)
        #expect(model.lastCompleted?.id == issueID)
        #expect(model.lastHandedOver == nil)
    }

    @Test func setStatus_openInASelectedProject_staysListedWithoutNotice() async {
        github.selectedSubContainerIDs = ["PVT_1", "PVT_2"]
        await model.reload()
        await model.setStatus(issueID, subContainerID: "PVT_1", to: "Done")
        #expect(model.items.count == 1)
        #expect(model.lastHandedOver == nil)
    }

    @Test func editorSave_doneInSelection_showsNotice() async {
        github.selectedSubContainerIDs = ["PVT_1"]
        await model.reload()
        var handedOver: [TaskID] = []
        model.onHandedOver = { handedOver.append($0) }
        var saved = github.tasks[0]
        saved.statuses[0].current = "Done"

        model.didSave(saved)
        await waitUntil { !handedOver.isEmpty }

        #expect(model.items.isEmpty)
        #expect(model.lastHandedOver?.reason == .doneInSelection(doneIn: ["App"], openIn: ["Studium"]))
    }

    @Test func assistantWrite_doneInSelection_showsNoCapsule() async throws {
        github.selectedSubContainerIDs = ["PVT_1"]
        await model.reload()
        var handedOver: [TaskID] = []
        model.onHandedOver = { handedOver.append($0) }
        var edit = TaskEdit()
        edit.statusChanges = ["PVT_1": "Done"]

        _ = try await model.applyReturning(edit, to: issueID)

        #expect(model.items.isEmpty)
        #expect(handedOver == [issueID])
        #expect(model.lastHandedOver == nil)
    }
}

@MainActor
struct TaskContextMenuStatusTests {
    private func item(statuses: [SubContainerStatus], fields: Set<TaskField> = [.status]) -> TaskItem {
        var item = makeTask("Login", source: .github)
        item.editableFields = fields
        item.statuses = statuses
        return item
    }

    private func row(_ id: String, writable: Bool = true, options: [String] = ["Ready", "Done"]) -> SubContainerStatus {
        SubContainerStatus(subContainerID: id, subContainerName: id, current: "Ready", options: options, isWritable: writable)
    }

    @Test func statusRows_onlyWritableProjectsWithOptions() {
        let rows = TaskContextMenu.statusRows(of: item(statuses: [row("A"), row("B", writable: false), row("C", options: [])]))
        #expect(rows.map(\.subContainerID) == ["A"])
    }

    @Test func statusRows_emptyWithoutEditableStatusOrOutsideGitHub() {
        #expect(TaskContextMenu.statusRows(of: item(statuses: [row("A")], fields: [.title])).isEmpty)
        var local = item(statuses: [row("A")])
        local = TaskItem(id: TaskID(source: .local, rawValue: "x"), title: "x", notes: nil, due: nil, priority: nil,
                         estimateMinutes: nil, isCompleted: false, container: local.container, url: nil, version: "1",
                         editableFields: [.status], statuses: [row("A")])
        #expect(TaskContextMenu.statusRows(of: local).isEmpty)
    }

    // MARK: assignUnlisted (the assistant takes over an issue found by the GitHub search)

    private func unlistedIssue(assignees: [String]) -> (FakeTaskProvider, TaskItem) {
        let github = FakeTaskProvider(source: .github)
        github.viewerLogin = "octo"
        let item = TaskItem(id: TaskID(source: .github, rawValue: "ISSUE_151"), title: "Export prüfen", notes: nil, due: nil,
                            priority: nil, estimateMinutes: nil, isCompleted: false,
                            container: TaskContainer(id: "beispiel/app", name: "beispiel/app", colorHex: nil),
                            url: URL(string: "https://github.com/beispiel/app/issues/151"), version: "1",
                            editableFields: [.title, .assignees], assignees: assignees)
        return (github, item)
    }

    @Test func assignUnlisted_takeOver_joinsListWithoutVersionCheck() async throws {
        let (github, item) = unlistedIssue(assignees: [])
        let model = TaskListModel(providers: [github], now: testNow, calendar: testCalendar())
        await model.reload()
        github.tasks = [item]   // the provider holds the issue, the loaded list does not
        #expect(model.items.isEmpty)
        let updated = try await model.assignUnlisted(AssigneeChange(add: ["octo"]), to: item.id)
        #expect(updated.assignees == ["octo"])
        #expect(model.items.map(\.id) == [item.id])
        #expect(github.appliedEdits.last?.expectedVersion == nil)
    }

    @Test func assignUnlisted_assignOther_staysOutOfTheList() async throws {
        let (github, item) = unlistedIssue(assignees: [])
        let model = TaskListModel(providers: [github], now: testNow, calendar: testCalendar())
        await model.reload()
        github.tasks = [item]
        _ = try await model.assignUnlisted(AssigneeChange(add: ["lea-m"]), to: item.id)
        #expect(model.items.isEmpty)
    }

    @Test func assignUnlisted_handOverHookNotCalled() async throws {
        let (github, item) = unlistedIssue(assignees: [])
        let model = TaskListModel(providers: [github], now: testNow, calendar: testCalendar())
        await model.reload()
        github.tasks = [item]
        var handedOver: [TaskID] = []
        model.onHandedOver = { handedOver.append($0) }
        _ = try await model.assignUnlisted(AssigneeChange(add: ["lea-m"]), to: item.id)
        _ = try await model.assignUnlisted(AssigneeChange(add: ["octo"]), to: item.id)
        #expect(handedOver.isEmpty)
        // No capsule either: nothing left the lists.
        #expect(model.lastHandedOver == nil)
    }

    @Test func assignUnlisted_unknownSource_throws() async {
        let (github, item) = unlistedIssue(assignees: [])
        let model = TaskListModel(providers: [FakeTaskProvider(source: .local)], now: testNow, calendar: testCalendar())
        _ = github
        await #expect(throws: TaskWriteError.self) {
            _ = try await model.assignUnlisted(AssigneeChange(add: ["octo"]), to: item.id)
        }
    }
}


@MainActor
struct TaskListActivityTests {
    let local = FakeTaskProvider(source: .local, tasks: [makeTask("Fahrrad", source: .local)])

    private func makeModel() -> (TaskListModel, Recorder) {
        let model = TaskListModel(providers: [local], now: testNow, calendar: testCalendar())
        let recorder = Recorder()
        model.onActivity = { recorder.entries += $0 }
        return (model, recorder)
    }

    final class Recorder { var entries: [TaskActivityEntry] = [] }

    @Test func complete_isLogged() async {
        let (model, recorder) = makeModel()
        await model.reload()
        await model.complete(TaskID(source: .local, rawValue: "Fahrrad"))
        #expect(recorder.entries.map(\.kind) == [.completed])
        #expect(recorder.entries.first?.projectKeys == ["local:local"])
        #expect(recorder.entries.first?.occurredAt == testNow())
    }

    @Test func reschedule_isLoggedWithBeforeAndAfter() async {
        let due = DueDate(year: 2026, month: 11, day: 18)
        local.tasks = [makeTask("Bericht", source: .local, due: due)]
        let (model, recorder) = makeModel()
        await model.reload()
        await model.rescheduleReturningForTest(TaskID(source: .local, rawValue: "Bericht"), to: DueDate(year: 2026, month: 11, day: 25))
        #expect(recorder.entries.map(\.kind) == [.rescheduled])
        #expect(recorder.entries.first?.from == "2026-11-18" && recorder.entries.first?.to == "2026-11-25")
    }

    @Test func create_isLogged() async {
        let (model, recorder) = makeModel()
        await model.create(TaskDraft(title: "Neu"), in: .local)
        #expect(recorder.entries.map(\.kind) == [.created])
    }

    @Test func nothingChanged_logsNothing() async {
        let (model, recorder) = makeModel()
        await model.reload()
        let item = model.items[0]
        model.didSave(item)
        #expect(recorder.entries.isEmpty)
    }

    @Test func didSave_aCompletedSearchHitThatIsReopenedIsLogged() async {
        let (model, recorder) = makeModel()
        await model.reload()
        let reopened = makeTask("Alt", source: .local)
        model.didSave(reopened, wasCompleted: true)
        #expect(recorder.entries.map(\.kind) == [.reopened])
    }
}

private extension TaskListModel {
    func rescheduleReturningForTest(_ id: TaskID, to due: DueDate?) async {
        _ = try? await rescheduleReturning(id, to: due)
    }
}
