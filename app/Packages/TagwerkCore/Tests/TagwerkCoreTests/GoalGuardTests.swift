import Foundation
import Testing
@testable import TagwerkCore

struct GoalGuardTests {
    private let german = Locale(identifier: "de_DE")
    /// 82.1 kg, 180 cm, born 1992, male; in 2026 he is 34: resting energy 10 × 82.1 + 6.25 × 180 − 5 × 34 + 5 = 1,781 kcal.
    private let body = BodyProfileValues(heightCm: 180, birthYear: 1992, sex: .male)
    private let weight = 82.1
    private let year = 2026

    private func plan(kcal: Int = 2300, protein: Int? = nil, carbs: Int? = nil, fat: Int? = nil, fiber: Int? = nil, water: Int = 2000,
                      pace: Double? = nil) -> GoalPlan {
        GoalPlan(validFrom: PlanDay(year: 2026, month: 11, day: 21), kcal: kcal, proteinGrams: protein, carbsGrams: carbs, fatGrams: fat,
                 fiberGrams: fiber, waterMilliliters: water, stepsPerDay: 8000, workoutMinutesPerWeek: 150, paceKgPerWeek: pace)
    }

    private func check(_ plan: GoalPlan, body: BodyProfileValues? = nil, weight: Double? = 82.1, active: Double? = nil) -> GoalCheck {
        GoalGuard.check(proposal: plan, body: body ?? self.body, weightKg: weight, meanActiveKcal: active, year: year, locale: german)
    }

    private func kinds(_ check: GoalCheck) -> Set<GoalCheck.Kind> { Set(check.findings.map(\.kind)) }

    @Test func restingEnergy_example() {
        #expect(Int(GoalGuard.restingEnergy(weightKg: 82.1, heightCm: 180, ageYears: 34, sex: .male).rounded()) == 1781)
        #expect(Int(GoalGuard.restingEnergy(weightKg: 60, heightCm: 165, ageYears: 30, sex: .female).rounded()) == 1320)
        let result = check(plan())
        #expect(result.restingKcal == 1780)
        #expect(result.baseNeedKcal == 2140, "1,781 × 1.2 = 2,137")
    }

    @Test func warning_belowRestingEnergy() {
        #expect(kinds(check(plan(kcal: 1700))).contains(.belowRestingEnergy))
        #expect(!kinds(check(plan(kcal: 1800))).contains(.belowRestingEnergy))
    }

    @Test func warning_paceAboveShareOfBodyWeight() {
        // 1 % of 60 kg is 0.6 kg, below the 1 kg cap.
        #expect(kinds(check(plan(pace: -0.8), weight: 60)).contains(.paceAboveLimit))
        #expect(!kinds(check(plan(pace: -0.5), weight: 60)).contains(.paceAboveLimit))
    }

    @Test func warning_paceAboveOneKilogram() {
        let heavy = check(plan(pace: -1.2), weight: 130)
        #expect(kinds(heavy).contains(.paceAboveLimit))
        #expect(heavy.findings.first { $0.kind == .paceAboveLimit }?.modelReason != nil, "this part rests on a constant, not on the body")
        #expect(!kinds(check(plan(pace: -0.9), weight: 130)).contains(.paceAboveLimit))
        #expect(!kinds(check(plan(pace: 0.5), weight: 60)).contains(.paceAboveLimit), "gaining weight never warns here")
    }

    @Test func warning_belowSoftMinimum() {
        let male = body, female = BodyProfileValues(heightCm: 165, birthYear: 1992, sex: .female)
        #expect(kinds(check(plan(kcal: 1400), body: male)).contains(.belowSoftMinimum))
        #expect(!kinds(check(plan(kcal: 1400), body: female, weight: 60)).contains(.belowSoftMinimum))
        #expect(kinds(check(plan(kcal: 1150), body: female, weight: 60)).contains(.belowSoftMinimum))
        #expect(GoalGuard.softMinimumKcal(sex: nil) == GoalGuardConstants.softMinimumKcalFemale, "without a sex the lower value counts")
    }

    @Test func block_belowHardMinimum() {
        let result = check(plan(kcal: 900))
        #expect(result.isBlocked && result.hasWarning)
        #expect(!kinds(result).contains(.belowSoftMinimum), "the block replaces the soft warning")
        let reason = result.findings.first { $0.kind == .belowHardMinimum }?.modelReason
        #expect(reason?.contains("1.000") == true, "the reason names the constant")
        #expect(!check(plan(kcal: 1000)).isBlocked)
    }

    @Test func warning_proteinBelowReferenceWeight() {
        // BMI 25.3: the reference weight is the weight at BMI 22 (71.3 kg), so the minimum is 57 g.
        #expect(kinds(check(plan(protein: 50))).contains(.proteinBelowReference))
        #expect(!kinds(check(plan(protein: 60))).contains(.proteinBelowReference))
        let minimum = GoalGuard.minimumProteinGrams(weightKg: 82.1, heightCm: 180, ageYears: 34)
        #expect(abs((minimum ?? 0) - 57.0) < 0.1)
        // Normal weight: the body weight itself; from 65 years 1.0 g per kilogram.
        #expect(abs((GoalGuard.minimumProteinGrams(weightKg: 65, heightCm: 175, ageYears: 40) ?? 0) - 52) < 0.01)
        #expect(abs((GoalGuard.minimumProteinGrams(weightKg: 65, heightCm: 175, ageYears: 70) ?? 0) - 65) < 0.01)
        #expect(GoalGuard.minimumProteinGrams(weightKg: nil, heightCm: 175, ageYears: 40) == nil)
    }

