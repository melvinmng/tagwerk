import Foundation

/// Access to Apple Health. The app talks only to this protocol; tests use a fake.
///
/// Writes and deletes skip types the user did not allow and report that with `false`
/// ("not complete"), so the entry stays marked for a later retry. They throw only on real failures.
public protocol HealthStoring: Sendable {
    func access() async -> HealthAccess
    /// Shows the system sheet. Call only after a user tap.
    func requestAuthorization() async throws
    func save(_ meal: HealthMeal) async throws -> Bool
    func save(_ drink: HealthDrink) async throws -> Bool
    func save(_ workout: HealthWorkout) async throws -> Bool
    /// Removes every sample of the entry (all types).
    func deleteEntry(id: UUID) async throws -> Bool
    /// Workouts of other sources in `interval`; Tagwerk's own are filtered out. Empty when reading is not allowed.
    func foreignWorkouts(in interval: DateInterval) async throws -> [ForeignWorkout]
}
