import Foundation

/// One row of the card "Nährwerte" (decision NU2b): a name, the value against its goal and a bar.
public struct NutrientRow: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case protein, carbohydrates, fat
        case further(Nutrient)

        /// Protein, carbohydrates and fat are always on the card; the further nutrients fold out.
        public var isMacro: Bool {
            if case .further = self { false } else { true }
        }
    }

    public var kind: Kind
    public var id: Kind { kind }
    public var title: String
    /// "~68 / 140 g", "14 g", "38 / max. 50 g", "–" while nothing is known (never 0).
    public var valueText: String
    /// What a screen reader says for the value: "68 von 140 Gramm".
    public var spokenValue: String
    /// Share of the goal reached, `nil` without a goal or a value; the view caps the bar at 1.
    public var progress: Double?
    /// A limit (sugar) that is exceeded: the bar turns orange.
    public var isOverLimit: Bool
}

public enum NutrientCard {
    /// The rows of the card for a day: protein, carbohydrates and fat first, then the further nutrients in `visible`.
    ///
    /// - Protein and fiber goals stay as they are; the carbohydrate and fat goals are the ones that grew with the credited activity
    ///   (`budget.scaledCarbs`, `budget.scaledFat`, decision BU3c). Sugar has an upper limit, fiber a target; saturated fat and salt
    ///   have no goal, so they show the value alone.
    /// - Values include the entries of other apps (`totals`); the coverage of the further nutrients counts the own meals only.
    public static func rows(totals: IntakeTotals, plan: GoalPlan, budget: EnergyBudget, visible: [Nutrient],
                            locale: Locale = .current) -> [NutrientRow] {
        let estimated = totals.hasEstimate
        var rows = [
            macro(.protein, title: String(localized: "Eiweiß", bundle: .module), value: totals.protein, goal: plan.proteinGrams,
                  estimated: estimated),
            macro(.carbohydrates, title: String(localized: "Kohlenhydrate", bundle: .module), value: totals.carbs,
                  goal: budget.scaledCarbs, estimated: estimated),
            macro(.fat, title: String(localized: "Fett", bundle: .module), value: totals.fat, goal: budget.scaledFat, estimated: estimated)
        ]
        for nutrient in visible {
            let goal: Int? = switch nutrient {
            case .fiber: plan.fiberGrams
            case .sugar: plan.sugarLimitGrams
            case .saturatedFat, .salt: nil
            }
            rows.append(further(nutrient, sum: totals.nutrient(nutrient), goal: goal, locale: locale))
        }
        return rows
    }

    private static func macro(_ kind: NutrientRow.Kind, title: String, value: Double, goal: Int?, estimated: Bool) -> NutrientRow {
        let number = "\(estimated ? "~" : "")\(Int(value.rounded()))"
        let valueText = goal.map { String(localized: "\(number) / \($0) g", bundle: .module) } ?? String(localized: "\(number) g", bundle: .module)
        let spokenAmount = Int(value.rounded())
        let spoken = goal.map { String(localized: "\(spokenAmount) von \($0) Gramm", bundle: .module) }
            ?? String(localized: "\(spokenAmount) Gramm", bundle: .module)
        return NutrientRow(kind: kind, title: title, valueText: valueText, spokenValue: estimated ? String(localized: "etwa \(spoken)", bundle: .module) : spoken,
                           progress: goal.map { $0 > 0 ? value / Double($0) : 0 }, isOverLimit: false)
    }

    private static func further(_ nutrient: Nutrient, sum: NutrientSum, goal: Int?, locale: Locale) -> NutrientRow {
        let limit = nutrient.isLimit && goal != nil
        let text = IntakeFormat.nutrient(nutrient, sum: sum, goal: goal.map(Double.init), isLimitGoal: limit, locale: locale)
        let value = sum.value
        var spoken = String(localized: "keine Angabe", bundle: .module)
        if let value {
            let amount = value.formatted(.number.precision(.fractionLength(nutrient.fractionDigits)).locale(locale))
            if let goal {
                spoken = limit ? String(localized: "\(amount) von höchstens \(goal) Gramm", bundle: .module)
                               : String(localized: "\(amount) von \(goal) Gramm", bundle: .module)
            } else {
                spoken = String(localized: "\(amount) Gramm", bundle: .module)
            }
            if !sum.isComplete { spoken = String(localized: "mindestens \(spoken)", bundle: .module) }
        }
        return NutrientRow(kind: .further(nutrient), title: nutrient.displayName, valueText: text, spokenValue: spoken,
                           progress: value.flatMap { value in goal.map { $0 > 0 ? value / Double($0) : 0 } },
                           isOverLimit: limit && (value ?? 0) > Double(goal ?? Int.max))
    }
}

extension IntakeFormat {
    /// The names of the apps behind the entries of other apps, for the row "Aus Health · andere Apps": "Yazio, Lose It".
    public static func foreignSources(_ sources: [String]) -> String {
        sources.joined(separator: ", ")
    }
}
