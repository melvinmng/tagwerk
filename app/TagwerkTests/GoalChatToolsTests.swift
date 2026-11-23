import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The tools of the chat "Ziele planen" and its limits (strand G of the nutrition plan, tasks G5): own tool set, the data package, limits in code, opening. All data is invented.
@MainActor
struct GoalChatToolsTests: GoalChatSuite {
    let h: GoalChatHarness

    init() throws { h = try GoalChatHarness() }

    @Test func goalTools_haveNoAppFunctions() {
        let names = Set(makeTools().definitions.map(\.name))
        #expect(names == ["get_goal_data", "propose_nutrition_goals", "propose_activity_goals"])
        #expect(makeTools().kind(of: "get_goal_data") == .read)
        #expect(makeTools().kind(of: "propose_nutrition_goals") == .write)
    }

    @Test func appTools_haveNoGoalFunctions() async {
        let (model, _, _) = await makeModel()
        let goalNames = Set(GoalChatTools.allDefinitions.map(\.name))
        let appNames = Set((model.tools.definitions + AppTools.gitHubDefinitions + AppTools.noteDefinitions).map(\.name))
        #expect(appNames.isDisjoint(with: goalNames))
        let noteNames = Set((NoteChatTools.changeDefinitions + [NoteChatTools.listNotesDefinition]).map(\.name))
        #expect(noteNames.isDisjoint(with: goalNames))
    }

    @Test func noteSuggestions_neverOfferGoalFunctions() {
        #expect(NoteSuggestionRules.allowedTools.isDisjoint(with: GoalChatTools.proposalTools.union(GoalChatTools.readTools)))
    }

    @Test func goalChat_requestOffersExactlyTheThreeGoalFunctions() async {
        let (model, tools, _) = await makeModel()
        openGoals(model, tools)
        responder.enqueue("Hallo.")
        await model.send("Hallo")
        #expect(model.context == .goals)
        #expect(responder.instructions.last?.contains("get_goal_data") == true)
        #expect(responder.instructions.last?.contains("list_tasks") == false, "no app functions in the instructions")
    }

    // MARK: get_goal_data

    @Test func getGoalData_withoutConsent_returnsErrorWithoutValues() async {
        let tools = makeTools()
        tools.begin(session)
        settings.goalPlanningConsent = false
        let output = await tools.run(call(Self.readCall))
        #expect(output.contains("error"))
        #expect(!output.contains("82.1") && !output.contains("2350") && !output.contains("height_cm"))
    }

    @Test func getGoalData_withoutSelection_returnsNoValues() async {
        let output = await makeTools().run(call(Self.readCall))
        #expect(output.contains("error") && !output.contains("2350"))
    }

    @Test func getGoalData_returnsOnlySelectedGroups() async {
        let tools = makeTools()
        var selected = session
        selected.package = session.package.keeping([.weight, .goals])
        tools.begin(selected)
        let output = await tools.run(call(Self.readCall))
        #expect(output.contains("\"weight\"") && output.contains("\"goals\""))
        #expect(!output.contains("\"nutrition\"") && !output.contains("\"body\"") && !output.contains("2350") && !output.contains("height_cm"))
    }

    @Test func getGoalData_returnsTheFrozenPackage_notAFreshOne() async throws {
        let tools = makeTools()
        let frozen = session
        tools.begin(frozen)
        // The state of the app changes after the sheet: the model still gets what the sheet showed.
        var plan = try #require(goals.current(on: today))
        plan.kcal = 1999
        goals.adopt(plan)
        let output = await tools.run(call(Self.readCall))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        var expected = frozen.package.jsonObject
        expected["ok"] = true
        #expect(NSDictionary(dictionary: object).isEqual(to: expected))
    }

    // MARK: Proposals: limits in code

