import Foundation
import SwiftData
import TagwerkCore

/// User preferences, stored as a single SwiftData object.
/// Schema rule: later attributes must be optional or have a default value.
@Model
final class AppSettings {
    var workdayStartMinutes: Int = 540
    var workdayEndMinutes: Int = 1080
    var lunchStartMinutes: Int = 720
    var lunchDurationMinutes: Int = 60
    var bufferMinutes: Int = 10
    var leadTimeMinutes: Int = 120
    /// Notifications for events of deadline calendars (design 2b §11.13), next to those for tasks.
    var deadlineCalendarNotifications: Bool = true
    /// Notifications for tasks of each source; the Reminders app alerts only at the due moment, if at all.
    var githubTaskNotifications: Bool = true
    var reminderTaskNotifications: Bool = true
    var localTaskNotifications: Bool = true
    /// `nil` means the default selection (see `CalendarSelection.defaultSelected`).
    var selectedCalendarIDs: [String]? = nil
    /// `nil` means all reminder lists.
    var selectedReminderListIDs: [String]? = nil
    var setupCompleted: Bool = false
    /// `nil` means the default project selection (projects with assigned open issues).
    var selectedProjectIDs: [String]? = nil
    /// JSON of `WeekSchedule`; `nil` means the standard week (Mon–Fri 09:00–18:00).
    var weekScheduleData: Data? = nil
    /// Calendar Tagwerk writes time blocks into.
    var planCalendarID: String? = nil
    /// Calendars whose events count as important deadlines.
    var deadlineCalendarIDs: [String]? = nil
    /// Duration counted for tasks without effort.
    var defaultTaskMinutes: Int = 30
    /// Shows identical events from several calendars as one row (design §13.11).
    var mergeDuplicateEvents: Bool = true
    /// Day timeline as rows with free stretches ("list") or as a to-scale hour grid ("grid"), design §13.4.
    var dayTimelineStyle: String = "list"
    /// The day opens in the row list instead of the hour grid (grid is the default, design §13.15 S1).
    var prefersTimelineList: Bool = false
    /// ChatGPT model for all AI features; `nil` means "Automatisch" (the first model of the list).
    var aiModelSlug: String? = nil
    /// Last model list from ChatGPT (JSON of `[AIModel]`), kept to avoid loading it on every call.
    var aiModelsData: Data? = nil
    var aiModelsFetchedAt: Date? = nil
    /// Reasoning effort for all AI calls; `nil` means the model's own default ("Automatisch").
    var aiReasoningEffort: String? = nil
    /// "Vorarbeiten, wenn Luft ist": AI plans may pull in tasks of the next days.
    var aiWorkAhead: Bool = true
    /// "Längere Tage vorschlagen": `AIPlanner.LongerDays` raw value.
    var aiLongerDays: String = "forDeadlines"
    /// "Planungsvorgaben" (mockup VR1) as JSON: at most five short sentences.
    var aiPlanningRulesData: Data?
    /// Daily and weekly goals of the "Erfassen" tab (phase 3 design §8.5: placeholders, not a recommendation).
    var goalKilocalories: Int = 2300
    var goalWaterMilliliters: Int = 2000
    /// Former weekly goal as a number of workouts; no longer shown, kept in the schema (attributes are never removed)
    /// and read once by `migrateWorkoutGoalIfNeeded()`.
    var goalWorkoutsPerWeek: Int = 3
    /// Weekly training time goal in minutes; 0 hides the tile. A placeholder like the other goals, not a recommendation.
    var goalWorkoutMinutesPerWeek: Int = 150
    /// Daily step goal; 0 shows the steps without a goal.
    var goalStepsPerDay: Int = 8000
    /// The one-time takeover of the old workout goal ran.
    var workoutGoalMigrated: Bool = false
    var proteinGoalEnabled: Bool = false
    var goalProteinGrams: Int = 120
    /// The one-time consent for meal estimates (main design §7). The settings switch binds to it; off means typing values.
    var mealEstimationConsent: Bool = false
    /// Phase 5: the reminder list that serves as the shopping list; `nil` means none. Its reminders are not tasks.
    /// Written only through `AppEnvironment.setShoppingList(_:)`, which reloads everything that depends on it.
    var shoppingListID: String? = nil
    /// The card suggesting a shopping list was answered with "Nicht jetzt".
    var shoppingSuggestionDismissed: Bool = false
    /// The built-in shopping categories were created once; deleting them later does not bring them back.
    var shoppingCategoriesSeeded: Bool = false
    /// The one-time consent for "Mit ChatGPT sortieren"; the settings switch binds to it.
    var shoppingSortConsent: Bool = false
    /// The Health card in the tab was dismissed with "Nicht jetzt".
    var healthCardDismissed: Bool = false
    /// Phase 4: the calories/water line in the head of "Planen" (today's day view, from the first entry).
    var showsIntakeInPlan: Bool = true
    /// Phase 4: calories and water in the "Heute" widget; off keeps the values out of the shared snapshot file.
    var widgetShowsNutrition: Bool = true

