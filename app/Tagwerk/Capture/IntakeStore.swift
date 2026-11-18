import Foundation
import HealthBridge
import SwiftData
import TagwerkCore

/// One own entry of the "Erfassen" tab.
enum IntakeEntry: Sendable, Hashable {
    case meal(MealValue)
    case drink(DrinkValue)
    case workout(WorkoutValue)

    var id: UUID {
        switch self {
        case .meal(let meal): meal.id
        case .drink(let drink): drink.id
        case .workout(let workout): UUID(uuidString: workout.id) ?? UUID()
        }
    }
}

/// An entry whose current version is not in Health yet.
struct UnsyncedEntry: Sendable, Hashable {
    var entry: IntakeEntry
    var version: Int
}

/// Stores meals, water and workouts in SwiftData. Every change marks the entry for the Health mirror.
@MainActor
final class IntakeStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Reading

    func meals(on day: PlanDay, calendar: Calendar) -> [MealValue] {
        let (start, end) = bounds(day, calendar)
        let descriptor = FetchDescriptor<MealRecord>(predicate: #Predicate { $0.date >= start && $0.date < end },
                                                     sortBy: [SortDescriptor(\.date)])
        return ((try? context.fetch(descriptor)) ?? []).map(\.value)
    }

    func drinks(on day: PlanDay, calendar: Calendar) -> [DrinkValue] {
        let (start, end) = bounds(day, calendar)
        let descriptor = FetchDescriptor<DrinkRecord>(predicate: #Predicate { $0.date >= start && $0.date < end },
                                                      sortBy: [SortDescriptor(\.date)])
        return ((try? context.fetch(descriptor)) ?? []).map(\.value)
    }

    func workouts(in interval: DateInterval) -> [WorkoutValue] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.start >= start && $0.start < end },
                                                        sortBy: [SortDescriptor(\.start)])
        return ((try? context.fetch(descriptor)) ?? []).map(\.value)
    }

    /// Meals since `date`, newest first ("Zuletzt und häufig").
    func meals(since date: Date) -> [MealValue] {
        let descriptor = FetchDescriptor<MealRecord>(predicate: #Predicate { $0.date >= date },
                                                     sortBy: [SortDescriptor(\.date, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).map(\.value)
    }

    /// The most recent own workout, for the defaults of a new one.
    func latestWorkout() -> WorkoutValue? {
        var descriptor = FetchDescriptor<WorkoutRecord>(sortBy: [SortDescriptor(\.start, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.value
    }

    func estimatedAt(meal id: UUID) -> Date? { mealRecord(id)?.estimatedAt }

    func healthSynced(_ id: UUID) -> Bool {
        mealRecord(id)?.healthSynced ?? drinkRecord(id)?.healthSynced ?? workoutRecord(id)?.healthSynced ?? false
    }

    func exists(_ id: UUID) -> Bool { mealRecord(id) != nil || drinkRecord(id) != nil || workoutRecord(id) != nil }

    // MARK: Writing

    func addMeal(_ meal: MealValue, estimatedAt: Date?) {
        context.insert(MealRecord(meal, estimatedAt: estimatedAt))
        save()
    }

    func updateMeal(_ meal: MealValue, estimatedAt: Date?) {
        guard let record = mealRecord(meal.id) else { return addMeal(meal, estimatedAt: estimatedAt) }
        record.apply(meal)
        record.estimatedAt = estimatedAt
        record.healthVersion += 1
        record.healthSynced = false
        save()
    }

    func addDrink(_ drink: DrinkValue) {
        context.insert(DrinkRecord(drink))
        save()
    }

    func updateDrink(_ drink: DrinkValue) {
        guard let record = drinkRecord(drink.id) else { return addDrink(drink) }
        record.date = drink.date
        record.milliliters = drink.milliliters
        record.healthVersion += 1
        record.healthSynced = false
        save()
    }

    func addWorkout(_ workout: WorkoutValue) {
        guard let id = UUID(uuidString: workout.id) else { return }
        context.insert(WorkoutRecord(id: id, activity: workout.activity, start: workout.start, minutes: workout.minutes,
                                     kilocalories: workout.kilocalories))
        save()
    }

    func updateWorkout(_ workout: WorkoutValue) {
        guard let id = UUID(uuidString: workout.id), let record = workoutRecord(id) else { return addWorkout(workout) }
        record.activityRaw = workout.activity.rawValue
        record.start = workout.start
        record.minutes = workout.minutes
        record.kilocalories = workout.kilocalories
        record.healthVersion += 1
        record.healthSynced = false
        save()
    }

    /// A deleted entry and what is needed to bring it back.
    struct Deleted: Sendable {
        var entry: IntakeEntry
        var estimatedAt: Date?
        var version: Int
    }

    /// Deletes locally at once and queues the Health deletion after `notBefore` (undo window).
    @discardableResult
    func delete(_ id: UUID, healthNotBefore notBefore: Date) -> Deleted? {
        var deleted: Deleted?
        var kind = HealthEntryKind.meal
        if let record = mealRecord(id) {
            deleted = Deleted(entry: .meal(record.value), estimatedAt: record.estimatedAt, version: record.healthVersion)
            context.delete(record)
        } else if let record = drinkRecord(id) {
            deleted = Deleted(entry: .drink(record.value), estimatedAt: nil, version: record.healthVersion)
            kind = .drink
            context.delete(record)
        } else if let record = workoutRecord(id) {
            deleted = Deleted(entry: .workout(record.value), estimatedAt: nil, version: record.healthVersion)
            kind = .workout
            context.delete(record)
        }
        guard deleted != nil else { return nil }
        if let pending = pendingDeletion(id) {
            pending.notBefore = notBefore
            pending.kindRaw = kind.rawValue
        } else {
            context.insert(PendingHealthDeletion(entryID: id, notBefore: notBefore, kind: kind))
        }
        save()
        return deleted
    }

    /// "Widerrufen" after deleting: the entry returns with a higher version, and its Health deletion is dropped.
    func restore(_ deleted: Deleted) {
        if let pending = pendingDeletion(deleted.entry.id) { context.delete(pending) }
        let version = deleted.version + 1
        switch deleted.entry {
        case .meal(let meal):
            context.insert(MealRecord(meal, estimatedAt: deleted.estimatedAt, healthVersion: version))
        case .drink(let drink):
            context.insert(DrinkRecord(drink, healthVersion: version))
        case .workout(let workout):
            guard let id = UUID(uuidString: workout.id) else { return }
            context.insert(WorkoutRecord(id: id, activity: workout.activity, start: workout.start, minutes: workout.minutes,
                                         kilocalories: workout.kilocalories, healthVersion: version))
        }
        save()
    }

    // MARK: Health mirror bookkeeping

    func unsyncedEntries() -> [UnsyncedEntry] {
        let meals = (try? context.fetch(FetchDescriptor<MealRecord>(predicate: #Predicate { !$0.healthSynced }))) ?? []
        let drinks = (try? context.fetch(FetchDescriptor<DrinkRecord>(predicate: #Predicate { !$0.healthSynced }))) ?? []
        let workouts = (try? context.fetch(FetchDescriptor<WorkoutRecord>(predicate: #Predicate { !$0.healthSynced }))) ?? []
        return meals.map { UnsyncedEntry(entry: .meal($0.value), version: $0.healthVersion) }
            + drinks.map { UnsyncedEntry(entry: .drink($0.value), version: $0.healthVersion) }
            + workouts.map { UnsyncedEntry(entry: .workout($0.value), version: $0.healthVersion) }
    }

    /// Marks the entry as mirrored, unless it was edited (higher version) or deleted meanwhile.
    func markSynced(_ id: UUID, version: Int) {
        if let record = mealRecord(id), record.healthVersion == version { record.healthSynced = true }
        if let record = drinkRecord(id), record.healthVersion == version { record.healthSynced = true }
        if let record = workoutRecord(id), record.healthVersion == version { record.healthSynced = true }
        save()
    }

    /// Queued deletions whose undo window is over.
    func dueDeletions(now: Date) -> [UUID] {
        dueDeletionEntries(now: now).map(\.id)
    }

    func dueDeletionEntries(now: Date) -> [(id: UUID, kind: HealthEntryKind)] {
        let descriptor = FetchDescriptor<PendingHealthDeletion>(predicate: #Predicate { $0.notBefore <= now })
        return ((try? context.fetch(descriptor)) ?? []).map { ($0.entryID, HealthEntryKind(rawValue: $0.kindRaw) ?? .meal) }
    }

    func removeDeletion(_ id: UUID) {
        if let pending = pendingDeletion(id) {
            context.delete(pending)
            save()
        }
    }

    // MARK: Private

    private func bounds(_ day: PlanDay, _ calendar: Calendar) -> (Date, Date) {
        (day.startDate(in: calendar), day.adding(days: 1, calendar: calendar).startDate(in: calendar))
    }

    private func mealRecord(_ id: UUID) -> MealRecord? {
        try? context.fetch(FetchDescriptor<MealRecord>(predicate: #Predicate { $0.id == id })).first
    }

    private func drinkRecord(_ id: UUID) -> DrinkRecord? {
        try? context.fetch(FetchDescriptor<DrinkRecord>(predicate: #Predicate { $0.id == id })).first
    }

    private func workoutRecord(_ id: UUID) -> WorkoutRecord? {
        try? context.fetch(FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.id == id })).first
    }

    private func pendingDeletion(_ id: UUID) -> PendingHealthDeletion? {
        try? context.fetch(FetchDescriptor<PendingHealthDeletion>(predicate: #Predicate { $0.entryID == id })).first
    }

    private func save() {
        try? context.save()
    }
}

extension IntakeEntry {
    /// The Health copy of this entry at `version`.
    func healthValue(version: Int) -> HealthValue {
        switch self {
        case .meal(let meal):
            .meal(HealthMeal(id: meal.id, date: meal.date, version: version, kcal: meal.kcal, protein: meal.protein,
                             carbs: meal.carbs, fat: meal.fat, estimated: meal.hasEstimate))
        case .drink(let drink):
            .drink(HealthDrink(id: drink.id, date: drink.date, version: version, milliliters: drink.milliliters))
        case .workout(let workout):
            .workout(HealthWorkout(id: id, version: version, activity: workout.activity, start: workout.start,
                                   end: workout.end, kilocalories: workout.kilocalories))
        }
    }

    enum HealthValue {
        case meal(HealthMeal)
        case drink(HealthDrink)
        case workout(HealthWorkout)
    }
}
