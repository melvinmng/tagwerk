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
}
