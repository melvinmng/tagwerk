import AIKit
import Foundation
import HealthBridge
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The data package of the goal planning and the way into the chat (decisions PV1b, PV2a, ZI6b). All data is invented.
@MainActor
struct GoalPlanningFlowTests {
    let container: ModelContainer
    let intake: IntakeStore
    let goals: GoalStore
    let dayHealth: DayHealthStore
    let settings: AppSettings
    let health = FakeHealthStore()
    let responder = FakePlanResponder()
    let calendar = Calendar.tagwerk
    let today = PlanDay(year: 2026, month: 11, day: 18)
    var noon: Date { today.startDate(in: calendar).addingTimeInterval(12 * 3600 + 40 * 60) }

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        let noon = PlanDay(year: 2026, month: 11, day: 18).startDate(in: .tagwerk).addingTimeInterval(12 * 3600 + 40 * 60)
        settings = try AppSettings.current(in: container.mainContext)
        intake = IntakeStore(context: container.mainContext)
        goals = GoalStore(context: container.mainContext, settings: settings, calendar: .tagwerk, now: { noon })
        dayHealth = DayHealthStore(context: container.mainContext, now: { noon })
        goals.adopt(GoalPlan(validFrom: PlanDay(year: 2026, month: 10, day: 1), kcal: 2300, proteinGrams: 120, waterMilliliters: 2000,
                             stepsPerDay: 8000, workoutMinutesPerWeek: 150))
    }

    private func makeBuilder() -> GoalDataBuilder {
        let noon = self.noon
        let budgets = DayBudgets(intake: intake, goals: goals, dayHealth: dayHealth, health: health, settings: settings,
                                 calendar: calendar, now: { noon })
        let profile = BodyProfileStore(settings: settings, health: health, calendar: calendar, now: { noon })
        return GoalDataBuilder(intake: intake, budgets: budgets, weights: WeightStore(intake: intake, health: health, calendar: calendar),
                               health: health, bodyProfile: profile, goals: goals, calendar: calendar, now: { noon })
    }

    private func meal(kcal: Double, daysAgo: Int) {
        let day = today.adding(days: -daysAgo, calendar: calendar)
        let item = MealItem(name: "Essen", amount: "1", kcalMin: kcal, kcal: kcal, kcalMax: kcal, protein: 100, carbs: 200, fat: 60)
        intake.addMeal(MealValue(id: UUID(), date: day.startDate(in: calendar).addingTimeInterval(12 * 3600), kind: .lunch, title: "Essen",
                                 items: [item], origin: .manual), estimatedAt: nil)
    }

    // MARK: Flow

    private func makeFlow(signedIn: Bool = true) async -> (GoalPlanningFlow, AssistantModel) {
        let calendar = testCalendar()
        let taskList = TaskListModel(providers: [FakeTaskProvider(source: .local, tasks: [])], now: testNow, calendar: calendar)
        await taskList.reload()
        let calendarStore = FakeCalendarStore()
        let planStore = PlanStore(context: container.mainContext)
        let blocks = BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                                  settings: settings, calendar: calendar)
        let planning = PlanningModel(taskList: taskList, calendarStore: calendarStore, reminderStore: FakeAccessStore(),
                                     planStore: planStore, efforts: RecurringEffortStore(context: container.mainContext),
                                     blocks: blocks, settings: settings, marks: EventMarkStore(context: container.mainContext),
                                     now: testNow, calendar: calendar)
        await planning.reload()
        let tools = AppTools(taskList: taskList, planning: planning, planner: nil, events: { _ in [] })
        let model = AssistantModel(responder: responder, tools: tools, model: { "gpt-test" }, store: ChatStore(context: container.mainContext),
                                   planning: planning, now: testNow)
        let settings = self.settings, goals = self.goals, today = self.today
        model.goalTools = GoalChatTools(hasConsent: { settings.goalPlanningConsent },
                                        currentPlan: { goals.current(on: today) ?? GoalPlan(validFrom: today, kcal: 2300, waterMilliliters: 2000, stepsPerDay: 8000, workoutMinutesPerWeek: 150) },
                                        adopt: { goals.adopt($0) }, today: { today })
        model.hasGoalConsent = { settings.goalPlanningConsent }
        let flow = GoalPlanningFlow(settings: settings, builder: makeBuilder(), assistant: model, isSignedIn: { signedIn })
        return (flow, model)
    }

    @Test func entry_withoutSignIn_startsNothing() async {
        let (flow, _) = await makeFlow(signedIn: false)
        await flow.start(.plan)
        #expect(flow.stage == nil)
    }

    @Test func entry_withoutConsent_showsConsentFirst_andCollectsNothing() async {
        let (flow, _) = await makeFlow()
        await flow.start(.plan)
        #expect(flow.stage == .consent)
        #expect(health.activeEnergyReads.isEmpty && health.stepsReads.isEmpty, "nothing is collected before the consent")
        flow.decline()
        #expect(flow.stage == nil && !settings.goalPlanningConsent)
    }

    @Test func entry_afterAgreeing_showsTheDataSheet_andTheConsentStays() async {
        let (flow, _) = await makeFlow()
        await flow.start(.plan)
        flow.agree()
        #expect(settings.goalPlanningConsent)
        #expect(flow.stage == nil, "the consent sheet leaves first")
        await flow.finishPresentation()
        guard case .data(let session) = flow.stage else { Issue.record("no data sheet"); return }
        #expect(session.package.periodDays == GoalDataBuilder.standardDays)
        // The next entry skips the consent.
        flow.cancel()
        await flow.start(.plan)
        if case .data = flow.stage {} else { Issue.record("the consent is asked once") }
    }

    @Test func begin_remembersSwitchedOffGroups_freezesTheSelection_andOpensTheChatAfterTheSheet() async {
        settings.goalPlanningConsent = true
        meal(kcal: 2000, daysAgo: 1)
        let (flow, model) = await makeFlow()
        await flow.start(.plan)
        guard case .data(let draft) = flow.stage else { Issue.record("no data sheet"); return }
        flow.begin(selected: Set(draft.package.groups).subtracting([.nutrition]), draft: draft)
        #expect(flow.stage == nil)
        #expect(!model.isPresented, "the chat opens when the sheet has left")
        await flow.finishPresentation()
        #expect(model.isPresented && model.context == .goals)
        #expect(model.goalTools?.session?.package.nutrition == nil && model.goalTools?.session?.package.weight != nil)
        #expect(settings.goalDataOffGroups == [.nutrition])
        // The switches are remembered for the next time.
        flow.cancel()
        await flow.start(.plan)
        if case .data(let next) = flow.stage { #expect(flow.initialSelection(for: next.package).contains(.nutrition) == false) }
    }

    @Test func review_prefillsFirstMessage_withoutSending() async {
        settings.goalPlanningConsent = true
        let (flow, model) = await makeFlow()
        await flow.start(.review)
        guard case .data(let draft) = flow.stage else { Issue.record("no data sheet"); return }
        flow.begin(selected: Set(draft.package.groups), draft: draft)
        await flow.finishPresentation()
        #expect(model.takeGoalsPrefill() == GoalPlanningFlow.reviewPrefill)
        #expect(responder.calls.isEmpty, "nothing is sent before the user taps")
    }

    @Test func consentWithdrawnBeforeTheDataSheet_showsNoDataSheet() async {
        let (flow, _) = await makeFlow()
        await flow.start(.plan)
        flow.agree()
        // The consent is withdrawn while the consent sheet leaves: the data sheet must not follow.
        settings.goalPlanningConsent = false
        await flow.finishPresentation()
        #expect(flow.stage == nil)
    }
}
