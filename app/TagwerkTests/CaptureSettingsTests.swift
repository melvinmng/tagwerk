import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct CaptureSettingsTests {
    @Test func goalSummary_matchesSettingsRow() {
        #expect(IntakeFormat.goalSummary(kcal: 2300, waterMilliliters: 2000, workoutMinutesPerWeek: 150) == "2.300 kcal · 2,0 l · 2 h 30 min")
    }

    /// Held by the suite: a model object is unusable once its container is released.
    let container: ModelContainer
    let settings: AppSettings

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
    }

    @Test func defaults_minutesGoal150_stepsGoal8000() {
        #expect(settings.goalWorkoutMinutesPerWeek == 150)
        #expect(settings.goalStepsPerDay == 8000)
        #expect(settings.workoutGoalMigrated == false)
    }

    @Test func migration_oldGoalZero_setsMinutesGoalZero_once() {
        settings.goalWorkoutsPerWeek = 0
        settings.migrateWorkoutGoalIfNeeded()
        #expect(settings.goalWorkoutMinutesPerWeek == 0)
        #expect(settings.workoutGoalMigrated)
        // A goal set later is never overwritten by a second run.
        settings.goalWorkoutMinutesPerWeek = 90
        settings.migrateWorkoutGoalIfNeeded()
        #expect(settings.goalWorkoutMinutesPerWeek == 90)
    }

    @Test func migration_oldGoalNonZero_keepsDefault_andDoesNotRunTwice() {
        settings.migrateWorkoutGoalIfNeeded()
        #expect(settings.goalWorkoutMinutesPerWeek == 150)
        #expect(settings.workoutGoalMigrated)
        // A fresh install is marked too, so switching the old (hidden) goal later changes nothing.
        settings.goalWorkoutsPerWeek = 0
        settings.migrateWorkoutGoalIfNeeded()
        #expect(settings.goalWorkoutMinutesPerWeek == 150)
    }

    @Test func environment_migratesAtStart() throws {
        settings.goalWorkoutsPerWeek = 0
        let environment = try AppEnvironment(modelContainer: container, notificationCenter: FakeNotificationCenter(),
                                             health: FakeHealthStore())
        #expect(environment.settings.goalWorkoutMinutesPerWeek == 0)
        #expect(environment.settings.workoutGoalMigrated)
    }

    #if DEBUG && targetEnvironment(simulator)
    @Test func demoTransport_answersMealEstimate_beforePlanAnswer() throws {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/codex/responses")!)
        let body: [String: Any] = [
            "model": "demo",
            "input": [["role": "user", "content": [["type": "input_text", "text": "2 Brötchen mit Käse"]]]],
            "text": ["format": ["type": "json_schema", "name": "meal_estimate"]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let answer = try #require(DemoAITransport.mealAnswer(for: request))
        let estimate = try #require(try MealEstimateOutput.decode(Data(answer.utf8)).normalized())
        #expect(estimate.items.count == 2)
    }
    #endif
}
