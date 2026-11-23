import Foundation

/// The four terms of the head of "Erfassen" (decision BU4b): "Ziel + Aktiv − Gegessen = Noch", already formatted, plus the
/// sentence VoiceOver reads for the whole line.
public struct BudgetEquation: Sendable, Hashable {
    /// "2.300"
    public var goal: String
    /// What is credited, "260"; "–" while there is nothing to credit and Health gives no value (never 0); `nil` when crediting is
    /// switched off, so the line has no term for it.
    public var active: String?
    /// "~1.340"
    public var eaten: String
    /// The distance to the budget without sign: "~1.480", over the budget "~120".
    public var remaining: String
    public var isOver: Bool
    /// "Noch etwa 1.480 Kilokalorien: Ziel 2.300, plus 260 aktiv, minus etwa 1.340 gegessen".
    public var spoken: String
}

extension IntakeFormat {
    /// The terms of the budget line. The credited energy is the "Aktiv" term (not the raw sum), so the line adds up at every share;
    /// the share and the raw value are in the breakdown ("Aktiv heute").
    public static func budgetEquation(_ budget: EnergyBudget, locale: Locale = .current) -> BudgetEquation {
        let estimated = budget.isEstimated
        let goal = grouped(budget.base, locale: locale)
        let eaten = kcalNumber(budget.eatenKcal, estimated: estimated, locale: locale)
        let remainingMagnitude = abs(budget.remaining)
        let remaining = kcalNumber(remainingMagnitude, estimated: estimated, locale: locale)
        let hasActiveValue = budget.active.isFromHealth || budget.active.unsyncedOwnKcal > 0
        let active: String? = budget.creditPercent == 0 ? nil : (hasActiveValue ? grouped(budget.credited, locale: locale) : "–")

        let spokenGoal = String(localized: "Ziel \(goal)", bundle: .module)
        var terms = [spokenGoal]
        if let active {
            terms.append(hasActiveValue ? String(localized: "plus \(active) aktiv", bundle: .module)
                                        : String(localized: "plus aktiv ohne Werte", bundle: .module))
        }
        func spokenNumber(_ value: Double) -> String { grouped(estimated ? roundedKcal(value) : Int(value.rounded()), locale: locale) }
        let eatenNumber = spokenNumber(budget.eatenKcal)
        terms.append(estimated ? String(localized: "minus etwa \(eatenNumber) gegessen", bundle: .module)
                               : String(localized: "minus \(eatenNumber) gegessen", bundle: .module))
        let remainingNumber = spokenNumber(remainingMagnitude)
        let lead: String
        if budget.isOver {
            lead = estimated ? String(localized: "Etwa \(remainingNumber) Kilokalorien über dem Budget", bundle: .module)
                             : String(localized: "\(remainingNumber) Kilokalorien über dem Budget", bundle: .module)
        } else {
            lead = estimated ? String(localized: "Noch etwa \(remainingNumber) Kilokalorien", bundle: .module)
                             : String(localized: "Noch \(remainingNumber) Kilokalorien", bundle: .module)
        }
        return BudgetEquation(goal: goal, active: active, eaten: eaten, remaining: remaining, isOver: budget.isOver,
                              spoken: lead + ": " + terms.joined(separator: ", "))
    }
}

/// What the active energy of a day consists of, for the sheet "Aktiv heute": the workouts with their calories, the everyday
/// rest and what is credited.
public struct ActiveBreakdown: Sendable, Hashable {
    /// Workouts with calories (own and Health), by start.
    public var workouts: [WorkoutValue]
    /// The Health sum minus the calories of the workouts that are inside it; `nil` without a Health sum.
    public var everydayKcal: Double?
    /// Calories of own workouts that Health does not hold (yet); they count on top of the Health sum.
    public var gapKcal: Double
    /// Raw active energy of the day, as the budget counts it.
    public var totalKcal: Double
    public var creditPercent: Int
    public var creditedKcal: Int
    public var isFromHealth: Bool

    public static func make(budget: EnergyBudget, workouts: [WorkoutValue]) -> ActiveBreakdown {
        let withCalories = workouts.filter { ($0.kilocalories ?? 0) > 0 }.sorted { $0.start < $1.start }
        let foreignKcal = withCalories.filter { !$0.isOwn }.compactMap(\.kilocalories).reduce(0, +)
        let ownKcal = withCalories.filter(\.isOwn).compactMap(\.kilocalories).reduce(0, +)
        let gap = budget.active.unsyncedOwnKcal
        // Own workouts inside the Health sum: all own calories except the gap filler.
        let insideHealth = foreignKcal + max(0, ownKcal - gap)
        let everyday = budget.active.healthKcal.map { max(0, $0 - insideHealth) }
        return ActiveBreakdown(workouts: withCalories, everydayKcal: everyday, gapKcal: gap, totalKcal: budget.active.total,
                               creditPercent: budget.creditPercent, creditedKcal: budget.credited,
                               isFromHealth: budget.active.isFromHealth)
    }
}
