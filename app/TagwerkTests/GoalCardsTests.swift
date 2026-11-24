import AIKit
import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The cards of the goal proposals (task G6): old and new values, the cross-check, the second confirmation, "Anpassen". All data is invented.
@MainActor
struct GoalCardsTests: GoalChatSuite {
    let h: GoalChatHarness

    init() throws { h = try GoalChatHarness() }

    @Test func adopt_createsOnePlanFromToday_forBothCards() async throws {
        let (model, tools, _) = await makeModel()
        openGoals(model, tools)
        responder.enqueueEvents([Self.readCall, Self.nutritionCall(), Self.activityCall, .completed(usage: nil)])
        await model.send("Plane meine Ziele")
        #expect(model.conversation?.pendingActions.map(\.id) == ["n1", "a1"])
        let before = goals.plans().count
        await model.confirm(call(Self.nutritionCall()), acknowledgedWarning: true)
        await model.confirm(call(Self.activityCall))
        let plans = goals.plans()
        #expect(plans.count == before + 1 || plans.count == before, "both cards build one plan from today")
        let plan = try #require(goals.current(on: today))
        #expect(plan.validFrom == today && plan.origin == .assistant)
        #expect(plan.kcal == 1800 && plan.proteinGrams == 150 && plan.targetWeightKg == 78.0)
        #expect(plan.stepsPerDay == 9000 && plan.workoutMinutesPerWeek == 180, "the second card keeps the values of the first")
        #expect(plans.filter { $0.validFrom == today }.count == 1)
    }

    @Test func card_showsOldAndNewValues_andTheCrossCheck() async {
        let (model, tools, _) = await makeModel()
        openGoals(model, tools)
        responder.enqueueEvents([Self.nutritionCall(), .completed(usage: nil)])
        await model.send("Plane")
        let card = model.describe(call(Self.nutritionCall()))
        #expect(card.change.contains("2.300 kcal → 1.800 kcal"))
        #expect(card.change.contains("Gegenrechnung von Tagwerk"))
        #expect(card.change.contains("Grundbedarf ohne Bewegung"))
        #expect(card.confirmTitle == "Übernehmen")
    }

    @Test func card_withWarning_needsSecondConfirmation() async throws {
        let (model, tools, _) = await makeModel()
        openGoals(model, tools)
        // 1,500 kcal at an expenditure of about 2,540 kcal: the deficit is above the rule of the app.
        let risky = Self.nutritionCall(kcal: "1500", protein: "130", carbs: "130", fat: "50", pace: "-0.5")
        responder.enqueueEvents([risky, .completed(usage: nil)])
        await model.send("Plane")
        let card = model.describe(call(risky))
        #expect(card.warning != nil && card.asksTwice && !card.blocksConfirmation)
        let before = goals.plans()
        await model.confirm(call(risky))
        #expect(goals.plans() == before, "without the second confirmation nothing runs")
        #expect(model.conversation?.pendingActions.map(\.id) == ["n1"])
        await model.confirm(call(risky), acknowledgedWarning: true)
        #expect(goals.current(on: today)?.kcal == 1500)
    }

    @Test func card_belowHardLimit_isBlocked_andNeverRuns() async {
        let (model, tools, _) = await makeModel()
        openGoals(model, tools)
        let blocked = Self.nutritionCall(kcal: "900")
        responder.enqueueEvents([blocked, .completed(usage: nil)])
        await model.send("Plane")
        let card = model.describe(call(blocked))
        #expect(card.blocksConfirmation)
        let before = goals.plans()
        await model.confirm(call(blocked), acknowledgedWarning: true)
        #expect(goals.plans() == before)
    }

    @Test func spokenConfirmation_neverRunsAGoalCard() async {
        let (model, tools, _) = await makeModel()
        openGoals(model, tools)
        responder.enqueueEvents([Self.nutritionCall(), .completed(usage: nil)])
        await model.send("Plane")
        let before = goals.plans()
        await model.confirmCards(["n1"])
        #expect(goals.plans() == before)
    }

    @Test func spokenDescription_existsForGoalCards() async {
        let (model, tools, _) = await makeModel()
        openGoals(model, tools)
        responder.enqueueEvents([Self.nutritionCall(), Self.activityCall, .completed(usage: nil)])
        await model.send("Plane")
        for event in [Self.nutritionCall(), Self.activityCall] {
            let spoken = model.describe(call(event), language: .german, spoken: true)
            #expect(!spoken.title.isEmpty && !spoken.change.isEmpty && !spoken.change.contains("→"))
        }
    }

    // MARK: Adjusting

    @Test func adjust_thenAdopt_usesEditedValues_andRecomputesTheCheck() async throws {
        let (model, tools, _) = await makeModel()
        openGoals(model, tools)
        let risky = Self.nutritionCall(kcal: "1500", protein: "130", carbs: "130", fat: "50", pace: "-0.5")
        responder.enqueueEvents([risky, .completed(usage: nil)])
        await model.send("Plane")
        let original = model.describe(call(risky))
        #expect(original.warning != nil && original.canAdjust)
        var arguments = try #require(ProposalArguments.decode(call(risky).arguments))
        arguments["kcal"] = 2000
        arguments["carbs_g"] = 220
        arguments["fat_g"] = 65
        arguments["pace_kg_per_week"] = -0.2
        let adjusted = try #require(model.adjust(call(risky), arguments: ProposalArguments.encode(arguments)))
        let card = model.describe(adjusted)
        #expect(card.warning == nil, "the cross-check is computed again for the edited values")
        #expect(card.change.contains("2.000 kcal") && card.mark == .byUser)
        await model.confirm(adjusted)
        #expect(goals.current(on: today)?.kcal == 2000)
        let output = model.conversation?.history.compactMap { item -> String? in
            if case .functionOutput(_, let output) = item { return output } else { return nil }
        }.last ?? ""
        #expect(output.contains("2000") && output.contains("adjusted_by_user"), "the model learns what was adopted and that the user changed it")
    }

    @Test func goalEditor_isValidOnlyWhenTheValuesAreAllowed() async throws {
        let (model, tools, _) = await makeModel()
        openGoals(model, tools)
        let blocked = Self.nutritionCall(kcal: "900")
        responder.enqueueEvents([blocked, .completed(usage: nil)])
        await model.send("Plane")
        let editor = try #require(model.proposalEditor(for: call(blocked)) as? GoalProposalEditor)
        #expect(!editor.isValid)
        editor.values["kcal"] = 1800
        #expect(editor.isValid)
        let arguments = try #require(ProposalArguments.decode(editor.arguments()))
        #expect(arguments["kcal"] as? Int == 1800)
        #expect(arguments["protein_g"] as? Int == 150, "untouched values keep exactly what the call had")
    }

    @Test func cardFollowUp_needsTheGoalConsent() async {
        let (model, tools, _) = await makeModel()
        openGoals(model, tools)
        #expect(model.cardFollowUpHasConsent)
        settings.goalPlanningConsent = false
        #expect(!model.cardFollowUpHasConsent)
    }
}
