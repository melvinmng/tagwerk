import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct WeekPlanningModelTests {
    let container: ModelContainer
    let store: IntakeStore
    let settings: AppSettings
    let routines: RoutineStore
    let calendar = Calendar.tagwerk
    final class Opened { var days: [PlanDay] = [] }
    let opened = Opened()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = IntakeStore(context: container.mainContext)
        settings = try AppSettings.current(in: container.mainContext)
        routines = RoutineStore(context: container.mainContext)
    }

    /// Wednesday is the 18th, Sunday the 22nd of November 2026.
    private func make(today: Int, tasks: [TaskItem] = [], events: [WeekPlanningModel.DeadlineEvent] = []) -> WeekPlanningModel {
        let now = PlanDay(year: 2026, month: 11, day: today).startDate(in: calendar).addingTimeInterval(12 * 3600)
        let opened = self.opened
        let review = WeekReviewModel(store: store, health: FakeHealthStore(), settings: settings, calendar: calendar, now: { now },
                                     completedReminders: { _ in [] }, completedLocalTasks: { _ in [] },
                                     routineStore: routines, openPlanWeek: { opened.days.append($0) })
        return WeekPlanningModel(weekReview: review, calendar: calendar, now: { now }, tasks: { tasks }, deadlineEvents: { _ in events })
    }

    private func reflection(_ day: Int) -> WeekReflection { routines.reflection(weekStart: PlanDay(year: 2026, month: 11, day: day)) }

    @Test func weekPlanning_savesTheReflectionOfTheReviewedWeek() async {
        let model = make(today: 18)
        await model.load()
        #expect(model.reviewedWeek == PlanDay(year: 2026, month: 11, day: 9))
        #expect(model.weekReview.weekStart == model.reviewedWeek)
        model.next()
        model.weekReview.reflection.wentWell = "Viel geschafft"
        model.next()
        #expect(model.step == .deadlines)
        #expect(reflection(9).wentWell == "Viel geschafft")
        // Not the running week.
        #expect(reflection(16) == WeekReflection())
    }

    @Test func weekPlanning_onSunday_reviewsTheRunningWeek() async {
        let model = make(today: 22)
        await model.load()
        #expect(model.reviewedWeek == PlanDay(year: 2026, month: 11, day: 16))
        #expect(model.plannedWeek == PlanDay(year: 2026, month: 11, day: 23))
        #expect(model.weekReview.weekStart == PlanDay(year: 2026, month: 11, day: 16))
        model.weekReview.reflection.tasksPlanned = true
        model.close()
        #expect(reflection(16).tasksPlanned)
    }

    @Test func weekPlanning_closeSavesWithoutFinishing() async {
        let model = make(today: 18)
        await model.load()
        model.weekReview.reflection.burdens = "Wenig Schlaf"
        model.close()
        #expect(model.step == .review)
        #expect(reflection(9).burdens == "Wenig Schlaf")
    }

    private func seed(_ day: Int, _ text: String) {
        routines.saveReflection(WeekReflection(wentWell: text), weekStart: PlanDay(year: 2026, month: 11, day: day), at: Date(timeIntervalSince1970: 0))
    }

    @Test func weekPlanning_loadingKeepsAStoredReflectionOfTheRunningWeek() async {
        seed(16, "Laufende Woche")
        seed(9, "Vorwoche")
        let model = make(today: 18)
        await model.load()
        // Midweek the review looks at the 9th; the stored reflection of the running week is untouched.
        #expect(reflection(16).wentWell == "Laufende Woche")
        #expect(model.weekReview.reflection.wentWell == "Vorwoche")
        model.next()
        #expect(reflection(9).wentWell == "Vorwoche" && reflection(16).wentWell == "Laufende Woche")
    }

    @Test func weekPlanning_onSunday_loadingShowsTheStoredReflectionOfTheRunningWeek() async {
        seed(16, "Laufende Woche")
        let model = make(today: 22)
        await model.load()
        #expect(model.weekReview.reflection.wentWell == "Laufende Woche")
        model.close()
        #expect(reflection(16).wentWell == "Laufende Woche")
    }

    @Test func weekPlanning_closeBeforeLoading_writesNothing() {
        seed(16, "Laufende Woche")
        let model = make(today: 22)
        model.close()
        model.next()
        #expect(reflection(16).wentWell == "Laufende Woche")
        #expect(model.step == .reflection)
    }

    @Test func weekPlanning_walksThroughFiveStepsInBothDirections() async {
        let model = make(today: 18)
        await model.load()
        #expect(model.isFirstStep && model.stepNumber == 1 && model.stepCount == 5)
        for _ in 0..<10 { model.next() }
        #expect(model.step == .habits && model.isLastStep && model.stepNumber == 5)
        model.back()
        #expect(model.step == .plan)
        for _ in 0..<10 { model.back() }
        #expect(model.step == .review)
    }

    @Test func weekPlanning_deadlineStep_listsTasksOfThePlannedWeek() async {
        let tasks = [makeTask("Diese Woche", source: .local, due: DueDate(year: 2026, month: 11, day: 20)),
                     makeTask("Überfällig", source: .local, due: DueDate(year: 2026, month: 11, day: 12)),
                     makeTask("Später", source: .local, due: DueDate(year: 2026, month: 11, day: 24)),
                     makeTask("Ohne Datum", source: .local)]
        let events = [WeekPlanningModel.DeadlineEvent(title: "Klausur", day: PlanDay(year: 2026, month: 11, day: 20)),
                      WeekPlanningModel.DeadlineEvent(title: "Abgabe Bericht", day: PlanDay(year: 2026, month: 11, day: 19))]
        let model = make(today: 18, tasks: tasks, events: events)
        await model.load()
        // Wednesday: the planned week is the running one (the 16th to the 22nd).
        #expect(model.plannedWeek == PlanDay(year: 2026, month: 11, day: 16))
        #expect(model.deadlineTasks.map(\.title) == ["Überfällig", "Diese Woche"])
        #expect(model.deadlineEvents.map(\.title) == ["Abgabe Bericht", "Klausur"])
    }

    @Test func weekPlanning_planStep_opensThePlannedWeekInPlanen() async {
        let model = make(today: 22)
        await model.load()
        model.openPlanWeek()
        #expect(opened.days == [PlanDay(year: 2026, month: 11, day: 23)])
    }
}
