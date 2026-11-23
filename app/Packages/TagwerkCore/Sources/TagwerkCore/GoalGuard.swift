import Foundation

/// The numbers behind the checks of the goals and the weight trend. Every value carries its source from the fact check of
/// 21.11.2026 (`docs/superpowers/research/2026-11-21-ernaehrung-faktenpruefung.md`); no other place in the code names these
/// numbers. They are computing aids of the app, not medical limits, and not adjustable.
public enum GoalGuardConstants {
    // MARK: Weight pace

    /// A weight loss faster than `min(share of the body weight, kilograms)` per week triggers a hint. This is a rule of the app:
    /// neither "1 % per week" nor "1 kg per week" is a guideline. The CDC names about 0.45–0.9 kg per week as a usual pace; the
    /// percentage values in the literature come from sport (Garthe et al. 2011, doi:10.1123/ijsnem.21.2.97: 0.7 % of the body weight
    /// per week did better than 1.4 % for athletes in a diet phase).
    public static let maxWeeklyChangeShare = 0.01
    public static let maxWeeklyChangeKilograms = 1.0

    /// The weekly weight loss above which Tagwerk warns for a body weight of `bodyWeightKg`.
    public static func weeklyLossLimit(bodyWeightKg: Double) -> Double {
        min(maxWeeklyChangeShare * bodyWeightKg, maxWeeklyChangeKilograms)
    }

    /// Whether a trend of `trendPerWeek` kilograms per week (negative for losing weight) is above the limit. A gain never warns here.
    public static func exceedsWeeklyLossLimit(trendPerWeek: Double, bodyWeightKg: Double) -> Bool {
        trendPerWeek < 0 && -trendPerWeek > weeklyLossLimit(bodyWeightKg: bodyWeightKg)
    }

    /// The limit without a known body weight: only the absolute part of the rule applies.
    public static func weeklyLossLimit(bodyWeightKg: Double?) -> Double {
        bodyWeightKg.map { weeklyLossLimit(bodyWeightKg: $0) } ?? maxWeeklyChangeKilograms
    }

    // MARK: Resting energy (Mifflin–St Jeor)

    /// Resting energy = 10 × kg + 6.25 × cm − 5 × age + 5 (male) or − 161 (female). Mifflin MD, St Jeor ST, Hill LA et al. (1990),
    /// Am J Clin Nutr 51(2):241–247, doi:10.1093/ajcn/51.2.241. A sample of 498 healthy adults of 19–78 years. Validations
    /// (Frankenfield et al. 2003, 2005, 2013) find 18–25 % of single persons more than 10 % off: the text says "estimate, single
    /// errors of ±10 % and more possible".
    public static let mifflinWeightFactor = 10.0
    public static let mifflinHeightFactor = 6.25
    public static let mifflinAgeFactor = 5.0
    public static let mifflinMaleOffset = 5.0
    public static let mifflinFemaleOffset = -161.0

    /// "Grundbedarf ohne Bewegung" = resting energy × 1.2: the base of the daily budget, to which the credited active energy is added
    /// (the model of Apple Health: resting plus active energy). Never labelled "need". As a total need 1.2 is too low (FAO/WHO/UNU
    /// 2004 table 5.3: about 1.2 is the short-term survival of fully inactive people; DGE and EFSA 2017 name PAL 1.4 as sedentary).
    public static let baseNeedFactor = 1.2

    /// Total energy expenditure for the deficit check without active energy from Health: PAL 1.4 "sedentary" (DGE, EFSA 2017, FAO).
    public static let fallbackActivityFactor = 1.4

    /// The total expenditure for the deficit check is the base need plus the mean active energy (the full value, not the credited
    /// share) of the last 14 days. Fixed by the main session on 21.11.2026.
    public static let activityAverageDays = 14

    /// Rough conversion of a daily deficit into body mass, only for the short term (4–8 weeks): about 7,700 kcal per kilogram.
    /// Origin Wishnofsky 1958 (3,500 kcal per pound); Hall 2008 and Hall et al. 2011 (Lancet) show the rule ignores adaptation, so the
    /// real course flattens. Text: "rough estimate". The main check is the daily deficit; for a precise forecast the NIDDK Body Weight
    /// Planner exists.
    public static let kcalPerKilogramBodyMass = 7700.0

    // MARK: Lower limits

