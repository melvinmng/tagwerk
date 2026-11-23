import Foundation

/// The groups of the data package for the goal planning, as the selection sheet lists them (decision PV2a).
public enum GoalDataGroup: String, Sendable, CaseIterable, Hashable, Codable {
    case body, weight, nutrition, activity, water, goals

    /// The key of the group in the JSON that goes to ChatGPT.
    public var jsonKey: String { rawValue }
}

/// One day of the period as far as the package needs it. `nil` means "no value that day" (no entry, not readable): such a day is not
/// in the mean, and it is never a zero.
public struct GoalDataDay: Sendable, Hashable {
    public var eatenKcal: Double?
    public var proteinGrams: Double?
    public var fiberGrams: Double?
    public var waterMilliliters: Double?
    public var activeKcal: Double?
    public var steps: Double?

    public init(eatenKcal: Double? = nil, proteinGrams: Double? = nil, fiberGrams: Double? = nil, waterMilliliters: Double? = nil,
                activeKcal: Double? = nil, steps: Double? = nil) {
        self.eatenKcal = eatenKcal
        self.proteinGrams = proteinGrams
        self.fiberGrams = fiberGrams
        self.waterMilliliters = waterMilliliters
        self.activeKcal = activeKcal
        self.steps = steps
    }
}

/// The weight figures the package needs.
public struct GoalDataWeight: Sendable, Hashable {
    /// The 7-day mean, or the last weight.
    public var kilograms: Double?
    public var trendKgPerWeek: Double?
    /// The weight at the start of the period; only for "Fortschritt besprechen".
    public var startKilograms: Double?

    public init(kilograms: Double? = nil, trendKgPerWeek: Double? = nil, startKilograms: Double? = nil) {
        self.kilograms = kilograms
        self.trendKgPerWeek = trendKgPerWeek
        self.startKilograms = startKilograms
    }
}

/// The data package for ChatGPT (decision PV2a): averages and a trend over a period, in groups the user can switch off per
/// conversation. It holds no dates, no meal titles and no names of sources; Health entries of other apps are inside the averages when
/// the user lets them count. The same value gives the lines of the selection sheet and the JSON that is sent, so the user sees
/// exactly what goes out.
public struct GoalDataSummary: Sendable, Hashable {
    public struct Body: Sendable, Hashable {
        public var heightCm: Int?
        public var ageYears: Int?
        public var sex: FormulaSex?
        /// The fields without a value, so the model asks the user instead of guessing.
        public var missing: [BodyField]
    }

    public struct Weight: Sendable, Hashable {
        public var kilograms: Double?
        public var trendKgPerWeek: Double?
        public var startKilograms: Double?
    }

    public struct Nutrition: Sendable, Hashable {
        public var kcal: Int?
        public var proteinGrams: Int?
        public var fiberGrams: Int?
        /// Days with an entry, and the days of the period; days without an entry are not in the means.
        public var daysWithEntries: Int
    }

    public struct Activity: Sendable, Hashable {
        public var steps: Int?
        public var activeKcal: Int?
        /// Training minutes per week, as a mean over the weeks of the period.
        public var workoutMinutesPerWeek: Int?
    }

    public struct Water: Sendable, Hashable {
        public var milliliters: Int?
        public var daysWithEntries: Int
    }

    public struct Goals: Sendable, Hashable {
        public var kcal: Int
        public var proteinGrams: Int?
        public var carbsGrams: Int?
        public var fatGrams: Int?
        public var fiberGrams: Int?
        public var sugarLimitGrams: Int?
        public var waterMilliliters: Int
        public var stepsPerDay: Int
        public var workoutMinutesPerWeek: Int
        public var activeKcalPerDay: Int
        public var targetWeightKg: Double?
        public var paceKgPerWeek: Double?
    }

    /// The days of the period.
    public var periodDays: Int
    public var body: Body?
    public var weight: Weight?
    public var nutrition: Nutrition?
    public var activity: Activity?
    public var water: Water?
    public var goals: Goals?

    /// The groups that hold content, in the order of `GoalDataGroup.allCases`.
    public var groups: [GoalDataGroup] {
        GoalDataGroup.allCases.filter { has($0) }
    }

    public func has(_ group: GoalDataGroup) -> Bool {
        switch group {
        case .body: body != nil
        case .weight: weight != nil
        case .nutrition: nutrition != nil
        case .activity: activity != nil
        case .water: water != nil
        case .goals: goals != nil
        }
    }

    /// The package with only `selected` kept.
    public func keeping(_ selected: Set<GoalDataGroup>) -> GoalDataSummary {
        var result = self
        if !selected.contains(.body) { result.body = nil }
        if !selected.contains(.weight) { result.weight = nil }
        if !selected.contains(.nutrition) { result.nutrition = nil }
        if !selected.contains(.activity) { result.activity = nil }
        if !selected.contains(.water) { result.water = nil }
        if !selected.contains(.goals) { result.goals = nil }
        return result
    }

