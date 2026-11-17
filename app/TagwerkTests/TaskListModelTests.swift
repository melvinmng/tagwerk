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
