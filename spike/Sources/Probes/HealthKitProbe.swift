import Foundation
import HealthKit

/// Verifies HealthKit read access for steps, workouts and dietary energy.
/// iOS does not reveal whether read access was denied, so empty data counts as success.
struct HealthKitProbe: Probe {
    let name = "Apple Health"

    static func summarize(steps: Double?, workouts: Int) -> ProbeResult {
        let stepText = steps.map { String(Int($0)) } ?? "0"
        return ProbeResult(
            name: "Apple Health", ok: true,
            detail: "\(stepText) Schritte heute, \(workouts) Trainings in 7 Tagen"
        )
    }

    static func isNoData(_ error: Error) -> Bool {
        (error as? HKError)?.code == .errorNoData
    }

    func run() async -> ProbeResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            return ProbeResult(name: name, ok: false, detail: "Health auf diesem Gerät nicht verfügbar")
        }
        let store = HKHealthStore()
        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.dietaryEnergyConsumed),
            HKObjectType.workoutType(),
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            return ProbeResult(name: name, ok: false, detail: "Berechtigung fehlgeschlagen: \(error.localizedDescription)")
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now

        do {
            let stepsDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(
                    type: HKQuantityType(.stepCount),
                    predicate: HKQuery.predicateForSamples(withStart: startOfDay, end: now)
                ),
                options: .cumulativeSum
            )
            let steps: Double?
            do {
                steps = try await stepsDescriptor.result(for: store)?
                    .sumQuantity()?.doubleValue(for: .count())
            } catch where Self.isNoData(error) {
                steps = nil
            }

            let workoutDescriptor = HKSampleQueryDescriptor(
                predicates: [.workout(HKQuery.predicateForSamples(withStart: weekAgo, end: now))],
                sortDescriptors: []
            )
            let workouts = try await workoutDescriptor.result(for: store).count
            return Self.summarize(steps: steps, workouts: workouts)
        } catch {
            return ProbeResult(name: name, ok: false, detail: "Lesen fehlgeschlagen: \(error.localizedDescription)")
        }
    }
}
