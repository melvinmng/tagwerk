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

    /// The habits active today, for the shortcut's choice of habit.
    func activeHabits() -> [Habit] {
        let habits = environment.habits
        habits.refreshLocal()
        return habits.habits.filter { HabitRules.isActive($0, on: habits.today, today: habits.today) }
    }

    /// "Gewohnheit abhaken": today's manual check, also for a habit with an automatic source; writes the snapshot.
    /// The reply names neither streak nor rate, so it may be spoken on a locked device.
    func checkHabit(id: UUID) async -> LocalizedStringResource {
        let habits = environment.habits
        // Best effort: Health may be unreadable here; the counter then keeps its last value (see `AppEnvironment`).
        await habits.reload(day: habits.today)
        guard let habit = habits.habits.first(where: { $0.id == id }),
              HabitRules.isActive(habit, on: habits.today, today: habits.today) else {
            return "Diese Gewohnheit gibt es nicht mehr."
        }
        let changed = await habits.checkToday(id)
        environment.writeSnapshot()
        let name = habit.name
        return changed ? "\(name) ist für heute abgehakt." : "\(name) war heute schon abgehakt."
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

    /// "Auf die Einkaufsliste": splits the spoken text into items and adds them without duplicates.
    /// Needs only reminders, the settings and the categories: no loaded task list, no network, no AI feature.
    /// The reply names only what was just said, so it may be spoken on a locked device.
    func addToShopping(text: String) async -> LocalizedStringResource {
        let shopping = environment.shopping
        await shopping.reload()
        switch shopping.state {
        case .accessDenied: return "Tagwerk hat keinen Zugriff auf Erinnerungen."
        case .noList, .listMissing: return "Wähle zuerst in Tagwerk unter Einstellungen › Einkaufsliste eine Liste."
        case .ready: break
        }
        let items = ShoppingInputParser.parseAll(text).items
        guard !items.isEmpty else { return "Ich habe keinen Artikel verstanden." }
        let report = await shopping.add(items)
        return LocalizedStringResource(stringLiteral: Self.shoppingReply(report))
    }

    /// One sentence per group; reopened items count as added.
    static func shoppingReply(_ report: ShoppingModel.AddReport) -> String {
        var sentences: [String] = []
        let added = report.added + report.reopened
        if !added.isEmpty {
            sentences.append(String(localized: "\(added.count) Artikel hinzugefügt:") + " " + added.joined(separator: ", ") + ".")
        }
        if report.alreadyOnList.count == 1 {
            sentences.append(String(localized: "\(report.alreadyOnList[0]) steht schon auf der Liste."))
        } else if !report.alreadyOnList.isEmpty {
            sentences.append(String(localized: "\(report.alreadyOnList.joined(separator: ", ")) stehen schon auf der Liste."))
        }
        if !report.failed.isEmpty {
            sentences.append(String(localized: "Das hat nicht geklappt: \(report.errorMessage ?? report.failed.joined(separator: ", "))"))
        }
        return sentences.joined(separator: " ")
    }

    /// "Einkaufsliste zeigen": only navigates, like the `tagwerk://shopping` link.
    func openShopping() {
        environment.router.open(.shopping)
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
