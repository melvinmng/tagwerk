import Foundation
import Observation
import TagwerkCore

/// State of the guided weekly planning (#164): five steps, each of them optional. The sheet looks back on the reviewed
/// week (on Sunday the running week, else the previous one) and plans the week after it. Nothing here is sent anywhere;
/// the AI weekly plan is started by its own button in "Planen".
@MainActor
@Observable
final class WeekPlanningModel {
    /// A deadline event (deadline calendar or marked event) of the planned week.
    struct DeadlineEvent: Equatable, Identifiable {
        let title: String
        let day: PlanDay
        var id: String { "\(day.dayKey)|\(title)" }
    }

    let reviewedWeek: PlanDay
    let plannedWeek: PlanDay
    /// The weekly review, moved to the reviewed week: it carries the numbers and the reflection of that week.
    let weekReview: WeekReviewModel
    private(set) var step: WeekPlanningStep = .review
    private(set) var deadlineTasks: [TaskItem] = []
    private(set) var deadlineEvents: [DeadlineEvent] = []
    /// The reflection of the reviewed week is in `weekReview`. Before that, nothing is saved: a model that was never
    /// loaded holds an empty reflection and would overwrite the stored one of the week it starts on.
    private(set) var isLoaded = false

    let calendar: Calendar
    @ObservationIgnored private let tasks: () -> [TaskItem]
    @ObservationIgnored private let loadDeadlineEvents: (ClosedRange<PlanDay>) async -> [DeadlineEvent]

    init(weekReview: WeekReviewModel, calendar: Calendar = .tagwerk, now: () -> Date = Date.init,
         tasks: @escaping () -> [TaskItem], deadlineEvents: @escaping (ClosedRange<PlanDay>) async -> [DeadlineEvent]) {
        let today = PlanDay(date: now(), calendar: calendar)
        self.weekReview = weekReview
        self.calendar = calendar
        self.tasks = tasks
        self.loadDeadlineEvents = deadlineEvents
        reviewedWeek = WeekPlanningRules.reviewedWeekStart(today: today, calendar: calendar)
        plannedWeek = WeekPlanningRules.plannedWeekStart(today: today, calendar: calendar)
    }

    // MARK: Steps

    var stepNumber: Int { step.rawValue + 1 }
    var stepCount: Int { WeekPlanningRules.steps.count }
    var isFirstStep: Bool { step == WeekPlanningRules.steps.first }
    var isLastStep: Bool { step == WeekPlanningRules.steps.last }

    /// To the next step; the reflection is saved first. On the last step nothing happens.
    func next() {
        saveReflection()
        guard let index = WeekPlanningRules.steps.firstIndex(of: step), index + 1 < WeekPlanningRules.steps.count else { return }
        step = WeekPlanningRules.steps[index + 1]
    }

    func back() {
        saveReflection()
        guard let index = WeekPlanningRules.steps.firstIndex(of: step), index > 0 else { return }
        step = WeekPlanningRules.steps[index - 1]
    }

    /// Saves the reflection of the reviewed week. Called when the sheet closes, with "Fertig" or by swiping it away.
    func close() {
        saveReflection()
    }

    private func saveReflection() {
        guard isLoaded else { return }
        weekReview.saveReflection()
    }

    // MARK: Loading

    /// The numbers and the reflection of the reviewed week, and the deadlines of the planned week.
    func load() async {
        // The review starts on the running week: load its stored reflection first, so moving on saves that, not an empty one.
        await weekReview.reload()
        await weekReview.go(toWeekOf: reviewedWeek)
        isLoaded = true
        await reloadDeadlines()
    }

    func reloadDeadlines() async {
        deadlineTasks = WeekPlanningRules.deadlineTasks(tasks(), plannedWeek: plannedWeek, calendar: calendar)
        let range = plannedWeek...plannedWeek.adding(days: 6, calendar: calendar)
        deadlineEvents = await loadDeadlineEvents(range).sorted { ($0.day, $0.title) < ($1.day, $1.title) }
    }

    /// "KI-Wochenplan erstellen" and "Selbst planen": "Planen" in the week view of the planned week.
    func openPlanWeek() {
        saveReflection()
        weekReview.planNextWeek()
    }
}
