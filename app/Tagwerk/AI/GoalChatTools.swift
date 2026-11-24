import AIKit
import Foundation
import TagwerkCore

extension AppTools.Arguments {
    /// A number of the call as a `Double`; `nil` for a missing or null value.
    func double(_ key: String) -> Double? { (values[key] as? NSNumber)?.doubleValue }
}

/// The tool set of the chat "Ziele planen" (decisions ZI1b, ZI3b): `get_goal_data` reads the package of the session, the two proposals
/// are cards. An own handler without `AppTools` as a base: this chat has no search, no notes and no functions for tasks and events, and no
/// other chat has these functions. Every limit is enforced here in code; the instructions only repeat it.
@MainActor
final class GoalChatTools: ToolHandler {
    nonisolated static let readTools: Set<String> = ["get_goal_data"]
    nonisolated static let proposalTools: Set<String> = ["propose_nutrition_goals", "propose_activity_goals"]

    /// Called after a plan was adopted, so the screens that show the goals (the head of "Erfassen", the widget) read the new plan.
    var onAdopted: () -> Void = {}

    /// The session of the running conversation; `nil` before the user chose the data and after the conversation ended.
    private(set) var session: GoalPlanningSession?
    private let hasConsent: () -> Bool
    private let currentPlan: () -> GoalPlan
    private let adopt: (GoalPlan) -> Void
    private let today: () -> PlanDay

    /// - Parameters:
    ///   - currentPlan: the plan that holds today, where both cards of a conversation build on each other.
    ///   - adopt: stores the plan as the plan that holds from today (`GoalStore.adopt`).
    init(hasConsent: @escaping () -> Bool, currentPlan: @escaping () -> GoalPlan, adopt: @escaping (GoalPlan) -> Void,
         today: @escaping () -> PlanDay) {
        self.hasConsent = hasConsent
        self.currentPlan = currentPlan
        self.adopt = adopt
        self.today = today
    }

    /// The plan that holds today: the base every proposal builds on.
    func plan() -> GoalPlan { currentPlan() }

    func begin(_ session: GoalPlanningSession) { self.session = session }
    func end() { session = nil }

    // MARK: ToolHandler

    var definitions: [ToolDefinition] { Self.allDefinitions }

    func kind(of name: String) -> ToolKind { Self.readTools.contains(name) ? .read : .write }

    /// `get_goal_data` keeps only the groups and the period; the proposals keep their arguments and results (goal numbers, no
    /// measured values, and the user saw them).
    func storedForm(of call: ToolCall, output: String?) -> (arguments: String, output: String?) {
        let arguments = String(decoding: call.arguments, as: UTF8.self)
        guard call.name == "get_goal_data", let output else { return (arguments, output) }
        return (arguments, Self.storedPackageOutput(output))
    }

    func showsActivity(_ name: String) -> Bool { Self.readTools.contains(name) }

