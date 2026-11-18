import AIKit
import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct AIPlannerTests {
    let container: ModelContainer
    let settings: AppSettings
    let calendarStore = FakeCalendarStore()
    let local: FakeTaskProvider
    let github: FakeTaskProvider
    let taskList: TaskListModel
    let planStore: PlanStore
    let blocks: BlockPlanner
    let store: SuggestionStore
    let responder = FakePlanResponder()
    let calendar = testCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 18)  // Wednesday, now 10:00

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.planCalendarID = "plan"
        settings.bufferMinutes = 0
        local = FakeTaskProvider(source: .local, tasks: [
            makeTask("Fahrrad", source: .local, due: DueDate(year: 2026, month: 11, day: 18)),
            makeTask("Abgabe", source: .local, due: DueDate(year: 2026, month: 11, day: 20)),
        ])
        github = FakeTaskProvider(source: .github, tasks: [makeTask("Login", source: .github, due: DueDate(year: 2026, month: 11, day: 18))])
        taskList = TaskListModel(providers: [local, github], now: testNow, calendar: calendar)
        planStore = PlanStore(context: container.mainContext)
        blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                              settings: settings, calendar: calendar)
        store = SuggestionStore(context: container.mainContext)
    }

    private func make(scope: PlanScope = .day, reminderStore: FakeAccessStore = FakeAccessStore(),
                      now: @escaping () -> Date = testNow) async -> (AIPlanner, PlanningModel) {
        await taskList.reload()
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: reminderStore,
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     suggestions: store, now: now, calendar: calendar)
        planning.scope = scope
        await planning.reload()
        let planner = AIPlanner(responder: responder, model: { "gpt-test" }, planning: planning, store: store)
        return (planner, planning)
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func event(_ title: String, _ day: Int, _ from: Int, _ to: Int) -> CalendarEvent {
        CalendarEvent(id: title, externalID: nil, calendarID: "work", title: title, start: at(day, from), end: at(day, to),
                      isAllDay: false, url: nil, isBusy: true, version: "1")
    }

    static func dayAnswer(_ blocks: String, unscheduled: String = "", estimates: String = "") -> String {
        #"{"blocks":[\#(blocks)],"unscheduled":[\#(unscheduled)],"risks":["Knapp"],"estimates":[\#(estimates)]}"#
    }

    static func block(_ key: String, _ start: String, _ minutes: Int = 60) -> String {
        #"{"taskId":"\#(key)","start":"\#(start)","minutes":\#(minutes),"reason":"passt"}"#
    }

    // MARK: Marked deadlines (plan deadline-marking, Task 9)

    @Test func taskLinkedToMarkedDeadlineGetsAnchor() async throws {
        calendarStore.calendars.append(ListInfo(id: "timetable", title: "Stundenplan", colorHex: nil, kind: .subscription))
        let exam = CalendarEvent(id: "exam", externalID: nil, calendarID: "timetable", title: "Klausur Statistik",
                                 start: at(18, 15), end: at(18, 17), isAllDay: false, url: nil, isBusy: true, version: "1")
        calendarStore.storedEvents = [exam]
        blocks.links.link(eventID: "exam", to: TaskID(source: .local, rawValue: "Abgabe"))
        let (planner, planning) = await make()
        #expect(planner.makeInput(scope: .day, only: nil).tasks.first { $0.id == "local:Abgabe" }?.anchor == nil)
        await planning.markDeadline(exam, series: false)
        let input = planner.makeInput(scope: .day, only: nil)
        let task = try #require(input.tasks.first { $0.id == "local:Abgabe" })
        #expect(task.anchor == DueDate(date: exam.start, includeTime: true, calendar: calendar))
        #expect(input.days.first?.events.first { $0.title == "Klausur Statistik" }?.deadline == true)
    }

    // MARK: Planning

    @Test func planDay_validBlocks_becomeSuggestions() async throws {
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00"), estimates: #"{"taskId":"local:Fahrrad","minutes":60}"#))
        let (planner, planning) = await make()

        await planner.plan(scope: .day, anchor: today)

        #expect(planner.state == .idle)
        #expect(responder.calls.count == 1)
        #expect(responder.calls.first?.schema == "day_plan")
        let suggestion = try #require(planning.days.first?.suggestions.first)
        #expect(suggestion.taskKey == "local:Fahrrad")
        #expect(suggestion.startMinutes == 14 * 60)
        #expect(suggestion.title == "Fahrrad")
        #expect(planning.suggestionBatches.first?.risks == ["Knapp"])
        #expect(planning.suggestionBatches.first?.estimates == ["local:Fahrrad": 60])
        #expect(calendarStore.storedEvents.isEmpty)
    }

    @Test func planDay_inputContainsSelectedTasksAsJSON() async throws {
        responder.enqueue(Self.dayAnswer(""))
        let (planner, _) = await make()
        await planner.plan(scope: .day, anchor: today)
        guard case .user(let text) = try #require(responder.calls.first?.input.first) else {
            Issue.record("expected the input as a user message")
            return
        }
        #expect(text.contains("\"id\":\"local:Fahrrad\""))
        #expect(text.contains("\"id\":\"github:Login\""))
        // Due on the 20th: inside the three-day window (proposal 2026-11-18).
        #expect(text.contains("\"id\":\"local:Abgabe\""))
    }

    @Test func planDay_violations_retriedOnce_thenUnscheduled() async throws {
        calendarStore.storedEvents = [event("Meeting", 18, 14, 15)]
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00") + "," + Self.block("github:Login", "16:00")))
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:30") + "," + Self.block("github:Login", "16:00")))
        let (planner, planning) = await make()

        await planner.plan(scope: .day, anchor: today)

        #expect(responder.calls.count == 2)
        let retry = try #require(responder.calls.last?.input)
        #expect(retry.count == 3)
        guard case .user(let violations) = retry[2] else {
            Issue.record("expected the violations as a user message")
            return
        }
        #expect(violations.contains("local:Fahrrad"))
        #expect(planning.days.first?.suggestions.map(\.taskKey) == ["github:Login"])
        let unscheduled = try #require(planning.suggestionBatches.first?.unscheduled.first)
        #expect(unscheduled.taskKey == "local:Fahrrad")
        #expect(unscheduled.reason == PlanViolation.Reason.overlapsEvent.text)
    }

    @Test func plan_invalidJSON_fails_withoutSuggestions() async {
        responder.enqueue("kein JSON")
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        #expect(planner.state == .failed(AIPlanner.invalidAnswerMessage))
        #expect(planning.suggestionBatches.isEmpty)
    }

    @Test func plan_streamFails_showsErrorMessage() async {
        let (planner, _) = await make()
        await planner.plan(scope: .day, anchor: today)
        #expect(planner.state == .failed(ChatGPTError.incomplete.userMessage))
    }

    @Test func plan_nothingToPlan_sendsNothing() async {
        local.tasks = []
        github.tasks = []
        let (planner, _) = await make()
        await planner.plan(scope: .day, anchor: today)
        #expect(responder.calls.isEmpty)
        #expect(planner.notice == AIPlanner.nothingToPlanMessage)
    }

    @Test func planWeek_onlyFutureDays_periodSchema() async throws {
        responder.enqueue(#"{"assignments":[{"taskId":"local:Abgabe","day":"2026-11-19","reason":"r"}],"unscheduled":[],"risks":[],"estimates":[]}"#)
        let (planner, planning) = await make(scope: .week)
        await planner.plan(scope: .week, anchor: today)
        #expect(responder.calls.first?.schema == "period_plan")
        guard case .user(let text) = try #require(responder.calls.first?.input.first) else { return }
        #expect(!text.contains("2026-11-16"))
        #expect(text.contains("2026-11-18"))
        #expect(planning.days.first { $0.day == PlanDay(year: 2026, month: 11, day: 19) }?.suggestions.map(\.taskKey) == ["local:Abgabe"])
    }

    // MARK: Accepting

    @Test func acceptDaySuggestion_createsBlockInPlanCalendar() async throws {
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00", 90), estimates: #"{"taskId":"local:Fahrrad","minutes":90}"#))
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        let suggestion = try #require(planning.days.first?.suggestions.first)

        await planner.accept(suggestion)

        let block = try #require(calendarStore.storedEvents.first)
        #expect(block.calendarID == "plan")
        #expect(block.start == at(18, 14))
        #expect(block.end == at(18, 15, 30))
        #expect(planning.days.first?.suggestions.isEmpty == true)
        #expect(planStore.assignment(for: TaskID(source: .local, rawValue: "Fahrrad")) == today)
        // The estimate is stored locally on acceptance.
        #expect(local.appliedEdits.last.map { if case .set(90) = $0.edit.estimateMinutes { true } else { false } } == true)
    }

    @Test func accept_githubTask_doesNotWriteEstimateToSource() async throws {
        responder.enqueue(Self.dayAnswer(Self.block("github:Login", "14:00"), estimates: #"{"taskId":"github:Login","minutes":60}"#))
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        await planner.accept(try #require(planning.days.first?.suggestions.first))
        #expect(github.appliedEdits.isEmpty)
        #expect(calendarStore.storedEvents.count == 1)
    }

    @Test func accept_staleSuggestion_overNewEvent_rejected() async throws {
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00")))
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        let suggestion = try #require(planning.days.first?.suggestions.first)
        calendarStore.storedEvents = [event("Neu", 18, 14, 15)]

        await planner.accept(suggestion)

        #expect(!calendarStore.storedEvents.contains { $0.calendarID == "plan" })
        #expect(planner.notice?.contains(PlanViolation.Reason.overlapsEvent.text) == true)
        #expect(planning.days.first?.suggestions.isEmpty == true)
        #expect(planning.suggestionBatches.first?.unscheduled.map(\.taskKey) == ["local:Fahrrad"])
    }

    @Test func accept_missingPlanCalendar_showsError() async throws {
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00")))
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        let suggestion = try #require(planning.days.first?.suggestions.first)
        calendarStore.calendars = []

        await planner.accept(suggestion)

        #expect(planner.notice != nil)
        #expect(planning.days.first?.suggestions.map(\.id) == [suggestion.id])
    }

    @Test func acceptAll_week_assignsDays_keepsExistingAssignments() async throws {
        planStore.assign(TaskID(source: .local, rawValue: "Fahrrad"), to: today)
        responder.enqueue(#"{"assignments":[{"taskId":"local:Abgabe","day":"2026-11-19","reason":"r"},{"taskId":"github:Login","day":"2026-11-18","reason":"r"}],"unscheduled":[],"risks":[],"estimates":[]}"#)
        let (planner, planning) = await make(scope: .week)
        await planner.plan(scope: .week, anchor: today)

        await planner.acceptAll()

        #expect(planStore.assignment(for: TaskID(source: .local, rawValue: "Abgabe")) == PlanDay(year: 2026, month: 11, day: 19))
        #expect(planStore.assignment(for: TaskID(source: .github, rawValue: "Login")) == today)
        #expect(planStore.assignment(for: TaskID(source: .local, rawValue: "Fahrrad")) == today)
        #expect(planning.suggestionBatches.allSatisfy { $0.suggestions.isEmpty })
    }

    @Test func acceptAll_partialFailure_keepsRest_reportsCount() async throws {
        responder.enqueue(#"{"assignments":[{"taskId":"local:Abgabe","day":"2026-11-19","reason":"r"},{"taskId":"github:Login","day":"2026-11-18","reason":"r"}],"unscheduled":[],"risks":[],"estimates":[]}"#)
        let (planner, planning) = await make(scope: .week)
        await planner.plan(scope: .week, anchor: today)
        // Meanwhile Login got a work day elsewhere: its suggestion is stale.
        planStore.assign(TaskID(source: .github, rawValue: "Login"), to: PlanDay(year: 2026, month: 11, day: 20))

        await planner.acceptAll()

        #expect(planStore.assignment(for: TaskID(source: .local, rawValue: "Abgabe")) == PlanDay(year: 2026, month: 11, day: 19))
        #expect(planStore.assignment(for: TaskID(source: .github, rawValue: "Login")) == PlanDay(year: 2026, month: 11, day: 20))
        #expect(planner.notice == "1 Vorschlag übernommen, 1 passt nicht mehr.")
        #expect(planning.suggestionBatches.first?.unscheduled.map(\.taskKey) == ["github:Login"])
    }

    @Test func acceptAll_taskWithFutureBlocks_noSilentSkip() async throws {
        let abgabe = TaskID(source: .local, rawValue: "Abgabe")
        let task = try #require(local.tasks.first { $0.id == abgabe })
        try blocks.createBlock(for: task, start: at(21, 9), minutes: 60)
        planStore.unassign(abgabe)
        responder.enqueue(#"{"assignments":[{"taskId":"local:Abgabe","day":"2026-11-19","reason":"r"}],"unscheduled":[],"risks":[],"estimates":[]}"#)
        let (planner, planning) = await make(scope: .week)
        await planner.plan(scope: .week, anchor: today)
        #expect(planning.days.contains { !$0.suggestions.isEmpty })

        await planner.acceptAll()

        #expect(planning.pendingBlockDecision == nil)
        #expect(planStore.assignment(for: abgabe) == PlanDay(year: 2026, month: 11, day: 19))
        #expect(calendarStore.storedEvents.first?.start == at(19, 9))
    }

    @Test func dismiss_removesSuggestion() async throws {
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00") + "," + Self.block("github:Login", "16:00")))
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        let first = try #require(planning.days.first?.suggestions.first)

        await planner.dismiss(first)

        #expect(planning.days.first?.suggestions.map(\.taskKey) == ["github:Login"])
        #expect(calendarStore.storedEvents.isEmpty)
        await planner.dismissAll()
        #expect(planning.suggestionBatches.isEmpty)
    }

    @Test func planWeek_keepsOpenDaySuggestions() async throws {
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00")))
        responder.enqueue(#"{"assignments":[{"taskId":"local:Abgabe","day":"2026-11-19","reason":"r"}],"unscheduled":[],"risks":[],"estimates":[]}"#)
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        await planner.plan(scope: .week, anchor: today)
        let all = planning.suggestionBatches.flatMap(\.suggestions).map(\.taskKey)
        #expect(Set(all) == ["local:Fahrrad", "local:Abgabe"])
    }

    @Test func dismissOne_canBeUndone() async throws {
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00")))
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        let block = try #require(planning.days.first?.suggestions.first)
        await planner.dismiss(block)
        #expect(planner.dismissedCount == 1)
        #expect(planning.days.first?.suggestions.isEmpty == true)
        await planner.undoDismissAll()
        #expect(planning.days.first?.suggestions.map(\.id) == [block.id])
    }

    @Test func acceptOne_canBeUndone() async throws {
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00")))
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        let block = try #require(planning.days.first?.suggestions.first)
        await planner.accept(block)
        #expect(calendarStore.storedEvents.count == 1)
        #expect(planner.lastAcceptAll?.count == 1)
        await planner.undoAcceptAll()
        #expect(calendarStore.storedEvents.isEmpty)
        #expect(planning.days.first?.suggestions.map(\.id) == [block.id])
    }

    @Test func dismissAll_canBeUndone() async throws {
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00")))
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        await planner.dismissAll()
        #expect(planning.suggestionBatches.isEmpty)
        await planner.undoDismissAll()
        #expect(planning.days.first?.suggestions.map(\.taskKey) == ["local:Fahrrad"])
    }

    static func extendedAnswer() -> String {
        #"{"blocks":[{"taskId":"local:Fahrrad","start":"18:00","minutes":60,"reason":"abends"},{"taskId":"github:Login","start":"14:00","minutes":60,"reason":"r"}],"unscheduled":[],"risks":[],"estimates":[],"summary":"Heute ist es eng.","moves":[],"dayChanges":[{"day":"2026-11-18","start":"09:00","end":"20:00","reason":"Sonst wird Fahrrad nicht fertig."}]}"#
    }

    @Test func planDay_dayChange_becomesSuggestion_withDependentBlock() async throws {
        responder.enqueue(Self.extendedAnswer())
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        let suggestions = try #require(planning.days.first?.suggestions)
        let change = try #require(suggestions.first { $0.kind == .dayChange })
        #expect(change.startMinutes == 540)
        #expect(change.endMinutes == 1200)
        #expect(suggestions.first { $0.taskKey == "local:Fahrrad" }?.dependsOn == change.id)
        #expect(suggestions.first { $0.taskKey == "github:Login" }?.dependsOn == nil)
        #expect(planning.suggestionBatches.first?.summary == "Heute ist es eng.")
    }

    @Test func planDay_inputContainsLaterDays() async throws {
        responder.enqueue(Self.dayAnswer(""))
        let (planner, _) = await make()
        await planner.plan(scope: .day, anchor: today)
        guard case .user(let text) = try #require(responder.calls.first?.input.first) else { return }
        #expect(text.contains("\"laterDays\""))
        // The next two working days only (Thu 19th, Fri 20th).
        #expect(text.contains("2026-11-20"))
        #expect(!text.contains("2026-11-23"))
    }

    @Test func dependentBlock_waitsForDayChange_thenAcceptAllAppliesBoth() async throws {
        responder.enqueue(Self.extendedAnswer())
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        let block = try #require(planning.days.first?.suggestions.first { $0.taskKey == "local:Fahrrad" })
        await planner.accept(block)
        #expect(planner.notice == AIPlanner.needsLongerDayMessage)
        #expect(calendarStore.storedEvents.isEmpty)

        await planner.acceptAll()
        #expect(planStore.override(on: today) == .hours(WorkHours(startMinutes: 540, endMinutes: 1200)))
        #expect(calendarStore.storedEvents.map(\.start).sorted() == [at(18, 14), at(18, 18)])

        await planner.undoAcceptAll()
        #expect(planStore.override(on: today) == nil)
        #expect(calendarStore.storedEvents.isEmpty)
        #expect(planning.days.first?.suggestions.count == 3)
    }

    @Test func dismissDayChange_movesDependentBlocksToUnscheduled() async throws {
        responder.enqueue(Self.extendedAnswer())
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        let change = try #require(planning.days.first?.suggestions.first { $0.kind == .dayChange })
        await planner.dismiss(change)
        #expect(planning.days.first?.suggestions.map(\.taskKey) == ["github:Login"])
        #expect(planning.suggestionBatches.first?.unscheduled.first?.reason == PlanViolation.Reason.outsideWorkHours.text)
    }

    @Test func acceptMove_setsTheNewWorkDay() async throws {
        planStore.assign(TaskID(source: .local, rawValue: "Fahrrad"), to: today)
        responder.enqueue(#"{"blocks":[],"unscheduled":[],"risks":[],"estimates":[],"summary":"Zu voll.","moves":[{"taskId":"local:Fahrrad","day":"2026-11-19","reason":"kann warten"}],"dayChanges":[]}"#)
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        let move = try #require(planning.days.first?.suggestions.first { $0.kind == .move })
        #expect(move.fromDay == today)
        await planner.accept(move)
        #expect(planStore.assignment(for: TaskID(source: .local, rawValue: "Fahrrad")) == PlanDay(year: 2026, month: 11, day: 19))
    }

    @Test func fittingP1_isAddedLocally_whenTheModelLeavesItOut() async throws {
        local.tasks.append(TaskItem(id: TaskID(source: .local, rawValue: "Wichtig"), title: "Wichtig", notes: nil, due: nil,
                                    priority: .p1, estimateMinutes: 15, isCompleted: false,
                                    container: TaskContainer(id: "local", name: "Lokal", colorHex: nil), url: nil, version: "1",
                                    editableFields: []))
        responder.enqueue(Self.dayAnswer(""))
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        let added = try #require(planning.days.first?.suggestions.first { $0.taskKey == "local:Wichtig" })
        #expect(added.reason == AIPlanner.addedLocallyReason)
        #expect(added.minutes == 15)
        #expect(added.startMinutes == 600)
    }

    @Test func overdueRecurringP1_isPlannedWithItsEffort() async throws {
        let access = FakeAccessStore()
        access.openRecords = [ReminderRecord(id: "blumen", title: "Blumen gießen", notes: nil, due: DueDate(year: 2026, month: 11, day: 15),
                                             ekPriority: 1, isCompleted: false, listID: "l", lastModified: nil,
                                             recurrence: Recurrence(rule: .daily(interval: 3), start: PlanDay(year: 2026, month: 11, day: 15),
                                                                    end: nil, count: nil))]
        access.accessState = .fullAccess
        var reminder = makeTask("blumen", source: .reminders, due: DueDate(year: 2026, month: 11, day: 15))
        reminder.priority = .p1
        await taskList.register(FakeTaskProvider(source: .reminders, tasks: [reminder]))
        RecurringEffortStore(context: container.mainContext).setForAll(15, reminderID: "blumen", from: PlanDay(year: 2026, month: 11, day: 15))
        responder.enqueue(Self.dayAnswer(""))
        let (planner, planning) = await make(reminderStore: access)
        await planner.plan(scope: .day, anchor: today)
        guard case .user(let text) = try #require(responder.calls.first?.input.first) else { return }
        #expect(text.contains("\"id\":\"reminders:blumen\""))
        let block = try #require(planning.days.first?.suggestions.first { $0.taskKey == "reminders:blumen" })
        #expect(block.minutes == 15)
    }

    @Test func longerDaysNever_dropsDayChanges() async throws {
        responder.enqueue(Self.extendedAnswer())
        let (planner, planning) = await make()
        planner.longerDays = { .never }
        await planner.plan(scope: .day, anchor: today)
        #expect(!(planning.days.first?.suggestions.contains { $0.kind == .dayChange } ?? true))
    }

    @Test func suggestions_surviveNewPlanningModel() async throws {
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00")))
        let (planner, _) = await make()
        await planner.plan(scope: .day, anchor: today)
        let (_, reopened) = await make()
        #expect(reopened.days.first?.suggestions.map(\.taskKey) == ["local:Fahrrad"])
    }

    @Test func noCallWithoutUserAction() async {
        let transport = FakeAITransport()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ChatGPTSessionStore(store: InMemoryChatGPTCredentialStore(tokens: .valid(now: now)), transport: transport,
                                          now: { now })
        let ai = AIEnvironment(session: session, client: ChatGPTClient(session: session, transport: transport), settings: settings)
        let (_, planning) = await make()
        await ai.refreshAccount()
        await planning.reload()
        planning.scope = .week
        await planning.reload()
        planning.scope = .month
        await planning.reload()
        #expect(transport.requests.isEmpty)
        #expect(responder.calls.isEmpty)
    }
}

// MARK: Moving by hand and talking about suggestions (mockups VM1, VK1, VA1, VR1)

extension AIPlannerTests {
    private func twoBlocks() async throws -> (AIPlanner, PlanningModel, PlanSuggestion, PlanSuggestion) {
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00") + "," + Self.block("github:Login", "16:00")))
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        let all = try #require(planning.days.first?.suggestions)
        let fahrrad = try #require(all.first { $0.taskKey == "local:Fahrrad" })
        let login = try #require(all.first { $0.taskKey == "github:Login" })
        return (planner, planning, fahrrad, login)
    }

    private func current(_ planning: PlanningModel, _ id: UUID) -> PlanSuggestion? {
        planning.suggestionBatches.flatMap(\.suggestions).first { $0.id == id }
    }

    static func revision(_ reply: String, _ changes: String) -> String {
        #"{"reply":"\#(reply)","changes":[\#(changes)]}"#
    }

    static func change(_ ref: String, _ day: String = "2026-11-18", start: String?, minutes: Int?) -> String {
        let start = start.map { "\"\($0)\"" } ?? "null"
        let minutes = minutes.map(String.init) ?? "null"
        return #"{"ref":"\#(ref)","day":"\#(day)","start":\#(start),"minutes":\#(minutes)}"#
    }

    @Test func moveByHand_staysSuggestion_andRemembersTheAIPosition() async throws {
        let (planner, planning, fahrrad, _) = try await twoBlocks()
        let error = await planner.moveSuggestion(fahrrad, day: today, start: 11 * 60, minutes: 30)
        #expect(error == nil)
        let moved = try #require(current(planning, fahrrad.id))
        #expect(moved.startMinutes == 11 * 60)
        #expect(moved.minutes == 30)
        #expect(moved.aiPosition == SuggestionPosition(kind: .block, day: today, startMinutes: 14 * 60, minutes: 60))
        #expect(moved.isMovedByUser)
        #expect(calendarStore.storedEvents.isEmpty)
        #expect(responder.calls.count == 1)  // moving by hand calls nothing (§8.4)
    }

    @Test func moveByHand_ontoAnEvent_isRefused() async throws {
        calendarStore.storedEvents = [event("Meeting", 18, 11, 12)]
        let (planner, planning, fahrrad, _) = try await twoBlocks()
        let error = await planner.moveSuggestion(fahrrad, day: today, start: 11 * 60, minutes: 60)
        #expect(error != nil)
        #expect(current(planning, fahrrad.id)?.startMinutes == 14 * 60)
        #expect(current(planning, fahrrad.id)?.isMovedByUser == false)
    }

    @Test func moveByHand_canBeReset_andAcceptUsesTheNewPlace() async throws {
        let (planner, planning, fahrrad, login) = try await twoBlocks()
        _ = await planner.moveSuggestion(fahrrad, day: today, start: 11 * 60, minutes: 60)
        await planner.resetSuggestion(try #require(current(planning, fahrrad.id)))
        #expect(current(planning, fahrrad.id)?.startMinutes == 14 * 60)
        #expect(current(planning, fahrrad.id)?.isMovedByUser == false)

        _ = await planner.moveSuggestion(login, day: today, start: 15 * 60, minutes: 60)
        await planner.acceptAll()
        #expect(calendarStore.storedEvents.map(\.start).sorted() == [at(18, 14), at(18, 15)])
    }

    @Test func moveByHand_toAnotherDay_becomesAMove() async throws {
        let (planner, planning, fahrrad, _) = try await twoBlocks()
        let tomorrow = today.adding(days: 1, calendar: calendar)
        let error = await planner.moveSuggestion(fahrrad, day: tomorrow, start: nil, minutes: nil)
        #expect(error == nil)
        let moved = try #require(current(planning, fahrrad.id))
        #expect(moved.kind == .move)
        #expect(moved.day == tomorrow)
        #expect(moved.fromDay == today)
        #expect(moved.isMovedByUser)
    }

    @Test func revise_changesOnlyReferencedSuggestions_inPlace() async throws {
        let (planner, planning, fahrrad, login) = try await twoBlocks()
        responder.enqueue(Self.revision("Getauscht.", Self.change("s1", start: "16:00", minutes: 60) + "," + Self.change("s2", start: "14:00", minutes: 60)))
        await planner.revise(fahrrad, comment: "Fahrrad später")
        #expect(responder.calls.last?.schema == "suggestion_revision")
        let newFahrrad = try #require(current(planning, fahrrad.id))
        let newLogin = try #require(current(planning, login.id))
        #expect(newFahrrad.startMinutes == 16 * 60)
        #expect(newLogin.startMinutes == 14 * 60)
        #expect(newFahrrad.previousPosition?.startMinutes == 14 * 60)
        let conversation = try #require(planning.suggestionBatches.first?.conversation)
        #expect(conversation.map(\.role) == [.user, .assistant])
        #expect(conversation.last?.text == "Getauscht.")
        #expect(conversation.last?.changes?.count == 2)
        #expect(planner.revisionError == nil)
    }

    @Test func revise_neverMovesWhatTheUserMoved_exceptTheCommentedOne() async throws {
        let (planner, planning, fahrrad, login) = try await twoBlocks()
        _ = await planner.moveSuggestion(login, day: today, start: 15 * 60 + 30, minutes: 60)
        responder.enqueue(Self.revision("Verschoben.", Self.change("s2", start: "11:00", minutes: 60) + "," + Self.change("s1", start: "11:00", minutes: 60)))
        await planner.revise(fahrrad, comment: "früher")
        #expect(current(planning, login.id)?.startMinutes == 15 * 60 + 30)
        #expect(current(planning, fahrrad.id)?.startMinutes == 11 * 60)
        #expect(planning.suggestionBatches.first?.conversation?.last?.rejected?.isEmpty == false)
    }

    @Test func revise_rejectsAChangeThatDoesNotFit() async throws {
        calendarStore.storedEvents = [event("Meeting", 18, 11, 12)]
        let (planner, planning, fahrrad, _) = try await twoBlocks()
        responder.enqueue(Self.revision("Früher.", Self.change("s1", start: "11:00", minutes: 60)))
        await planner.revise(fahrrad, comment: "früher")
        #expect(current(planning, fahrrad.id)?.startMinutes == 14 * 60)
        let answer = try #require(planning.suggestionBatches.first?.conversation?.last)
        #expect(answer.changes?.isEmpty == true)
        #expect(answer.rejected?.first?.contains("Fahrrad") == true)
    }

    @Test func revise_canBeUndone() async throws {
        let (planner, planning, fahrrad, login) = try await twoBlocks()
        let before = planning.suggestionBatches.first?.suggestions
        responder.enqueue(Self.revision("Getauscht.", Self.change("s1", start: "16:00", minutes: 60) + "," + Self.change("s2", start: "14:00", minutes: 60)))
        await planner.revise(fahrrad, comment: "tauschen")
        let batch = try #require(planning.suggestionBatches.first)
        await planner.undoRevision(of: batch.id)
        #expect(planning.suggestionBatches.first?.suggestions == before)
        #expect(current(planning, login.id)?.startMinutes == 16 * 60)
    }

    @Test func revise_sendsComment_userMoves_statusAndPreferences() async throws {
        let (planner, _, fahrrad, login) = try await twoBlocks()
        planner.preferences = { ["Mails nicht nach 18 Uhr einplanen."] }
        _ = await planner.moveSuggestion(login, day: today, start: 15 * 60 + 30, minutes: 60)
        responder.enqueue(Self.revision("Gut so.", ""))
        await planner.revise(fahrrad, comment: "Nach 18 Uhr keine Mails")
        guard case .user(let text) = try #require(responder.calls.last?.input.last) else {
            Issue.record("expected the request as a user message")
            return
        }
        #expect(text.contains("Nach 18 Uhr keine Mails"))
        #expect(text.contains("\"about\":\"s1\""))
        #expect(text.contains("\"status\":\"movedByUser\""))
        #expect(text.contains("\"aiStart\":\"16:00\""))
        #expect(responder.instructions.last?.contains("Mails nicht nach 18 Uhr einplanen.") == true)
        #expect(responder.instructions.first?.contains("Mails nicht nach 18 Uhr einplanen.") == false)
    }

    // MARK: Language

    @Test func planDay_asksForReasonsInTheAppLanguage() async throws {
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00")))
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00")))
        let (planner, _) = await make()
        await planner.plan(scope: .day, anchor: today)
        planner.language = { .english }
        await planner.plan(scope: .day, anchor: today)
        let german = try #require(responder.instructions.first)
        let english = try #require(responder.instructions.last)
        #expect(german.contains("auf Deutsch"))
        #expect(!german.contains("Englisch"))
        #expect(english.contains("auf Englisch (English)"))
        #expect(!english.contains("auf Deutsch"))
    }

    @Test func revise_repliesInTheCommentLanguage_orTheAppLanguage() async throws {
        let (planner, _, fahrrad, _) = try await twoBlocks()
        responder.enqueue(Self.revision("Gut so.", ""))
        responder.enqueue(Self.revision("Fine.", ""))
        await planner.revise(fahrrad, comment: "früher")
        planner.language = { .english }
        await planner.revise(fahrrad, comment: "earlier")
        let german = try #require(responder.instructions.dropLast().last)
        let english = try #require(responder.instructions.last)
        #expect(german.contains("in der Sprache des Kommentars"))
        #expect(german.contains("sonst auf Deutsch"))
        #expect(english.contains("in der Sprache des Kommentars"))
        #expect(english.contains("sonst auf Englisch (English)"))
        #expect(!english.contains("auf Deutsch"))
    }

    @Test func replan_keepsSuggestionsTheUserMoved() async throws {
        let (planner, planning, fahrrad, _) = try await twoBlocks()
        _ = await planner.moveSuggestion(fahrrad, day: today, start: 11 * 60, minutes: 60)
        responder.enqueue(Self.dayAnswer(Self.block("github:Login", "15:00")))
        await planner.plan(scope: .day, anchor: today)
        guard case .user(let text) = try #require(responder.calls.last?.input.first) else { return }
        #expect(!text.contains("\"id\":\"local:Fahrrad\""))
        let all = planning.suggestionBatches.flatMap(\.suggestions)
        #expect(all.first { $0.id == fahrrad.id }?.startMinutes == 11 * 60)
        #expect(all.contains { $0.taskKey == "github:Login" && $0.startMinutes == 15 * 60 })
    }

    @Test func oldStoredBatch_stillDecodes() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","scope":"day","days":[{"year":2026,"month":11,"day":18}],"createdAt":0,"suggestions":[{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"block","taskKey":"local:Fahrrad","title":"Fahrrad","day":{"year":2026,"month":11,"day":18},"startMinutes":840,"minutes":60,"reason":"r"}],"unscheduled":[],"risks":[],"estimates":{}}"#
        let batch = try JSONDecoder().decode(SuggestionBatch.self, from: Data(json.utf8))
        #expect(batch.suggestions.first?.isMovedByUser == false)
        #expect(batch.conversation == nil)
    }

    @Test func acceptAfterRevision_cannotBeUndoneIntoADuplicate() async throws {
        let (planner, planning, fahrrad, _) = try await twoBlocks()
        responder.enqueue(Self.revision("Später.", Self.change("s1", start: "15:00", minutes: 60)))
        await planner.revise(fahrrad, comment: "später")
        await planner.accept(try #require(current(planning, fahrrad.id)))
        #expect(planning.suggestionBatches.first?.revisionUndo == nil)
        await planner.undoRevision(of: try #require(planning.suggestionBatches.first?.id))
        #expect(current(planning, fahrrad.id) == nil)
    }

    @Test func dismissThenAccept_undoDismissDoesNotBringTheAcceptedBack() async throws {
        let (planner, planning, fahrrad, login) = try await twoBlocks()
        await planner.dismiss(fahrrad)
        await planner.accept(try #require(current(planning, login.id)))
        await planner.undoDismissAll()
        #expect(current(planning, login.id) == nil)
        #expect(calendarStore.storedEvents.count == 1)
    }

    @Test func replan_dropsMovedSuggestionsOfFinishedTasks() async throws {
        let (planner, planning, fahrrad, _) = try await twoBlocks()
        _ = await planner.moveSuggestion(fahrrad, day: today, start: 11 * 60, minutes: 60)
        await taskList.complete(try #require(fahrrad.taskID))
        responder.enqueue(Self.dayAnswer(Self.block("github:Login", "15:00")))
        await planner.plan(scope: .day, anchor: today)
        #expect(planning.suggestionBatches.flatMap(\.suggestions).first { $0.id == fahrrad.id } == nil)
    }

    @Test func blockMovedToAnotherDay_acceptsAsWorkDayWithoutBlock() async throws {
        let (planner, planning, fahrrad, _) = try await twoBlocks()
        let tomorrow = today.adding(days: 1, calendar: calendar)
        _ = await planner.moveSuggestion(fahrrad, day: tomorrow, start: nil, minutes: nil)
        await planner.accept(try #require(current(planning, fahrrad.id)))
        #expect(planStore.assignment(for: try #require(fahrrad.taskID)) == tomorrow)
        #expect(calendarStore.storedEvents.isEmpty)
    }

    @Test func longerDay_isDropped_whenNoBlockNeedsItAnymore() async throws {
        responder.enqueue(Self.extendedAnswer())
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        let late = try #require(planning.days.first?.suggestions.first { $0.taskKey == "local:Fahrrad" })
        #expect(late.dependsOn != nil)
        _ = await planner.moveSuggestion(late, day: today, start: 15 * 60, minutes: 60)
        #expect(planning.suggestionBatches.flatMap(\.suggestions).contains { $0.kind == .dayChange } == false)
    }

    @Test func revise_weekPlan_movesAnAssignmentToAnotherDayOfThePlan() async throws {
        responder.enqueue(#"{"assignments":[{"taskId":"local:Abgabe","day":"2026-11-19","reason":"r"}],"unscheduled":[],"risks":[],"estimates":[]}"#)
        let (planner, planning) = await make(scope: .week)
        await planner.plan(scope: .week, anchor: today)
        let assignment = try #require(planning.suggestionBatches.flatMap(\.suggestions).first { $0.taskKey == "local:Abgabe" })
        responder.enqueue(Self.revision("Freitag.", Self.change("s1", "2026-11-20", start: nil, minutes: nil)))
        await planner.revise(assignment, comment: "lieber Freitag")
        let changed = try #require(current(planning, assignment.id))
        #expect(changed.day == PlanDay(year: 2026, month: 11, day: 20))
        #expect(changed.kind == .assignment)
        #expect(changed.previousPosition?.day == PlanDay(year: 2026, month: 11, day: 19))
    }

    @Test func timeAndDayParsing_rejectsValuesOutOfRange() {
        #expect(AIPlanner.minutes("09:30") == 570)
        #expect(AIPlanner.minutes("24:00") == 1440)
        #expect(AIPlanner.minutes("99:00") == nil)
        #expect(AIPlanner.minutes("10:75") == nil)
        #expect(AIPlanner.planDay("2026-11-18") == PlanDay(year: 2026, month: 11, day: 18))
        #expect(AIPlanner.planDay("2026-13-45") == nil)
        #expect(AIPlanner.planDay("2026-02-30") == nil)
    }

    @Test func plan_cutStreamWithoutCompletion_isNotStored() async throws {
        responder.enqueueEvents([.textDelta(Self.dayAnswer(Self.block("local:Fahrrad", "14:00")))])
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        #expect(planning.suggestionBatches.isEmpty)
        #expect(planner.state != .idle)
    }

    @Test func newPlan_dropsUndoOfEarlierActions() async throws {
        let (planner, planning, fahrrad, _) = try await twoBlocks()
        await planner.dismiss(fahrrad)
        #expect(planner.dismissedCount == 1)
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00")))
        await planner.plan(scope: .day, anchor: today)
        #expect(planner.lastDismissed.isEmpty)
        #expect(planning.suggestionBatches.count == 1)
    }

    // MARK: Planning tomorrow (plan-tomorrow, step 5)

    private var tomorrow: PlanDay { PlanDay(year: 2026, month: 11, day: 19) }

    /// The JSON the model got in the last planning call.
    private func lastInputText() -> String {
        guard case .user(let text)? = responder.calls.last?.input.first else { return "" }
        return text
    }

    @Test func planTomorrow_usesRecurringEffortOfPlannedDay() async throws {
        let reminderStore = FakeAccessStore()
        reminderStore.accessState = .fullAccess
        reminderStore.openRecords = [ReminderRecord(id: "k", title: "Training", notes: nil, due: DueDate(year: 2026, month: 11, day: 19),
                                                    ekPriority: 0, isCompleted: false, listID: "l", lastModified: nil,
                                                    recurrence: Recurrence(rule: .daily(interval: 1), start: today, end: nil, count: nil))]
        await taskList.register(FakeTaskProvider(source: .reminders,
                                                 tasks: [makeTask("k", source: .reminders, due: DueDate(year: 2026, month: 11, day: 19))]))
        let efforts = RecurringEffortStore(context: container.mainContext)
        efforts.setForAll(30, reminderID: "k", from: today)
        efforts.setForDay(90, reminderID: "k", day: tomorrow)
        let (planner, planning) = await make(reminderStore: reminderStore)
        planning.anchor = tomorrow
        await planning.reload()

        let input = planner.makeInput(scope: .day, only: nil)

        #expect(input.tasks.first { $0.id == "reminders:k" }?.minutes == 90)
    }

    @Test func planTomorrow_keepsTodaysBatch() async throws {
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00")))
        responder.enqueue(Self.dayAnswer(Self.block("local:Abgabe", "09:00")))
        let (planner, _) = await make()
        await planner.plan(scope: .day, anchor: today)
        await planner.plan(scope: .day, anchor: tomorrow)

        let days = Set(store.batches().flatMap(\.suggestions).map(\.day))
        #expect(days == [today, tomorrow])
    }

    @Test func planTomorrow_includesTasksWithOpenSuggestionForToday() async throws {
        // Decision 7: an open suggestion for today does not keep a task out of tomorrow's plan.
        responder.enqueue(Self.dayAnswer(Self.block("local:Abgabe", "14:00")))
        responder.enqueue(Self.dayAnswer(""))
        let (planner, _) = await make()
        await planner.plan(scope: .day, anchor: today)
        await planner.plan(scope: .day, anchor: tomorrow)
        #expect(lastInputText().contains("\"id\":\"local:Abgabe\""))
    }

    @Test func planToday_excludesTasksWithOpenSuggestionForAnotherFutureDay() async throws {
        responder.enqueue(Self.dayAnswer(Self.block("local:Abgabe", "09:00")))
        responder.enqueue(Self.dayAnswer(""))
        let (planner, _) = await make()
        await planner.plan(scope: .day, anchor: tomorrow)
        await planner.plan(scope: .day, anchor: today)
        #expect(!lastInputText().contains("\"id\":\"local:Abgabe\""))
        #expect(lastInputText().contains("\"id\":\"local:Fahrrad\""))
    }

    @Test func planTomorrow_carriesTodaysLeftovers_onlyWhenTodayIsOver() async throws {
        // 10:00: Fahrrad is due today and can still be done today.
        responder.enqueue(Self.dayAnswer(""))
        let (morningPlanner, _) = await make()
        await morningPlanner.plan(scope: .day, anchor: tomorrow)
        #expect(!lastInputText().contains("\"id\":\"local:Fahrrad\""))

        // 18:40: today's work time is over; Fahrrad goes along and its block tomorrow is valid.
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "09:00")))
        let evening = at(18, 18, 40)
        let (planner, planning) = await make(now: { evening })
        await planner.plan(scope: .day, anchor: tomorrow)
        #expect(lastInputText().contains("\"id\":\"local:Fahrrad\""))
        let suggestion = try #require(planning.days.first?.suggestions.first { $0.taskKey == "local:Fahrrad" })
        #expect(responder.calls.count == 2)  // no retry: nothing was rejected

        await planner.accept(suggestion)

        #expect(planner.notice == nil)
        #expect(calendarStore.storedEvents.contains { $0.start == at(19, 9) })
    }

    @Test func replanToday_keepsTasksTheReplacedPlanSuggestedToMove() async throws {
        // The day batch a new plan replaces must not keep its own tasks out (its move points to another day).
        let move = PlanSuggestion(id: UUID(), kind: .move, taskKey: "local:Fahrrad", title: "Fahrrad",
                                  day: PlanDay(year: 2026, month: 11, day: 20), startMinutes: nil, minutes: nil, reason: "r",
                                  fromDay: today)
        store.replace(with: SuggestionBatch(id: UUID(), scope: .day, days: [today], createdAt: testNow(), suggestions: [move],
                                            unscheduled: [], risks: [], estimates: [:]))
        responder.enqueue(Self.dayAnswer(""))
        let (planner, _) = await make()
        await planner.plan(scope: .day, anchor: today)
        #expect(lastInputText().contains("\"id\":\"local:Fahrrad\""))
    }

    @Test func planLaterDay_inTheEvening_doesNotCarryTodaysLeftovers() async throws {
        // Decision 6: leftovers go to the next planning day (Thursday), not to Friday.
        responder.enqueue(Self.dayAnswer(""))
        let evening = at(18, 18, 40)
        let (planner, _) = await make(now: { evening })
        await planner.plan(scope: .day, anchor: PlanDay(year: 2026, month: 11, day: 20))
        #expect(!lastInputText().contains("\"id\":\"local:Fahrrad\""))
    }

    @Test func contextMenuPlanAnchor_usesShownFutureDay() {
        #expect(TaskContextMenu.aiPlanAnchor(shownDay: tomorrow, today: today) == tomorrow)
        #expect(TaskContextMenu.aiPlanAnchor(shownDay: PlanDay(year: 2026, month: 11, day: 17), today: today) == today)
        #expect(TaskContextMenu.aiPlanAnchor(shownDay: nil, today: today) == today)
    }

    @Test func instructions_dayPlan_explainPlannedDay() {
        let text = AIPlanner.instructions(.day, language: .app)
        #expect(text.contains("days[0]"))
    }

    // MARK: Side findings (plan-tomorrow, step 6)

    /// A day batch with a block for Fahrrad today and a week batch with a work day for Abgabe on Thursday.
    private func dayAndWeekBatches() {
        let block = PlanSuggestion(id: UUID(), kind: .block, taskKey: "local:Fahrrad", title: "Fahrrad", day: today,
                                   startMinutes: 14 * 60, minutes: 60, reason: "r")
        let assignment = PlanSuggestion(id: UUID(), kind: .assignment, taskKey: "local:Abgabe", title: "Abgabe", day: tomorrow,
                                        startMinutes: nil, minutes: nil, reason: "r")
        store.replace(with: SuggestionBatch(id: UUID(), scope: .week, days: (16...22).map { PlanDay(year: 2026, month: 11, day: $0) },
                                            createdAt: testNow(), suggestions: [assignment], unscheduled: [], risks: [], estimates: [:]))
        store.replace(with: SuggestionBatch(id: UUID(), scope: .day, days: [today], createdAt: testNow(), suggestions: [block],
                                            unscheduled: [], risks: [], estimates: [:]))
    }

    private var weekSuggestions: [PlanSuggestion] {
        store.batches().filter { $0.scope == .week }.flatMap(\.suggestions)
    }

    @Test func acceptAll_dayScope_leavesWeekBatchUntouched() async throws {
        dayAndWeekBatches()
        let (planner, _) = await make()

        await planner.acceptAll(scope: .day)

        #expect(calendarStore.storedEvents.contains { $0.start == at(18, 14) })
        #expect(planStore.assignment(for: TaskID(source: .local, rawValue: "Abgabe")) == nil)
        #expect(weekSuggestions.map(\.taskKey) == ["local:Abgabe"])

        await planner.undoAcceptAll()

        #expect(weekSuggestions.map(\.taskKey) == ["local:Abgabe"])
        #expect(store.batches().filter { $0.scope == .day }.flatMap(\.suggestions).map(\.taskKey) == ["local:Fahrrad"])
    }

    @Test func dismissAll_dayScope_leavesWeekBatchUntouched() async throws {
        dayAndWeekBatches()
        let (planner, _) = await make()

        await planner.dismissAll(scope: .day)

        #expect(weekSuggestions.map(\.taskKey) == ["local:Abgabe"])
        #expect(store.batches().filter { $0.scope == .day }.isEmpty)
        #expect(planner.dismissedCount == 1)
    }
}