    /// Below this base goal Tagwerk warns: 1,200 kcal for women, 1,500 kcal for men (AHA/ACC/TOS 2013 guideline, confirmed only
    /// secondarily). Without a known sex the lower value counts.
    public static let softMinimumKcalFemale = 1200
    public static let softMinimumKcalMale = 1500

    /// A base goal below this value cannot be adopted (NIDDK Body Weight Planner: minimum 1,000 kcal per day).
    public static let hardMinimumKcal = 1000

    /// Protein: 0.8 g per kilogram (19 to under 65 years), 1.0 g per kilogram from 65 (DGE reference values). The reference weight
    /// is the body weight, with a BMI above 25 the weight at BMI 22 (DGE FAQ on protein).
    public static let minimumProteinPerKilogram = 0.8
    public static let minimumProteinPerKilogramFrom65 = 1.0
    public static let proteinOlderAge = 65
    public static let referenceBmi = 22.0
    public static let overweightBmi = 25.0

    /// Hint only, no warning: at least 30 g fibre per day, or 14.6 g per 1,000 kcal (DGE reference values).
    public static let fibreHint = 30
    public static let fibreHintPer1000Kcal = 14.6

    /// Hint only: drinks of about 1.2–1.5 litres per day (DGE reference value for water; the rest comes with the food).
    public static let drinkHintMinLitres = 1.2
    public static let drinkHintLitres = 1.5

    /// Default of the credited share of the active energy (decision BU1b, set by the user on 21.11.2026): wrist devices estimate the
    /// active energy coarsely, Apple more often too high (Fuller et al. 2020, doi:10.2196/18694).
    public static let activityCreditShareDefault = 0.5

    /// A warning when 4 × protein + 4 × carbohydrates + 9 × fat differs from the base goal by more than this share. Rule of this plan.
    public static let macroEnergyTolerance = 0.10
}

/// The result of the cross-check of a goal proposal. Tagwerk computes it from the numbers of `GoalGuardConstants`; ChatGPT only
/// proposes. It is a computing aid, not medical advice.
public struct GoalCheck: Sendable, Hashable {
    public enum Severity: String, Sendable, Hashable {
        /// Only a remark.
        case hint
        /// "Übernehmen" asks a second time.
        case warning
        /// The proposal cannot be adopted.
        case block
    }

    public enum Kind: String, Sendable, Hashable {
        case belowHardMinimum, belowSoftMinimum, belowRestingEnergy, paceAboveLimit, deficitAboveLimit
        case proteinBelowReference, macrosDoNotAdd, fibreHint, drinkHint, bodyDataMissing
    }

    public struct Finding: Sendable, Hashable {
        public var kind: Kind
        public var severity: Severity
        /// The text for the card; it may name numbers that come from the body data (resting energy, reference weight).
        public var text: String
        /// A short reason for ChatGPT that rests on constants and the proposal alone; `nil` when the finding depends on the body data.
        /// Values derived from height, age and sex never go back to the model (the user may have switched that group off).
        public var modelReason: String?
    }

    public var findings: [Finding]
    /// Resting energy by Mifflin–St Jeor in kcal, rounded to tens; `nil` without complete body data.
    public var restingKcal: Int?
    /// "Grundbedarf ohne Bewegung": resting energy × 1.2.
    public var baseNeedKcal: Int?
    /// Total expenditure of the deficit check: base need plus the mean active energy, or resting × 1.4 without a mean.
    public var totalNeedKcal: Int?
    /// Whether `totalNeedKcal` used the factor 1.4 because no mean active energy was given.
    public var usesFallbackActivity: Bool
    /// Weekly change in kilograms that the base goal implies at the total expenditure; negative for losing weight.
    public var impliedKgPerWeek: Double?
    /// The base goal that the stated pace would need at the total expenditure.
    public var kcalForPace: Int?
    /// Lines of the card, starting with "Gegenrechnung von Tagwerk".
    public var summaryLines: [String]

    public var isBlocked: Bool { findings.contains { $0.severity == .block } }
    public var warnings: [Finding] { findings.filter { $0.severity == .warning || $0.severity == .block } }
    public var hasWarning: Bool { !warnings.isEmpty }
    public var hints: [Finding] { findings.filter { $0.severity == .hint } }

    /// All lines of the card as one text: the summary and every warning or hint.
    public var cardText: String { (summaryLines + findings.map(\.text)).joined(separator: "\n") }

