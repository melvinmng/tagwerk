import Foundation
import HealthBridge
import TagwerkCore

/// A nutrition sample in the fake Health database: own samples come from Tagwerk's mirror, the others from "other apps".
struct FakeNutritionSample: Sendable {
    var day: Date
    var kilocalories: Double
    var isOwn: Bool
    var sourceName: String
}

/// Records Health writes in memory. Saves suspend once, so concurrent runs can interleave in tests.
final class FakeHealthStore: HealthStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _access: HealthAccess
    private var _stepsAccess: StepsAccess
    private var _meals: [HealthMeal] = []
    private var _drinks: [HealthDrink] = []
    private var _workouts: [HealthWorkout] = []
    private var _deleted: [UUID] = []
    private var _foreign: [ForeignWorkout] = []
    private var _steps: [DailySteps] = []
    private var _nutritionSamples: [FakeNutritionSample] = []
    private var _weights: [HealthWeight] = []
    private var _foreignWeights: [ForeignWeight] = []
    private var _activeEnergy: [DailyActiveEnergy] = []
    private var _activeEnergyReads: [DateInterval] = []
    private var _groupAccess: [HealthAccessGroup: HealthGroupAccess] = [:]
    private var _groupRequests: [HealthAccessGroup: Int] = [:]
    private var _authorizationRequests = 0
    private var _stepsAuthorizationRequests = 0
    private var _foreignReads: [DateInterval] = []
    private var _stepsReads: [DateInterval] = []
    var failWrites = false
    var incompleteWrites = false
    /// Step reads throw, like HealthKit while the device is locked.
    var failStepReads = false
    /// Runs inside a step read before it returns, e.g. to navigate while the query is still running.
    var onStepsRead: (@MainActor @Sendable (DateInterval) async -> Void)?

    init(access: HealthAccess = .authorized, stepsAccess: StepsAccess = .asked) {
        _access = access
        _stepsAccess = stepsAccess
    }

    var currentAccess: HealthAccess {
        get { lock.withLock { _access } }
        set { lock.withLock { _access = newValue } }
    }
    var currentStepsAccess: StepsAccess {
        get { lock.withLock { _stepsAccess } }
        set { lock.withLock { _stepsAccess = newValue } }
    }
    var meals: [HealthMeal] { lock.withLock { _meals } }
    var drinks: [HealthDrink] { lock.withLock { _drinks } }
    var workouts: [HealthWorkout] { lock.withLock { _workouts } }
    var deleted: [UUID] { lock.withLock { _deleted } }
    var weights: [HealthWeight] { lock.withLock { _weights } }
    /// Nutrition samples of other apps; own samples come in through `save(_ meal:)`.
    func addForeignNutrition(day: Date, kilocalories: Double, source: String) {
        lock.withLock { _nutritionSamples.append(FakeNutritionSample(day: day, kilocalories: kilocalories, isOwn: false, sourceName: source)) }
    }
    var foreignWeights: [ForeignWeight] {
        get { lock.withLock { _foreignWeights } }
        set { lock.withLock { _foreignWeights = newValue } }
    }
    var authorizationRequests: Int { lock.withLock { _authorizationRequests } }
    var stepsAuthorizationRequests: Int { lock.withLock { _stepsAuthorizationRequests } }
    var foreignReads: [DateInterval] { lock.withLock { _foreignReads } }
    var stepsReads: [DateInterval] { lock.withLock { _stepsReads } }
    var foreign: [ForeignWorkout] {
        get { lock.withLock { _foreign } }
        set { lock.withLock { _foreign = newValue } }
    }
    var steps: [DailySteps] {
        get { lock.withLock { _steps } }
        set { lock.withLock { _steps = newValue } }
    }

    func access() async -> HealthAccess { currentAccess }

    /// Like the real store, the Health card's request covers the step type too.
    func requestAuthorization() async throws {
        lock.withLock {
            _authorizationRequests += 1
            if _access == .notDetermined { _access = .authorized }
            if _stepsAccess == .notAsked { _stepsAccess = .asked }
        }
    }

    private func write(_ apply: () -> Void) async throws -> Bool {
        await Task.yield()
        if failWrites { throw NSError(domain: "FakeHealth", code: 1) }
        lock.withLock(apply)
        return !incompleteWrites
    }

    /// A mirrored meal is a sample of Tagwerk itself, like in Health: it must never come back as a foreign entry.
    func save(_ meal: HealthMeal) async throws -> Bool {
        try await write {
            _meals.append(meal)
            _nutritionSamples.append(FakeNutritionSample(day: meal.date, kilocalories: meal.kcal, isOwn: true, sourceName: "Tagwerk"))
        }
    }
    func save(_ drink: HealthDrink) async throws -> Bool { try await write { _drinks.append(drink) } }
    func save(_ workout: HealthWorkout) async throws -> Bool { try await write { _workouts.append(workout) } }
    func save(_ weight: HealthWeight) async throws -> Bool { try await write { _weights.append(weight) } }
    func deleteEntry(id: UUID, kind: HealthEntryKind) async throws -> Bool { try await write { _deleted.append(id) } }

    func foreignWorkouts(in interval: DateInterval) async throws -> [ForeignWorkout] {
        lock.withLock {
            _foreignReads.append(interval)
            return _foreign.filter { $0.start >= interval.start && $0.start < interval.end }
        }
    }

    func stepsAccess() async -> StepsAccess { currentStepsAccess }

    func dailyForeignNutrition(in interval: DateInterval, calendar: Calendar) async throws -> [DailyForeignNutrition] {
        lock.withLock {
            guard (_groupAccess[.foreignNutrition] ?? .notAsked) == .asked else { return [] }
            let foreign = _nutritionSamples.filter { !$0.isOwn && $0.day >= interval.start && $0.day < interval.end }
            let byDay = Dictionary(grouping: foreign) { calendar.startOfDay(for: $0.day) }
            return byDay.keys.sorted().map { start in
                let samples = byDay[start] ?? []
                return DailyForeignNutrition(start: start, intake: ForeignIntake(kcal: samples.reduce(0) { $0 + $1.kilocalories },
                                                                                  sources: Set(samples.map(\.sourceName)).sorted()))
            }
        }
    }

    func foreignWeights(in interval: DateInterval) async throws -> [ForeignWeight] {
        lock.withLock {
            guard (_groupAccess[.body] ?? .notAsked) == .asked else { return [] }
            return _foreignWeights.filter { $0.date >= interval.start && $0.date < interval.end }
        }
    }

    var activeEnergy: [DailyActiveEnergy] {
        get { lock.withLock { _activeEnergy } }
        set { lock.withLock { _activeEnergy = newValue } }
    }
    var activeEnergyReads: [DateInterval] { lock.withLock { _activeEnergyReads } }

    /// Like HealthKit, a group that was not asked (or denied) gives no data instead of an error.
    func dailyActiveEnergy(in interval: DateInterval, calendar: Calendar) async throws -> [DailyActiveEnergy] {
        lock.withLock {
            _activeEnergyReads.append(interval)
            guard (_groupAccess[.activeEnergy] ?? .notAsked) == .asked else { return [] }
            return _activeEnergy.filter { $0.start >= interval.start && $0.start < interval.end }
        }
    }

    /// Groups start as not asked, like on a device that has never shown their sheet.
    func groupAccess(_ group: HealthAccessGroup) async -> HealthGroupAccess { lock.withLock { _groupAccess[group] ?? .notAsked } }

    func setGroupAccess(_ access: HealthGroupAccess, for group: HealthAccessGroup) {
        lock.withLock { _groupAccess[group] = access }
    }

    func groupRequests(_ group: HealthAccessGroup) -> Int { lock.withLock { _groupRequests[group] ?? 0 } }

    func requestAuthorization(for group: HealthAccessGroup) async throws {
        lock.withLock {
            _groupRequests[group, default: 0] += 1
            if (_groupAccess[group] ?? .notAsked) == .notAsked { _groupAccess[group] = .asked }
        }
    }

    func requestStepsAuthorization() async throws {
        lock.withLock {
            _stepsAuthorizationRequests += 1
            if _stepsAccess == .notAsked { _stepsAccess = .asked }
        }
    }

    func dailySteps(in interval: DateInterval, calendar: Calendar) async throws -> [DailySteps] {
        let result = lock.withLock {
            _stepsReads.append(interval)
            return _steps.filter { $0.start >= interval.start && $0.start < interval.end }
        }
        if let onStepsRead { await onStepsRead(interval) }
        if failStepReads { throw NSError(domain: "FakeHealth", code: 2) }
        return result
    }
}
