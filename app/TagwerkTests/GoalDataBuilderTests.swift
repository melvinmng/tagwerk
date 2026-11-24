import Foundation
import HealthBridge
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The data package of the goal planning (decision PV2a): what the builder collects from the days of the app. All data is invented.
@MainActor
struct GoalDataBuilderTests {
    let container: ModelContainer
    let intake: IntakeStore
    let goals: GoalStore
    let dayHealth: DayHealthStore
    let settings: AppSettings
    let health = FakeHealthStore()
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

    // MARK: Builder

    @Test func builder_daysWithoutEntries_notCountedAsZero_andTodayIsLeftOut() async {
        meal(kcal: 2000, daysAgo: 1)
        meal(kcal: 3000, daysAgo: 5)
        meal(kcal: 9999, daysAgo: 0)
        let session = await makeBuilder().build(periodDays: 28)
        let nutrition = session.package.nutrition
        #expect(nutrition?.kcal == 2500 && nutrition?.daysWithEntries == 2, "today is not finished and stays out; empty days are no zeros")
        #expect(nutrition?.proteinGrams == 100)
    }

    @Test func builder_bodyGroup_usesResolvedProfile() async {
        settings.typedBodyValues = BodyProfileValues(heightCm: 170, birthYear: 1985, sex: .female)
        health.bodyProfileValue = HealthBodyProfile(heightCm: 181, birthYear: nil, sex: nil)
        health.setGroupAccess(.asked, for: .bodyProfile)
        let session = await makeBuilder().build(periodDays: 28)
        let body = session.package.body
        #expect(body?.heightCm == 181, "Health wins where it delivers")
        #expect(body?.ageYears == 41 && body?.sex == .female, "the typed fields fill the rest")
        #expect(session.guardInput.body == BodyProfileValues(heightCm: 181, birthYear: 1985, sex: .female))
    }

    @Test func builder_activityFromHealthOnlyOnDaysThatHaveASum() async {
        health.setGroupAccess(.asked, for: .activeEnergy)
        health.activeEnergy = [DailyActiveEnergy(start: today.adding(days: -1, calendar: calendar).startDate(in: calendar), kilocalories: 400),
                               DailyActiveEnergy(start: today.adding(days: -2, calendar: calendar).startDate(in: calendar), kilocalories: 600)]
        health.currentStepsAccess = .asked
        health.steps = [DailySteps(start: today.adding(days: -1, calendar: calendar).startDate(in: calendar), count: 8000)]
        let session = await makeBuilder().build(periodDays: 28)
        #expect(session.package.activity?.activeKcal == 500, "the days without a sum are no zeros")
        #expect(session.package.activity?.steps == 8000)
        #expect(session.guardInput.meanActiveKcal == 500)
    }

    @Test func builder_withoutHealthData_hasNoActivityValuesAndNoMeanForTheGuard() async {
        let session = await makeBuilder().build(periodDays: 28)
        #expect(session.package.activity?.activeKcal == nil && session.package.activity?.steps == nil)
        #expect(session.guardInput.meanActiveKcal == nil)
        #expect(session.package.goals?.kcal == 2300)
    }

    @Test func builder_reviewPeriod_isSinceTheCurrentGoals() {
        // The plan holds since October 1st: 48 days.
        #expect(makeBuilder().reviewPeriodDays() == 48)
    }

    @Test func builder_reviewPeriod_atMostTwelveWeeks_andAtLeastAWeek() {
        for plan in goals.plans() { goals.delete(plan.id) }
        goals.adopt(GoalPlan(validFrom: PlanDay(year: 2025, month: 1, day: 1), kcal: 2300, waterMilliliters: 2000, stepsPerDay: 8000,
                             workoutMinutesPerWeek: 150))
        #expect(makeBuilder().reviewPeriodDays() == 84)
        goals.adopt(GoalPlan(validFrom: today.adding(days: -3, calendar: calendar), kcal: 2300, waterMilliliters: 2000, stepsPerDay: 8000,
                             workoutMinutesPerWeek: 150))
        #expect(makeBuilder().reviewPeriodDays() == GoalDataBuilder.standardDays, "less than a week of goals gives the standard period")
    }
}