    /// The warnings as one text, for the card's warning line and the second confirmation.
    public var warningText: String? {
        let texts = warnings.map(\.text)
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }
}

/// The local cross-check of goal proposals (decision ZI2b): ChatGPT proposes, Tagwerk recomputes and warns. The limits are enforced here
/// in code, never only in the prompt.
public enum GoalGuard {
    /// Resting energy in kcal by Mifflin–St Jeor.
    public static func restingEnergy(weightKg: Double, heightCm: Double, ageYears: Int, sex: FormulaSex) -> Double {
        let offset = sex == .male ? GoalGuardConstants.mifflinMaleOffset : GoalGuardConstants.mifflinFemaleOffset
        return GoalGuardConstants.mifflinWeightFactor * weightKg + GoalGuardConstants.mifflinHeightFactor * heightCm
            - GoalGuardConstants.mifflinAgeFactor * Double(ageYears) + offset
    }

    /// The lowest base goal that raises no warning for `sex`.
    public static func softMinimumKcal(sex: FormulaSex?) -> Int {
        sex == .male ? GoalGuardConstants.softMinimumKcalMale : GoalGuardConstants.softMinimumKcalFemale
    }

    /// The lowest daily protein in grams that raises no warning; `nil` without weight, height or age.
    public static func minimumProteinGrams(weightKg: Double?, heightCm: Int?, ageYears: Int?) -> Double? {
        guard let weightKg, let heightCm, let ageYears else { return nil }
        let metres = Double(heightCm) / 100
        let bmi = weightKg / (metres * metres)
        let reference = bmi > GoalGuardConstants.overweightBmi ? GoalGuardConstants.referenceBmi * metres * metres : weightKg
        let perKilogram = ageYears >= GoalGuardConstants.proteinOlderAge
            ? GoalGuardConstants.minimumProteinPerKilogramFrom65 : GoalGuardConstants.minimumProteinPerKilogram
        return perKilogram * reference
    }

