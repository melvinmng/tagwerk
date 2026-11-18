import Foundation
import TagwerkCore

/// What the App Intents may do (phase 4 design §8). Registered once per process with `AppDependencyManager`;
/// uses the app's single model container. Never calls an AI feature and never fetches anything from the network.
@MainActor
final class IntentServices {
    static let defaultWaterMilliliters = 250
    static let waterRange = 50...2000

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Records water now (not on the day the tab shows), mirrors it to Health and updates the widget.
    /// The reply names no daily total: Siri may speak it on a locked device.
    func logWater(milliliters: Int?) async -> LocalizedStringResource {
        let amount = min(max(milliliters ?? Self.defaultWaterMilliliters, Self.waterRange.lowerBound), Self.waterRange.upperBound)
        let capture = environment.capture
        await capture.reload()
        await capture.addWater(amount, at: .now, offersUndo: false)
        await capture.waitForHealth()
        environment.writeSnapshot()
        // Plain digits (no grouping), as before: "2000 ml".
        let amountText = String(amount)
        return "\(amountText) ml Wasser erfasst."
    }

    struct Overview {
        var text: String
        var entries: [SnapshotEntry]
    }

    /// "Was steht heute an?" from the snapshot: counts and the next entries, never nutrition.
    func todayOverview(now: Date = .now) -> Overview {
        if environment.settings.setupCompleted, environment.taskList.allSourcesSettled {
            environment.writeSnapshot(now: now)
        }
        let calendar = environment.planning.calendar
        guard let snapshot = environment.snapshotWriter.current(), !snapshot.isStale(at: now, calendar: calendar) else {
            return Overview(text: String(localized: "Öffne Tagwerk, um den Plan zu laden."), entries: [])
        }
        let upcoming = snapshot.upcoming(at: now, calendar: calendar, limit: 3)
        return Overview(text: snapshot.overviewText(at: now, calendar: calendar), entries: upcoming.isTomorrow ? [] : upcoming.entries)
    }

    /// Opens the meal sheet with the text prefilled; estimating still needs a tap in the sheet (and consent).
    func openMeal(text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        environment.router.open(.captureMeal, prefill: .meal(text: trimmed?.isEmpty == false ? trimmed : nil))
    }

    /// Opens the workout sheet prefilled; the overlap warning needs Health, so nothing is saved without the sheet.
    func openWorkout(activity: WorkoutActivity?, minutes: Int?) {
        environment.router.open(.captureWorkout, prefill: .workout(activity: activity, minutes: minutes.map { min(max($0, 1), 600) }))
    }
}
