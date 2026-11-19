import Foundation

/// The five steps of the guided weekly planning (#164), in this order. Every step can be skipped.
public enum WeekPlanningStep: Int, CaseIterable, Sendable {
    case review, reflection, deadlines, plan, habits
}

/// Pure rules of the weekly planning: which week is looked back on, which one is planned, and which tasks matter.
public enum WeekPlanningRules {
    public static let steps = WeekPlanningStep.allCases

    /// The Monday of the week that is reviewed: on Sunday the running week (the week is over, the planning starts),
    /// on any other day the previous week.
    public static func reviewedWeekStart(today: PlanDay, calendar: Calendar) -> PlanDay {
        let monday = PlanDay(date: IntakeRules.weekStart(containing: today.startDate(in: calendar), calendar: calendar), calendar: calendar)
        return today.weekday(in: calendar) == 1 ? monday : monday.adding(days: -7, calendar: calendar)
    }

    /// The Monday of the week that is planned: the week after the reviewed one.
    public static func plannedWeekStart(today: PlanDay, calendar: Calendar) -> PlanDay {
        reviewedWeekStart(today: today, calendar: calendar).adding(days: 7, calendar: calendar)
    }

    /// Open tasks due in the planned week or earlier (overdue), in the usual order: earliest due first. Tasks without a
    /// due date are not part of it.
    public static func deadlineTasks(_ tasks: [TaskItem], plannedWeek: PlanDay, calendar: Calendar) -> [TaskItem] {
        let lastDay = plannedWeek.adding(days: 6, calendar: calendar)
        let due = tasks.filter { task in
            guard !task.isCompleted, let dueDate = task.due else { return false }
            return PlanDay(dueDate) <= lastDay
        }
        return sortedTasks(due, calendar: calendar)
    }
}