    /// Checks `proposal` (the complete plan as it would hold: proposed values over the current ones).
    /// - Parameters:
    ///   - body: height, birth year and sex as resolved; missing fields skip the checks that need them.
    ///   - weightKg: the 7-day mean of the weight, or the last weight.
    ///   - meanActiveKcal: the mean active energy of the last 14 days from Health, `nil` without Health data.
    ///   - year: the current year, for the age.
    public static func check(proposal: GoalPlan, body: BodyProfileValues, weightKg: Double?, meanActiveKcal: Double?, year: Int,
                             locale: Locale = .current) -> GoalCheck {
        var findings: [GoalCheck.Finding] = []
        func add(_ kind: GoalCheck.Kind, _ severity: GoalCheck.Severity, _ text: String, model: String? = nil) {
            findings.append(GoalCheck.Finding(kind: kind, severity: severity, text: text, modelReason: model))
        }
        func kcalText(_ value: Int) -> String { IntakeFormat.grouped(value, locale: locale) }
        let kcal = proposal.kcal
        let age = body.birthYear.flatMap { year >= $0 ? year - $0 : nil }

        // Lower limits of the base goal.
        let hard = kcalText(GoalGuardConstants.hardMinimumKcal)
        if kcal < GoalGuardConstants.hardMinimumKcal {
            add(.belowHardMinimum, .block,
                String(localized: "Ein Grundziel unter \(hard) kcal lässt sich nicht übernehmen.", bundle: .module),
                model: String(localized: "Das Grundziel liegt unter der harten Grenze von \(hard) kcal und lässt sich nicht übernehmen.", bundle: .module))
        } else {
            let soft = softMinimumKcal(sex: body.sex)
            if kcal < soft {
                add(.belowSoftMinimum, .warning,
                    String(localized: "Das Grundziel liegt unter \(kcalText(soft)) kcal. Besprich ein so niedriges Ziel mit einer Ärztin oder einem Arzt.", bundle: .module))
            }
        }

        // Macros against the base goal.
        if let protein = proposal.proteinGrams, let carbs = proposal.carbsGrams, let fat = proposal.fatGrams, kcal > 0 {
            let energy = 4 * Double(protein) + 4 * Double(carbs) + 9 * Double(fat)
            if abs(energy - Double(kcal)) / Double(kcal) > GoalGuardConstants.macroEnergyTolerance {
                let share = Int((GoalGuardConstants.macroEnergyTolerance * 100).rounded())
                add(.macrosDoNotAdd, .warning,
                    String(localized: "Eiweiß, Kohlenhydrate und Fett ergeben etwa \(kcalText(Int(energy.rounded()))) kcal und weichen um mehr als \(share) % vom Grundziel ab.", bundle: .module),
                    model: String(localized: "Eiweiß, Kohlenhydrate und Fett ergeben zusammen etwa \(kcalText(Int(energy.rounded()))) kcal und weichen um mehr als \(share) % vom Grundziel ab. Rechne sie so, dass sie zum Grundziel passen.", bundle: .module))
            }
        }

        // The stated pace.
        if let pace = proposal.paceKgPerWeek, GoalGuardConstants.exceedsWeeklyLossLimit(trendPerWeek: pace, bodyWeightKg: weightKg ?? .infinity) {
            let limit = GoalGuardConstants.weeklyLossLimit(bodyWeightKg: weightKg)
            let limitText = WeightFormat.kilograms(limit, locale: locale)
            let share = Int((GoalGuardConstants.maxWeeklyChangeShare * 100).rounded())
            let kilograms = WeightFormat.kilograms(GoalGuardConstants.maxWeeklyChangeKilograms, locale: locale)
            add(.paceAboveLimit, .warning,
                String(localized: "Das Tempo \(WeightFormat.changePerWeek(pace, locale: locale)) liegt über \(limitText) pro Woche. Das ist die Regel von Tagwerk: der kleinere Wert aus \(share) % des Körpergewichts und \(kilograms).", bundle: .module),
                model: -pace > GoalGuardConstants.maxWeeklyChangeKilograms
                    ? String(localized: "Das Tempo liegt über \(kilograms) Abnahme pro Woche. Schlage ein langsameres Tempo vor.", bundle: .module) : nil)
        }

        // Everything that needs the body data.
        var resting: Double?
        if let weightKg, let height = body.heightCm, let age, let sex = body.sex {
            resting = restingEnergy(weightKg: weightKg, heightCm: Double(height), ageYears: age, sex: sex)
        } else {
            var missing = body.missingFieldNames
            if weightKg == nil { missing.append(String(localized: "Gewicht", bundle: .module)) }
            add(.bodyDataMissing, .hint,
                String(localized: "Für die volle Gegenrechnung fehlen: \(missing.joined(separator: ", ")). Trage Größe, Geburtsjahr und Geschlecht unter Einstellungen › Erfassen › Körper ein.", bundle: .module))
        }

        var baseNeed: Double?, total: Double?, implied: Double?, kcalForPace: Int?
        var usesFallback = false
        if let resting {
            let base = resting * GoalGuardConstants.baseNeedFactor
            baseNeed = base
            let expenditure: Double
            if let meanActiveKcal {
                expenditure = base + max(0, meanActiveKcal)
            } else {
                expenditure = resting * GoalGuardConstants.fallbackActivityFactor
                usesFallback = true
            }
            total = expenditure
            let change = (Double(kcal) - expenditure) * 7 / GoalGuardConstants.kcalPerKilogramBodyMass
            implied = change
            if let pace = proposal.paceKgPerWeek {
                kcalForPace = tens(expenditure + pace * GoalGuardConstants.kcalPerKilogramBodyMass / 7)
            }
            if Double(kcal) < resting, kcal >= GoalGuardConstants.hardMinimumKcal {
                add(.belowRestingEnergy, .warning,
                    String(localized: "Das Grundziel liegt unter deinem geschätzten Ruheumsatz (~\(kcalText(tens(resting))) kcal).", bundle: .module))
            }
            if GoalGuardConstants.exceedsWeeklyLossLimit(trendPerWeek: change, bodyWeightKg: weightKg ?? .infinity) {
                let limit = WeightFormat.kilograms(GoalGuardConstants.weeklyLossLimit(bodyWeightKg: weightKg), locale: locale)
                add(.deficitAboveLimit, .warning,
                    String(localized: "Das Grundziel bedeutet bei deinem geschätzten Verbrauch etwa \(WeightFormat.changePerWeek(change, locale: locale)). Das liegt über der Regel von Tagwerk von \(limit) pro Woche.", bundle: .module))
            }
            if let protein = proposal.proteinGrams,
               let minimum = minimumProteinGrams(weightKg: weightKg, heightCm: body.heightCm, ageYears: age), Double(protein) < minimum {
                add(.proteinBelowReference, .warning,
                    String(localized: "Das Eiweißziel liegt unter \(Int(minimum.rounded())) g, dem Richtwert von \(proteinPerKilogramText(age: age, locale: locale)) g je Kilogramm Referenzgewicht.", bundle: .module))
            }
        }

        // Hints.
        if let fibre = proposal.fiberGrams, Double(fibre) < GoalGuardConstants.fibreHintPer1000Kcal * Double(kcal) / 1000 {
            let target = Int((GoalGuardConstants.fibreHintPer1000Kcal * Double(kcal) / 1000).rounded())
            add(.fibreHint, .hint,
                String(localized: "Hinweis: Der Richtwert liegt bei \(GoalGuardConstants.fibreHint) g Ballaststoffen oder \(decimal(GoalGuardConstants.fibreHintPer1000Kcal, locale: locale)) g je 1.000 kcal, bei diesem Grundziel etwa \(target) g.", bundle: .module))
        }
        if Double(proposal.waterMilliliters) < GoalGuardConstants.drinkHintLitres * 1000 {
            add(.drinkHint, .hint,
                String(localized: "Hinweis: Getränke von etwa \(decimal(GoalGuardConstants.drinkHintMinLitres, locale: locale)) bis \(decimal(GoalGuardConstants.drinkHintLitres, locale: locale)) l am Tag gelten als Richtwert.", bundle: .module))
        }

        var lines: [String] = []
        if let resting, let baseNeed, let implied {
            lines.append(String(localized: "Gegenrechnung von Tagwerk: Ruheumsatz ~\(kcalText(tens(resting))) kcal, Grundbedarf ohne Bewegung ~\(kcalText(tens(baseNeed))) kcal.", bundle: .module))
            let activity = usesFallback
                ? String(localized: "ohne Aktivitätsdaten aus Health mit dem Faktor \(decimal(GoalGuardConstants.fallbackActivityFactor, locale: locale)) gerechnet", bundle: .module)
                : String(localized: "mit der mittleren Aktivenergie der letzten \(GoalGuardConstants.activityAverageDays) Tage gerechnet", bundle: .module)
            lines.append(String(localized: "\(kcalText(kcal)) kcal entsprechen etwa \(WeightFormat.changePerWeek(implied, locale: locale)) (\(activity); grobe Schätzung, der tatsächliche Verlauf flacht ab).", bundle: .module))
            if let kcalForPace, let pace = proposal.paceKgPerWeek {
                lines.append(String(localized: "Für \(WeightFormat.changePerWeek(pace, locale: locale)) wären etwa \(kcalText(kcalForPace)) kcal nötig.", bundle: .module))
            }
            lines.append(String(localized: "Alle Werte sind Schätzungen; Einzelfehler von ±10 % und mehr sind möglich.", bundle: .module))
        }
        return GoalCheck(findings: findings, restingKcal: resting.map(tens), baseNeedKcal: baseNeed.map(tens), totalNeedKcal: total.map(tens),
                         usesFallbackActivity: usesFallback, impliedKgPerWeek: implied, kcalForPace: kcalForPace, summaryLines: lines)
    }

    private static func tens(_ value: Double) -> Int { Int((value / 10).rounded()) * 10 }

    /// One decimal place in the number format of `locale`: "14,6", "1,2".
    private static func decimal(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func proteinPerKilogramText(age: Int?, locale: Locale) -> String {
        let value = (age ?? 0) >= GoalGuardConstants.proteinOlderAge
            ? GoalGuardConstants.minimumProteinPerKilogramFrom65 : GoalGuardConstants.minimumProteinPerKilogram
        return decimal(value, locale: locale)
    }
}

extension BodyProfileValues {
    /// The names of the fields without a value, for the notice of the cross-check.
    var missingFieldNames: [String] {
        var names: [String] = []
        if heightCm == nil { names.append(String(localized: "Größe", bundle: .module)) }
        if birthYear == nil { names.append(String(localized: "Geburtsjahr", bundle: .module)) }
        if sex == nil { names.append(String(localized: "Geschlecht", bundle: .module)) }
        return names
    }
}