    @Test func proposal_outOfRange_isRejectedWithMessage_andChangesNothing() async throws {
        let tools = makeTools()
        tools.begin(session)
        let before = goals.plans()
        let output = await tools.run(call(.functionCall(callID: "x", name: "propose_nutrition_goals", arguments:
            #"{"kcal":null,"protein_g":9000,"carbs_g":null,"fat_g":null,"fiber_g":null,"sugar_limit_g":null,"water_ml":null,"target_weight_kg":null,"pace_kg_per_week":null,"reason":""}"#)))
        #expect(output.contains("protein_g"))
        #expect(goals.plans() == before)
    }

    @Test func proposal_belowHardLimit_isRefused_evenWithoutTheInterface() async throws {
        let tools = makeTools()
        tools.begin(session)
        let before = goals.plans()
        let output = await tools.run(call(Self.nutritionCall(kcal: "900")))
        #expect(output.contains("error") && output.contains("1.000"))
        #expect(goals.plans() == before, "a proposal below the hard limit can never be saved")
    }

    @Test func toolResults_neverCarryBodyDerivedNumbers() async {
        let tools = makeTools()
        tools.begin(session)
        // The proposal itself raises warnings; the result may name its own values and constants, never resting energy and the like.
        let output = await tools.run(call(Self.nutritionCall(kcal: "900")))
        let accepted = await tools.run(call(Self.nutritionCall(kcal: "1400", protein: "60", carbs: "120", fat: "40", pace: "-0.9")))
        for derived in ["1780", "1.780", "2140", "2.140", "2540", "2.540", "57", "82.1", "1992"] {
            #expect(!output.contains(derived) && !accepted.contains(derived), "\(derived) would reveal the body data")
        }
    }

    // MARK: Adopting

    @Test func nullFields_keepCurrentValues() async throws {
        let tools = makeTools()
        tools.begin(session)
        let current = try #require(goals.current(on: today))
        _ = await tools.run(call(.functionCall(callID: "x", name: "propose_nutrition_goals", arguments:
            #"{"kcal":2000,"protein_g":null,"carbs_g":null,"fat_g":null,"fiber_g":null,"sugar_limit_g":null,"water_ml":null,"target_weight_kg":null,"pace_kg_per_week":null,"reason":"x"}"#)))
        let adopted = try #require(goals.current(on: today))
        #expect(adopted.kcal == 2000 && adopted.waterMilliliters == current.waterMilliliters && adopted.stepsPerDay == current.stepsPerDay)
        #expect(adopted.proteinGrams == current.proteinGrams)
    }

    // MARK: Cards

    @Test func goalCards_areSingleConfirmation_andConfirmAllSkipsThem() async {
        let (model, tools, _) = await makeModel()
        openGoals(model, tools)
        responder.enqueueEvents([Self.nutritionCall(), Self.activityCall, .completed(usage: nil)])
        await model.send("Plane")
        #expect(AssistantModel.needsSingleConfirmation(call(Self.nutritionCall()), me: nil))
        #expect(model.batchConfirmable.isEmpty)
        let before = goals.plans()
        await model.confirmAll()
        #expect(goals.plans() == before)
        #expect(model.conversation?.pendingActions.count == 2)
        #expect(AssistantModel.singleConfirmationNotice(for: model.conversation?.pendingActions ?? []) == "Ziele bestätigst du einzeln.")
        #expect(model.openCards.guarded == 2)
    }

    @Test func clearingTheHistory_endsTheSession() async {
        let (model, tools, _) = await makeModel()
        openGoals(model, tools)
        #expect(tools.session != nil)
        model.clear()
        #expect(tools.session == nil)
    }

    @Test func openGoals_withoutConsent_doesNothing() async {
        let (model, tools, _) = await makeModel()
        settings.goalPlanningConsent = false
        model.openGoals(session: session)
        #expect(!model.isPresented && tools.session == nil)
    }

    @Test func openGoals_whileOtherChatBusy_waits() async {
        let gate = TurnGate()
        let (model, tools, _) = await makeModel(responder: gate)
        model.open(context: .settings)
        gate.enqueue([.textDelta("Hallo."), .completed(usage: nil)], blocked: true)
        let sending = Task { await model.send("Hallo") }
        while !gate.isHolding { await Task.yield() }
        model.openGoals(session: session)
        #expect(model.context == .settings, "the running chat stays")
        gate.release()
        await sending.value
        _ = tools
    }

    @Test func prefill_isTakenOnce_andNothingIsSent() async {
        let (model, tools, _) = await makeModel()
        model.openGoals(session: session, prefill: "Fortschritt besprechen")
        #expect(model.takeGoalsPrefill() == "Fortschritt besprechen")
        #expect(model.takeGoalsPrefill() == nil)
        #expect(responder.calls.isEmpty)
        _ = tools
    }

    @Test func activityLine_sameForFullAndStoredOutput() async throws {
        let tools = makeTools()
        tools.begin(session)
        let full = await tools.run(call(Self.readCall))
        let stored = GoalChatTools.storedPackageOutput(full)
        let fullLine = try #require(AssistantModel.goalActivityText(full))
        #expect(fullLine == AssistantModel.goalActivityText(stored))
        #expect(fullLine.contains("28"))
        #expect(AssistantModel.goalActivityText(#"{"error":"x"}"#) == nil)
    }

    @Test func adopting_tellsTheScreensToReload() async {
        let tools = makeTools()
        tools.begin(session)
        var adopted = 0
        tools.onAdopted = { adopted += 1 }
        _ = await tools.run(call(Self.nutritionCall()))
        #expect(adopted == 1)
        _ = await tools.run(call(Self.nutritionCall(kcal: "900")))
        #expect(adopted == 1, "a refused proposal changes nothing and tells nobody")
    }
}
