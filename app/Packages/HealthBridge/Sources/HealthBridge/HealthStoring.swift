import Foundation

/// Access to Apple Health. The app talks only to this protocol; tests use a fake.
///
/// Writes and deletes skip types the user did not allow and report that with `false`
/// ("not complete"), so the entry stays marked for a later retry. They throw only on real failures.
public protocol HealthStoring: Sendable {
    func access() async -> HealthAccess
    /// Shows the one system sheet for everything the app needs: core types, steps, active energy, weight and height. Types answered
    /// before are not shown again. Call only after a user tap.
    func requestAuthorization() async throws
    func save(_ meal: HealthMeal) async throws -> Bool
    func save(_ drink: HealthDrink) async throws -> Bool
    /// Writes the weight (and the body fat percentage, when given) of the group `body`; `false` when the weight may not be written.
    func save(_ weight: HealthWeight) async throws -> Bool
    func save(_ workout: HealthWorkout) async throws -> Bool
    /// Removes every sample of the entry, in the types of its kind. Types Tagwerk may not write count as done,
    /// because nothing of the entry can be stored there.
    func deleteEntry(id: UUID, kind: HealthEntryKind) async throws -> Bool
    /// Workouts of other sources in `interval`; Tagwerk's own are filtered out. Empty when reading is not allowed.
    func foreignWorkouts(in interval: DateInterval) async throws -> [ForeignWorkout]

    /// Whether Tagwerk may write the weight or the height. iOS reports the write permission per type, so a refusal is visible
    /// (unlike reading); a denied write is never silent.
    func writeAccess(for target: HealthWriteTarget) async -> HealthWriteAccess

    /// Whether the system sheet of `group` was shown; independent of `access()` and of the other groups.
    func groupAccess(_ group: HealthAccessGroup) async -> HealthGroupAccess
    /// Shows the system sheet for `group` only. Call only after a user tap.
    func requestAuthorization(for group: HealthAccessGroup) async throws

    /// Weights of other sources in `interval`; Tagwerk's own are filtered out. Empty when reading is not allowed, which iOS
    /// does not tell apart from "no measurement".
    func foreignWeights(in interval: DateInterval) async throws -> [ForeignWeight]

    /// Day totals of the nutrition entries of other apps for the days of `interval`, by `calendar`; days without a foreign value are
    /// missing, and so is everything while the group `foreignNutrition` was not asked. A denied read looks like "no entries": the
    /// result is then empty or holds `nil` values, and callers must not show an error for it.
    func dailyForeignNutrition(in interval: DateInterval, calendar: Calendar) async throws -> [DailyForeignNutrition]

    /// Height, birth year and sex from Health; every field on its own, `nil` where Health gives nothing (also while the group
    /// `bodyProfile` was not asked or reading was denied).
    func bodyProfile() async -> HealthBodyProfile

    /// Day sums of the active energy for the days of `interval`, by `calendar`; days without statistics are missing.
    /// Health merges overlapping sources itself, so Tagwerk never adds single samples and never removes own workouts.
    /// Empty when reading is not allowed: iOS reports that as "no data", so callers treat empty as unknown, never as 0.
    func dailyActiveEnergy(in interval: DateInterval, calendar: Calendar) async throws -> [DailyActiveEnergy]

    /// Whether the step sheet was shown; independent of `access()`, which never looks at the step type.
    func stepsAccess() async -> StepsAccess
    /// Shows the system sheet for steps only. Call only after a user tap.
    func requestStepsAuthorization() async throws
    /// Day sums of steps for the days of `interval`, by `calendar`; days without data are missing.
    /// Empty when reading is not allowed (iOS reports that as "no data").
    func dailySteps(in interval: DateInterval, calendar: Calendar) async throws -> [DailySteps]
}
