import AIKit
import Foundation
import TagwerkCore

/// What a card of a goal proposal shows and what its limits are (decisions ZI2b, ZI3b): the old and new values, the cross-check of
/// Tagwerk and the warning that makes "Übernehmen" ask a second time. The assistant chat describes the card with it, the editor of
/// "Anpassen" checks its values with it, and the confirmation asks it before it runs anything.
struct GoalCardContent: Equatable {
    var title: String
    /// The rows "Kalorien ohne Aktivität: 2.300 → 1.800 kcal" and below them the lines of the cross-check.
    var change: String
    /// The warnings of the cross-check; `nil` without one. The card shows it in red and the confirmation asks a second time.
    var warning: String?
    /// The proposal cannot be adopted: the base goal is below the hard limit, or a value is out of range.
    var isBlocked: Bool
}

@MainActor
enum GoalCards {
    static func isGoalCall(_ name: String) -> Bool { GoalChatTools.proposalTools.contains(name) }

    /// The content of the card of `call`; `nil` for any other function. `plan` is the plan that holds today, `input` the data of the
    /// cross-check (`nil` while the conversation has none).
    static func content(for call: ToolCall, plan: GoalPlan, input: GoalGuardInput?, locale: Locale = .current) -> GoalCardContent? {
        guard let object = try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any] else { return nil }
        let args = AppTools.Arguments(object)
        switch call.name {
        case "propose_nutrition_goals":
            return nutritionContent(GoalChatTools.nutritionProposal(args), plan: plan, input: input, locale: locale)
        case "propose_activity_goals":
            return activityContent(GoalChatTools.activityProposal(args), plan: plan, locale: locale)
        default:
            return nil
        }
    }

    /// The cross-check of the plan that would hold after `proposal`.
    static func check(_ proposal: NutritionGoalProposal, plan: GoalPlan, input: GoalGuardInput?, locale: Locale = .current) -> GoalCheck {
        let merged = plan.applying(proposal)
        guard let input else {
            // Without data the checks that need none still run.
            return GoalGuard.check(proposal: merged, body: .empty, weightKg: nil, meanActiveKcal: nil,
                                   year: Calendar.current.component(.year, from: Date()), locale: locale)
        }
        return GoalGuard.check(proposal: merged, body: input.body, weightKg: input.weightKg, meanActiveKcal: input.meanActiveKcal,
                               year: input.year, locale: locale)
    }

    private static func nutritionContent(_ proposal: NutritionGoalProposal, plan: GoalPlan, input: GoalGuardInput?,
                                         locale: Locale) -> GoalCardContent {
        func grams(_ value: Int) -> String { IntakeFormat.grams(Double(value), estimated: false) }
        var rows: [String] = []
        func row(_ label: String, _ old: String?, _ new: String) {
            rows.append(old.map { "\(label): \($0) → \(new)" } ?? "\(label): \(new)")
        }
        if let value = proposal.kcal {
            row(String(localized: "Kalorien ohne Aktivität"), IntakeFormat.kcal(Double(plan.kcal), estimated: false, locale: locale),
                IntakeFormat.kcal(Double(value), estimated: false, locale: locale))
        }
        if let value = proposal.proteinGrams { row(String(localized: "Eiweiß"), plan.proteinGrams.map(grams), grams(value)) }
        if let value = proposal.carbsGrams { row(String(localized: "Kohlenhydrate"), plan.carbsGrams.map(grams), grams(value)) }
        if let value = proposal.fatGrams { row(String(localized: "Fett"), plan.fatGrams.map(grams), grams(value)) }
        if let value = proposal.fiberGrams { row(String(localized: "Ballaststoffe"), plan.fiberGrams.map(grams), grams(value)) }
        if let value = proposal.sugarLimitGrams { row(String(localized: "Zucker, höchstens"), plan.sugarLimitGrams.map(grams), grams(value)) }
        if let value = proposal.waterMilliliters {
            row(String(localized: "Wasser"), IntakeFormat.liters(plan.waterMilliliters, locale: locale), IntakeFormat.liters(value, locale: locale))
        }
        if let value = proposal.targetWeightKg {
            row(String(localized: "Zielgewicht"), plan.targetWeightKg.map { WeightFormat.kilograms($0, locale: locale) }, WeightFormat.kilograms(value, locale: locale))
        }
        if let value = proposal.paceKgPerWeek {
            row(String(localized: "Tempo"), plan.paceKgPerWeek.map { WeightFormat.changePerWeek($0, locale: locale) }, WeightFormat.changePerWeek(value, locale: locale))
        }
        if rows.isEmpty { rows.append(String(localized: "Keine Änderung")) }
        var lines = rows
        if !proposal.reason.isEmpty { lines.append(String(localized: "Begründung: \(proposal.reason)")) }
        let check = check(proposal, plan: plan, input: input, locale: locale)
        lines += check.summaryLines
        lines += check.hints.map(\.text)
        var warning = check.warningText
        let violations = proposal.violations.filter { !($0.field == "kcal" && (proposal.kcal ?? 0) < GoalGuardConstants.hardMinimumKcal) }
        var blocked = check.isBlocked || !violations.isEmpty || proposal.isEmpty
        if let message = GoalChatTools.rangeMessage(violations) { warning = [warning, message].compactMap { $0 }.joined(separator: "\n") }
        if let kcal = proposal.kcal, kcal < GoalGuardConstants.hardMinimumKcal { blocked = true }
        return GoalCardContent(title: String(localized: "Ernährungsziele"), change: lines.joined(separator: "\n"), warning: warning,
                               isBlocked: blocked)
    }

    private static func activityContent(_ proposal: ActivityGoalProposal, plan: GoalPlan, locale: Locale) -> GoalCardContent {
        var rows: [String] = []
        if let value = proposal.stepsPerDay {
            rows.append(String(localized: "Schritte pro Tag: \(stepsText(plan.stepsPerDay, locale: locale)) → \(stepsText(value, locale: locale))"))
        }
        if let value = proposal.workoutMinutesPerWeek {
            rows.append(String(localized: "Training pro Woche: \(minutesText(plan.workoutMinutesPerWeek)) → \(minutesText(value))"))
        }
        if let value = proposal.activeKcalPerDay {
            rows.append(String(localized: "Aktivitätsenergie pro Tag: \(kcalText(plan.activeKcalPerDay, locale: locale)) → \(kcalText(value, locale: locale))"))
        }
        if rows.isEmpty { rows.append(String(localized: "Keine Änderung")) }
        if !proposal.reason.isEmpty { rows.append(String(localized: "Begründung: \(proposal.reason)")) }
        let message = GoalChatTools.rangeMessage(proposal.violations)
        return GoalCardContent(title: String(localized: "Aktivitätsziele"), change: rows.joined(separator: "\n"), warning: message,
                               isBlocked: message != nil || proposal.isEmpty)
    }

    private static func stepsText(_ steps: Int, locale: Locale) -> String {
        steps > 0 ? IntakeFormat.grouped(steps, locale: locale) : String(localized: "ohne Ziel")
    }

    private static func minutesText(_ minutes: Int) -> String {
        minutes > 0 ? IntakeFormat.duration(minutes: minutes) : String(localized: "aus")
    }

    private static func kcalText(_ kcal: Int, locale: Locale) -> String {
        kcal > 0 ? IntakeFormat.kcal(Double(kcal), estimated: false, locale: locale) : String(localized: "aus")
    }
}
