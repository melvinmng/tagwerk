import Foundation
import Observation
import TagwerkCore

/// Edits the goals as dated goal plans (decisions ZI5b, ZI4b). A change never touches earlier days: it creates a plan that holds
/// from today, and further edits on the same day replace it. Fields the screen does not show (macro goals, fibre, sugar, weight
/// goals) are carried over from the plan that held before.
@MainActor
@Observable
final class GoalPlanEditor {
    private let goals: GoalStore
    private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    /// The plan of today as edited so far.
    private(set) var plan: GoalPlan

    init(goals: GoalStore, calendar: Calendar = .tagwerk, now: @escaping () -> Date = Date.init) {
        self.goals = goals
        self.calendar = calendar
        self.now = now
        let today = PlanDay(date: now(), calendar: calendar)
        plan = goals.current(on: today) ?? GoalPlan(validFrom: today, kcal: 2300, waterMilliliters: 2000, stepsPerDay: 8000,
                                                    workoutMinutesPerWeek: 150)
    }

    var today: PlanDay { PlanDay(date: now(), calendar: calendar) }

    /// Applies `change` and keeps the result as the plan that holds from today. Nothing changes when the plan stays as it is.
    func update(_ change: (inout GoalPlan) -> Void) {
        var edited = plan
        change(&edited)
        guard edited != plan else { return }
        if edited.validFrom != today {
            edited.id = UUID()
            edited.validFrom = today
            edited.origin = .manual
        }
        goals.adopt(edited)
        plan = goals.current(on: today) ?? edited
    }

    /// The plans that held before the current one, newest first.
    var earlierPlans: [GoalPlan] {
        goals.plans().filter { $0.validFrom < plan.validFrom }.reversed()
    }

    /// A binding-friendly accessor: reads one value of the plan, writes it through `update`.
    func value<Value>(_ keyPath: WritableKeyPath<GoalPlan, Value>) -> Value { plan[keyPath: keyPath] }

    func set<Value>(_ keyPath: WritableKeyPath<GoalPlan, Value>, to newValue: Value) {
        update { $0[keyPath: keyPath] = newValue }
    }
}
