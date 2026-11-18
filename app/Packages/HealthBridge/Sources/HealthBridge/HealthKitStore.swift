import Foundation
@preconcurrency import HealthKit
import TagwerkCore

/// `HealthStoring` on top of HealthKit. HealthKit objects are created and used inside one function only;
/// only Tagwerk value types leave it. Errors are thrown as they are; callers log codes, never values.
public final class HealthKitStore: HealthStoring, Sendable {
    private let store: HKHealthStore
    private let ownBundleID: String?

    public init(ownBundleID: String? = Bundle.main.bundleIdentifier) {
        self.store = HKHealthStore()
        self.ownBundleID = ownBundleID
    }

    public static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: Types

    private static func type(of kind: HealthShareKind) -> HKSampleType {
        switch kind {
        case .energy: HKQuantityType(.dietaryEnergyConsumed)
        case .protein: HKQuantityType(.dietaryProtein)
        case .carbs: HKQuantityType(.dietaryCarbohydrates)
        case .fat: HKQuantityType(.dietaryFatTotal)
        case .water: HKQuantityType(.dietaryWater)
        case .workouts: HKObjectType.workoutType()
        case .activeEnergy: HKQuantityType(.activeEnergyBurned)
        }
    }

    private static var shareTypes: Set<HKSampleType> { Set(HealthShareKind.allCases.map(type(of:))) }
    private static var readTypes: Set<HKObjectType> { [HKObjectType.workoutType()] }

    private func mayWrite(_ kind: HealthShareKind) -> Bool {
        store.authorizationStatus(for: Self.type(of: kind)) == .sharingAuthorized
    }

    // MARK: Access

    public func access() async -> HealthAccess {
        guard Self.isAvailable else { return .unavailable }
        let status = (try? await store.statusForAuthorizationRequest(toShare: Self.shareTypes, read: Self.readTypes)) ?? .unknown
        let denied = Set(HealthShareKind.allCases.filter { !mayWrite($0) })
        return HealthMapping.access(shouldRequest: status != .unnecessary, denied: denied)
    }

    public func requestAuthorization() async throws {
        guard Self.isAvailable else { return }
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    }

    // MARK: Writing

    public func save(_ meal: HealthMeal) async throws -> Bool {
        let plan = HealthMapping.nutrientPlan(for: meal)
        var complete = true
        for nutrient in plan.removals {
            guard mayWrite(nutrient.shareKind) else { continue }
            let identifier = HealthMapping.syncIdentifier(.meal, id: meal.id, part: nutrient.rawValue)
            try await delete(type: HKQuantityType(nutrient.identifier), key: HKMetadataKeySyncIdentifier, value: identifier)
        }
        var samples: [HKObject] = []
        for (nutrient, value) in plan.writes {
            guard mayWrite(nutrient.shareKind) else {
                complete = false
                continue
            }
            let identifier = HealthMapping.syncIdentifier(.meal, id: meal.id, part: nutrient.rawValue)
            let metadata = HealthMapping.metadata(syncIdentifier: identifier, entryID: meal.id, version: meal.version,
                                                  estimated: meal.estimated, userEntered: !meal.estimated)
            samples.append(HKQuantitySample(type: HKQuantityType(nutrient.identifier),
                                            quantity: HKQuantity(unit: nutrient.unit, doubleValue: value),
                                            start: meal.date, end: meal.date, metadata: metadata))
        }
        if !samples.isEmpty { try await store.save(samples) }
        return complete
    }

    public func save(_ drink: HealthDrink) async throws -> Bool {
        guard mayWrite(.water) else { return false }
        let identifier = HealthMapping.syncIdentifier(.drink, id: drink.id)
        let metadata = HealthMapping.metadata(syncIdentifier: identifier, entryID: drink.id, version: drink.version,
                                              estimated: false, userEntered: true)
        let sample = HKQuantitySample(type: HKQuantityType(.dietaryWater),
                                      quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(drink.milliliters)),
                                      start: drink.date, end: drink.date, metadata: metadata)
        try await store.save(sample)
        return true
    }

    /// Workouts cannot be replaced by sync version reliably, so the old one (and its energy sample) is removed first.
    public func save(_ workout: HealthWorkout) async throws -> Bool {
        guard mayWrite(.workouts) else { return false }
        _ = try await deleteEntry(id: workout.id)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = HealthMapping.activityType(workout.activity)
        if workout.activity == .swimming { configuration.swimmingLocationType = .unknown }
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: workout.start)
        var complete = true
        if let kilocalories = workout.kilocalories, kilocalories > 0 {
            if mayWrite(.activeEnergy) {
                let identifier = HealthMapping.syncIdentifier(.workout, id: workout.id, part: "energy")
                let metadata = HealthMapping.metadata(syncIdentifier: identifier, entryID: workout.id, version: workout.version,
                                                      estimated: false, userEntered: true)
                let energy = HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                              quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kilocalories),
                                              start: workout.start, end: workout.end, metadata: metadata)
                try await builder.addSamples([energy])
            } else {
                complete = false
            }
        }
        let identifier = HealthMapping.syncIdentifier(.workout, id: workout.id)
        try await builder.addMetadata(HealthMapping.metadata(syncIdentifier: identifier, entryID: workout.id,
                                                             version: workout.version, estimated: false, userEntered: true))
        try await builder.endCollection(at: workout.end)
        guard try await builder.finishWorkout() != nil else { throw HealthBridgeError.workoutNotSaved }
        return complete
    }

    // MARK: Deleting

    public func deleteEntry(id: UUID) async throws -> Bool {
        var complete = true
        for kind in HealthShareKind.allCases {
            guard mayWrite(kind) else {
                complete = false
                continue
            }
            try await delete(type: Self.type(of: kind), key: HealthMapping.entryIDKey, value: id.uuidString)
        }
        return complete
    }

    private func delete(type: HKSampleType, key: String, value: String) async throws {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: key, allowedValues: [value])
        do {
            _ = try await store.deleteObjects(of: type, predicate: predicate)
        } catch let error as HKError where error.code == .errorNoData {
            // Nothing to delete counts as success.
        }
    }

    // MARK: Reading

    public func foreignWorkouts(in interval: DateInterval) async throws -> [ForeignWorkout] {
        guard Self.isAvailable else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: interval.start, end: interval.end))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let workouts: [HKWorkout]
        do {
            workouts = try await descriptor.result(for: store)
        } catch let error as HKError where error.code == .errorNoData || error.code == .errorAuthorizationNotDetermined {
            return []
        }
        let energyType = HKQuantityType(.activeEnergyBurned)
        return workouts.compactMap { workout in
            let source = workout.sourceRevision.source
            guard !HealthMapping.isOwn(metadata: workout.metadata, sourceBundleID: source.bundleIdentifier,
                                       ownBundleID: ownBundleID) else { return nil }
            return ForeignWorkout(id: workout.uuid,
                                  activityName: HealthMapping.activityName(workout.workoutActivityType),
                                  activity: HealthMapping.activity(for: workout.workoutActivityType),
                                  start: workout.startDate, end: workout.endDate,
                                  kilocalories: workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                                  sourceName: source.name)
        }
    }
}

public enum HealthBridgeError: Error, Equatable, Sendable {
    case workoutNotSaved
}
