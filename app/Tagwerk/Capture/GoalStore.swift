import Foundation
import SwiftData
import TagwerkCore

/// Stores the goal plans in SwiftData and hands out the plan that applies on a day.
///
/// Until every reader of the goals uses the plans (strand C of the nutrition plan), each adopted plan is also written to the
/// single goal fields of `AppSettings`, so the screens that still read them show the current plan.
@MainActor
final class GoalStore {
    private let context: ModelContext
    private let settings: AppSettings?
    private let calendar: Calendar
    private let now: () -> Date

    init(context: ModelContext, settings: AppSettings? = nil, calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.context = context
        self.settings = settings
        self.calendar = calendar
        self.now = now
    }

    // MARK: Reading

    /// All plans, oldest first.
    func plans() -> [GoalPlan] {
        let records = (try? context.fetch(FetchDescriptor<GoalPlanRecord>(sortBy: [SortDescriptor(\.validFromKey)]))) ?? []
        return records.map(\.value)
    }

    var timeline: GoalTimeline { GoalTimeline(plans: plans()) }

    /// The plan that applies on `day`; `nil` while no plan exists.
    func current(on day: PlanDay) -> GoalPlan? { timeline.plan(on: day) }

    // MARK: Writing

    /// Stores `plan`; a plan of the same `validFrom` day is replaced. A plan applies from the day it is given for, never
    /// to earlier days: callers pass today as `validFrom`.
    func adopt(_ plan: GoalPlan) {
        if let existing = record(on: plan.validFrom) {
            existing.apply(plan)
        } else {
            context.insert(GoalPlanRecord(plan))
        }
        save()
        mirrorCurrentPlanToSettings()
    }

    func delete(_ id: UUID) {
        let descriptor = FetchDescriptor<GoalPlanRecord>(predicate: #Predicate { $0.id == id })
        for record in (try? context.fetch(descriptor)) ?? [] { context.delete(record) }
        save()
        mirrorCurrentPlanToSettings()
    }

    // MARK: Migration

    /// Takes over the single goals of the settings as the first plan, once. The plan holds from the day of the oldest meal (the
    /// goals applied to all of them), or from today without meals. Existing plans are left alone and the flag is set anyway.
    func migrateIfNeeded() {
        guard let settings, !settings.goalPlansMigrated else { return }
        defer {
            settings.goalPlansMigrated = true
            save()
        }
        guard plans().isEmpty else { return }
        var oldest = FetchDescriptor<MealRecord>(sortBy: [SortDescriptor(\.date)])
        oldest.fetchLimit = 1
        let firstDay = ((try? context.fetch(oldest))?.first).map { PlanDay(date: $0.date, calendar: calendar) }
        let start = min(firstDay ?? PlanDay(date: now(), calendar: calendar), PlanDay(date: now(), calendar: calendar))
        context.insert(GoalPlanRecord(.migrated(validFrom: start, kcal: settings.goalKilocalories,
                                                waterMilliliters: settings.goalWaterMilliliters,
                                                proteinGoalEnabled: settings.proteinGoalEnabled,
                                                proteinGrams: settings.goalProteinGrams, stepsPerDay: settings.goalStepsPerDay,
                                                workoutMinutesPerWeek: settings.goalWorkoutMinutesPerWeek)))
    }

    /// Carries edits of the single goal fields into the plans. Until the settings screens used the plans, the fields were edited
    /// directly while the first plan stood still, so the plan of today may be older than what the user set. When the mirrored
    /// fields differ from the plan of today, a copy of that plan with only those fields replaced applies from today; macro, fibre,
    /// sugar and weight goals are kept. Equal values change nothing, so the call is safe at every launch.
    func reconcileWithSettings() {
        guard let settings else { return }
        let today = PlanDay(date: now(), calendar: calendar)
        guard var plan = current(on: today) else { return }
        let protein = settings.proteinGoalEnabled ? settings.goalProteinGrams : nil
        guard plan.kcal != settings.goalKilocalories || plan.waterMilliliters != settings.goalWaterMilliliters
            || plan.stepsPerDay != settings.goalStepsPerDay || plan.workoutMinutesPerWeek != settings.goalWorkoutMinutesPerWeek
            || plan.proteinGrams != protein else { return }
        if plan.validFrom != today {
            plan.id = UUID()
            plan.validFrom = today
        }
        plan.kcal = settings.goalKilocalories
        plan.waterMilliliters = settings.goalWaterMilliliters
        plan.stepsPerDay = settings.goalStepsPerDay
        plan.workoutMinutesPerWeek = settings.goalWorkoutMinutesPerWeek
        plan.proteinGrams = protein
        plan.origin = .manual
        adopt(plan)
    }

    // MARK: Private

    private func record(on day: PlanDay) -> GoalPlanRecord? {
        let key = day.dayKey
        let descriptor = FetchDescriptor<GoalPlanRecord>(predicate: #Predicate { $0.validFromKey == key })
        return (try? context.fetch(descriptor))?.first
    }

    private func mirrorCurrentPlanToSettings() {
        guard let settings, let plan = current(on: PlanDay(date: now(), calendar: calendar)) else { return }
        settings.goalKilocalories = plan.kcal
        settings.goalWaterMilliliters = plan.waterMilliliters
        settings.goalStepsPerDay = plan.stepsPerDay
        settings.goalWorkoutMinutesPerWeek = plan.workoutMinutesPerWeek
        settings.proteinGoalEnabled = plan.proteinGrams != nil
        if let protein = plan.proteinGrams { settings.goalProteinGrams = protein }
        save()
    }

    private func save() {
        try? context.save()
    }
}