    @Test func deficitCheck_usesAverageActivity_orFallbackFactor() {
        // Base need 2,137 kcal. With a mean active energy of 400 kcal the total is 2,537; 1,500 kcal lose about 0.94 kg a week.
        let withHealth = check(plan(kcal: 1500), active: 400)
        #expect(withHealth.totalNeedKcal == 2540)
        #expect(!withHealth.usesFallbackActivity)
        #expect(abs((withHealth.impliedKgPerWeek ?? 0) + 0.94) < 0.01)
        #expect(kinds(withHealth).contains(.deficitAboveLimit))
        // Without Health data: resting × 1.4 = 2,493 kcal.
        let fallback = check(plan(kcal: 1500))
        #expect(fallback.usesFallbackActivity && fallback.totalNeedKcal == 2490)
        // A moderate base goal does not warn.
        #expect(!kinds(check(plan(kcal: 2000), active: 400)).contains(.deficitAboveLimit))
        // The pace needs 2,537 − 0.5 × 7,700 / 7 = 1,987 kcal.
        #expect(check(plan(pace: -0.5), active: 400).kcalForPace == 1990)
    }

    @Test func warning_macrosDoNotAdd() {
        #expect(kinds(check(plan(kcal: 1800, protein: 150, carbs: 110, fat: 60))).contains(.macrosDoNotAdd))
        #expect(!kinds(check(plan(kcal: 1800, protein: 150, carbs: 165, fat: 60))).contains(.macrosDoNotAdd))
        #expect(!kinds(check(plan(kcal: 1800, protein: 150, carbs: nil, fat: 60))).contains(.macrosDoNotAdd), "needs all three")
    }

    @Test func noBodyData_noCheckButNotice() {
        let result = check(plan(kcal: 1500), body: BodyProfileValues(heightCm: 180), weight: nil)
        #expect(kinds(result).contains(.bodyDataMissing))
        #expect(result.restingKcal == nil && result.impliedKgPerWeek == nil && result.summaryLines.isEmpty)
        #expect(!result.hasWarning, "a notice is not a warning")
        // What does not need the body still runs.
        #expect(check(plan(kcal: 900), body: .empty, weight: nil).isBlocked)
    }

    @Test func check_text_alwaysSaysEstimate() {
        let result = check(plan(kcal: 1800))
        #expect(result.summaryLines.first?.hasPrefix("Gegenrechnung von Tagwerk") == true)
        #expect(result.summaryLines.joined(separator: " ").contains("Schätzungen"))
        #expect(result.summaryLines.joined(separator: " ").contains("Grundbedarf ohne Bewegung"), "never called a need")
        #expect(!result.cardText.contains("Bedarf ohne Training"))
    }

    @Test func constants_areTheOnlySourceOfNumbers() {
        let soft = check(plan(kcal: 1400))
        #expect(soft.findings.first { $0.kind == .belowSoftMinimum }?.text.contains("1.500") == true)
        let hard = check(plan(kcal: 900))
        #expect(hard.findings.first { $0.kind == .belowHardMinimum }?.text.contains("1.000") == true)
        let pace = check(plan(pace: -1.2), weight: 130)
        #expect(pace.findings.first { $0.kind == .paceAboveLimit }?.text.contains("1 %") == true)
        let hints = check(plan(kcal: 2300, fiber: 20, water: 1000))
        #expect(hints.hints.contains { $0.kind == .fibreHint && $0.text.contains("14,6") })
        #expect(hints.hints.contains { $0.kind == .drinkHint && $0.text.contains("1,2") && $0.text.contains("1,5") })
    }

    @Test func modelReasons_neverCarryBodyDerivedNumbers() {
        // A proposal that raises every warning: only constant-based reasons may go back to the model.
        let everything = check(plan(kcal: 900, protein: 20, carbs: 20, fat: 10, pace: -1.5), weight: 130, active: 100)
        let reasons = everything.findings.compactMap(\.modelReason).joined(separator: " ")
        for derived in ["1780", "1.780", "2140", "2.140", "130", "180", "1992", "34"] {
            #expect(!reasons.contains(derived), "\(derived) would reveal the body data")
        }
        #expect(everything.findings.contains { $0.kind == .belowRestingEnergy || $0.kind == .proteinBelowReference })
        #expect(everything.findings.filter { $0.kind == .belowRestingEnergy || $0.kind == .proteinBelowReference }.allSatisfy { $0.modelReason == nil })
    }

    @Test func ranges_matchTheSettingsSteppers() {
        #expect(GoalRanges.kcal.lowerBound == GoalGuardConstants.hardMinimumKcal, "the lowest value the stepper offers is the hard limit")
    }
}
