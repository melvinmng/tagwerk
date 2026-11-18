import Foundation
import HealthBridge

/// Records Health writes in memory. Saves suspend once, so concurrent runs can interleave in tests.
final class FakeHealthStore: HealthStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _access: HealthAccess
    private var _meals: [HealthMeal] = []
    private var _drinks: [HealthDrink] = []
    private var _workouts: [HealthWorkout] = []
    private var _deleted: [UUID] = []
    private var _foreign: [ForeignWorkout] = []
    private var _authorizationRequests = 0
    private var _foreignReads: [DateInterval] = []
    var failWrites = false
    var incompleteWrites = false

    init(access: HealthAccess = .authorized) { _access = access }

    var currentAccess: HealthAccess {
        get { lock.withLock { _access } }
        set { lock.withLock { _access = newValue } }
    }
    var meals: [HealthMeal] { lock.withLock { _meals } }
    var drinks: [HealthDrink] { lock.withLock { _drinks } }
    var workouts: [HealthWorkout] { lock.withLock { _workouts } }
    var deleted: [UUID] { lock.withLock { _deleted } }
    var authorizationRequests: Int { lock.withLock { _authorizationRequests } }
    var foreignReads: [DateInterval] { lock.withLock { _foreignReads } }
    var foreign: [ForeignWorkout] {
        get { lock.withLock { _foreign } }
        set { lock.withLock { _foreign = newValue } }
    }

    func access() async -> HealthAccess { currentAccess }

    func requestAuthorization() async throws {
        lock.withLock {
            _authorizationRequests += 1
            if _access == .notDetermined { _access = .authorized }
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
}
