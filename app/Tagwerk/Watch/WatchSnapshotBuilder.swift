import Foundation
import TagwerkCore

/// Collects the data of the watch snapshot from the app's models. Notes, journal and every other private content stay
/// out: `WatchSnapshot` has no field for them.
@MainActor
enum WatchSnapshotBuilder {
    /// `nil` while nothing reliable can be said: setup is not done or the tasks are not loaded (a background start).
    /// The phone then sends nothing, and the watch keeps showing its last snapshot.
    static func make(environment: AppEnvironment, appliedActionIDs: [UUID], now: Date = .now) -> WatchSnapshot? {
        guard environment.settings.setupCompleted, environment.taskList.allSourcesSettled else { return nil }
        let calendar = environment.planning.calendar
        let widget = environment.makeSnapshot(now: now)
        let habits = environment.habits
        habits.refreshLocal(notify: false)
        let habitRows = habits.rows(for: habits.today).map {
            WatchHabit(habit: $0.habit, done: $0.isFulfilled, isAutomatic: $0.isAutomatic)
        }
        let today = PlanDay(date: now, calendar: calendar)
        let deadlineKeys = Set(environment.planning.days.filter { $0.day == today }.flatMap(\.deadlines).compactMap { $0.taskID?.key })
        return WatchSnapshot.make(widget: widget, tasks: environment.taskList.items, habits: habitRows,
                                  water: water(environment: environment, on: today),
                                  deadlineTaskKeys: deadlineKeys, appliedActionIDs: appliedActionIDs, now: now, calendar: calendar)
    }

    /// Today's water straight from the store (correct after midnight and without a loaded capture tab).
    private static func water(environment: AppEnvironment, on day: PlanDay) -> WatchWater {
        let calendar = environment.capture.calendar
        let milliliters = environment.intake.drinks(on: day, calendar: calendar).reduce(0) { $0 + $1.milliliters }
        return WatchWater(milliliters: milliliters, goalMilliliters: environment.settings.goalWaterMilliliters,
                          showsInComplication: environment.settings.widgetShowsNutrition)
    }
}