    // MARK: Building

    /// Builds the package from the days of the period and the current state.
    /// - Parameters:
    ///   - days: one entry per day of the period (a day without values may be left out or empty).
    ///   - workoutMinutesPerWeek: the mean over the weeks of the period; `nil` without a reading.
    public static func make(periodDays: Int, days: [GoalDataDay], profile: BodyProfile, year: Int, weight: GoalDataWeight,
                            workoutMinutesPerWeek: Double?, plan: GoalPlan?) -> GoalDataSummary {
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        func rounded(_ value: Double?) -> Int? { value.map { Int($0.rounded()) } }
        let eaten = days.compactMap(\.eatenKcal)
        let water = days.compactMap(\.waterMilliliters)
        let nutrition = Nutrition(kcal: rounded(mean(eaten)), proteinGrams: rounded(mean(days.compactMap(\.proteinGrams))),
                                  fiberGrams: rounded(mean(days.compactMap(\.fiberGrams))), daysWithEntries: eaten.count)
        return GoalDataSummary(
            periodDays: periodDays,
            body: Body(heightCm: profile.height.value, ageYears: profile.ageYears(inYear: year), sex: profile.sex.value,
                       missing: profile.missingFields),
            weight: Weight(kilograms: weight.kilograms.map { ($0 * 10).rounded() / 10 },
                           trendKgPerWeek: weight.trendKgPerWeek.map { ($0 * 10).rounded() / 10 },
                           startKilograms: weight.startKilograms.map { ($0 * 10).rounded() / 10 }),
            nutrition: nutrition,
            activity: Activity(steps: rounded(mean(days.compactMap(\.steps))), activeKcal: rounded(mean(days.compactMap(\.activeKcal))),
                               workoutMinutesPerWeek: rounded(workoutMinutesPerWeek)),
            water: Water(milliliters: rounded(mean(water)), daysWithEntries: water.count),
            goals: plan.map {
                Goals(kcal: $0.kcal, proteinGrams: $0.proteinGrams, carbsGrams: $0.carbsGrams, fatGrams: $0.fatGrams,
                      fiberGrams: $0.fiberGrams, sugarLimitGrams: $0.sugarLimitGrams, waterMilliliters: $0.waterMilliliters,
                      stepsPerDay: $0.stepsPerDay, workoutMinutesPerWeek: $0.workoutMinutesPerWeek,
                      activeKcalPerDay: $0.activeKcalPerDay, targetWeightKg: $0.targetWeightKg, paceKgPerWeek: $0.paceKgPerWeek)
            })
    }

    // MARK: Output

    /// The JSON that goes to ChatGPT: only the groups that hold content, only values that exist, no dates.
    public var jsonObject: [String: Any] {
        var object: [String: Any] = ["period_days": periodDays,
                                     "note": "Durchschnitte; Tage ohne Eintrag zählen nicht mit. Alle Werte sind Schätzungen."]
        if let body {
            var part: [String: Any] = [:]
            if let value = body.heightCm { part["height_cm"] = value }
            if let value = body.ageYears { part["age_years"] = value }
            if let value = body.sex { part["sex_for_formula"] = value.rawValue }
            if !body.missing.isEmpty { part["missing"] = body.missing.map(\.rawValue) }
            object[GoalDataGroup.body.jsonKey] = part
        }
        if let weight {
            var part: [String: Any] = [:]
            if let value = weight.kilograms { part["kg"] = value }
            if let value = weight.trendKgPerWeek { part["trend_kg_per_week"] = value }
            if let value = weight.startKilograms { part["start_kg"] = value }
            object[GoalDataGroup.weight.jsonKey] = part
        }
        if let nutrition {
            var part: [String: Any] = ["days_with_entries": nutrition.daysWithEntries]
            if let value = nutrition.kcal { part["kcal"] = value }
            if let value = nutrition.proteinGrams { part["protein_g"] = value }
            if let value = nutrition.fiberGrams { part["fiber_g"] = value }
            object[GoalDataGroup.nutrition.jsonKey] = part
        }
        if let activity {
            var part: [String: Any] = [:]
            if let value = activity.steps { part["steps_per_day"] = value }
            if let value = activity.activeKcal { part["active_kcal_per_day"] = value }
            if let value = activity.workoutMinutesPerWeek { part["workout_minutes_per_week"] = value }
            object[GoalDataGroup.activity.jsonKey] = part
        }
        if let water {
            var part: [String: Any] = ["days_with_entries": water.daysWithEntries]
            if let value = water.milliliters { part["ml_per_day"] = value }
            object[GoalDataGroup.water.jsonKey] = part
        }
        if let goals {
            var part: [String: Any] = ["base_kcal_without_activity": goals.kcal, "water_ml": goals.waterMilliliters,
                                       "steps_per_day": goals.stepsPerDay, "workout_minutes_per_week": goals.workoutMinutesPerWeek,
                                       "active_kcal_per_day": goals.activeKcalPerDay]
            if let value = goals.proteinGrams { part["protein_g"] = value }
            if let value = goals.carbsGrams { part["carbs_g"] = value }
            if let value = goals.fatGrams { part["fat_g"] = value }
            if let value = goals.fiberGrams { part["fiber_g"] = value }
            if let value = goals.sugarLimitGrams { part["sugar_limit_g"] = value }
            if let value = goals.targetWeightKg { part["target_weight_kg"] = value }
            if let value = goals.paceKgPerWeek { part["pace_kg_per_week"] = value }
            object[GoalDataGroup.goals.jsonKey] = part
        }
        return object
    }

