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

    /// "Fokus starten / beenden": a free session without task or block, also from the background. The reply names no
    /// task, so it may be spoken on a locked device.
    func setFocus(_ on: Bool) async -> LocalizedStringResource {
        let changed = await environment.focus.setRunning(on)
        switch (on, changed) {
        case (true, true): return "Fokus gestartet."
        case (true, false): return "Der Fokus läuft schon."
        case (false, true): return "Fokus beendet."
        case (false, false): return "Es läuft gerade kein Fokus."
        }
    }

    /// "Notiz diktieren": only navigates, like the `tagwerk://notes/dictate` link; the recording starts in the app.
    func openDictation() {
        environment.router.open(.notesDictate)
    }

    /// The Focus filter "Mitteilungen ruhen lassen" (plan quiet-hours, decision 5): iOS runs it when a Focus with the
    /// filter starts (`active`) and, with the default value, when it ends. Remembers the state and plans the
    /// notifications again; the plan holds them back while active and lets those that came due fire after the end.
    func setFocusQuiet(active: Bool, now: Date = .now) async {
        let settings = environment.settings
        settings.focusQuietState = FocusQuiet.applying(active: active, now: now, to: settings.focusQuietState)
        try? environment.modelContainer.mainContext.save()
        // A cold start in the background has loaded nothing; sources that are not loaded keep their old requests.
        if settings.setupCompleted { await environment.loadTasksInBackground() }
        await environment.notifications.reschedule()
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
        // Keeps the day the tab shows; the check below is always for today.
        await habits.reload()
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
        // The list was just loaded above.
        let report = await shopping.add(items, reloadFirst: false)
        return LocalizedStringResource(stringLiteral: Self.shoppingReply(report))
    }

    /// "Füge Milch zur Einkaufsliste hinzu": adds the chosen article through the same path as the text shortcut.
    /// A free-typed name may still hold a quantity or several items; it is split like spoken text.
    func addToShopping(article: ShoppingArticleEntity) async -> LocalizedStringResource {
        await addToShopping(text: article.name)
    }

    /// The article names Siri can speak, see `ShoppingSuggestions`: own names (open and completed) first,
    /// then common terms from the offline dictionary in the app language. Reads Reminders only; with no list
    /// or access only the common terms remain.
    func shoppingArticleNames(preferEnglish: Bool = IntentServices.prefersEnglish) async -> [String] {
        let history = await environment.shopping.history()
        return ShoppingSuggestions.articles(history: history, commonTerms: ShoppingSuggestions.commonTerms(preferEnglish: preferEnglish))
    }

    /// Names that match a typed or spoken text. A text that matches no suggestion but holds an article resolves
    /// to itself, so a spoken answer to "Was soll auf die Liste?" always works; blank text resolves to nothing.
    func shoppingArticleNames(matching text: String, preferEnglish: Bool = IntentServices.prefersEnglish) async -> [String] {
        let matches = ShoppingSuggestions.matching(text, in: await shoppingArticleNames(preferEnglish: preferEnglish))
        guard matches.isEmpty else { return matches }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ShoppingInputParser.parseAll(trimmed).items.isEmpty else { return [] }
        return [String(trimmed.prefix(Self.maxArticleTextLength))]
    }

    /// Longest free-typed article text that is accepted as one entity.
    static let maxArticleTextLength = 200

    /// Whether the app currently runs in English; decides which common terms come first.
    static var prefersEnglish: Bool { Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true }

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
