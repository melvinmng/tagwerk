import Foundation
import Testing
@testable import TagwerkCore

struct GoalDataSummaryTests {
    private let german = Locale(identifier: "de_DE")
    private let profile = BodyProfile.resolved(health: BodyProfileValues(heightCm: 180, birthYear: 1992, sex: .male), typed: .empty)
    private let plan = GoalPlan(validFrom: PlanDay(year: 2026, month: 11, day: 1), kcal: 2300, proteinGrams: 120, waterMilliliters: 2000,
                                stepsPerDay: 8000, workoutMinutesPerWeek: 150, targetWeightKg: 78, paceKgPerWeek: -0.3)

    private func summary(days: [GoalDataDay], weight: GoalDataWeight = GoalDataWeight(kilograms: 82.14, trendKgPerWeek: -0.31),
                         profile: BodyProfile? = nil, workouts: Double? = 130.4) -> GoalDataSummary {
        GoalDataSummary.make(periodDays: 28, days: days, profile: profile ?? self.profile, year: 2026, weight: weight,
                             workoutMinutesPerWeek: workouts, plan: plan)
    }

    private var fullDays: [GoalDataDay] {
        (0..<24).map { _ in GoalDataDay(eatenKcal: 2350, proteinGrams: 112, fiberGrams: 21, waterMilliliters: 1700, activeKcal: 410, steps: 7240) }
    }

    private func json(_ summary: GoalDataSummary) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(summary.json.utf8)) as? [String: Any])
    }

    @Test func summary_averagesOver28Days_withCoverage() throws {
        let result = summary(days: fullDays)
        let nutrition = try #require(result.nutrition)
        #expect(nutrition.kcal == 2350 && nutrition.proteinGrams == 112 && nutrition.fiberGrams == 21)
        #expect(nutrition.daysWithEntries == 24)
        #expect(result.periodDays == 28)
        #expect(result.lines(for: .nutrition, locale: german).contains("an 24 von 28 Tagen erfasst"))
        #expect(result.weight?.kilograms == 82.1 && result.weight?.trendKgPerWeek == -0.3, "weight values are rounded to one decimal")
        #expect(result.activity?.workoutMinutesPerWeek == 130)
    }

    @Test func daysWithoutEntries_notCountedAsZero() throws {
        var days = [GoalDataDay(eatenKcal: 2000, waterMilliliters: 1500), GoalDataDay(eatenKcal: 3000, waterMilliliters: 2500)]
        days += (0..<10).map { _ in GoalDataDay() }
        let result = summary(days: days)
        #expect(result.nutrition?.kcal == 2500, "ten empty days do not pull the mean down")
        #expect(result.nutrition?.daysWithEntries == 2)
        #expect(result.water?.milliliters == 2000 && result.water?.daysWithEntries == 2)
        // A group without any value has no mean, not a zero.
        let none = summary(days: [GoalDataDay()])
        #expect(none.nutrition?.kcal == nil && none.activity?.steps == nil && none.water?.milliliters == nil)
        let object = try json(none)
        #expect((object["nutrition"] as? [String: Any])?["kcal"] == nil)
    }

    @Test func summary_excludesSwitchedOffGroups() throws {
        let result = summary(days: fullDays).keeping([.weight, .goals])
        #expect(result.groups == [.weight, .goals])
        let object = try json(result)
        #expect(object["weight"] != nil && object["goals"] != nil)
        #expect(object["nutrition"] == nil && object["body"] == nil && object["activity"] == nil && object["water"] == nil)
        #expect(!result.json.contains("2350") && !result.json.contains("height_cm"))
        #expect(result.keeping([]).groups.isEmpty)
    }

    @Test func summary_noMealTitlesNoDatesNoSourceNames() throws {
        let text = summary(days: fullDays).json
        #expect(!text.contains("2026"), "no dates (the age is a number, the year of birth is not sent)")
        #expect(!text.contains("1992"))
        #expect(!text.lowercased().contains("yazio") && !text.lowercased().contains("source"))
        let object = try json(summary(days: fullDays))
        #expect(object["period_days"] as? Int == 28)
    }

    @Test func json_matchesWhatSheetShows() throws {
        let result = summary(days: fullDays)
        let object = try json(result)
        let nutrition = try #require(object["nutrition"] as? [String: Any])
        let lines = result.lines(for: .nutrition, locale: german).joined(separator: " | ")
        #expect(nutrition["kcal"] as? Int == 2350 && lines.contains("2.350"))
        #expect(nutrition["protein_g"] as? Int == 112 && lines.contains("112 g Eiweiß"))
        let weight = try #require(object["weight"] as? [String: Any])
        #expect(weight["kg"] as? Double == 82.1 && result.lines(for: .weight, locale: german).contains("82,1 kg"))
        let goals = try #require(object["goals"] as? [String: Any])
        #expect(goals["base_kcal_without_activity"] as? Int == 2300 && result.lines(for: .goals, locale: german).joined().contains("2.300"))
        // Every group the package holds has lines, and a group that was kept out has none.
        for group in result.groups { #expect(!result.lines(for: group, locale: german).isEmpty) }
        #expect(result.keeping([.weight]).lines(for: .nutrition, locale: german).isEmpty)
    }

    @Test func summary_bodyGroup_usesResolvedProfile() throws {
        let missingSex = BodyProfile.resolved(health: BodyProfileValues(heightCm: 180, birthYear: 1992), typed: .empty)
        let result = summary(days: [], profile: missingSex)
        let body = try #require(result.body)
        #expect(body.heightCm == 180 && body.ageYears == 34 && body.sex == nil && body.missing == [.sex])
        let object = try #require(try json(result)["body"] as? [String: Any])
        #expect(object["height_cm"] as? Int == 180 && object["age_years"] as? Int == 34 && object["sex_for_formula"] == nil)
        #expect(object["missing"] as? [String] == ["sex"])
        #expect(result.lines(for: .body, locale: german).contains { $0.contains("Fehlt noch") })
    }

    @Test func storedForm_keepsGroupsAndPeriodOnly() throws {
        let stored = summary(days: fullDays).keeping([.weight, .nutrition]).storedForm
        let object = try #require(try JSONSerialization.jsonObject(with: Data(stored.utf8)) as? [String: Any])
        #expect(object["ok"] as? Bool == true && object["days"] as? Int == 28)
        #expect(object["groups"] as? [String] == ["weight", "nutrition"])
        #expect(!stored.contains("2350") && !stored.contains("82"))
    }
}
