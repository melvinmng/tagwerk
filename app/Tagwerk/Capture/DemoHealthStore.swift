#if DEBUG && targetEnvironment(simulator)
import Foundation
import HealthBridge
import TagwerkCore

/// Health for `-TagwerkDemoData` in the simulator: connected, with one Apple Watch run this morning and steps for today
/// and the two days before. Writes are kept in memory only.
final class DemoHealthStore: HealthStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var connected = true
    private var stepsAsked = true

    func access() async -> HealthAccess { lock.withLock { connected ? .authorized : .notDetermined } }
    func requestAuthorization() async throws {
        lock.withLock {
            connected = true
            stepsAsked = true
        }
    }
    /// The demo allows the active energy, like the steps; the other groups start as not asked and become asked on request.
    private var askedGroups: Set<HealthAccessGroup> = [.activeEnergy]
    func groupAccess(_ group: HealthAccessGroup) async -> HealthGroupAccess {
        lock.withLock { askedGroups.contains(group) ? .asked : .notAsked }
    }
    func requestAuthorization(for group: HealthAccessGroup) async throws { lock.withLock { _ = askedGroups.insert(group) } }
    func writeAccess(for target: HealthWriteTarget) async -> HealthWriteAccess { .allowed }
    func stepsAccess() async -> StepsAccess { lock.withLock { stepsAsked ? .asked : .notAsked } }
    func requestStepsAuthorization() async throws { lock.withLock { stepsAsked = true } }

    func dailySteps(in interval: DateInterval, calendar: Calendar) async throws -> [DailySteps] {
        let today = calendar.startOfDay(for: .now)
        let demo = [(0, 6412), (-1, 8240), (-2, 5750)].compactMap { offset, count -> DailySteps? in
            guard let start = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return DailySteps(start: start, count: count)
        }
        return demo.filter { interval.contains($0.start) && $0.start < interval.end }
    }
    func dailyActiveEnergy(in interval: DateInterval, calendar: Calendar) async throws -> [DailyActiveEnergy] {
        let today = calendar.startOfDay(for: .now)
        let demo = [(0, 520.0), (-1, 610.0), (-2, 430.0)].compactMap { offset, kcal -> DailyActiveEnergy? in
            guard let start = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return DailyActiveEnergy(start: start, kilocalories: kcal)
        }
        return demo.filter { interval.contains($0.start) && $0.start < interval.end }
    }
    func dailyForeignNutrition(in interval: DateInterval, calendar: Calendar) async throws -> [DailyForeignNutrition] { [] }
    func bodyProfile() async -> HealthBodyProfile { HealthBodyProfile(heightCm: 180, birthYear: 1990, sex: .male) }
    func save(_ meal: HealthMeal) async throws -> Bool { true }
    func save(_ drink: HealthDrink) async throws -> Bool { true }
    func save(_ workout: HealthWorkout) async throws -> Bool { true }
    func save(_ weight: HealthWeight) async throws -> Bool { true }
    func foreignWeights(in interval: DateInterval) async throws -> [ForeignWeight] { [] }
    func deleteEntry(id: UUID, kind: HealthEntryKind) async throws -> Bool { true }

    func foreignWorkouts(in interval: DateInterval) async throws -> [ForeignWorkout] {
        let start = Calendar.tagwerk.startOfDay(for: .now).addingTimeInterval(7 * 3600 + 5 * 60)
        let run = ForeignWorkout(id: UUID(uuidString: "6D3A1C2E-0000-4000-8000-000000000001")!, activityName: "Laufen",
                                 activity: .running, start: start, end: start.addingTimeInterval(32 * 60), kilocalories: 310,
                                 sourceName: "Apple Watch")
        return interval.contains(run.start) ? [run] : []
    }
}
#endif
