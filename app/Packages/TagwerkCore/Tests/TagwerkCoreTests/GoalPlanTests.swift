import Foundation
import Testing
@testable import TagwerkCore

struct GoalPlanTests {
    private func plan(_ month: Int, _ day: Int, kcal: Int) -> GoalPlan {
        GoalPlan(validFrom: PlanDay(year: 2026, month: month, day: day), kcal: kcal, waterMilliliters: 2000, stepsPerDay: 8000,
                 workoutMinutesPerWeek: 150)
    }

    @Test func timeline_planForDay_picksLatestNotAfter() {
        let timeline = GoalTimeline(plans: [plan(11, 20, kcal: 2100), plan(11, 1, kcal: 2300), plan(12, 1, kcal: 1900)])
        #expect(timeline.plan(on: PlanDay(year: 2026, month: 11, day: 19))?.kcal == 2300)
        #expect(timeline.plan(on: PlanDay(year: 2026, month: 11, day: 20))?.kcal == 2100)
        #expect(timeline.plan(on: PlanDay(year: 2026, month: 11, day: 30))?.kcal == 2100)
        #expect(timeline.plan(on: PlanDay(year: 2027, month: 1, day: 5))?.kcal == 1900)
    }

    @Test func timeline_beforeFirstPlan_usesFirst() {
        let timeline = GoalTimeline(plans: [plan(11, 20, kcal: 2100), plan(12, 1, kcal: 1900)])
        #expect(timeline.plan(on: PlanDay(year: 2026, month: 1, day: 1))?.kcal == 2100)
    }

    @Test func timeline_empty_hasNoPlan() {
        #expect(GoalTimeline(plans: []).plan(on: PlanDay(year: 2026, month: 11, day: 20)) == nil)
    }

    @Test func timeline_adopting_sameDayReplaces() {
        let timeline = GoalTimeline(plans: [plan(11, 20, kcal: 2100)]).adopting(plan(11, 20, kcal: 1800))
        #expect(timeline.plans.map(\.kcal) == [1800])
    }

    @Test func timeline_orderedByDay_whateverTheInputOrder() {
        let timeline = GoalTimeline(plans: [plan(12, 1, kcal: 3), plan(11, 1, kcal: 1), plan(11, 20, kcal: 2)])
        #expect(timeline.plans.map(\.kcal) == [1, 2, 3])
    }

    @Test func migrated_proteinOnlyWhenEnabled() {
        let day = PlanDay(year: 2026, month: 11, day: 20)
        let off = GoalPlan.migrated(validFrom: day, kcal: 2300, waterMilliliters: 2000, proteinGoalEnabled: false, proteinGrams: 120,
                                    stepsPerDay: 8000, workoutMinutesPerWeek: 150)
        #expect(off.proteinGrams == nil)
        let on = GoalPlan.migrated(validFrom: day, kcal: 2300, waterMilliliters: 2000, proteinGoalEnabled: true, proteinGrams: 120,
                                   stepsPerDay: 8000, workoutMinutesPerWeek: 150)
        #expect(on.proteinGrams == 120)
        #expect(on.kcal == 2300 && on.waterMilliliters == 2000 && on.stepsPerDay == 8000 && on.workoutMinutesPerWeek == 150)
        #expect(on.activeKcalPerDay == 0 && on.origin == .manual)
    }
}
