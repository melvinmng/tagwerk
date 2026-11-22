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

    /// Write types of `access()`: the core group. Must stay exactly as it is, see `HealthAccessGroup`.
    static var shareTypes: Set<HKSampleType> { Set(HealthShareKind.allCases.map(type(of:))) }
    /// Read types of `access()`. The step type must never join them: a new type makes the status "should request"
    /// again, which would stop mirroring and hide Watch workouts for every existing user until they agree again.
    static var coreReadTypes: Set<HKObjectType> { [HKObjectType.workoutType()] }
    private static var stepType: HKQuantityType { HKQuantityType(.stepCount) }
    /// Steps have their own status (`stepsAccess()`) and their own request.
    static var stepReadTypes: Set<HKObjectType> { [stepType] }
    /// The Health card asks for everything in one sheet.
    static var connectReadTypes: Set<HKObjectType> { coreReadTypes.union(stepReadTypes) }

    private static func sampleTypes(_ identifiers: [HKQuantityTypeIdentifier]) -> Set<HKSampleType> {
        Set(identifiers.map { HKQuantityType($0) as HKSampleType })
    }

    private static func objectTypes(_ identifiers: [HKQuantityTypeIdentifier]) -> Set<HKObjectType> {
        Set(identifiers.map { HKQuantityType($0) as HKObjectType })
    }

    /// Types a group writes; empty for groups that only read.
    static func shareTypes(of group: HealthAccessGroup) -> Set<HKSampleType> {
        switch group {
        case .moreNutrients: sampleTypes([.dietaryFiber, .dietarySugar, .dietaryFatSaturated, .dietarySodium])
        case .body: sampleTypes([.bodyMass, .bodyFatPercentage])
        case .activeEnergy, .foreignNutrition, .bodyProfile: []
        }
    }

    /// Types a group reads.
    static func readTypes(of group: HealthAccessGroup) -> Set<HKObjectType> {
        switch group {
        case .moreNutrients: []
        case .activeEnergy: objectTypes([.activeEnergyBurned])
        case .body: objectTypes([.bodyMass, .bodyFatPercentage])
        case .foreignNutrition:
            objectTypes([.dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryFiber,
                         .dietarySugar, .dietaryFatSaturated, .dietarySodium, .dietaryWater])
        case .bodyProfile:
            objectTypes([.height]).union([HKCharacteristicType(.dateOfBirth), HKCharacteristicType(.biologicalSex)])
        }
    }

    private func mayWrite(_ kind: HealthShareKind) -> Bool { mayWrite(type: Self.type(of: kind)) }

    private func mayWrite(type: HKSampleType) -> Bool {
        store.authorizationStatus(for: type) == .sharingAuthorized
    }

    // MARK: Access

    public func access() async -> HealthAccess {
        guard Self.isAvailable else { return .unavailable }
        let status = (try? await store.statusForAuthorizationRequest(toShare: Self.shareTypes, read: Self.coreReadTypes)) ?? .unknown
        let denied = Set(HealthShareKind.allCases.filter { !mayWrite($0) })
        return HealthMapping.access(shouldRequest: status != .unnecessary, denied: denied)
    }

    public func requestAuthorization() async throws {
        guard Self.isAvailable else { return }
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.connectReadTypes)
    }

    public func groupAccess(_ group: HealthAccessGroup) async -> HealthGroupAccess {
        guard Self.isAvailable else { return .unavailable }
        let status = (try? await store.statusForAuthorizationRequest(toShare: Self.shareTypes(of: group),
                                                                     read: Self.readTypes(of: group))) ?? .unknown
        return HealthMapping.groupAccess(status)
    }

    public func requestAuthorization(for group: HealthAccessGroup) async throws {
        guard Self.isAvailable else { return }
        try await store.requestAuthorization(toShare: Self.shareTypes(of: group), read: Self.readTypes(of: group))
    }

    public func stepsAccess() async -> StepsAccess {
        guard Self.isAvailable else { return .unavailable }
        let status = (try? await store.statusForAuthorizationRequest(toShare: [], read: Self.stepReadTypes)) ?? .unknown
        return HealthMapping.stepsAccess(status)
    }

    public func requestStepsAuthorization() async throws {
        guard Self.isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: Self.stepReadTypes)
    }

    // MARK: Writing

    public func save(_ meal: HealthMeal) async throws -> Bool {
        let outcome = HealthMapping.mealWrite(plan: HealthMapping.nutrientPlan(for: meal),
                                              mayWrite: { mayWrite(type: HKQuantityType($0.identifier)) })
        for nutrient in outcome.removals {
            let identifier = HealthMapping.syncIdentifier(.meal, id: meal.id, part: nutrient.rawValue)
            try await delete(type: HKQuantityType(nutrient.identifier), key: HKMetadataKeySyncIdentifier, value: identifier)
        }
        // A denied nutrient is skipped for good; the meal still counts as mirrored, so it is not rewritten on every run.
        var samples: [HKObject] = []
        for (nutrient, value) in outcome.writes {
            let identifier = HealthMapping.syncIdentifier(.meal, id: meal.id, part: nutrient.rawValue)
            let metadata = HealthMapping.metadata(syncIdentifier: identifier, entryID: meal.id, version: meal.version,
                                                  estimated: meal.estimated, userEntered: !meal.estimated)
            samples.append(HKQuantitySample(type: HKQuantityType(nutrient.identifier),
                                            quantity: HKQuantity(unit: nutrient.unit, doubleValue: value),
                                            start: meal.date, end: meal.date, metadata: metadata))
        }
        guard outcome.isComplete else { return false }
        if !samples.isEmpty { try await store.save(samples) }
        return true
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

    public func save(_ weight: HealthWeight) async throws -> Bool {
        let outcome = HealthMapping.weightWrite(for: weight, mayWrite: { mayWrite(type: HKQuantityType($0.identifier)) })
        for part in outcome.removals {
            let identifier = HealthMapping.syncIdentifier(.weight, id: weight.id, part: part.rawValue)
            try await delete(type: HKQuantityType(part.identifier), key: HKMetadataKeySyncIdentifier, value: identifier)
        }
        guard outcome.isComplete else { return false }
        let samples: [HKObject] = outcome.writes.map { part, value in
            let identifier = HealthMapping.syncIdentifier(.weight, id: weight.id, part: part.rawValue)
            let metadata = HealthMapping.metadata(syncIdentifier: identifier, entryID: weight.id, version: weight.version,
                                                  estimated: false, userEntered: true)
            return HKQuantitySample(type: HKQuantityType(part.identifier),
                                    quantity: HKQuantity(unit: part.unit, doubleValue: value),
                                    start: weight.date, end: weight.date, metadata: metadata)
        }
        if !samples.isEmpty { try await store.save(samples) }
        return true
    }

    /// Workouts cannot be replaced by sync version reliably, so the old one (and its energy sample) is removed first.
    public func save(_ workout: HealthWorkout) async throws -> Bool {
        guard mayWrite(.workouts) else { return false }
        _ = try await deleteEntry(id: workout.id, kind: .workout)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = HealthMapping.activityType(workout.activity)
        if workout.activity == .swimming { configuration.swimmingLocationType = .unknown }
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: workout.start)
        // Denied calories are left out; the workout itself counts as mirrored and is not rebuilt on every run.
        if let kilocalories = workout.kilocalories, kilocalories > 0, mayWrite(.activeEnergy) {
                let identifier = HealthMapping.syncIdentifier(.workout, id: workout.id, part: "energy")
                let metadata = HealthMapping.metadata(syncIdentifier: identifier, entryID: workout.id, version: workout.version,
                                                      estimated: false, userEntered: true)
                let energy = HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                              quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kilocalories),
                                              start: workout.start, end: workout.end, metadata: metadata)
            try await builder.addSamples([energy])
        }
        let identifier = HealthMapping.syncIdentifier(.workout, id: workout.id)
        try await builder.addMetadata(HealthMapping.metadata(syncIdentifier: identifier, entryID: workout.id,
                                                             version: workout.version, estimated: false, userEntered: true))
        try await builder.endCollection(at: workout.end)
        guard try await builder.finishWorkout() != nil else { throw HealthBridgeError.workoutNotSaved }
        return true
    }

    // MARK: Deleting

    public func deleteEntry(id: UUID, kind: HealthEntryKind) async throws -> Bool {
        for shareKind in kind.shareKinds where mayWrite(shareKind) {
            try await delete(type: Self.type(of: shareKind), key: HealthMapping.entryIDKey, value: id.uuidString)
        }
        // Types outside the core group (fibre, sugar, …) only when their group may be written; otherwise nothing of the entry is there.
        for identifier in HealthMapping.extraDeleteIdentifiers(for: kind) where mayWrite(type: HKQuantityType(identifier)) {
            try await delete(type: HKQuantityType(identifier), key: HealthMapping.entryIDKey, value: id.uuidString)
        }
        return true
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

extension HealthKitStore {
    public func foreignWeights(in interval: DateInterval) async throws -> [ForeignWeight] {
        guard Self.isAvailable else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass),
                                         predicate: HKQuery.predicateForSamples(withStart: interval.start, end: interval.end))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples: [HKQuantitySample]
        do {
            samples = try await descriptor.result(for: store)
        } catch let error as HKError where error.code == .errorNoData || error.code == .errorAuthorizationNotDetermined {
            return []
        }
        let raw = samples.map { sample in
            HealthMapping.WeightSample(id: sample.uuid, date: sample.startDate,
                                       kilograms: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                                       metadata: sample.metadata, sourceBundleID: sample.sourceRevision.source.bundleIdentifier,
                                       sourceName: sample.sourceRevision.source.name)
        }
        return HealthMapping.foreignWeights(raw, ownBundleID: ownBundleID)
    }

    /// Day sums of a quantity type from a statistics collection: Health merges overlapping sources (iPhone, Apple Watch) by its
    /// source order, so Tagwerk never adds up single samples. A denied read gives no statistics, like a day without data.
    private func dailySums(of identifier: HKQuantityTypeIdentifier, unit: HKUnit, in interval: DateInterval,
                           calendar: Calendar) async throws -> [(start: Date, value: Double?)] {
        guard Self.isAvailable else { return [] }
        let predicate = HKSamplePredicate.quantitySample(
            type: HKQuantityType(identifier),
            predicate: HKQuery.predicateForSamples(withStart: interval.start, end: interval.end))
        let descriptor = HKStatisticsCollectionQueryDescriptor(predicate: predicate, options: .cumulativeSum,
                                                               anchorDate: calendar.startOfDay(for: interval.start),
                                                               intervalComponents: DateComponents(day: 1))
        let collection: HKStatisticsCollection
        do {
            collection = try await descriptor.result(for: store)
        } catch let error as HKError where error.code == .errorNoData || error.code == .errorAuthorizationNotDetermined {
            return []
        }
        var sums: [(start: Date, value: Double?)] = []
        collection.enumerateStatistics(from: interval.start, to: interval.end) { statistics, _ in
            sums.append((statistics.startDate, statistics.sumQuantity()?.doubleValue(for: unit)))
        }
        return sums
    }

    /// One statistics query per nutrition type, without Tagwerk's own samples (see `HealthMapping.foreignPredicate`). The merged sum
    /// is read first; if it is missing for a day with sources, the sum over the single sources is the fallback. Needs the group
    /// `foreignNutrition` to be asked, otherwise nothing is queried.
    public func dailyForeignNutrition(in interval: DateInterval, calendar: Calendar) async throws -> [DailyForeignNutrition] {
        guard Self.isAvailable, await groupAccess(.foreignNutrition) == .asked else { return [] }
        let foreign = HealthMapping.foreignPredicate(ownSource: HealthMapping.ownSourcePredicate())
        let time = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [time, foreign])
        var series: [HealthMapping.ForeignSeries] = []
        for type in HealthMapping.ForeignType.allCases {
            let descriptor = HKStatisticsCollectionQueryDescriptor(
                predicate: .quantitySample(type: HKQuantityType(type.identifier), predicate: predicate),
                options: [.cumulativeSum, .separateBySource], anchorDate: calendar.startOfDay(for: interval.start),
                intervalComponents: DateComponents(day: 1))
            let collection: HKStatisticsCollection
            do {
                collection = try await descriptor.result(for: store)
            } catch let error as HKError where error.code == .errorNoData || error.code == .errorAuthorizationNotDetermined {
                continue
            }
            var days: [(start: Date, value: Double?, sources: [String])] = []
            collection.enumerateStatistics(from: interval.start, to: interval.end) { statistics, _ in
                let sources = statistics.sources ?? []
                let merged = statistics.sumQuantity()?.doubleValue(for: type.unit)
                let bySource = sources.compactMap { statistics.sumQuantity(for: $0)?.doubleValue(for: type.unit) }
                let value = merged ?? (bySource.isEmpty ? nil : bySource.reduce(0, +))
                days.append((statistics.startDate, value, sources.map(\.name)))
            }
            series.append(HealthMapping.ForeignSeries(type: type, days: days))
        }
        return HealthMapping.foreignDays(series)
    }

    /// Steps typed in the Health app count as Health counts them.
    public func dailySteps(in interval: DateInterval, calendar: Calendar) async throws -> [DailySteps] {
        let sums = try await dailySums(of: .stepCount, unit: .count(), in: interval, calendar: calendar)
        return HealthMapping.dailySteps(sums.map { (start: $0.start, count: $0.value) })
    }

    public func dailyActiveEnergy(in interval: DateInterval, calendar: Calendar) async throws -> [DailyActiveEnergy] {
        HealthMapping.dailyActiveEnergy(try await dailySums(of: .activeEnergyBurned, unit: .kilocalorie(), in: interval,
                                                            calendar: calendar))
    }
}

public enum HealthBridgeError: Error, Equatable, Sendable {
    case workoutNotSaved
}
