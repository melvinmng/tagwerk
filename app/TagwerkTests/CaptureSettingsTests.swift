import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct CaptureSettingsTests {
    @Test func goalSummary_matchesSettingsRow() {
        #expect(IntakeFormat.goalSummary(kcal: 2300, waterMilliliters: 2000, workoutsPerWeek: 3) == "2.300 kcal · 2,0 l · 3×")
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
