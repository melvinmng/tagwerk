import Foundation
import HealthBridge
import TagwerkCore

/// Reads the body weights for the history: own entries from Tagwerk's database and, once the Health group "body" was asked, the
/// measurements of other apps from Health (decision KG2a). Own entries are written through `IntakeStore`, which shares the undo
/// window and the Health queue with the other entries.
///
/// Reading is best effort: iOS does not tell a denied read from "no measurement", and Health is locked while the phone is, so an
/// answer without foreign values simply means there are none to show.
@MainActor
final class WeightStore {
    private let intake: IntakeStore
    private let health: any HealthStoring
    private let calendar: Calendar

    init(intake: IntakeStore, health: any HealthStoring, calendar: Calendar) {
        self.intake = intake
        self.health = health
        self.calendar = calendar
    }

    /// Own entries only, oldest first.
    func ownMeasurements(in interval: DateInterval) -> [WeightMeasurement] {
        intake.weights(in: interval).map(WeightMeasurement.init)
    }

    /// Own and foreign measurements of `interval` in one list, oldest first, without duplicates. Foreign values are left out while the
    /// group "body" was not asked or when Health does not answer.
    func measurements(in interval: DateInterval) async -> [WeightMeasurement] {
        let own = ownMeasurements(in: interval)
        guard await health.groupAccess(.body) == .asked, let read = try? await health.foreignWeights(in: interval) else { return own }
        let foreign = read.map {
            WeightMeasurement(id: $0.id, date: $0.date, kilograms: $0.kilograms, bodyFatPercent: $0.bodyFatPercent, sourceName: $0.sourceName)
        }
        return WeightRules.merge(own: own, foreign: foreign)
    }

    /// The weight of each day of `interval`: the earliest measurement of the day, own and foreign together.
    func dayValues(in interval: DateInterval) async -> [PlanDay: DayWeight] {
        WeightRules.dayValues(await measurements(in: interval), calendar: calendar)
    }

    /// The default of a new entry: the newest own weight.
    func latestOwn() -> WeightValue? { intake.latestWeight() }

    func weight(_ id: UUID) -> WeightValue? { intake.weight(id) }

    /// The first day an own weight exists for; `nil` without entries.
    var earliestOwnDay: PlanDay? { intake.earliestWeightDate().map { PlanDay(date: $0, calendar: calendar) } }
}
