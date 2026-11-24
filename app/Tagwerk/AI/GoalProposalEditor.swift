import AIKit
import Observation
import SwiftUI
import TagwerkCore

/// Editor for `propose_nutrition_goals` and `propose_activity_goals` (plan ki-vorschlaege-anpassen, "Anpassen" of the goal cards, decision
/// ZI3b): one switch and one number field per value. A switched-off value is `null` in the arguments and keeps the current goal. The
/// cross-check of the card is computed again from the fields after every change, and "Fertig" stays disabled while a value is out of
/// range or the base goal is below the hard limit.
@MainActor
@Observable
final class GoalProposalEditor: ProposalEditor {
    nonisolated static let toolNames: Set<String> = GoalChatTools.proposalTools

    /// One value of a proposal as the sheet edits it.
    struct Field: Identifiable {
        enum Number {
            case whole(ClosedRange<Int>, step: Int)
            case decimal(ClosedRange<Double>, step: Double)
        }

        var key: String
        var title: LocalizedStringKey
        var number: Number
        /// What the field starts with when it is switched on for a goal that has no value yet.
        var start: Double
        var id: String { key }
    }

    let call: ToolCall
    let context: ProposalEditorContext
    let isNutrition: Bool
    let fieldList: [Field]
    /// The value of each switched-on field; a missing key is `null` ("keep as it is").
    var values: [String: Double]
    var reason: String

    @ObservationIgnored private let base: [String: Any]
    @ObservationIgnored private let initialValues: [String: Double]
    @ObservationIgnored private let initialReason: String

    required init?(call: ToolCall, context: ProposalEditorContext) {
        guard Self.toolNames.contains(call.name), let base = ProposalArguments.decode(call.arguments) else { return nil }
        self.call = call
        self.context = context
        self.base = base
        isNutrition = call.name == "propose_nutrition_goals"
        let plan = context.currentGoalPlan()
        fieldList = isNutrition ? Self.nutritionFields(plan: plan) : Self.activityFields(plan: plan)
        var present: [String: Double] = [:]
        for field in fieldList {
            if let number = base[field.key] as? NSNumber, !(base[field.key] is NSNull) { present[field.key] = number.doubleValue }
        }
        values = present
        initialValues = present
        let reasonText = base["reason"] as? String ?? ""
        reason = reasonText
        initialReason = reasonText
    }

    // MARK: Fields

    private static func nutritionFields(plan: GoalPlan?) -> [Field] {
        [
            Field(key: "kcal", title: "Kalorien ohne Aktivität", number: .whole(GoalRanges.kcal, step: 50), start: Double(plan?.kcal ?? 2000)),
            Field(key: "protein_g", title: "Eiweiß", number: .whole(GoalRanges.proteinGrams, step: 5), start: Double(plan?.proteinGrams ?? 120)),
            Field(key: "carbs_g", title: "Kohlenhydrate", number: .whole(GoalRanges.carbsGrams, step: 5), start: Double(plan?.carbsGrams ?? 250)),
            Field(key: "fat_g", title: "Fett", number: .whole(GoalRanges.fatGrams, step: 5), start: Double(plan?.fatGrams ?? 70)),
            Field(key: "fiber_g", title: "Ballaststoffe", number: .whole(GoalRanges.fiberGrams, step: 1), start: Double(plan?.fiberGrams ?? 30)),
            Field(key: "sugar_limit_g", title: "Zucker, höchstens", number: .whole(GoalRanges.sugarLimitGrams, step: 5), start: Double(plan?.sugarLimitGrams ?? 50)),
            Field(key: "water_ml", title: "Wasser", number: .whole(GoalRanges.waterMilliliters, step: 250), start: Double(plan?.waterMilliliters ?? 2000)),
            Field(key: "target_weight_kg", title: "Zielgewicht", number: .decimal(GoalRanges.targetWeightKg, step: WeightRules.stepKilograms), start: plan?.targetWeightKg ?? 75),
            Field(key: "pace_kg_per_week", title: "Tempo", number: .decimal(GoalRanges.paceKgPerWeek, step: 0.1), start: plan?.paceKgPerWeek ?? -0.3),
        ]
    }

