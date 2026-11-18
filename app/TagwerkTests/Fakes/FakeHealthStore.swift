import Foundation
import HealthBridge

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
    private var _authorizationRequests = 0
    private var _stepsAuthorizationRequests = 0
    private var _foreignReads: [DateInterval] = []
    private var _stepsReads: [DateInterval] = []
    var failWrites = false
    var incompleteWrites = false
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

    func save(_ meal: HealthMeal) async throws -> Bool { try await write { _meals.append(meal) } }
    func save(_ drink: HealthDrink) async throws -> Bool { try await write { _drinks.append(drink) } }
    func save(_ workout: HealthWorkout) async throws -> Bool { try await write { _workouts.append(workout) } }
    func deleteEntry(id: UUID, kind: HealthEntryKind) async throws -> Bool { try await write { _deleted.append(id) } }

    func foreignWorkouts(in interval: DateInterval) async throws -> [ForeignWorkout] {
        lock.withLock {
            _foreignReads.append(interval)
            return _foreign.filter { $0.start >= interval.start && $0.start < interval.end }
        }
    }

    func stepsAccess() async -> StepsAccess { currentStepsAccess }

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
        return result
    }
}
