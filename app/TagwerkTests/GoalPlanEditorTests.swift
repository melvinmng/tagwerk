import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct GoalPlanEditorTests {
    let container: ModelContainer
    let settings: AppSettings
    let goals: GoalStore
    let calendar = Calendar.tagwerk
    let today = PlanDay(year: 2026, month: 11, day: 22)
    var noon: Date { today.startDate(in: calendar).addingTimeInterval(12 * 3600) }

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        let noon = PlanDay(year: 2026, month: 11, day: 22).startDate(in: .tagwerk).addingTimeInterval(12 * 3600)
        goals = GoalStore(context: container.mainContext, settings: settings, calendar: .tagwerk, now: { noon })
        goals.adopt(GoalPlan(validFrom: PlanDay(year: 2026, month: 10, day: 20), kcal: 2300, proteinGrams: 120, carbsGrams: 250,
                             fatGrams: 78, fiberGrams: 30, sugarLimitGrams: 50, waterMilliliters: 2000, stepsPerDay: 8000,
                             workoutMinutesPerWeek: 150, targetWeightKg: 72))
    }

    private func makeEditor() -> GoalPlanEditor {
        let noon = self.noon
        return GoalPlanEditor(goals: goals, calendar: calendar, now: { noon })
    }

    @Test func editingGoal_createsNewPlanFromToday() {
        let editor = makeEditor()
        editor.set(\.kcal, to: 2000)
        let plans = goals.plans()
        #expect(plans.count == 2)
        #expect(plans.last?.validFrom == today && plans.last?.kcal == 2000)
        #expect(plans.first?.kcal == 2300, "earlier days keep their plan")
        #expect(goals.current(on: today.adding(days: -1, calendar: calendar))?.kcal == 2300)
    }

    @Test func editingSameDayTwice_replaces() {
        let editor = makeEditor()
        editor.set(\.kcal, to: 2000)
        editor.set(\.kcal, to: 1900)
        editor.set(\.waterMilliliters, to: 2500)
        let plans = goals.plans()
        #expect(plans.count == 2)
        #expect(plans.last?.kcal == 1900 && plans.last?.waterMilliliters == 2500)
    }

    @Test func editing_keepsFieldsTheScreenDoesNotShow() {
        let editor = makeEditor()
        editor.set(\.stepsPerDay, to: 10_000)
        let plan = goals.plans().last
        #expect(plan?.carbsGrams == 250 && plan?.fatGrams == 78 && plan?.fiberGrams == 30 && plan?.sugarLimitGrams == 50)
        #expect(plan?.targetWeightKg == 72 && plan?.proteinGrams == 120)
    }

    @Test func editing_withoutChange_createsNothing() {
        let editor = makeEditor()
        editor.set(\.kcal, to: 2300)
        #expect(goals.plans().count == 1)
    }

    @Test func switchingAGoalOff_storesNoGoal() {
        let editor = makeEditor()
        editor.set(\.proteinGrams, to: nil)
        #expect(goals.plans().last?.proteinGrams == nil)
        #expect(!settings.proteinGoalEnabled, "the single goal fields still follow the plan for the screens that read them")
    }

    @Test func earlierPlans_areNewestFirst_withoutTheCurrentOne() {
        let editor = makeEditor()
        #expect(editor.earlierPlans.isEmpty)
        editor.set(\.kcal, to: 2000)
        #expect(editor.earlierPlans.map(\.kcal) == [2300])
        #expect(editor.plan.validFrom == today)
    }
}
