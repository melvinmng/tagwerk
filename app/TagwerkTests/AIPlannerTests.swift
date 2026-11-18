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

    private func make(scope: PlanScope = .day) async -> (AIPlanner, PlanningModel) {
        await taskList.reload()
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     suggestions: store, now: testNow, calendar: calendar)
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
        #expect(!text.contains("Abgabe"))
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
        #expect(unscheduled.reason == PlanViolation.Reason.overlapsEvent.rawValue)
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
        #expect(planner.notice?.contains(PlanViolation.Reason.overlapsEvent.rawValue) == true)
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

    @Test func dismissAll_canBeUndone() async throws {
        responder.enqueue(Self.dayAnswer(Self.block("local:Fahrrad", "14:00")))
        let (planner, planning) = await make()
        await planner.plan(scope: .day, anchor: today)
        await planner.dismissAll()
        #expect(planning.suggestionBatches.isEmpty)
        await planner.undoDismissAll()
        #expect(planning.days.first?.suggestions.map(\.taskKey) == ["local:Fahrrad"])
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
