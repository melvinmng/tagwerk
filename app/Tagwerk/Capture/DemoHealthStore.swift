#if DEBUG && targetEnvironment(simulator)
import Foundation
import HealthBridge
import TagwerkCore

/// Health for `-TagwerkDemoData` in the simulator: connected, with one Apple Watch run this morning.
/// Writes are kept in memory only.
final class DemoHealthStore: HealthStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var connected = true

    func access() async -> HealthAccess { lock.withLock { connected ? .authorized : .notDetermined } }
    func requestAuthorization() async throws { lock.withLock { connected = true } }
    func save(_ meal: HealthMeal) async throws -> Bool { true }
    func save(_ drink: HealthDrink) async throws -> Bool { true }
    func save(_ workout: HealthWorkout) async throws -> Bool { true }
    func deleteEntry(id: UUID) async throws -> Bool { true }

    func foreignWorkouts(in interval: DateInterval) async throws -> [ForeignWorkout] {
        let start = Calendar.tagwerk.startOfDay(for: .now).addingTimeInterval(7 * 3600 + 5 * 60)
        let run = ForeignWorkout(id: UUID(uuidString: "6D3A1C2E-0000-4000-8000-000000000001")!, activityName: "Laufen",
                                 activity: .running, start: start, end: start.addingTimeInterval(32 * 60), kilocalories: 310,
                                 sourceName: "Apple Watch")
        return interval.contains(run.start) ? [run] : []
    }
}
#endif