    private static func activityFields(plan: GoalPlan?) -> [Field] {
        [
            Field(key: "steps_per_day", title: "Schritte pro Tag", number: .whole(GoalRanges.stepsPerDay, step: 500), start: Double(plan?.stepsPerDay ?? 8000)),
            Field(key: "workout_minutes_per_week", title: "Training pro Woche", number: .whole(GoalRanges.workoutMinutesPerWeek, step: 15), start: Double(plan?.workoutMinutesPerWeek ?? 150)),
            Field(key: "active_kcal_per_day", title: "Aktivitätsenergie pro Tag", number: .whole(GoalRanges.activeKcalPerDay, step: 50), start: Double(plan?.activeKcalPerDay ?? 400)),
        ]
    }

    // MARK: ProposalEditor

    /// The arguments as the fields hold them now, as a call, for the live cross-check.
    private var currentCall: ToolCall { ToolCall(id: call.id, name: call.name, arguments: arguments()) }

    /// The card content of the current values: the cross-check and whether the proposal can be adopted.
    var content: GoalCardContent? {
        GoalCards.content(for: currentCall, plan: context.currentGoalPlan() ?? Self.fallbackPlan, input: context.goalGuardInput())
    }

    private static var fallbackPlan: GoalPlan {
        GoalPlan(validFrom: PlanDay(year: 1970, month: 1, day: 1), kcal: 2000, waterMilliliters: 2000, stepsPerDay: 8000, workoutMinutesPerWeek: 150)
    }

    var isValid: Bool { content.map { !$0.isBlocked } ?? false }

    func arguments() -> Data {
        var result = base
        for field in fieldList where values[field.key] != initialValues[field.key] {
            if let value = values[field.key] {
                switch field.number {
                case .whole: result[field.key] = Int(value.rounded())
                case .decimal: result[field.key] = value
                }
            } else {
                result[field.key] = NSNull()
            }
        }
        if reason != initialReason { result["reason"] = reason }
        return ProposalArguments.encode(result)
    }

    var fields: AnyView { AnyView(GoalProposalFields(editor: self)) }

    func load() async {}

    func isOn(_ key: String) -> Bool { values[key] != nil }

    func setOn(_ isOn: Bool, for field: Field) {
        if isOn { values[field.key] = values[field.key] ?? field.start } else { values[field.key] = nil }
    }
}

private struct GoalProposalFields: View {
    @Bindable var editor: GoalProposalEditor

    var body: some View {
        Section {
            ForEach(editor.fieldList) { field in
                Toggle(field.title, isOn: Binding(get: { editor.isOn(field.key) }, set: { editor.setOn($0, for: field) }))
                if editor.isOn(field.key) { stepper(field) }
            }
        } footer: {
            Text("Ein Wert, der aus ist, bleibt, wie er in deinen Zielen steht.")
        }
        if let content = editor.content {
            Section {
                Text(content.change).font(.footnote)
                if let warning = content.warning { Text(warning).font(.footnote).foregroundStyle(.redText) }
            } header: {
                Text("Gegenrechnung")
            }
        }
    }

    @ViewBuilder
    private func stepper(_ field: GoalProposalEditor.Field) -> some View {
        switch field.number {
        case .whole(let range, let step):
            ValueStepper(field.title, value: Binding(get: { Int((editor.values[field.key] ?? field.start).rounded()) },
                                                     set: { editor.values[field.key] = Double($0) }),
                         in: range, step: step) { String($0) }
        case .decimal(let range, let step):
            ValueStepper(field.title, value: Binding(get: { editor.values[field.key] ?? field.start }, set: { editor.values[field.key] = $0 }),
                         in: range, step: step, kind: .decimal(fractionDigits: 1)) { String(format: "%.1f", $0) }
        }
    }
}
