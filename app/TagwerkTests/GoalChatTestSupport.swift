import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The shared set-up of the tests of the chat "Ziele planen": settings with the consent on, a goal store, the fake model and the goal
/// tools, wired as in `AppEnvironment`. All data is invented.
@MainActor
struct GoalChatHarness {
    let container: ModelContainer
    let settings: AppSettings
    let goals: GoalStore
    let calendarStore = FakeCalendarStore()
    let taskList: TaskListModel
    let responder = FakePlanResponder()
    let calendar = testCalendar()
    /// Body values that must never appear in what goes back to the model: resting energy ~1,780 kcal for these.
    static let body = BodyProfileValues(heightCm: 180, birthYear: 1992, sex: .male)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.planCalendarID = "plan"
        settings.goalPlanningConsent = true
        goals = GoalStore(context: container.mainContext, settings: settings, calendar: testCalendar(), now: testNow)
        goals.migrateIfNeeded()
        taskList = TaskListModel(providers: [FakeTaskProvider(source: .local, tasks: [])], now: testNow, calendar: testCalendar())
    }

    var today: PlanDay { PlanDay(date: testNow(), calendar: calendar) }

    /// A package with every group, so the tests can switch groups off.
    var package: GoalDataSummary {
        let days = (0..<28).map { _ in GoalDataDay(eatenKcal: 2350, proteinGrams: 112, fiberGrams: 21, waterMilliliters: 1700, activeKcal: 410, steps: 7240) }
        return GoalDataSummary.make(periodDays: 28, days: days, profile: .resolved(health: .empty, typed: Self.body), year: 2026,
                                    weight: GoalDataWeight(kilograms: 82.1, trendKgPerWeek: -0.3), workoutMinutesPerWeek: 130,
                                    plan: goals.current(on: today))
    }

    var session: GoalPlanningSession {
        GoalPlanningSession(package: package, guardInput: GoalGuardInput(body: Self.body, weightKg: 82.1, meanActiveKcal: 400, year: 2026))
    }

    func makeTools() -> GoalChatTools {
        let settings = settings, goals = goals, today = today
        return GoalChatTools(hasConsent: { settings.goalPlanningConsent },
                             currentPlan: { goals.current(on: today) ?? GoalPlan(validFrom: today, kcal: 2300, waterMilliliters: 2000, stepsPerDay: 8000, workoutMinutesPerWeek: 150) },
                             adopt: { goals.adopt($0) }, today: { today })
    }

    func makeModel(responder override: ResponseStreaming? = nil) async -> (AssistantModel, GoalChatTools, ChatStore) {
        await taskList.reload()
        let planStore = PlanStore(context: container.mainContext)
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     now: testNow, calendar: calendar)
        await planning.reload()
        let tools = AppTools(taskList: taskList, planning: planning, planner: nil, events: { _ in [] })
        let store = ChatStore(context: container.mainContext)
        let model = AssistantModel(responder: override ?? responder, tools: tools, model: { "gpt-test" }, store: store,
                                   planning: planning, now: testNow)
        model.language = { .german }
        let goalTools = makeTools()
        model.goalTools = goalTools
        let settings = settings
        model.hasGoalConsent = { settings.goalPlanningConsent }
        model.watchGoalConsent { settings.goalPlanningConsent }
        return (model, goalTools, store)
    }

    static let readCall = StreamEvent.functionCall(callID: "g1", name: "get_goal_data", arguments: "{}")

    static func nutritionCall(id: String = "n1", kcal: String = "1800", protein: String = "150", carbs: String = "165",
                                      fat: String = "60", pace: String = "-0.3", reason: String = "Ruhiges Tempo") -> StreamEvent {
        .functionCall(callID: id, name: "propose_nutrition_goals",
                      arguments: #"{"kcal":\#(kcal),"protein_g":\#(protein),"carbs_g":\#(carbs),"fat_g":\#(fat),"fiber_g":null,"sugar_limit_g":null,"water_ml":null,"target_weight_kg":78.0,"pace_kg_per_week":\#(pace),"reason":"\#(reason)"}"#)
    }

    static let activityCall = StreamEvent.functionCall(
        callID: "a1", name: "propose_activity_goals",
        arguments: #"{"steps_per_day":9000,"workout_minutes_per_week":180,"active_kcal_per_day":null,"reason":"Mehr Bewegung"}"#)

    func storedText(_ store: ChatStore) -> String {
        (try? String(decoding: JSONEncoder().encode(store.history(for: ChatStore.goalsKey)), as: UTF8.self)) ?? ""
    }

    func openGoals(_ model: AssistantModel, _ tools: GoalChatTools) {
        model.openGoals(session: session)
    }

    func call(_ event: StreamEvent) -> ToolCall {
        guard case .functionCall(let id, let name, let arguments) = event else { fatalError("not a call") }
        return ToolCall(id: id, name: name, arguments: Data(arguments.utf8))
    }
}

/// The members of the harness under their short names, so a suite reads like a test of the chat itself.
@MainActor
protocol GoalChatSuite {
    var h: GoalChatHarness { get }
}

@MainActor
extension GoalChatSuite {
    var settings: AppSettings { h.settings }
    var goals: GoalStore { h.goals }
    var responder: FakePlanResponder { h.responder }
    var today: PlanDay { h.today }
    var package: GoalDataSummary { h.package }
    var session: GoalPlanningSession { h.session }
    func makeTools() -> GoalChatTools { h.makeTools() }
    func makeModel(responder override: ResponseStreaming? = nil) async -> (AssistantModel, GoalChatTools, ChatStore) {
        await h.makeModel(responder: override)
    }
    func openGoals(_ model: AssistantModel, _ tools: GoalChatTools) { h.openGoals(model, tools) }
    func call(_ event: StreamEvent) -> ToolCall { h.call(event) }
    func storedText(_ store: ChatStore) -> String { h.storedText(store) }
    static var readCall: StreamEvent { GoalChatHarness.readCall }
    static var activityCall: StreamEvent { GoalChatHarness.activityCall }
    static func nutritionCall(id: String = "n1", kcal: String = "1800", protein: String = "150", carbs: String = "165",
                              fat: String = "60", pace: String = "-0.3", reason: String = "Ruhiges Tempo") -> StreamEvent {
        GoalChatHarness.nutritionCall(id: id, kcal: kcal, protein: protein, carbs: carbs, fat: fat, pace: pace, reason: reason)
    }
}