    /// Phase 7 routines: target bedtime in minutes after midnight (23:00); the evening checklist counts back from it.
    var bedtimeMinutes: Int = 1380
    /// Notifications of the evening checklist; at most four, one per point with a time anchor.
    var eveningRemindersEnabled: Bool = true
    /// The optional reminder to start the day, off by default.
    var morningReminderEnabled: Bool = false
    var morningReminderMinutes: Int = 450
    /// The routine card and the evening line in "Planen".
    var showsRoutinesInPlan: Bool = true
    /// "Notizen an ChatGPT senden": a thought note may be sent, only on a tap on "Vorschläge holen".
    var noteSuggestionConsent: Bool = false

    /// Quiet hours (plan quiet-hours, #169): task and deadline notifications that fall into the window move to its end.
    var quietHoursEnabled: Bool = false
    /// The window starts at `bedtimeMinutes`; `quietStartMinutes` applies only while this is off.
    var quietHoursStartsAtBedtime: Bool = true
    var quietStartMinutes: Int = 1380
    var quietEndMinutes: Int = 420
    /// Focus filter "Mitteilungen ruhen lassen" (runtime state, not a preference): set while a Focus with the filter is
    /// active, and the start kept after it ended until the notifications that came due meanwhile were caught up.
    var focusQuietSince: Date? = nil
    var focusQuietCatchUpFrom: Date? = nil
    var focusQuietCatchUpAt: Date? = nil

    /// Voice: microphone in conversations (plan voice-chat, SP7a).
    var voiceInputEnabled: Bool = true
    /// The one-time explanation before the first recording (SP8a) was confirmed.
    var voiceExplained: Bool = false
    /// "auto" follows the iPhone language; otherwise a `VoiceLanguage` raw value.
    var voiceRecognitionLanguage: String = "auto"
    /// `ReadAloudPolicy` raw value; "never" by default (SP3).
    var voiceReadAloud: String = "never"
    /// Chosen system voices per language; nil picks the best installed voice.
    var voiceGermanVoiceID: String? = nil
    var voiceEnglishVoiceID: String? = nil
    /// `AVSpeechUtterance.rate`, 0...1.
    var voiceRate: Double = 0.5
    /// Read action cards aloud when answers are read (SP4a).
    var voiceAnnounceActions: Bool = true
    /// Voice mode (SP5a, Task 12): seconds of pause before sending, seconds of silence before pausing, and
    /// whether the one-time explanation was shown.
    var voiceModeSendDelay: Double = 2
    var voiceModeSilenceLimit: Double = 30
    var voiceModeExplained: Bool = false

    static let maximumPlanningRules = 5

    var aiPlanningRules: [String] {
        get { aiPlanningRulesData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [] }
        set { aiPlanningRulesData = try? JSONEncoder().encode(Array(newValue.prefix(Self.maximumPlanningRules))) }
    }

    var weekSchedule: WeekSchedule {
        get { weekScheduleData.flatMap { try? JSONDecoder().decode(WeekSchedule.self, from: $0) } ?? .standard }
        set { weekScheduleData = try? JSONEncoder().encode(newValue) }
    }

    init() {}

    /// Returns the single settings object, creating it on first access.
    @MainActor
    static func current(in context: ModelContext) throws -> AppSettings {
        if let existing = try context.fetch(FetchDescriptor<AppSettings>()).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        return settings
    }
}

extension AppSettings {
    /// One-time takeover when the workout goal moved from a count to minutes: a switched-off goal (0) stays off;
    /// any other count keeps the minute default. Runs once, also on a fresh install, so it never touches a later choice.
    func migrateWorkoutGoalIfNeeded() {
        guard !workoutGoalMigrated else { return }
        if goalWorkoutsPerWeek == 0 { goalWorkoutMinutesPerWeek = 0 }
        workoutGoalMigrated = true
    }

    /// The quiet hours the settings describe; `nil` when switched off or empty.
    var quietHours: QuietHours? {
        QuietHours.resolved(enabled: quietHoursEnabled, startsAtBedtime: quietHoursStartsAtBedtime, bedtimeMinutes: bedtimeMinutes,
                            startMinutes: quietStartMinutes, endMinutes: quietEndMinutes)
    }

    /// The Focus filter state, see `FocusQuiet`.
    var focusQuietState: FocusQuiet.State {
        get { FocusQuiet.State(since: focusQuietSince, catchUpFrom: focusQuietCatchUpFrom, catchUpAt: focusQuietCatchUpAt) }
        set {
            focusQuietSince = newValue.since
            focusQuietCatchUpFrom = newValue.catchUpFrom
            focusQuietCatchUpAt = newValue.catchUpAt
        }
    }

    /// Task sources whose switch for notifications is on.
    var notifiedTaskSources: Set<TaskSource> {
        var sources: Set<TaskSource> = []
        if githubTaskNotifications { sources.insert(.github) }
        if reminderTaskNotifications { sources.insert(.reminders) }
        if localTaskNotifications { sources.insert(.local) }
        return sources
    }
}