    /// The compact JSON text of `jsonObject` with sorted keys.
    public var json: String {
        let data = (try? JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The groups and the period without any value: what a stored chat keeps of the package (decision PV3b).
    public var storedForm: String {
        let object: [String: Any] = ["ok": true, "groups": groups.map(\.jsonKey), "days": periodDays]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The lines of the selection sheet for one group; every number is the one in `jsonObject`.
    public func lines(for group: GoalDataGroup, locale: Locale = .current) -> [String] {
        func grouped(_ value: Int) -> String { IntakeFormat.grouped(value, locale: locale) }
        var lines: [String] = []
        switch group {
        case .body:
            guard let body else { return [] }
            if let value = body.heightCm { lines.append(String(localized: "Größe \(value) cm", bundle: .module)) }
            if let value = body.ageYears { lines.append(String(localized: "Alter \(value) Jahre", bundle: .module)) }
            if let value = body.sex {
                lines.append(value == .male ? String(localized: "Geschlecht männlich", bundle: .module)
                                            : String(localized: "Geschlecht weiblich", bundle: .module))
            }
            if !body.missing.isEmpty { lines.append(String(localized: "Fehlt noch: \(Self.missingText(body.missing))", bundle: .module)) }
        case .weight:
            guard let weight else { return [] }
            if let value = weight.kilograms { lines.append(WeightFormat.kilograms(value, locale: locale)) }
            if let value = weight.trendKgPerWeek { lines.append(String(localized: "Trend \(WeightFormat.changePerWeek(value, locale: locale))", bundle: .module)) }
            if let value = weight.startKilograms { lines.append(String(localized: "Start \(WeightFormat.kilograms(value, locale: locale))", bundle: .module)) }
        case .nutrition:
            guard let nutrition else { return [] }
            if let value = nutrition.kcal { lines.append(String(localized: "~\(grouped(value)) kcal pro Tag", bundle: .module)) }
            if let value = nutrition.proteinGrams { lines.append(String(localized: "\(value) g Eiweiß", bundle: .module)) }
            if let value = nutrition.fiberGrams { lines.append(String(localized: "\(value) g Ballaststoffe", bundle: .module)) }
            lines.append(String(localized: "an \(nutrition.daysWithEntries) von \(periodDays) Tagen erfasst", bundle: .module))
        case .activity:
            guard let activity else { return [] }
            if let value = activity.steps { lines.append(String(localized: "\(grouped(value)) Schritte pro Tag", bundle: .module)) }
            if let value = activity.activeKcal { lines.append(String(localized: "\(grouped(value)) kcal aktiv pro Tag", bundle: .module)) }
            if let value = activity.workoutMinutesPerWeek {
                lines.append(String(localized: "\(IntakeFormat.duration(minutes: value)) Training pro Woche", bundle: .module))
            }
        case .water:
            guard let water else { return [] }
            if let value = water.milliliters { lines.append(String(localized: "\(IntakeFormat.liters(value, locale: locale)) pro Tag", bundle: .module)) }
        case .goals:
            guard let goals else { return [] }
            lines.append(String(localized: "Grundziel \(grouped(goals.kcal)) kcal ohne Aktivität", bundle: .module))
            if let value = goals.proteinGrams { lines.append(String(localized: "\(value) g Eiweiß", bundle: .module)) }
            if let value = goals.targetWeightKg { lines.append(String(localized: "Zielgewicht \(WeightFormat.kilograms(value, locale: locale))", bundle: .module)) }
            if let value = goals.paceKgPerWeek { lines.append(String(localized: "Tempo \(WeightFormat.changePerWeek(value, locale: locale))", bundle: .module)) }
            lines.append(String(localized: "\(grouped(goals.stepsPerDay)) Schritte pro Tag, \(IntakeFormat.duration(minutes: goals.workoutMinutesPerWeek)) Training pro Woche", bundle: .module))
        }
        return lines
    }

    private static func missingText(_ fields: [BodyField]) -> String {
        fields.map { field in
            switch field {
            case .height: String(localized: "Größe", bundle: .module)
            case .birthYear: String(localized: "Alter", bundle: .module)
            case .sex: String(localized: "Geschlecht", bundle: .module)
            }
        }.joined(separator: ", ")
    }
}