    func run(_ call: ToolCall) async -> String {
        guard hasConsent() else { return AppTools.error(String(localized: "Die Einwilligung „Ziele mit ChatGPT planen“ fehlt.")) }
        guard let object = try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any] else {
            return AppTools.error(String(localized: "Die Argumente sind kein gültiges JSON."))
        }
        switch call.name {
        case "get_goal_data": return packageOutput()
        case "propose_nutrition_goals": return adoptNutrition(Self.nutritionProposal(AppTools.Arguments(object)))
        case "propose_activity_goals": return adoptActivity(Self.activityProposal(AppTools.Arguments(object)))
        default: return AppTools.error(String(localized: "Unbekannte Funktion \(call.name)."))
        }
    }

    // MARK: get_goal_data

    /// The frozen package; the same value the sheet showed. Without a session (no selection yet) there is no value.
    private func packageOutput() -> String {
        guard let session else { return AppTools.error(String(localized: "Der Nutzer hat noch keine Daten freigegeben.")) }
        var object = session.package.jsonObject
        object["ok"] = true
        return AppTools.json(object)
    }

    /// `{"ok":true,"groups":[…],"days":N}`: what a stored chat keeps. An error or an unknown shape stays as it is.
    static func storedPackageOutput(_ output: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any], object["ok"] as? Bool == true else {
            return output
        }
        // Already the stored form: nothing left to reduce.
        if object["groups"] is [String] { return output }
        let groups = GoalDataGroup.allCases.map(\.jsonKey).filter { object[$0] != nil }
        return AppTools.json(["ok": true, "groups": groups, "days": object["period_days"] as? Int ?? 0])
    }

    // MARK: Proposals

    static func nutritionProposal(_ args: AppTools.Arguments) -> NutritionGoalProposal {
        NutritionGoalProposal(kcal: args.int("kcal"), proteinGrams: args.int("protein_g"), carbsGrams: args.int("carbs_g"),
                              fatGrams: args.int("fat_g"), fiberGrams: args.int("fiber_g"), sugarLimitGrams: args.int("sugar_limit_g"),
                              waterMilliliters: args.int("water_ml"), targetWeightKg: args.double("target_weight_kg"),
                              paceKgPerWeek: args.double("pace_kg_per_week"), reason: args.string("reason") ?? "")
    }

    static func activityProposal(_ args: AppTools.Arguments) -> ActivityGoalProposal {
        ActivityGoalProposal(stepsPerDay: args.int("steps_per_day"), workoutMinutesPerWeek: args.int("workout_minutes_per_week"),
                             activeKcalPerDay: args.int("active_kcal_per_day"), reason: args.string("reason") ?? "")
    }

    /// Adopts a nutrition proposal as the plan of today. The limits hold here as well as on the card: an out-of-range value and a base
    /// goal below the hard limit are refused, whatever the interface did. Nothing that is derived from the body goes into the answer.
    private func adoptNutrition(_ proposal: NutritionGoalProposal) -> String {
        guard !proposal.isEmpty else { return AppTools.error(String(localized: "Der Vorschlag enthält keinen Wert.")) }
        if let kcal = proposal.kcal, kcal < GoalGuardConstants.hardMinimumKcal {
            return AppTools.error(Self.hardLimitMessage)
        }
        if let message = Self.rangeMessage(proposal.violations) { return AppTools.error(message) }
        let plan = currentPlan().applying(proposal)
        if let input = session?.guardInput, GoalGuard.check(proposal: plan, body: input.body, weightKg: input.weightKg,
                                                            meanActiveKcal: input.meanActiveKcal, year: input.year).isBlocked {
            return AppTools.error(Self.hardLimitMessage)
        }
        store(plan, reason: proposal.reason)
        return AppTools.json(["ok": true, "adopted": Self.adoptedValues(of: proposal)])
    }

    private func adoptActivity(_ proposal: ActivityGoalProposal) -> String {
        guard !proposal.isEmpty else { return AppTools.error(String(localized: "Der Vorschlag enthält keinen Wert.")) }
        if let message = Self.rangeMessage(proposal.violations) { return AppTools.error(message) }
        store(currentPlan().applying(proposal), reason: proposal.reason)
        return AppTools.json(["ok": true, "adopted": Self.adoptedValues(of: proposal)])
    }

    /// The plan that holds from today, built on the plan of today: a second card of the same conversation adds to the first.
    private func store(_ plan: GoalPlan, reason: String) {
        var adopted = plan
        let day = today()
        if adopted.validFrom != day {
            adopted.id = UUID()
            adopted.validFrom = day
        }
        adopted.origin = .assistant
        if !reason.isEmpty { adopted.note = reason }
        adopt(adopted)
        onAdopted()
    }

    static var hardLimitMessage: String {
        let limit = IntakeFormat.grouped(GoalGuardConstants.hardMinimumKcal)
        return String(localized: "Das Grundziel liegt unter der harten Grenze von \(limit) kcal und lässt sich nicht übernehmen.")
    }

    static func rangeMessage(_ violations: [GoalRangeViolation]) -> String? {
        guard !violations.isEmpty else { return nil }
        let parts = violations.map { violation -> String in
            let lower = violation.lower.rounded() == violation.lower ? String(Int(violation.lower)) : String(violation.lower)
            let upper = violation.upper.rounded() == violation.upper ? String(Int(violation.upper)) : String(violation.upper)
            return "\(violation.field) (\(lower) … \(upper))"
        }
        return String(localized: "Diese Werte liegen außerhalb des erlaubten Bereichs: \(parts.joined(separator: ", ")).")
    }

    /// The values that were adopted: goal numbers only.
    static func adoptedValues(of proposal: NutritionGoalProposal) -> [String: Any] {
        var values: [String: Any] = [:]
        if let value = proposal.kcal { values["kcal"] = value }
        if let value = proposal.proteinGrams { values["protein_g"] = value }
        if let value = proposal.carbsGrams { values["carbs_g"] = value }
        if let value = proposal.fatGrams { values["fat_g"] = value }
        if let value = proposal.fiberGrams { values["fiber_g"] = value }
        if let value = proposal.sugarLimitGrams { values["sugar_limit_g"] = value }
        if let value = proposal.waterMilliliters { values["water_ml"] = value }
        if let value = proposal.targetWeightKg { values["target_weight_kg"] = value }
        if let value = proposal.paceKgPerWeek { values["pace_kg_per_week"] = value }
        return values
    }

    static func adoptedValues(of proposal: ActivityGoalProposal) -> [String: Any] {
        var values: [String: Any] = [:]
        if let value = proposal.stepsPerDay { values["steps_per_day"] = value }
        if let value = proposal.workoutMinutesPerWeek { values["workout_minutes_per_week"] = value }
        if let value = proposal.activeKcalPerDay { values["active_kcal_per_day"] = value }
        return values
    }

    // MARK: Definitions

    private static func number(_ description: String) -> [String: Any] {
        ["type": ["number", "null"], "description": description]
    }

    private static func integer(_ description: String) -> [String: Any] {
        ["type": ["integer", "null"], "description": description]
    }

    /// The three functions of the chat; strict schemas like every function of the app (all properties required, optional ones nullable).
    static var allDefinitions: [ToolDefinition] {
        [
            AppTools.tool("get_goal_data", "Returns the data package the user selected for this conversation: body values, weight and trend, averages of nutrition, activity and water over the period, and the current goals. Only the groups the user switched on are in it; a group that is missing was not shared. Call it before every proposal and do not ask the user for values that are in it.", [:]),
            AppTools.tool("propose_nutrition_goals", "Proposes nutrition goals as a card the user confirms, adjusts or declines. kcal is the BASE goal for a day without credited activity (it is not a total need). Pass null for every value that should stay as it is. Needs confirmation.", [
                "kcal": integer("Base goal in kcal for a day without credited activity; at least 1000"),
                "protein_g": integer("Protein goal in grams"),
                "carbs_g": integer("Carbohydrate goal in grams, for a day without credited activity"),
                "fat_g": integer("Fat goal in grams, for a day without credited activity"),
                "fiber_g": integer("Fibre goal in grams"),
                "sugar_limit_g": integer("Upper limit of sugar in grams"),
                "water_ml": integer("Water goal in millilitres"),
                "target_weight_kg": number("Target weight in kilograms"),
                "pace_kg_per_week": number("Intended weekly change of the weight in kilograms; negative for losing weight"),
                "reason": AppTools.string("One or two sentences why, shown on the card and kept with the goals"),
            ]),
            AppTools.tool("propose_activity_goals", "Proposes activity goals as a card the user confirms, adjusts or declines. Activity goals are optional: propose them only when the user wants them. Pass null for every value that should stay as it is. Needs confirmation.", [
                "steps_per_day": integer("Steps per day; 0 shows the steps without a goal"),
                "workout_minutes_per_week": integer("Training minutes per week; 0 hides the tile"),
                "active_kcal_per_day": integer("Goal for the active energy per day in kcal; 0 switches it off"),
                "reason": AppTools.string("One or two sentences why, shown on the card and kept with the goals"),
            ]),
        ]
    }
}
