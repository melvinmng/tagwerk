import Foundation
import HealthBridge
import Testing

/// The in-memory Health store behaves like HealthKit for the read groups: nothing is delivered until the group was asked.
struct HealthBridgeFakeTests {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)
    private var interval: DateInterval { DateInterval(start: day.addingTimeInterval(-86_400), end: day.addingTimeInterval(86_400)) }

    @Test func dailyActiveEnergy_emptyWhenNotAuthorized() async throws {
        let health = FakeHealthStore()
        health.activeEnergy = [DailyActiveEnergy(start: day, kilocalories: 520)]
        #expect(try await health.dailyActiveEnergy(in: interval, calendar: .current).isEmpty)
        try await health.requestAuthorization(for: .activeEnergy)
        #expect(try await health.dailyActiveEnergy(in: interval, calendar: .current).map(\.kilocalories) == [520])
    }

    @Test func foreignWeights_emptyUntilTheBodyGroupWasAsked() async throws {
        let health = FakeHealthStore()
        health.foreignWeights = [ForeignWeight(id: UUID(), date: day, kilograms: 80.2, sourceName: "Waage")]
        #expect(try await health.foreignWeights(in: interval).isEmpty)
        try await health.requestAuthorization(for: .body)
        #expect(try await health.foreignWeights(in: interval).map(\.sourceName) == ["Waage"])
    }

    @Test func dailyForeignNutrition_emptyWhenGroupNotAsked() async throws {
        let health = FakeHealthStore()
        health.addForeignNutrition(day: day, kilocalories: 340, source: "Yazio")
        #expect(try await health.dailyForeignNutrition(in: interval, calendar: .current).isEmpty)
        try await health.requestAuthorization(for: .foreignNutrition)
        let days = try await health.dailyForeignNutrition(in: interval, calendar: .current)
        #expect(days.count == 1 && days.first?.intake.kcal == 340 && days.first?.intake.sources == ["Yazio"])
    }

    @Test func ownMeal_mirrored_notCountedAsForeign() async throws {
        let health = FakeHealthStore()
        try await health.requestAuthorization(for: .foreignNutrition)
        let meal = HealthMeal(id: UUID(), date: day, version: 1, kcal: 600, protein: 20, carbs: 70, fat: 20, estimated: true)
        _ = try await health.save(meal)
        #expect(try await health.dailyForeignNutrition(in: interval, calendar: .current).isEmpty,
                "a meal mirrored by Tagwerk must not come back as another app's entry")
        health.addForeignNutrition(day: day, kilocalories: 150, source: "Lifesum")
        #expect(try await health.dailyForeignNutrition(in: interval, calendar: .current).first?.intake.kcal == 150,
                "only the foreign entry counts")
    }

    @Test func bodyProfile_allNilWhenNotAsked() async throws {
        let health = FakeHealthStore()
        health.bodyProfileValue = HealthBodyProfile(heightCm: 181, birthYear: 1990, sex: .male)
        #expect(await health.bodyProfile() == .empty)
        try await health.requestAuthorization(for: .bodyProfile)
        #expect(await health.bodyProfile() == HealthBodyProfile(heightCm: 181, birthYear: 1990, sex: .male))
    }
}
